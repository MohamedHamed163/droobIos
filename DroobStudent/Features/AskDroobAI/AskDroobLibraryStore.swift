import Foundation
import Darwin
import UIKit

// MARK: - Durable storage for everything Ask Droob AI produces
//
// WHERE. `Application Support/AskDroobLibrary/`. Not `Documents` — that is one
// `UIFileSharingEnabled` flip away from being user-browsable and is iCloud-backed
// by default. Not `Caches` and not `temporaryDirectory` — the OS reclaims both,
// which is the whole bug this file exists to close: a student who exported a
// forty-question solution sheet must still find it tomorrow. Application Support
// is app-private, is never purged by the system, and is the documented home for
// data an app manages on the user's behalf.
//
// PROTECTION. Every file and directory carries
// `.completeUntilFirstUserAuthentication`, not `.complete`. `.complete` makes a
// file unreadable while the device is locked, which would fail the background
// flush this store performs on `willResignActive` and would kill a batch that
// keeps answering with the screen off. `.completeUntilFirstUserAuthentication`
// still protects the exam photographs at rest before first unlock — the threat
// that matters for a lost or seized phone — and never fails a write afterwards.
//
// BACKUP. The root is excluded from iCloud backup: up to 200 MB of photographed
// exam papers is a privacy and quota cost this feature has no reason to impose,
// and the Library footer says so in both languages ("Saved on this device only").
//
// FORMAT. JSON, no database. Room/SwiftData/Core Data for a list of at most 200
// rows is a schema, a migration story and a build-time processor for something a
// 40 KB file answers. The manifest is split — one `index.json` plus one
// `session.json` per session — so a forty-question batch rewrites a few hundred
// KB per answer instead of the whole library, and so corruption is survivable at
// the granularity of one session instead of all of them.
//
// THE INDEX IS A CACHE; THE SESSION FILES ARE THE TRUTH. `index.json` is
// derivable by walking `sessions/`, so a corrupt, truncated, missing or
// future-schema index is answered by a rebuild rather than by an error. A corrupt
// `session.json` damages exactly one row, which still renders (from the index)
// and can still be deleted. There is no single file whose loss loses the library.
//
// ATOMICITY. Nothing is ever written in place. Every manifest and every PDF goes
// through `writeAtomically` — temp file in the *same* directory, fsync, protect,
// `rename(2)`, fsync the directory. `rename(2)` is atomic, so a kill mid-write
// leaves the reader looking at the complete previous file or the complete new
// one, never at half of either. `Data.write(to:options:.atomic)` is deliberately
// not used: it renames but does not fsync, and it gives no place to set the
// protection class before the rename.

// MARK: - Public value types

/// One attachment as the UI sees it: already validated, already resolved to a
/// URL that exists.
struct LibraryAttachment: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let mime: String
    let bytes: Int64
    let pages: Int
    let url: URL

    var isPDF: Bool {
        mime == "application/pdf" || url.pathExtension.lowercased() == "pdf"
    }
}

/// One row of the Library list. Everything here comes from `index.json`, so
/// drawing the list never opens a session file.
struct LibrarySessionSummary: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let createdAt: Date
    let updatedAt: Date
    let lastOpenedAt: Date?
    let locale: String
    let questionCount: Int
    let answerCount: Int
    let attachmentCount: Int
    let attachmentMime: String?
    let scansEvicted: Bool
    let hasExport: Bool
    let bytes: Int64
    let damaged: Bool
}

/// What eviction removed since the student last dismissed the banner. Persisted
/// in the index because eviction almost always happens during a batch, with the
/// Library closed.
struct LibraryEvictionNotice: Equatable, Sendable {
    var pdfs: Int
    var scans: Int
    var sessions: Int

    var isEmpty: Bool { pdfs == 0 && scans == 0 && sessions == 0 }
}

/// A message crossing the store boundary. Deliberately not `AskDroobMessage`:
/// this one is a plain `Sendable` record, so handing it to an actor carries no
/// concurrency caveat.
struct LibraryMessage: Sendable, Equatable {
    let id: String
    let isUser: Bool
    let text: String
    let at: Date
    let provider: String?
}

/// Everything needed to create a session file that does not exist yet.
struct LibrarySessionSeed: Sendable {
    let title: String
    let locale: String
    let createdAt: Date
}

/// A full snapshot write. The whole transcript every time: a session file is at
/// most a few hundred KB and a partial append has no atomic form.
struct LibrarySessionPayload: Sendable {
    let id: String
    let title: String
    let locale: String
    let createdAt: Date
    let messages: [LibraryMessage]
}

/// A session read back off disk.
struct LoadedLibrarySession: Sendable {
    let id: String
    let title: String
    let locale: String
    let createdAt: Date
    let messages: [LibraryMessage]
    let attachments: [LibraryAttachment]
    let scansEvicted: Bool
    let exportURL: URL?
}

/// The published state, produced by the writer after every mutation.
struct LibrarySnapshot: Sendable {
    let sessions: [LibrarySessionSummary]
    let totalBytes: Int64
    let notice: LibraryEvictionNotice?
}

enum LibraryError: Error {
    /// The device has no room. Distinct because it is the one failure the
    /// student can actually do something about.
    case outOfSpace
    case writeFailed
    case unreadable
}

/// What an exported sheet is *for*, which decides whether it becomes the
/// session's PDF.
enum LibraryExportKind: Sendable {
    /// The whole thread's solutions sheet. Exactly one per session: a new one
    /// replaces the old one, because it is a pure function of the same
    /// transcript and keeping both is how 40 MB of PDFs accumulates unnoticed.
    case session
    /// One answer, saved from its own bubble. Kept so it can be shared, never
    /// registered as the session's export and never allowed to delete the
    /// whole-thread sheet beside it — a student who exports forty answers and
    /// then saves one of them must still have the forty.
    case singleAnswer
}

// MARK: - The store

/// The single entry point. `@MainActor` so the published state needs no hops,
/// with every `FileManager` call behind `LibraryIO` — an actor, serial by
/// construction, running on the cooperative pool and never on the main thread.
@MainActor
final class AskDroobLibraryStore: ObservableObject {

    static let shared = AskDroobLibraryStore()

    @Published private(set) var sessions: [LibrarySessionSummary] = []
    @Published private(set) var notice: LibraryEvictionNotice?
    @Published private(set) var totalBytes: Int64 = 0
    /// True only while the first read — or a rebuild after a corrupt index — is
    /// running. It is the one state that can take longer than a frame.
    @Published private(set) var isLoading = true

    /// 200 MB. A worst-case session is a 20 MB scan (the intake cap) plus ~1 MB
    /// of PDF plus ~200 KB of JSON, so this holds ~9 of those or several hundred
    /// typed ones, and is small enough never to be the reason a 32 GB phone runs
    /// out of space.
    let budgetBytes: Int64 = 200 * 1024 * 1024
    let warnFraction: Double = 0.90

    private let io = LibraryIO()
    private var started = false

    /// Strict FIFO over every mutation. Two bare `Task { await io.write(…) }`
    /// are not ordered against each other, and because each payload is a whole
    /// transcript an out-of-order pair would write the older one last.
    private var writeChain: Task<Void, Never> = Task {}

