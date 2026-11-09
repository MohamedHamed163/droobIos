import SwiftUI

/// Read-only list of document attachments shared in the room. Search
/// is client-side over filenames; the server returns the full list.
struct DocumentsView: View {
    let roomId: String
    /// Optional override for the "Add" CTA. When nil (the default and
    /// the only path in use today), the screen drives its own document
    /// picker + upload + room-send flow. Passing a closure lets a
    /// future caller substitute a different picker (e.g. a host that
    /// wants to route through a course-scoped attachment library) — in
    /// that case this view emits the tap and the caller takes over.
    ///
    /// Previous shape: `var onAddDocument: () -> Void = {}`. That made
    /// "no caller passed a handler" indistinguishable from "the caller
    /// passed an explicit no-op", and every real caller (just
    /// RoomSettingsView) hit the silent-no-op default. Switching to
    /// `Optional` lets us tell the two apart and removes the dead
    /// button.
    var onAddDocument: (() -> Void)? = nil
    /// When the room is CLOSED the documents list is read-only — the
    /// server rejects uploads — so the "Add" affordances are dropped.
    /// Defaults to `false` so existing/active callers are unaffected.
    var isRoomClosed: Bool = false

    @State private var docs: [RoomDocument] = []
    @State private var search: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    /// Drives presentation of `DocumentPicker` (UIDocumentPickerViewController
    /// wrapper from the chat sheet). Tapping the empty-state CTA flips
    /// this true; the picker's coordinator hands back a `PickedAttachment`
    /// which we upload and post into the room.
    @State private var showPicker: Bool = false
    /// True while the multipart upload + send-message round trip is in
    /// flight. Used to disable the CTA so a fat-finger double tap can't
    /// fire two uploads of the same file.
    @State private var isUploading: Bool = false

    /// True once the user has typed a non-blank query. Drives the
    /// header count (matches vs room total) and the no-results state.
    private var isSearching: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var filtered: [RoomDocument] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !q.isEmpty else { return docs }
        return docs.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    headerRow