    /// The newest coalesced payload, applied to disk 400 ms after the last
    /// request or immediately on the next flush — whichever comes first.
    private var pendingPayload: LibrarySessionPayload?
    private var debounceTask: Task<Void, Never>?

    private init() {
        // The store owns its own background hooks so no view has to remember to
        // call it. `willResignActive` matters as much as `didEnterBackground`:
        // it fires for the app switcher and for an incoming call, which is when
        // the OS is most likely to kill the process next.
        for name in [UIApplication.willResignActiveNotification,
                     UIApplication.didEnterBackgroundNotification] {
            NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.flushPending() }
            }
        }
    }

    // MARK: Lifecycle

    /// Reads (or rebuilds) the index once per process.
    func start() {
        guard !started else { return }
        started = true
        enqueue { [weak self] in
            guard let self else { return }
            let snapshot = await self.io.load()
            self.apply(snapshot)
            self.isLoading = false
        }
    }

    // MARK: Writing

    /// Enqueues a transcript write.
    ///
    /// `immediate` for assistant messages — an answer is 3–6 s of network and,
    /// on the free tier, a spent quota unit, and "killing the app mid-batch must
    /// not lose the answers already produced" is the requirement this whole file
    /// exists for. Coalesced for user messages: an unanswered question bubble
    /// costs nothing to retype, and during a batch it is followed by an
    /// immediate write seconds later anyway.
    func persist(_ payload: LibrarySessionPayload, immediate: Bool) {
        pendingPayload = payload
        debounceTask?.cancel()
        debounceTask = nil

        if immediate {
            flushPending()
        } else {
            debounceTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                self?.flushPending()
            }
        }
    }

    /// Writes whatever is dirty. Safe to call at any time; a no-op when nothing
    /// is pending.
    func flushPending() {
        debounceTask?.cancel()
        debounceTask = nil
        guard let payload = pendingPayload else { return }
        pendingPayload = nil
        enqueue { [weak self] in
            guard let self else { return }
            let result = await self.io.write(payload)
            self.apply(result.snapshot)
        }
    }

    /// Writes a transcript and reports whether it actually landed.
    ///
    /// `persist` is deliberately fire-and-forget — the conversation stays in
    /// memory either way, and the next message tries again. This one exists for
    /// the single caller that *discards* its in-memory copy on the strength of
    /// the write: "Clear chat". A full disk is exactly the situation a feature
    /// that budgets 200 MB of scans and PDFs has to expect, and a silent failure
    /// there is forty questions destroyed under a message saying they were
    /// saved.
    ///
    /// `touch: false` writes the same bytes without restamping `updatedAt`, for
    /// the case where the archive is only confirming what the disk already
    /// holds. Restamping there would move a session the student merely read to
    /// the top of the Library, dated today.
    func archive(_ payload: LibrarySessionPayload, touch: Bool) async -> Bool {
        // This snapshot supersedes anything coalesced for the same session.
        if pendingPayload?.id == payload.id { dropPending() }
        return await serialized { [weak self] in
            guard let self else { return false }
            let result = await self.io.write(payload, touch: touch)
            self.apply(result.snapshot)
            return result.written
        }
    }

    /// Marks which session must never be evicted.
    func setLiveSession(_ id: String?) {
        enqueue { [weak self] in
            await self?.io.setLive(id)
        }
    }

    // MARK: Files

    /// Stores the uploaded PDF or photograph beside its session, before a single
    /// byte of it is read. A kill during intake then leaves the scan in the
    /// Library with an empty transcript — recoverable, and honest about what
    /// happened.
    func addAttachment(
        sessionId: String,
        seed: LibrarySessionSeed,
        data: Data,
        name: String,
        mime: String,
        pages: Int
    ) async throws -> LibraryAttachment {
        // Ordered *inside* the queue rather than merely behind the queue as it
        // stood: a transcript write requested while this one is in flight then
        // follows it instead of racing it.
        let result = try await serializedThrowing { [io] in
            try await io.addAttachment(
                sessionId: sessionId, seed: seed, data: data,
                name: name, mime: mime, pages: pages)
        }
        apply(result.1)
        return result.0
    }

    /// Writes an exported solution sheet into the session's own `exports/`
    /// directory. A `.session` sheet is recorded as *the* export — at most one
    /// per session, the old file removed rather than orphaned. A
    /// `.singleAnswer` sheet is kept for sharing only and never touches the
    /// whole-thread sheet.
    func storeExport(
        sessionId: String,
        seed: LibrarySessionSeed,
        data: Data,
        title: String,
        problemCount: Int,
        kind: LibraryExportKind
    ) async throws -> URL {
        let result = try await serializedThrowing { [io] in
            try await io.storeExport(
                sessionId: sessionId, seed: seed, data: data,
                title: title, problemCount: problemCount, kind: kind)
        }
        apply(result.1)
        return result.0
    }

    // MARK: Reading

    func loadSession(id: String) async throws -> LoadedLibrarySession {
        await drain()
        return try await io.loadSession(id: id)
    }

    func exportURL(for id: String) async -> URL? {
        await drain()
        return await io.exportURL(for: id)
    }

    func markOpened(_ id: String) {
        enqueue { [weak self] in
            guard let self else { return }
            self.apply(await self.io.markOpened(id: id))
        }
    }

    /// Records that a session's `session.json` could not be decoded, so the row
    /// stops offering Open and starts saying why.
    func markDamaged(_ id: String) {
        enqueue { [weak self] in
            guard let self else { return }
            self.apply(await self.io.markDamaged(id: id))
        }
    }

    // MARK: Deleting
    //
    // Deleting is the one destructive path in the feature, so it has to be
    // final. `drain()` alone is not enough to make it final: it waits for the
    // queue *as it stood*, and an answer that returns while the files are being
    // removed enqueues a whole-transcript write that then lands afterwards and
    // puts the session back — half of it, since the scan and the PDF really are
    // gone. Three things close that: the coalesced payload is dropped, the
    // deletion joins the same serial chain every write uses, and the writer
    // remembers the id long enough to refuse a write that was already in flight.

    func delete(id: String) async {
        if pendingPayload?.id == id { dropPending() }
        let snapshot = await serialized { [io] in await io.delete(id: id) }
        apply(snapshot)
    }

    func deleteAll() async {
        dropPending()
        let snapshot = await serialized { [io] in await io.deleteAll() }
        apply(snapshot)
    }

    /// Throws away a session that was created but never used — a "New chat" tap
    /// on an empty chat must not leave a row behind.
    func discardIfEmpty(id: String) {
        enqueue { [weak self] in
            guard let self else { return }
            self.apply(await self.io.discardIfEmpty(id: id))
        }
    }

    func dismissNotice() {
        notice = nil
        enqueue { [weak self] in
            guard let self else { return }
            self.apply(await self.io.dismissNotice())
        }
    }

    // MARK: Plumbing

    private func apply(_ snapshot: LibrarySnapshot) {
        sessions = snapshot.sessions
        totalBytes = snapshot.totalBytes
        notice = (snapshot.notice?.isEmpty ?? true) ? nil : snapshot.notice
    }

    private func enqueue(_ work: @escaping () async -> Void) {
        let previous = writeChain
        writeChain = Task { @MainActor in
            await previous.value
            await work()
        }
    }

    /// Waits for the queue to empty so a read sees every write before it.
    private func drain() async {
        let pending = writeChain
        await pending.value
    }

    /// Runs `work` as a link in the same chain and returns its result.
    ///
    /// The difference from `drain()` + a bare call matters exactly once, and it
    /// is the whole of the deletion bug: `drain()` returns when the queue is
    /// empty, and anything enqueued during the `await` that follows is ordered
    /// *after* the work — so a write requested mid-deletion re-created the
    /// session. Joining the chain puts this work in the queue, so a later write
    /// waits for it.
    private func serialized<T>(_ work: @escaping @MainActor () async -> T) async -> T {
        let previous = writeChain
        let task = Task { @MainActor () -> T in
            await previous.value
            return await work()
        }
        writeChain = Task { @MainActor in _ = await task.value }
        return await task.value
    }

    /// `serialized` for the two file paths that can fail. A thrown error still
    /// leaves the chain intact, so a failed attachment never wedges the queue.
    private func serializedThrowing<T>(
        _ work: @escaping @MainActor () async throws -> T
    ) async throws -> T {
        let previous = writeChain
        let task = Task { @MainActor () -> Result<T, Error> in
            await previous.value
            do { return .success(try await work()) } catch { return .failure(error) }
        }
        writeChain = Task { @MainActor in _ = await task.value }
        return try await task.value.get()
    }

    /// Throws away the coalesced payload. A user message caught inside the
    /// 400 ms window must not be written back after the session it belongs to
    /// has been deleted.
    private func dropPending() {
        debounceTask?.cancel()
        debounceTask = nil
        pendingPayload = nil
    }

    // MARK: - Title derivation
    //
    // Computed once, when the first user message is appended, and never
    // recomputed: a row whose title changed under the student is a row they can
    // no longer recognise.

    static func derivedTitle(from text: String) -> String {
        // `$` first, so `$$3x+7=22$$` reads as `3x+7=22` rather than as dollar
        // noise in a list of one-line titles.
        var cleaned = text.replacingOccurrences(of: "$", with: "")
        cleaned = cleaned.trimmingCharacters(
            in: CharacterSet(charactersIn: "#*_`> \t\n\r"))

        var collapsed = ""
        var lastWasSpace = false
        for character in cleaned {
            if character.isWhitespace || character.isNewline {
                if !lastWasSpace { collapsed.append(" ") }
                lastWasSpace = true
            } else {
                collapsed.append(character)
                lastWasSpace = false
            }
        }
        collapsed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)

        guard collapsed.count > 60 else { return collapsed }
        var cut = String(collapsed.prefix(60))
        // Cutting mid-word is uglier than losing up to twelve characters.
        let tail = cut.suffix(12)
        if let space = tail.lastIndex(of: " ") {
            cut = String(cut[cut.startIndex..<space])
        }
        return cut.trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }
}

// MARK: - The writer

/// Every `FileManager` call in the feature lives here. An actor is serial by
/// construction, so there is exactly one writer and no lock to forget.
actor LibraryIO {

    // MARK: Budget

    private let maxTotalBytes: Int64 = 200 * 1024 * 1024
    private let maxSessions = 200

    // MARK: Layout
    //
    // Three sibling trees rather than everything under `sessions/<id>/` so the
    // binaries a student explicitly asked to share (`scans/`, `exports/`) are
    // separable from the transcripts, which nothing outside the app should ever
    // be able to name.

    private let fm = FileManager.default
    private let root: URL
    private let sessionsDir: URL
    private let scansDir: URL
    private let exportsDir: URL
    private let indexURL: URL

    private let stamp: DateFormatter
    private let iso: DateFormatter

    // MARK: State

    private var entries: [String: EntryRecord] = [:]
    private var totalBytes: Int64 = 0
    private var notice: NoticeRecord?
    private var liveId: String?
    private var loaded = false
    /// Sessions deleted in this process. A deletion is the destructive path and
    /// has to be final: an export or an answer that was already in flight when
    /// the student confirmed it must not put a half-session back on disk. Ids
    /// are UUIDs and are never reused, so refusing a write for one costs
    /// nothing; the list is capped because it only has to outlive the in-flight
    /// work, not the process.
    private var tombstones: [String] = []
    private let maxTombstones = 128
    /// One-answer sheets live one level down so the whole-thread sheet's
    /// single-export cleanup cannot see them.
    private static let singleExportDirectory = "single"
    /// One-entry cache so a forty-answer batch does not re-read the session file
    /// forty times.
    private var cachedId: String?
    private var cachedSession: SessionRecord?

    init() {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        root = support.appendingPathComponent("AskDroobLibrary", isDirectory: true)
        sessionsDir = root.appendingPathComponent("sessions", isDirectory: true)
        scansDir = root.appendingPathComponent("scans", isDirectory: true)
        exportsDir = root.appendingPathComponent("exports", isDirectory: true)
        indexURL = root.appendingPathComponent("index.json")

        // `en_US_POSIX` in both formatters: a file name and a manifest timestamp
        // must not change shape because the student switched the app to Arabic.
        stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.timeZone = TimeZone.current
        stamp.dateFormat = "yyyyMMdd-HHmmss"

        iso = DateFormatter()
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.timeZone = TimeZone(identifier: "UTC")
        iso.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
    }

    // MARK: - Init and recovery

    func load() -> LibrarySnapshot {
        ensureLoaded()
        return snapshot()
    }

    func setLive(_ id: String?) {
        liveId = id
    }

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true

        createDirectories()
        sweepTemps()

        var healthy = false
        if let data = try? Data(contentsOf: indexURL),
           !data.isEmpty,
           let record = try? JSONDecoder().decode(IndexRecord.self, from: data),
           record.schema == 1,
           record.droppedEntries == 0,
           record.totalBytes >= 0,
           record.totalBytes <= maxTotalBytes * 2 {
            entries = [:]
            for entry in record.sessions { entries[entry.id] = entry }
            totalBytes = record.totalBytes
            notice = record.notice
            healthy = entries.count == record.sessions.count
        }

        if healthy {
            adoptUnlistedSessions()
            orphanSweep()
            evictIfNeeded()
        } else {
            // Missing, empty, truncated, not JSON, a future schema, or an entry
            // the lenient decode had to drop. Never an error the student sees,
            // never a deletion: the session files are the truth and they are all
            // still there.
            rebuild()
        }
    }

    private func createDirectories() {
        let attributes: [FileAttributeKey: Any] = [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ]
        for directory in [root, sessionsDir, scansDir, exportsDir] {
            try? fm.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: attributes)
        }
        var url = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// There is one writer and it is serial, so at init no live temp can exist.
    /// Anything matching is debris from a killed write.
    private func sweepTemps() {
        for directory in [root, sessionsDir, scansDir, exportsDir] {
            // Two levels under the trees, one of which is
            // `exports/<id>/single/`; none under the root, which holds only the
            // index and the trees themselves.
            sweepTemps(in: directory, depth: directory == root ? 0 : 2)
        }
    }

    private func sweepTemps(in directory: URL, depth: Int) {
        guard let items = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey],
            options: []) else { return }
        for item in items {
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?
                .isDirectory ?? false
            if isDirectory {
                if depth > 0 { sweepTemps(in: item, depth: depth - 1) }
                continue
            }
            let name = item.lastPathComponent
            if name.contains(".tmp-") || name.hasSuffix(".part") {
                try? fm.removeItem(at: item)
            }
        }
    }

    /// Walks `sessions/` and reconstructs the index from the files themselves.
    /// A few hundred `stat` calls — tens of milliseconds — and it happens only
    /// after a corrupt index, never on a normal launch.
    private func rebuild() {
        entries = [:]
        notice = nil

        let names = (try? fm.contentsOfDirectory(atPath: sessionsDir.path)) ?? []
        for name in names where isSessionId(name) {
            let bytes = measure(name)
            if let record = readSessionFile(name) {
                entries[name] = entry(from: record, bytes: bytes)
            } else {
                // Still emitted. The row is visible, shows "Couldn't be read"
                // and can be deleted; a session swallowed silently is 40 MB the
                // student can never reclaim.
                let modified = (try? fm.attributesOfItem(
                    atPath: sessionsDir.appendingPathComponent(name).path)[.modificationDate])
                    as? Date ?? Date(timeIntervalSince1970: 0)
                entries[name] = EntryRecord(
                    id: name, title: "",
                    createdAt: iso.string(from: modified),
                    updatedAt: iso.string(from: modified),
                    lastOpenedAt: nil, locale: "ar",
                    questionCount: 0, answerCount: 0, attachmentCount: 0,
                    attachmentMime: nil, scansEvicted: false,
                    hasExport: hasExportFile(name), bytes: bytes, damaged: true)
            }
        }

        orphanSweep()
        totalBytes = entries.values.reduce(0) { $0 + $1.bytes }
        writeIndex()
        evictIfNeeded()
    }

    /// Closes the one window a healthy index can still leave open.
    ///
    /// `commit` writes `session.json` and *then* the index, so a kill between
    /// the two leaves a session on disk that the index has never heard of. For
    /// an existing session that costs only a stale row count, which the next
    /// message repairs. For a brand-new one the whole session — scan included —
    /// would be invisible, and the orphan sweep below would delete its scan on
    /// the next launch. One directory listing per launch buys it back.
    private func adoptUnlistedSessions() {
        let names = (try? fm.contentsOfDirectory(atPath: sessionsDir.path)) ?? []
        var adopted = false
        for name in names where isSessionId(name) && entries[name] == nil {
            guard let record = readSessionFile(name) else { continue }
            var entry = self.entry(from: record, bytes: measure(name))
            entry.damaged = false
            entries[name] = entry
            totalBytes += entry.bytes
            adopted = true
        }
        if adopted { writeIndex() }
    }

    /// Any directory under `scans/` or `exports/` with no `sessions/<id>/`
    /// beside it is unreachable by construction — the association is the
    /// directory name, not a stored path — so an orphan can always be identified
    /// without consulting a manifest at all.
    private func orphanSweep() {
        for parent in [scansDir, exportsDir] {
            let names = (try? fm.contentsOfDirectory(atPath: parent.path)) ?? []
            for name in names {
                let live = isSessionId(name) && fm.fileExists(
                    atPath: sessionsDir.appendingPathComponent(name).path)
                if !live {
                    try? fm.removeItem(at: parent.appendingPathComponent(name))
                }
            }
        }
        for name in (try? fm.contentsOfDirectory(atPath: sessionsDir.path)) ?? []
        where !isSessionId(name) {
            try? fm.removeItem(at: sessionsDir.appendingPathComponent(name))
        }
    }

    // MARK: - Writing a transcript

    /// `written` is false when nothing reached the disk — a bad id, a deleted
    /// session, or a failed write. The only caller that looks at it is the one
    /// that throws its in-memory copy away afterwards.
    func write(
        _ payload: LibrarySessionPayload, touch: Bool = true
    ) -> (written: Bool, snapshot: LibrarySnapshot) {
        ensureLoaded()
        guard isSessionId(payload.id), !isDeleted(payload.id) else {
            return (false, snapshot())
        }

        var record = session(payload.id) ?? SessionRecord(
            id: payload.id,
            title: payload.title,
            createdAt: iso.string(from: payload.createdAt),
            updatedAt: iso.string(from: payload.createdAt),
            locale: payload.locale,
            messages: [], attachments: [], export: nil, scansEvicted: false)

        record.title = payload.title
        record.locale = payload.locale
        record.createdAt = iso.string(from: payload.createdAt)
        if touch { record.updatedAt = iso.string(from: Date()) }
        record.messages = payload.messages.map {
            MessageRecord(
                id: $0.id,
                role: $0.isUser ? "user" : "assistant",
                text: $0.text,
                at: iso.string(from: $0.at),
                provider: $0.provider)
        }

        let written = commit(record, touch: touch)
        evictIfNeeded()
        return (written, snapshot())
    }

    // MARK: - Attachments

    func addAttachment(
        sessionId: String,
        seed: LibrarySessionSeed,
        data: Data,
        name: String,
        mime: String,
        pages: Int
    ) throws -> (LibraryAttachment, LibrarySnapshot) {
        ensureLoaded()
        guard isSessionId(sessionId), !isDeleted(sessionId) else {
            throw LibraryError.writeFailed
        }

        let attachmentId = UUID().uuidString.lowercased()
        // Extension from the sniffed content, never from the user-supplied file
        // name: a manifest is a file on a device the student controls, and a
        // name is the easiest thing in it to make lie.
        let ext = Self.extension(forMime: mime, data: data)
        let relative = "scans/\(sessionId)/\(attachmentId).\(ext)"
        let target = root.appendingPathComponent(relative)

        try writeAtomically(data, to: target)

        var record = session(sessionId) ?? blankSession(id: sessionId, seed: seed)
        record.attachments.append(AttachmentRecord(
            id: attachmentId, path: relative, name: name, mime: mime,
            bytes: Int64(data.count), pages: pages, at: iso.string(from: Date())))
        record.updatedAt = iso.string(from: Date())
        commit(record)
        evictIfNeeded()

        let attachment = LibraryAttachment(
            id: attachmentId, name: name, mime: mime,
            bytes: Int64(data.count), pages: pages, url: target)
        return (attachment, snapshot())
    }

    // MARK: - Exports

    func storeExport(
        sessionId: String,
        seed: LibrarySessionSeed,
        data: Data,
        title: String,
        problemCount: Int,
        kind: LibraryExportKind
    ) throws -> (URL, LibrarySnapshot) {
        ensureLoaded()
        guard isSessionId(sessionId), !isDeleted(sessionId), !data.isEmpty else {
            throw LibraryError.writeFailed
        }

        let name = Self.exportFileName(for: title, stamp: stamp.string(from: Date()))
        let sessionExports = exportsDir.appendingPathComponent(sessionId, isDirectory: true)

        guard kind == .session else {
            // One answer, saved from its own bubble. It goes in a subdirectory
            // so the whole-thread sheet's cleanup below cannot reach it, it is
            // never registered as the session's export, and it never sets the
            // row's PDF badge — "Share PDF" from the Library must keep handing
            // the teacher the forty-question sheet, not the one-problem one.
            let relative =
                "exports/\(sessionId)/\(Self.singleExportDirectory)/\(name)"
            let target = root.appendingPathComponent(relative)
            try writeAtomically(data, to: target)

            let directory = sessionExports.appendingPathComponent(
                Self.singleExportDirectory, isDirectory: true)
            for other in (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
            where other != name {
                try? fm.removeItem(at: directory.appendingPathComponent(other))
            }

            // No `commit`, so no `updatedAt` bump and no export record — only
            // the size, so the budget still counts what is on the disk.
            if var entry = entries[sessionId] {
                entry.bytes = measure(sessionId)
                apply(entry)
                writeIndex()
            }
            evictIfNeeded()
            return (target, snapshot())
        }

        let relative = "exports/\(sessionId)/\(name)"
        let target = root.appendingPathComponent(relative)
        try writeAtomically(data, to: target)

        // At most one export per session: the previous sheet is a pure function
        // of the same transcript, and keeping both is how 40 MB of PDFs
        // accumulates unnoticed. The one-answer subdirectory is skipped — those
        // sheets are not this sheet's older selves.
        let directory = sessionExports
        for other in (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
        where other != name && other != Self.singleExportDirectory {
            try? fm.removeItem(at: directory.appendingPathComponent(other))
        }

        if var record = session(sessionId) {
            record.export = ExportRecord(
                path: relative, bytes: Int64(data.count),
                problemCount: problemCount, at: iso.string(from: Date()))
            record.updatedAt = iso.string(from: Date())
            commit(record)
        } else if var entry = entries[sessionId] {
            // A damaged `session.json` must not cost the student the PDF beside
            // it. The index still learns the export exists.
            entry.hasExport = true
            entry.updatedAt = iso.string(from: Date())
            entry.bytes = measure(sessionId)
            apply(entry)
            writeIndex()
        } else {
            var record = blankSession(id: sessionId, seed: seed)
            record.export = ExportRecord(
                path: relative, bytes: Int64(data.count),
                problemCount: problemCount, at: iso.string(from: Date()))
            commit(record)
        }

        evictIfNeeded()
        return (target, snapshot())
    }

    func exportURL(for id: String) -> URL? {
        ensureLoaded()
        guard isSessionId(id) else { return nil }
        if let record = session(id), let export = record.export,
           let url = resolve(path: export.path, sessionId: id, folder: "exports") {
            return url
        }
        // §2.5: the association is the directory, not the stored path. A missing
        // or invalid `path` still finds the file when the directory holds one.
        return newestFile(in: exportsDir.appendingPathComponent(id), ext: "pdf")
    }

    // MARK: - Reading a session

    func loadSession(id: String) throws -> LoadedLibrarySession {
        ensureLoaded()
        guard isSessionId(id), let record = readSessionFile(id) else {
            throw LibraryError.unreadable
        }
        cachedId = id
        cachedSession = record

        var attachments: [LibraryAttachment] = []
        for attachment in record.attachments {
            guard let url = resolve(
                path: attachment.path, sessionId: id, folder: "scans") else { continue }
            attachments.append(LibraryAttachment(
                id: attachment.id, name: attachment.name, mime: attachment.mime,
                bytes: attachment.bytes, pages: attachment.pages, url: url))
        }

        return LoadedLibrarySession(
            id: id,
            title: record.title,
            locale: record.locale,
            createdAt: date(record.createdAt) ?? Date(timeIntervalSince1970: 0),
            messages: record.messages.compactMap { message in
                guard message.role == "user" || message.role == "assistant" else {
                    // One bad role drops the message, never the session.
                    return nil
                }
                return LibraryMessage(
                    id: message.id,
                    isUser: message.role == "user",
                    text: message.text,
                    at: date(message.at) ?? Date(timeIntervalSince1970: 0),
                    provider: message.provider)
            },
            attachments: attachments,
            scansEvicted: record.scansEvicted,
            exportURL: exportURL(for: id))
    }

    func markOpened(id: String) -> LibrarySnapshot {
        ensureLoaded()
        guard var entry = entries[id] else { return snapshot() }
        entry.lastOpenedAt = iso.string(from: Date())
        entries[id] = entry
        writeIndex()
        return snapshot()
    }

    func markDamaged(id: String) -> LibrarySnapshot {
        ensureLoaded()
        guard var entry = entries[id] else { return snapshot() }
        entry.damaged = true
        entries[id] = entry
        writeIndex()
        return snapshot()
    }

    // MARK: - Deleting

    /// Files first, then the entry, then the index. A crash between them leaves
    /// an entry pointing at nothing — rendered as damaged, deletable again —
    /// rather than files with no entry, which are invisible and un-deletable.
    func delete(id: String) -> LibrarySnapshot {
        ensureLoaded()
        tombstone(id)
        removeFiles(id)
        if let entry = entries.removeValue(forKey: id) {
            totalBytes -= entry.bytes
        }
        if totalBytes < 0 { totalBytes = 0 }
        if cachedId == id { cachedId = nil; cachedSession = nil }
        writeIndex()
        return snapshot()
    }

    func deleteAll() -> LibrarySnapshot {
        ensureLoaded()
        for id in entries.keys { tombstone(id) }
        if let liveId { tombstone(liveId) }
        for directory in [sessionsDir, scansDir, exportsDir] {
            try? fm.removeItem(at: directory)
        }
        createDirectories()
        entries = [:]
        totalBytes = 0
        notice = nil
        cachedId = nil
        cachedSession = nil
        writeIndex()
        return snapshot()
    }

    func discardIfEmpty(id: String) -> LibrarySnapshot {
        ensureLoaded()
        guard let entry = entries[id] else {
            removeFiles(id)
            return snapshot()
        }
        guard entry.questionCount == 0, entry.answerCount == 0,
              entry.attachmentCount == 0, !entry.hasExport else {
            return snapshot()
        }
        return delete(id: id)
    }

    func dismissNotice() -> LibrarySnapshot {
        ensureLoaded()
        notice = nil
        writeIndex()
        return snapshot()
    }

    private func tombstone(_ id: String) {
        guard isSessionId(id), !tombstones.contains(id) else { return }
        tombstones.append(id)
        if tombstones.count > maxTombstones {
            tombstones.removeFirst(tombstones.count - maxTombstones)
        }
    }

    private func isDeleted(_ id: String) -> Bool { tombstones.contains(id) }

    private func removeFiles(_ id: String) {
        guard isSessionId(id) else { return }
        for parent in [sessionsDir, scansDir, exportsDir] {
            try? fm.removeItem(at: parent.appendingPathComponent(id, isDirectory: true))
        }
    }

    // MARK: - Eviction
    //
    // In increasing order of irreplaceability. An export is a pure function of
    // the transcript, so losing it costs one tap. A scan cannot be recreated,
    // but the questions read out of it are already in the transcript, so what is
    // lost is the picture, not the content. The transcript is the only
    // irreplaceable thing, so it goes last. The live session is never a
    // candidate at any stage.

    private func evictIfNeeded() {
        guard totalBytes > maxTotalBytes || entries.count > maxSessions else { return }

        var evictedPDFs = 0
        var evictedScans = 0
        var evictedSessions = 0

        // A count overflow is only solved by removing rows.
        while entries.count > maxSessions, let victim = oldest({ _ in true }) {
            _ = delete(id: victim)
            evictedSessions += 1
        }

        var guardCount = 0
        while totalBytes > maxTotalBytes, guardCount < maxSessions * 3 {
            guardCount += 1
            if let victim = oldest({ $0.hasExport }) {
                dropExports(victim)
                evictedPDFs += 1
                continue
            }
            if let victim = oldest({ $0.attachmentCount > 0 }) {
                dropScans(victim)
                evictedScans += 1
                continue
            }
            if let victim = oldest({ _ in true }) {
                _ = delete(id: victim)
                evictedSessions += 1
                continue
            }
            break
        }

        guard evictedPDFs + evictedScans + evictedSessions > 0 else { return }
        var current = notice ?? NoticeRecord(pdfs: 0, scans: 0, sessions: 0, at: "")
        current.pdfs += evictedPDFs
        current.scans += evictedScans
        current.sessions += evictedSessions
        current.at = iso.string(from: Date())
        notice = current
        writeIndex()
    }

    /// "Oldest" is `updatedAt`, ties broken by `createdAt`, then by `id` — a
    /// total order, so the same library evicts the same session every time.
    private func oldest(_ include: (EntryRecord) -> Bool) -> String? {
        entries.values
            .filter { $0.id != liveId && include($0) }
            .min { a, b in
                if a.updatedAt != b.updatedAt { return a.updatedAt < b.updatedAt }
                if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
                return a.id < b.id
            }?.id
    }

    private func dropExports(_ id: String) {
        try? fm.removeItem(at: exportsDir.appendingPathComponent(id, isDirectory: true))
        if var record = session(id) {
            record.export = nil
            commit(record, touch: false)
        } else if var entry = entries[id] {
            entry.hasExport = false
            entry.bytes = measure(id)
            apply(entry)
            writeIndex()
        }
    }

    private func dropScans(_ id: String) {
        try? fm.removeItem(at: scansDir.appendingPathComponent(id, isDirectory: true))
        if var record = session(id) {
            record.attachments = []
            record.scansEvicted = true
            commit(record, touch: false)
        } else if var entry = entries[id] {
            entry.attachmentCount = 0
            entry.scansEvicted = true
            entry.bytes = measure(id)
            apply(entry)
            writeIndex()
        }
    }

    // MARK: - Session file plumbing

    private func blankSession(id: String, seed: LibrarySessionSeed) -> SessionRecord {
        SessionRecord(
            id: id, title: seed.title,
            createdAt: iso.string(from: seed.createdAt),
            updatedAt: iso.string(from: seed.createdAt),
            locale: seed.locale,
            messages: [], attachments: [], export: nil, scansEvicted: false)
    }

    private func session(_ id: String) -> SessionRecord? {
        if cachedId == id, let cached = cachedSession { return cached }
        guard let record = readSessionFile(id) else { return nil }
        cachedId = id
        cachedSession = record
        return record
    }

    private func readSessionFile(_ id: String) -> SessionRecord? {
        let url = sessionsDir
            .appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("session.json")
        guard let data = try? Data(contentsOf: url), !data.isEmpty,
              let record = try? JSONDecoder().decode(SessionRecord.self, from: data),
              record.schema == 1
        else { return nil }
        return record
    }

    /// The one path that writes a session file and reconciles the index with it.
    /// Returns false when the file did not land, so a caller that is about to
    /// discard its in-memory copy can find out.
    @discardableResult
    private func commit(_ record: SessionRecord, touch: Bool = true) -> Bool {
        var record = record
        if touch { record.updatedAt = iso.string(from: Date()) }

        let url = sessionsDir
            .appendingPathComponent(record.id, isDirectory: true)
            .appendingPathComponent("session.json")
        guard let data = try? JSONEncoder().encode(record) else { return false }
        do {
            try writeAtomically(data, to: url)
        } catch {
            // A failed transcript write must not corrupt the index or lose the
            // in-memory conversation; the next message tries again.
            return false
        }

        cachedId = record.id
        cachedSession = record
        apply(entry(from: record, bytes: measure(record.id)))
        writeIndex()
        return true
    }

    private func apply(_ entry: EntryRecord) {
        let previous = entries[entry.id]?.bytes ?? 0
        entries[entry.id] = entry
        totalBytes += entry.bytes - previous
        if totalBytes < 0 { totalBytes = 0 }
    }

    private func entry(from record: SessionRecord, bytes: Int64) -> EntryRecord {
        EntryRecord(
            id: record.id,
            title: record.title,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            lastOpenedAt: entries[record.id]?.lastOpenedAt,
            locale: record.locale,
            questionCount: record.messages.filter { $0.role == "user" }.count,
            answerCount: record.messages.filter { $0.role == "assistant" }.count,
            attachmentCount: record.attachments.count,
            attachmentMime: record.attachments.first?.mime,
            scansEvicted: record.scansEvicted,
            hasExport: record.export != nil || hasExportFile(record.id),
            bytes: bytes,
            damaged: false)
    }

    private func hasExportFile(_ id: String) -> Bool {
        newestFile(in: exportsDir.appendingPathComponent(id), ext: "pdf") != nil
    }

    // MARK: - Index file

    private func writeIndex() {
        let record = IndexRecord(
            schema: 1,
            updatedAt: iso.string(from: Date()),
            totalBytes: totalBytes,
            notice: (notice?.isEmpty ?? true) ? nil : notice,
            sessions: sorted())
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? writeAtomically(data, to: indexURL)
    }

    private func sorted() -> [EntryRecord] {
        entries.values.sorted { a, b in
            if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
            if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
            return a.id < b.id
        }
    }

    private func snapshot() -> LibrarySnapshot {
        LibrarySnapshot(
            sessions: sorted().map { entry in
                LibrarySessionSummary(
                    id: entry.id,
                    title: entry.title,
                    createdAt: date(entry.createdAt) ?? Date(timeIntervalSince1970: 0),
                    updatedAt: date(entry.updatedAt)
                        ?? date(entry.createdAt) ?? Date(timeIntervalSince1970: 0),
                    lastOpenedAt: entry.lastOpenedAt.flatMap { date($0) },
                    locale: entry.locale == "en" ? "en" : "ar",
                    questionCount: entry.questionCount,
                    answerCount: entry.answerCount,
                    attachmentCount: entry.attachmentCount,
                    attachmentMime: entry.attachmentMime,
                    scansEvicted: entry.scansEvicted,
                    hasExport: entry.hasExport,
                    bytes: entry.bytes,
                    damaged: entry.damaged)
            },
            totalBytes: totalBytes,
            notice: notice.map {
                LibraryEvictionNotice(pdfs: $0.pdfs, scans: $0.scans, sessions: $0.sessions)
            })
    }

    // MARK: - Atomic write (§2.7)
    //
    // The only reason a kill mid-write is survivable. `Data.write(…, .atomic)`
    // renames but does not fsync and offers no place to set the protection class
    // before the rename, so it is not used anywhere in this file.

    private func writeAtomically(_ data: Data, to target: URL) throws {
        let directory = target.deletingLastPathComponent()
        try ensureDirectory(directory)

        // Same directory as the final file. A cross-directory rename is fine on
        // one filesystem, but "same directory" removes the question entirely.
        let tmp = directory.appendingPathComponent(
            target.lastPathComponent + ".tmp-" + UUID().uuidString.lowercased())

        let attributes: [FileAttributeKey: Any] = [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ]
        guard fm.createFile(atPath: tmp.path, contents: nil, attributes: attributes) else {
            throw LibraryError.writeFailed
        }

        do {
            let handle = try FileHandle(forWritingTo: tmp)
            do {
                try handle.write(contentsOf: data)
                try handle.synchronize()   // durability of the CONTENT
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }

            // Before the rename, so the file is never visible at the final path
            // unprotected.
            try? fm.setAttributes(attributes, ofItemAtPath: tmp.path)

            guard Darwin.rename(tmp.path, target.path) == 0 else {
                throw errno == ENOSPC ? LibraryError.outOfSpace : LibraryError.writeFailed
            }

            // Durability of the RENAME. A nicety, not correctness: some
            // filesystems answer EINVAL for a directory descriptor, and that is
            // not a reason to fail a write that already landed.
            let descriptor = Darwin.open(directory.path, O_RDONLY)
            if descriptor >= 0 {
                _ = Darwin.fsync(descriptor)
                Darwin.close(descriptor)
            }
        } catch {
            try? fm.removeItem(at: tmp)   // never touch the target
            throw Self.mapped(error)
        }
    }

    private func ensureDirectory(_ url: URL) throws {
        guard !fm.fileExists(atPath: url.path) else { return }
        do {
            try fm.createDirectory(
                at: url, withIntermediateDirectories: true,
                attributes: [
                    .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
                ])
        } catch {
            throw Self.mapped(error)
        }
    }

    private static func mapped(_ error: Error) -> Error {
        if let library = error as? LibraryError { return library }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == NSFileWriteOutOfSpaceError {
            return LibraryError.outOfSpace
        }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(ENOSPC) {
            return LibraryError.outOfSpace
        }
        return LibraryError.writeFailed
    }

    // MARK: - Measuring

    /// Three flat directory listings for one session — never the whole tree.
    /// The tree is walked in exactly two situations: a rebuild, and the
    /// consistency tripwire that schedules one.
    private func measure(_ id: String) -> Int64 {
        directorySize(sessionsDir.appendingPathComponent(id, isDirectory: true))
            + directorySize(scansDir.appendingPathComponent(id, isDirectory: true))
            + directorySize(exportsDir.appendingPathComponent(id, isDirectory: true))
    }

    /// Descends, because `exports/<id>/single/` holds the one-answer sheets and
    /// a byte the budget cannot see is a byte the student loses to eviction
    /// they were never warned about. One level deep in practice.
    private func directorySize(_ url: URL) -> Int64 {
        guard let items = try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]) else { return 0 }
        return items.reduce(Int64(0)) { total, item in
            let values = try? item.resourceValues(
                forKeys: [.fileSizeKey, .isDirectoryKey])
            if values?.isDirectory == true { return total + directorySize(item) }
            return total + Int64(values?.fileSize ?? 0)
        }
    }

    // MARK: - Validation
    //
    // A manifest is a file on a device the student controls. Treat it as
    // untrusted input.

    /// Written against ASCII scalars rather than `Character.isHexDigit`, which
    /// is true for full-width and other Unicode numeric forms — none of which
    /// `UUID().uuidString.lowercased()` can produce, and all of which would be a
    /// way to smuggle a surprising directory name past this check.
    private func isSessionId(_ value: String) -> Bool {
        let scalars = Array(value.unicodeScalars)
        guard scalars.count == 36 else { return false }
        let dashes: Set<Int> = [8, 13, 18, 23]
        for (position, scalar) in scalars.enumerated() {
            if dashes.contains(position) {
                if scalar != "-" { return false }
            } else {
                let digit = scalar >= "0" && scalar <= "9"
                let hex = scalar >= "a" && scalar <= "f"
                if !digit && !hex { return false }
            }
        }
        return true
    }

    /// A stored path is opened only if it is exactly where it claims to be.
    private func resolve(path: String, sessionId: String, folder: String) -> URL? {
        guard !path.isEmpty,
              !path.contains(".."),
              !path.hasPrefix("/"),
              !path.contains("\\"),
              path.hasPrefix("\(folder)/\(sessionId)/")
        else { return nil }
        let url = root.appendingPathComponent(path)
        return fm.fileExists(atPath: url.path) ? url : nil
    }

    private func newestFile(in directory: URL, ext: String) -> URL? {
        guard let items = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return nil }
        return items
            .filter { $0.pathExtension.lowercased() == ext }
            .max { a, b in
                let left = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? Date(timeIntervalSince1970: 0)
                let right = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? Date(timeIntervalSince1970: 0)
                return left < right
            }
    }

    private func date(_ text: String) -> Date? {
        iso.date(from: text)
    }

    /// Sniffed, never trusted from the file name.
    private static func `extension`(forMime mime: String, data: Data) -> String {
        let bytes = [UInt8](data.prefix(8))
        if bytes.count >= 4, bytes[0] == 0x25, bytes[1] == 0x50,
           bytes[2] == 0x44, bytes[3] == 0x46 { return "pdf" }          // %PDF
        if bytes.count >= 3, bytes[0] == 0xFF, bytes[1] == 0xD8,
           bytes[2] == 0xFF { return "jpg" }                            // JPEG SOI
        if bytes.count >= 8, bytes[0] == 0x89, bytes[1] == 0x50,
           bytes[2] == 0x4E, bytes[3] == 0x47 { return "png" }          // \x89PNG
        if mime == "application/pdf" { return "pdf" }
        if mime == "image/png" { return "png" }
        if mime.hasPrefix("image/") { return "jpg" }
        return "bin"
    }

    /// The share sheet shows this name and Files saves under it, so it is the
    /// title — Arabic included — with only the characters a path cannot hold
    /// replaced, plus a stable timestamp.
    static func exportFileName(for title: String, stamp: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        let cleaned = title.components(separatedBy: forbidden)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = cleaned.isEmpty ? "Droob" : String(cleaned.prefix(60))
        return "\(base)-\(stamp).pdf"
    }
}