                    if isLoading && docs.isEmpty {
                        HStack { ProgressView().tint(MyCoursesPalette.accent); Spacer() }
                            .padding(.vertical, 40)
                    } else if docs.isEmpty {
                        emptyState
                    } else if filtered.isEmpty {
                        // Room has documents but the active search
                        // matched none — show a results-specific empty
                        // state instead of an empty list card.
                        noResultsState
                    } else {
                        list
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        // `studyRoomsSearchPlaceholder` reads "Search rooms" — correct
        // on the rooms-list screen, wrong here where we're already
        // inside one room filtering its files. Use the documents-
        // specific copy so the placeholder matches what the field
        // actually filters.
        .searchable(text: $search, prompt: L10n.studyRoomsDocumentsSearchPlaceholder)
        // System file picker hosted as a sheet so the OS UI doesn't
        // fight with our dark theme overlay. The reusable bridge lives
        // in `ChatAttachmentSheet.swift`; both the chat composer's "+"
        // button and this CTA share its security-scoped-URL handling.
        .sheet(isPresented: $showPicker) {
            DocumentPicker { picked in
                showPicker = false
                Task { await uploadAndPost(picked) }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(L10n.studyRoomsDocumentsTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.accent)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    /// Big-illustration empty state with a gold "Add the first
    /// document" CTA pinned to the bottom of the safe area. The CTA
    /// calls `onAddDocument`; for v1 the parent leaves it as a no-op
    /// (matching the disabled + in the chat composer). Once the
    /// attachment picker ships, the same callback gets wired and both
    /// surfaces fire it.
    private var emptyState: some View {
        VStack {
            Spacer().frame(height: 60)
            ZStack {
                Circle()
                    .fill(Color.droobGold.opacity(0.10))
                    .frame(width: 110, height: 110)
                Image(systemName: "doc")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.accent)
                // The "+" badge advertises adding files — drop it in a
                // read-only ended room.
                if !isRoomClosed {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(MyCoursesPalette.accent)
                        .offset(x: 18, y: 18)
                }
            }
            .padding(.bottom, 14)

            Text(isRoomClosed
                 ? L10n.studyRoomsDocumentsEmptyClosedTitle
                 : L10n.studyRoomsDocumentsEmptyTitle)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(MyCoursesPalette.textPrimary)
            Text(isRoomClosed
                 ? L10n.studyRoomsDocumentsEmptyClosedSubtitle
                 : L10n.studyRoomsDocumentsEmptySubtitle)
                .font(.system(size: 13))
                .foregroundColor(MyCoursesPalette.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .padding(.top, 4)
            // The filter hint ("PDF · PPT · Word only") only matters
            // when you can upload, so hide it for ended rooms.
            if !isRoomClosed {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                    Text(L10n.studyRoomsDocumentsFilter)
                        .font(.system(size: 11))
                }
                .foregroundColor(MyCoursesPalette.muted)
                .padding(.top, 8)
            }

            Spacer()

            // Uploads are rejected once the room is closed, so the CTA
            // is removed entirely rather than left to fail on tap.
            if !isRoomClosed {
                Button(action: addDocumentTapped) {
                    HStack(spacing: 8) {
                        if isUploading {
                            ProgressView()
                                .tint(.black)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        Text(L10n.studyRoomsDocumentsEmptyCta)
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(
                                colors: [Color.droobGold,
                                         Color.droobGold.opacity(0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing)))
                }
                .buttonStyle(.plain)
                .disabled(isUploading)
                .opacity(isUploading ? 0.7 : 1)
                .padding(.top, 12)
            }
            if let err = errorMessage {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundColor(MyCoursesPalette.danger)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 480)
    }

    private var headerRow: some View {
        HStack {
            Text(countLabel)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundColor(MyCoursesPalette.muted)
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                Text(L10n.studyRoomsDocumentsFilter)
                    .font(.system(size: 11))
            }
            .foregroundColor(MyCoursesPalette.muted)
        }
    }

    /// Count label above the list. While a search is active it reflects
    /// the number of matches (so it reads "0 FOUND" on a miss rather
    /// than the misleading room total); otherwise it shows the full
    /// room document count.
    private var countLabel: String {
        if isSearching {
            return String(format: L10n.studyRoomsDocumentsFoundFmt,
                          filtered.count)
        }
        return docs.count == 1
            ? L10n.studyRoomsDocumentsOneFmt
            : String(format: L10n.studyRoomsDocumentsCountFmt, docs.count)
    }

    /// Shown when the room has documents but the current search matched
    /// none. Echoes the query so it's clear what was searched.
    private var noResultsState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 34))
                .foregroundColor(MyCoursesPalette.textTertiary)
            Text(L10n.studyRoomsDocumentsNoResultsTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(MyCoursesPalette.textPrimary)
            Text(String(format: L10n.studyRoomsDocumentsNoResultsSubtitleFmt,
                        search.trimmingCharacters(in: .whitespacesAndNewlines)))
                .font(.system(size: 13))
                .foregroundColor(MyCoursesPalette.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(Array(filtered.enumerated()), id: \.element.messageId) { idx, d in
                row(d)
                if idx < filtered.count - 1 {
                    Divider().background(MyCoursesPalette.stroke)
                        .padding(.leading, 78)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MyCoursesPalette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(MyCoursesPalette.stroke, lineWidth: 1))
        )
    }

    @ViewBuilder
    private func row(_ d: RoomDocument) -> some View {
        HStack(spacing: 12) {
            FileTypeIcon(typeTag: d.typeTag)
                .frame(width: 50, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(d.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    FileTypeBadge(typeTag: d.typeTag)
                }
                Text(uploaderLine(d))
                    .font(.system(size: 11))
                    .foregroundColor(MyCoursesPalette.muted)
            }
            Spacer()
            if let url = URL(string: d.downloadUrl) {
                Link(destination: url) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 20))
                        .foregroundColor(MyCoursesPalette.accent.opacity(0.85))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func uploaderLine(_ d: RoomDocument) -> String {
        let sizeText: String = d.sizeBytes.map {
            L10n.fileSize(Int64($0))
        } ?? "—"
        // Uploader names are often Latin while the size is "2.4 MB" —
        // without isolating each part the RTL line tears the number away
        // from its unit ("MB 2.4").
        return bidiJoin(d.uploaderName, sizeText)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            docs = try await StudyRoomsAPI.listDocuments(roomId: roomId)
        } catch { errorMessage = error.localizedDescription }
    }

    /// Empty-state CTA action. Defers to the host-provided closure
    /// when one was passed (so a future override path can take over),
    /// otherwise drives the in-screen file picker. Previously the
    /// default was a no-op closure, so the button looked clickable but
    /// did nothing — the root cause of this bug.
    private func addDocumentTapped() {
        // Drop any previous attempt's error so a fresh tap shows a
        // clean state until the new flow either succeeds or fails.
        errorMessage = nil
        if let override = onAddDocument {
            override()
            return
        }
        showPicker = true
    }

    /// Uploads the picked file to the chat-attachment endpoint, then
    /// posts it as a `DOCUMENT` message in this room. The same two-step
    /// (upload → send) pipeline the chat composer uses; reused so the
    /// document lands as a real room message and shows up here on the
    /// next `listDocuments` fetch.
    ///
    /// Failures surface inline in `errorMessage` — the empty-state
    /// CTA renders it directly under the button. We deliberately don't
    /// alert: the error copy lives in the same visual block as the
    /// retry affordance, so users see "tap failed → message → tap
    /// again" without a modal in the middle.
    private func uploadAndPost(_ picked: PickedAttachment) async {
        isUploading = true
        errorMessage = nil
        defer { isUploading = false }
        do {
            let upload = try await ChatAttachmentUploader.upload(
                data: picked.data,
                filename: picked.filename,
                contentType: picked.contentType)
            // `sendAttachment` is a room-scoped call — it both
            // persists the message and broadcasts it through the room
            // socket so other members see it. Using `.document` here
            // (vs the picker's `isImage` flag) because this surface
            // is the Documents tab; an image picked through the
            // system files app would also land as a document, which
            // matches user intent in this context.
            _ = try await StudyRoomsAPI.sendAttachment(
                roomId: roomId,
                body: nil,
                type: .document,
                key: upload.attachmentKey,
                name: upload.attachmentName,
                sizeBytes: Int(upload.attachmentSizeBytes),
                durationSeconds: nil)
            await load()
        } catch let e as ChatAttachmentUploader.UploadError {
            errorMessage = e.errorDescription
        } catch let e as DroobError {
            if case .unauthenticated = e {
                await AuthSession.shared.handleUnauthenticated()
            } else {
                errorMessage = e.errorDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - File-type chrome

/// Coloured icon tile reflecting the document type. PDF = red, DOC =
/// blue, PPT = orange, XLS = green, TXT/OTHER = neutral. Matches the
/// figma colour-coding.
private struct FileTypeIcon: View {
    let typeTag: String
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(colour.opacity(0.22))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(colour.opacity(0.40), lineWidth: 1))
            Image(systemName: "doc.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(colour)
        }
    }
    private var colour: Color {
        switch typeTag {
        case "PDF": return Color(red: 0.95, green: 0.40, blue: 0.40)
        case "DOC": return Color(red: 0.30, green: 0.55, blue: 0.95)
        case "PPT": return Color(red: 0.95, green: 0.62, blue: 0.20)
        case "XLS": return Color(red: 0.30, green: 0.78, blue: 0.40)
        default:    return Color(red: 0.75, green: 0.70, blue: 0.60)
        }
    }
}

private struct FileTypeBadge: View {
    let typeTag: String
    var body: some View {
        Text(typeTag)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(colour)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(colour.opacity(0.18)))
    }
    private var colour: Color {
        switch typeTag {
        case "PDF": return Color(red: 0.95, green: 0.40, blue: 0.40)
        case "DOC": return Color(red: 0.30, green: 0.55, blue: 0.95)
        case "PPT": return Color(red: 0.95, green: 0.62, blue: 0.20)
        case "XLS": return Color(red: 0.30, green: 0.78, blue: 0.40)
        default:    return Color(red: 0.75, green: 0.70, blue: 0.60)
        }
    }
}