// MARK: - On-disk records
//
// Every optional has a default and every decode is lenient, so a v2 file written
// by a newer build still decodes on an older one and one bad element never fails
// the array that holds it.

/// `value` is nil when the element could not be decoded. Used to drop a bad row
/// instead of a whole file.
private struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try? container.decode(T.self)
    }
}

private extension KeyedDecodingContainer {
    func lenient<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }

    func lenientOptional<T: Decodable>(_ key: Key, _ type: T.Type) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }
}

struct EntryRecord: Codable {
    var id: String
    var title: String
    var createdAt: String
    var updatedAt: String
    var lastOpenedAt: String?
    var locale: String
    var questionCount: Int
    var answerCount: Int
    var attachmentCount: Int
    /// Additive, optional key: it decides the row icon and nothing else, so a
    /// manifest written without it simply falls back to the generic glyph.
    var attachmentMime: String?
    var scansEvicted: Bool
    var hasExport: Bool
    var bytes: Int64
    var damaged: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, createdAt, updatedAt, lastOpenedAt, locale
        case questionCount, answerCount, attachmentCount, attachmentMime
        case scansEvicted, hasExport, bytes, damaged
    }

    init(id: String, title: String, createdAt: String, updatedAt: String,
         lastOpenedAt: String?, locale: String, questionCount: Int,
         answerCount: Int, attachmentCount: Int, attachmentMime: String?,
         scansEvicted: Bool, hasExport: Bool, bytes: Int64, damaged: Bool) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastOpenedAt = lastOpenedAt
        self.locale = locale
        self.questionCount = questionCount
        self.answerCount = answerCount
        self.attachmentCount = attachmentCount
        self.attachmentMime = attachmentMime
        self.scansEvicted = scansEvicted
        self.hasExport = hasExport
        self.bytes = bytes
        self.damaged = damaged
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // The one field whose absence drops the entry: without an id there is
        // nothing on disk it can point at.
        id = try container.decode(String.self, forKey: .id)
        guard id.count == 36 else {
            throw DecodingError.dataCorruptedError(
                forKey: .id, in: container, debugDescription: "not a session id")
        }
        title = container.lenient(.title, "")
        let created = container.lenientOptional(.createdAt, String.self)
        let updated = container.lenientOptional(.updatedAt, String.self)
        createdAt = created ?? updated ?? ""
        updatedAt = updated ?? created ?? ""
        lastOpenedAt = container.lenientOptional(.lastOpenedAt, String.self)
        locale = container.lenient(.locale, "ar")
        questionCount = container.lenient(.questionCount, 0)
        answerCount = container.lenient(.answerCount, 0)
        attachmentCount = container.lenient(.attachmentCount, 0)
        attachmentMime = container.lenientOptional(.attachmentMime, String.self)
        scansEvicted = container.lenient(.scansEvicted, false)
        hasExport = container.lenient(.hasExport, false)
        bytes = container.lenient(.bytes, Int64(0))
        damaged = container.lenient(.damaged, false)
    }
}

struct NoticeRecord: Codable {
    var pdfs: Int
    var scans: Int
    var sessions: Int
    var at: String

    var isEmpty: Bool { pdfs == 0 && scans == 0 && sessions == 0 }

    init(pdfs: Int, scans: Int, sessions: Int, at: String) {
        self.pdfs = pdfs
        self.scans = scans
        self.sessions = sessions
        self.at = at
    }

    enum CodingKeys: String, CodingKey { case pdfs, scans, sessions, at }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pdfs = container.lenient(.pdfs, 0)
        scans = container.lenient(.scans, 0)
        sessions = container.lenient(.sessions, 0)
        at = container.lenient(.at, "")
    }
}

struct IndexRecord: Codable {
    var schema: Int
    var updatedAt: String
    var totalBytes: Int64
    var notice: NoticeRecord?
    var sessions: [EntryRecord]
    /// Not persisted. Non-zero means the file lost rows to the lenient decode,
    /// which is the tripwire that forces a rebuild.
    var droppedEntries: Int = 0

    enum CodingKeys: String, CodingKey {
        case schema, updatedAt, totalBytes, notice, sessions
    }

    init(schema: Int, updatedAt: String, totalBytes: Int64,
         notice: NoticeRecord?, sessions: [EntryRecord]) {
        self.schema = schema
        self.updatedAt = updatedAt
        self.totalBytes = totalBytes
        self.notice = notice
        self.sessions = sessions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = container.lenient(.schema, 0)
        updatedAt = container.lenient(.updatedAt, "")
        totalBytes = container.lenient(.totalBytes, Int64(-1))
        notice = container.lenientOptional(.notice, NoticeRecord.self)
        let raw = container.lenient(.sessions, [Lenient<EntryRecord>]())
        sessions = raw.compactMap { $0.value }
        droppedEntries = raw.count - sessions.count
    }
}

struct MessageRecord: Codable {
    var id: String
    var role: String
    var text: String
    var at: String
    var provider: String?

    init(id: String, role: String, text: String, at: String, provider: String?) {
        self.id = id
        self.role = role
        self.text = text
        self.at = at
        self.provider = provider
    }

    enum CodingKeys: String, CodingKey { case id, role, text, at, provider }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)
        // The text is the point of the record; an entry without it is noise.
        text = try container.decode(String.self, forKey: .text)
        id = container.lenient(.id, UUID().uuidString)
        at = container.lenient(.at, "")
        provider = container.lenientOptional(.provider, String.self)
    }
}

struct AttachmentRecord: Codable {
    var id: String
    var path: String
    var name: String
    var mime: String
    var bytes: Int64
    var pages: Int
    var at: String

    init(id: String, path: String, name: String, mime: String,
         bytes: Int64, pages: Int, at: String) {
        self.id = id
        self.path = path
        self.name = name
        self.mime = mime
        self.bytes = bytes
        self.pages = pages
        self.at = at
    }

    enum CodingKeys: String, CodingKey {
        case id, path, name, mime, bytes, pages, at
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        id = container.lenient(.id, UUID().uuidString.lowercased())
        name = container.lenient(.name, "")
        mime = container.lenient(.mime, "application/octet-stream")
        bytes = container.lenient(.bytes, Int64(0))
        pages = container.lenient(.pages, 0)
        at = container.lenient(.at, "")
    }
}

struct ExportRecord: Codable {
    var path: String
    var bytes: Int64
    var problemCount: Int
    var at: String

    init(path: String, bytes: Int64, problemCount: Int, at: String) {
        self.path = path
        self.bytes = bytes
        self.problemCount = problemCount
        self.at = at
    }

    enum CodingKeys: String, CodingKey { case path, bytes, problemCount, at }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        bytes = container.lenient(.bytes, Int64(0))
        problemCount = container.lenient(.problemCount, 0)
        at = container.lenient(.at, "")
    }
}

struct SessionRecord: Codable {
    var schema: Int = 1
    var id: String
    var title: String
    var createdAt: String
    var updatedAt: String
    var locale: String
    var messages: [MessageRecord]
    var attachments: [AttachmentRecord]
    var export: ExportRecord?
    var scansEvicted: Bool

    init(id: String, title: String, createdAt: String, updatedAt: String,
         locale: String, messages: [MessageRecord],
         attachments: [AttachmentRecord], export: ExportRecord?,
         scansEvicted: Bool) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.locale = locale
        self.messages = messages
        self.attachments = attachments
        self.export = export
        self.scansEvicted = scansEvicted
    }

    enum CodingKeys: String, CodingKey {
        case schema, id, title, createdAt, updatedAt, locale
        case messages, attachments, export, scansEvicted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        schema = container.lenient(.schema, 1)
        title = container.lenient(.title, "")
        let created = container.lenientOptional(.createdAt, String.self)
        let updated = container.lenientOptional(.updatedAt, String.self)
        createdAt = created ?? updated ?? ""
        updatedAt = updated ?? created ?? ""
        locale = container.lenient(.locale, "ar")
        messages = container.lenient(.messages, [Lenient<MessageRecord>]())
            .compactMap { $0.value }
        attachments = container.lenient(.attachments, [Lenient<AttachmentRecord>]())
            .compactMap { $0.value }
        export = container.lenientOptional(.export, ExportRecord.self)
        scansEvicted = container.lenient(.scansEvicted, false)
    }
}
