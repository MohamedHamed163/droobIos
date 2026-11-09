import SwiftUI

// MARK: - Chat (1:1 student ↔ instructor)
//
// Pushed from the "Message" CTA on the instructor profile screen. The
// flow opens by instructor id rather than thread id so a student who
// has never messaged this instructor lands on an empty conversation
// instead of seeing a "create" step. The backend's GET-by-instructor
// endpoint returns the existing thread's messages (if any) or an empty
// envelope, both with the instructor's display name + initials
// populated so the header renders on first paint.
//
// Bubbles use the figma's two-tone treatment: instructor on the left
// in a dark surface bubble, student on the right in a gold bubble with
// dark text. Day separators ("Today" / "Yesterday" / "May 14") slot
// between groups of messages from different days; per-bubble
// timestamps appear under each one. The last sent bubble shows
// "Seen {time}" when read.

struct InstructorChatView: View {
    let instructorId: String
    let instructorName: String
    /// Presigned instructor avatar URL seeded by the caller (inbox row /
    /// instructor profile). The header prefers the ViewModel's resolved
    /// value and falls back to this, then to initials.
    let instructorAvatarUrl: String?

    @StateObject private var viewModel: InstructorChatViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code

    @State private var draft: String = ""
    @State private var didScrollToBottom = false
    @State private var showAttachmentSheet = false
    /// Pending attachment uploaded but not yet sent — drives the
    /// composer preview pill above the input. Nil when no attachment
    /// is queued. Cleared after a successful send.
    @State private var pendingAttachment: ChatAttachmentUpload? = nil
    /// True between picker selection and the `attachment_key` coming
    /// back from the upload endpoint; the composer shows a spinner so
    /// the user doesn't tap send before the key is available.
    @State private var isUploading = false
    @State private var uploadError: String? = nil
    /// Captured duration of the recording-in-flight — passed alongside
    /// the upload payload when the recording ships so the backend
    /// receives `attachment_duration_seconds`.
    @State private var pendingVoiceDuration: Int? = nil
    @StateObject private var recorder = VoiceNoteRecorder()
    @State private var showMicPermissionAlert = false
    @State private var recordingPulse = false
    @State private var previewImage: ImagePreviewItem? = nil

    /// Thread id known at construction (Messages-tab / push entry). Nil for the
    /// instructor-profile entry, where the thread may not exist yet — in that
    /// case the active conversation is registered once the load resolves it.
    private let initialThreadId: String?
    /// True when this chat was pushed from `InstructorProfileView`. The
    /// header's identity tap then pops back to the profile already on the
    /// stack instead of pushing a duplicate copy of it.
    private let openedFromProfile: Bool
    /// Conversation id currently registered for foreground push suppression.
    @State private var registeredThreadId: String? = nil

    init(instructorId: String, instructorName: String,
         instructorAvatarUrl: String? = nil,
         threadId: String? = nil,
         openedFromProfile: Bool = false,
         viewModelOverride: InstructorChatViewModel? = nil) {
        self.instructorId = instructorId
        self.instructorName = instructorName
        self.instructorAvatarUrl = instructorAvatarUrl
        self.initialThreadId = threadId
        self.openedFromProfile = openedFromProfile
        _viewModel = StateObject(
            wrappedValue: viewModelOverride ?? InstructorChatViewModel(
                instructorId: instructorId,
                instructorName: instructorName,
                avatarUrl: instructorAvatarUrl,
                threadId: threadId))
    }

    /// Mark the resolved thread as on-screen so a push for it is suppressed
    /// (WhatsApp-style), and clear its tray notifications. Re-points cleanly if
    /// the id resolves after the view appears.
    private func registerActiveThread(_ id: String?) {
        guard let id, !id.isEmpty, id != registeredThreadId else { return }
        if let prev = registeredThreadId { PushService.shared.leaveConversation(prev) }
        registeredThreadId = id
        PushService.shared.enterConversation(id)
    }

    private var ar: Bool { appLocale == "ar" }

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Divider().background(MyCoursesPalette.stroke)
                messagesScroll
                composer
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        // The composer's send button sits in the same bottom-trailing
        // corner as the tab bar's AI orb, which overlays every screen
        // pushed inside a tab. Stand the orb down while this chat is up.
        .hidesAiTutorOrb()
        .task { await viewModel.load() }
        .onAppear { registerActiveThread(viewModel.threadId ?? initialThreadId) }
        .onChange(of: viewModel.threadId) { newId in registerActiveThread(newId) }
        .onDisappear {
            viewModel.stopPolling()
            if let id = registeredThreadId { PushService.shared.leaveConversation(id) }
        }
        .sheet(isPresented: $showAttachmentSheet) {
            attachmentSheetContent
        }
        .fullScreenCover(item: $previewImage) { item in
            ImagePreviewView(url: item.url) { previewImage = nil }
        }
    }

    @ViewBuilder
    private var attachmentSheetContent: some View {
        let sheet = ChatAttachmentSheet(
            onPicked: { picked in handlePicked(picked) },
            onClose: { showAttachmentSheet = false })
        if #available(iOS 16.0, *) {
            sheet
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.hidden)
        } else {
            sheet
        }
    }

    /// Bridges a picker result into the composer:
    /// 1. Show a placeholder preview immediately.
    /// 2. Upload bytes through `ChatAttachmentUploader`.
    /// 3. On success, swap the placeholder for the real upload payload
    ///    (so send can include the opaque key). On failure, surface the
    ///    error inline and clear the preview.
    private func handlePicked(_ picked: PickedAttachment) {
        showAttachmentSheet = false
        uploadError = nil
        isUploading = true
        Task {
            do {
                let upload = try await ChatAttachmentUploader.upload(
                    data: picked.data,
                    filename: picked.filename,
                    contentType: picked.contentType)
                await MainActor.run {
                    pendingAttachment = upload
                    isUploading = false
                }
            } catch {
                await MainActor.run {
                    uploadError = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                    isUploading = false
                    pendingAttachment = nil
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: ar ? "chevron.right" : "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color.droobGold)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

            headerIdentity

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Avatar + name + activity. Tapping opens the instructor's profile —
    /// no visual affordance, same as Messages/WhatsApp. Inert when the
    /// caller couldn't supply an instructor id (nothing to route to).
    @ViewBuilder
    private var headerIdentity: some View {
        if instructorId.isEmpty {
            headerIdentityLabel
        } else if openedFromProfile {
            // Came from the profile — pop back to it rather than pushing a
            // second copy onto the stack.
            Button { dismiss() } label: { headerIdentityLabel }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isButton)
        } else {
            NavigationLink {
                InstructorProfileView(instructorId: instructorId)
            } label: { headerIdentityLabel }
            .buttonStyle(.plain)
        }
    }

    private var headerIdentityLabel: some View {
        HStack(spacing: 12) {
            ReviewAvatar(name: instructorName,
                         avatarUrl: viewModel.instructorAvatarUrl ?? instructorAvatarUrl)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.instructorName ?? instructorName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                if let activity = viewModel.activityLabel {
                    Text(activity)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(MyCoursesPalette.success)
                }
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: Messages

    private var messagesScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(grouped, id: \.id) { group in
                        daySeparator(group.day)
                        ForEach(group.messages) { msg in
                            bubble(for: msg, isLast: msg.id == viewModel.messages.last?.id)
                                .id(msg.id)
                        }
                    }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
            }
            .onChange(of: viewModel.messages.count) { _ in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onAppear {
                // Initial pin to the bottom — only once per appearance.
                if !didScrollToBottom {
                    didScrollToBottom = true
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private func daySeparator(_ day: String) -> some View {
        Text(day)
            .font(.system(size: 11, weight: .regular))
            .foregroundColor(MyCoursesPalette.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(MyCoursesPalette.surface)
            .clipShape(Capsule())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }

    // MARK: Bubble

    @ViewBuilder
    private func bubble(for msg: DirectMessage, isLast: Bool) -> some View {
        let outgoing = !msg.fromInstructor
        HStack(alignment: .bottom, spacing: 8) {
            if outgoing {
                Spacer(minLength: 50)
            } else {
                // 1:1 chat — every incoming bubble is this instructor, so
                // reuse the resolved header avatar (initials fallback).
                ReviewAvatar(name: msg.senderName,
                             avatarUrl: viewModel.instructorAvatarUrl ?? instructorAvatarUrl)
                    .frame(width: 22, height: 22)
            }
            VStack(alignment: outgoing ? .trailing : .leading, spacing: 6) {
                // Image attachment renders as a square thumbnail at the
                // top of the bubble stack; document attachment renders
                // as a chip with filename + size. Both can coexist with
                // a body caption underneath.
                if msg.isImageAttachment, let url = msg.attachmentUrl.flatMap(URL.init(string:)) {
                    imageAttachmentBubble(url: url, outgoing: outgoing)
                } else if msg.isDocumentAttachment {
                    documentAttachmentChip(msg: msg, outgoing: outgoing)
                } else if msg.isVoiceAttachment,
                          let url = msg.attachmentUrl.flatMap(URL.init(string:)) {
                    VoiceNoteBubble(
                        url: url,
                        messageId: msg.messageId,
                        totalSeconds: msg.attachmentDurationSeconds ?? 0,
                        outgoing: outgoing)
                }
                if let body = msg.body, !body.isEmpty {
                    Text(body)
                        .font(.system(size: 14, weight: outgoing ? .semibold : .regular))
                        .foregroundColor(outgoing
                                         ? Color(red: 0.08, green: 0.06, blue: 0.04)
                                         : .primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(bubbleBackground(outgoing: outgoing))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 4) {
                    Text(formattedClock(msg.sentAt))
                    if outgoing, isLast, let readAt = msg.readAt {
                        Text("·")
                        Text(String(format: L10n.chatSeenFmt, formattedClock(readAt)))
                    }
                }
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(MyCoursesPalette.muted)
            }
            if !outgoing { Spacer(minLength: 50) }
        }
    }

    /// Image bubble — square thumbnail loaded directly from the
    /// presigned URL the backend mints into `attachment_url`. Tap to
    /// open the full-resolution preview.
    private func imageAttachmentBubble(url: URL, outgoing: Bool) -> some View {
        Button {
            previewImage = ImagePreviewItem(url: url)
        } label: {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                case .failure:
                    Color.gray.opacity(0.2)
                default:
                    ZStack {
                        Color.gray.opacity(0.15)
                        ProgressView().tint(Color.droobGold)
                    }
                }
            }
            .frame(width: 220, height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(outgoing
                            ? Color.black.opacity(0.1)
                            : MyCoursesPalette.stroke,
                            lineWidth: 1))
            // Pin the hit region to the visible thumbnail. Without this
            // the AsyncImage's hit shape is ambiguous and SwiftUI can
            // route a tap on a neighbouring bubble (e.g. the voice note
            // above) back to this button after a fullScreenCover dismiss
            // — which re-opens the image instead of toggling playback.
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Document chip — filename + formatted size + paperclip icon. Tap
    /// opens the file in the system viewer (Safari handles PDFs etc).
    private func documentAttachmentChip(msg: DirectMessage, outgoing: Bool) -> some View {
        Button {
            if let url = msg.attachmentUrl.flatMap(URL.init(string:)) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 16))
                    .foregroundColor(outgoing
                                     ? Color(red: 0.08, green: 0.06, blue: 0.04)
                                     : Color.droobGold)
                VStack(alignment: .leading, spacing: 2) {
                    Text(msg.attachmentName ?? L10n.chatDocumentDefault)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(outgoing
                                         ? Color(red: 0.08, green: 0.06, blue: 0.04)
                                         : .primary)
                        .lineLimit(1)
                    Text(formatBytes(msg.attachmentSizeBytes ?? 0))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(outgoing
                                         ? Color(red: 0.08, green: 0.06, blue: 0.04).opacity(0.7)
                                         : MyCoursesPalette.muted)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: 220, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(bubbleBackground(outgoing: outgoing))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// File size for the chip subtitle, in the app's language.
    private func formatBytes(_ bytes: Int64) -> String {
        L10n.fileSize(bytes)
    }

    private func bubbleBackground(outgoing: Bool) -> some ShapeStyle {
        if outgoing {
            return AnyShapeStyle(LinearGradient.droobBrand)
        } else {
            return AnyShapeStyle(MyCoursesPalette.surface)
        }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: 6) {
            // Pending-attachment preview sits above the input row so
            // the user sees the file they're about to send and can
            // pull the X to back out.
            if let pending = pendingAttachment {
                attachmentPreview(pending)
            } else if isUploading {
                uploadingPreview
            }
            if let err = uploadError {
                Text(err)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
            }
            // Recording swaps the whole composer for a live recording
            // bar — text input + attachment button don't make sense
            // mid-record.
            if recorder.isRecording {
                recordingBar
            } else {
                inputRow
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .alert(L10n.chatVoiceMicDeniedTitle,
               isPresented: $showMicPermissionAlert) {
            Button(L10n.chatVoiceMicDeniedOk, role: .cancel) {}
        } message: {
            Text(L10n.chatVoiceMicDeniedBody)
        }
    }

    private var inputRow: some View {
        HStack(spacing: 10) {
                // Pill input.
                HStack {
                    TextField("", text: $draft,
                              prompt: Text(L10n.chatComposerPlaceholder)
                                .foregroundColor(MyCoursesPalette.muted))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.primary)
                        .submitLabel(.send)
                        .onSubmit { send() }
                    // Mic icon — tap to start a voice recording.
                    Button {
                        Task { await startRecording() }
                    } label: {
                        Image(systemName: "mic")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(MyCoursesPalette.muted)
                    }
                    .buttonStyle(.plain)
                    .disabled(isUploading || pendingAttachment != nil)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(MyCoursesPalette.surface)
                .clipShape(Capsule())

                // Attachments — opens the Gallery / Documents sheet.
                Button { showAttachmentSheet = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.muted)
                        .frame(width: 38, height: 38)
                        .background(MyCoursesPalette.surface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isUploading)

                Button { send() } label: {
                    sendButtonLabel
                }
                .buttonStyle(.plain)
                .disabled(canSend == false)
        }
    }

    /// Two-tone send button: dark-on-gold gradient when active, muted
    /// chevron on the same surface as the other circular buttons when
    /// disabled. Previously we dropped opacity to 0.5 on the whole
    /// view which made the dark arrow blend into the dimmed gradient
    /// and read as a featureless dark circle on this dark UI.
    private var sendButtonLabel: some View {
        Group {
            if canSend {
                Image(systemName: ar ? "arrow.left" : "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 0.08, green: 0.06, blue: 0.04))
                    .frame(width: 38, height: 38)
                    .background(LinearGradient.droobBrand)
                    .clipShape(Circle())
            } else {
                Image(systemName: ar ? "arrow.left" : "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(MyCoursesPalette.muted)
                    .frame(width: 38, height: 38)
                    .background(MyCoursesPalette.surface)
                    .clipShape(Circle())
            }
        }
    }

    /// Replaces the input row mid-recording. Shows a red recording
    /// dot, the live elapsed timer, a cancel (×) to discard, and a
    /// gold send (↑) to stop + upload + send.
    private var recordingBar: some View {
        HStack(spacing: 12) {
            Button {
                recorder.cancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.muted)
                    .frame(width: 36, height: 36)
                    .background(MyCoursesPalette.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .opacity(recordingPulse ? 1.0 : 0.3)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                               value: recordingPulse)
                    .onAppear { recordingPulse = true }
                Text(formatDuration(Int(recorder.elapsed)))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                Text(L10n.chatVoiceRecording)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(MyCoursesPalette.muted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(MyCoursesPalette.surface)
            .clipShape(Capsule())

            Button {
                Task { await finishRecording() }
            } label: {
                Image(systemName: ar ? "arrow.left" : "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 0.08, green: 0.06, blue: 0.04))
                    .frame(width: 38, height: 38)
                    .background(LinearGradient.droobBrand)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    /// In-flight preview pill while we wait for the upload's
    /// `attachment_key` to come back. Disables the send button (via
    /// `canSend`) so the user can't fire before the key is available.
    private var uploadingPreview: some View {
        HStack(spacing: 10) {
            ProgressView().tint(Color.droobGold)
            Text(L10n.chatAttachmentUploading)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(MyCoursesPalette.muted)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(MyCoursesPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Settled preview after upload — shows the thumbnail for images
    /// or a doc chip for files, plus an X to drop the attachment.
    private func attachmentPreview(_ pending: ChatAttachmentUpload) -> some View {
        HStack(spacing: 10) {
            if pending.attachmentType == "IMAGE",
               let url = URL(string: pending.attachmentUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Color.gray.opacity(0.2)
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.droobGold.opacity(0.15))
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color.droobGold)
                }
                .frame(width: 40, height: 40)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(pending.attachmentName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(formatBytes(pending.attachmentSizeBytes))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(MyCoursesPalette.muted)
            }
            Spacer()
            Button { pendingAttachment = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.muted)
                    .frame(width: 24, height: 24)
                    .background(MyCoursesPalette.background)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(MyCoursesPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MyCoursesPalette.stroke, lineWidth: 1))
    }

    /// Send is enabled when there's *something* to send (text or
    /// attachment) AND we're not mid-upload or mid-send.
    private var canSend: Bool {
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachment = pendingAttachment != nil
        return (hasText || hasAttachment) && !viewModel.isSending && !isUploading
    }

    private func send() {
        let body = draft
        let attachment = pendingAttachment
        let voiceDuration = pendingVoiceDuration
        draft = ""
        pendingAttachment = nil
        pendingVoiceDuration = nil
        Task { await viewModel.send(
            body: body,
            attachment: attachment,
            voiceDurationSeconds: voiceDuration) }
    }

    // MARK: Voice recording flow

    /// Mic-tap entry point. Asks for permission via the recorder, then
    /// kicks off recording. Surfaces the permission-denied alert if
    /// the user previously denied + closes the recording bar
    /// gracefully if `start()` returns false for any other reason.
    private func startRecording() async {
        // Don't let a stale upload error linger over the recording bar.
        uploadError = nil
        let ok = await recorder.start()
        if !ok {
            if recorder.permissionDenied {
                showMicPermissionAlert = true
            }
        }
    }

    /// Stop button on the recording bar. Closes the recording, uploads
    /// the bytes, then immediately submits the message — voice notes
    /// don't carry a separate "send" tap. Empty / zero-duration
    /// recordings are dropped silently.
    private func finishRecording() async {
        guard let recording = await recorder.stop() else { return }
        guard recording.durationSeconds > 0 else { return }
        uploadError = nil
        isUploading = true
        defer { isUploading = false }
        do {
            let upload = try await ChatAttachmentUploader.upload(
                data: recording.data,
                filename: recording.filename,
                contentType: recording.contentType)
            // Send straight away — different from images/documents
            // where the user usually wants to type a caption first.
            pendingAttachment = upload
            pendingVoiceDuration = recording.durationSeconds
            send()
        } catch {
            uploadError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func formatDuration(_ s: Int) -> String {
        String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: Day grouping

    /// Buckets messages into per-day groups for the "Today" / "Yesterday"
    /// / "May 14" separators. Day key is locale-aware so Arabic gets the
    /// right calendar.
    private var grouped: [DayGroup] {
        let calendar = Calendar.current
        var out: [DayGroup] = []
        for msg in viewModel.messages {
            let day = startOfDay(for: msg.sentAt, calendar: calendar)
            if let last = out.last, calendar.isDate(last.date, inSameDayAs: day) {
                out[out.count - 1].messages.append(msg)
            } else {
                out.append(DayGroup(date: day, label: dayLabel(for: day), messages: [msg]))
            }
        }
        return out
    }

    private struct DayGroup {
        let date: Date
        let label: String
        var messages: [DirectMessage]
        var day: String { label }
        var id: String { ISO8601DateFormatter().string(from: date) }
    }

    private func startOfDay(for date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: date)
    }

    private func dayLabel(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return L10n.chatDayToday }
        if cal.isDateInYesterday(date) { return L10n.chatDayYesterday }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: appLocale)
        fmt.setLocalizedDateFormatFromTemplate("MMM d")
        return fmt.string(from: date)
    }

    private func formattedClock(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: appLocale)
        fmt.dateFormat = "h:mm a"
        return fmt.string(from: date)
    }
}

// MARK: - ViewModel

@MainActor
final class InstructorChatViewModel: ObservableObject {
    let instructorId: String
    let initialName: String
    /// Avatar URL seeded by the caller (inbox row / instructor profile)
    /// so the header shows a picture immediately, before the
    /// thread-messages fetch resolves. Nil when the caller doesn't know it.
    let initialAvatarUrl: String?
    /// Set when the chat is opened from the Messages-tab inbox, which
    /// knows the thread id up front. Drives the load through the
    /// by-thread endpoint so the student's unread counter is reset
    /// server-side (the by-instructor endpoint deliberately doesn't).
    /// Nil for the instructor-profile entry, where the thread may not
    /// exist yet.
    let initialThreadId: String?

    @Published var messages: [DirectMessage] = []
    @Published var instructorName: String?
    /// Resolved instructor avatar URL. Seeded from `initialAvatarUrl`, then
    /// refreshed from the thread-messages response. Drives the header
    /// avatar; nil/blank falls back to initials.
    @Published var instructorAvatarUrl: String?
    @Published var threadId: String?
    @Published var lastActiveAt: Date?
    @Published var isLoading = true
    @Published var isSending = false

    private var pollTask: Task<Void, Never>?

    init(instructorId: String, instructorName: String,
         avatarUrl: String? = nil, threadId: String? = nil) {
        self.instructorId = instructorId
        self.initialName = instructorName
        self.instructorName = instructorName
        self.initialAvatarUrl = avatarUrl
        self.instructorAvatarUrl = avatarUrl
        self.initialThreadId = threadId
    }

    /// "Active now" / "Active 5m ago" derived from `lastActiveAt`. Nil
    /// when the column hasn't been populated yet.
    var activityLabel: String? {
        guard let lastActiveAt else { return nil }
        let elapsed = Date().timeIntervalSince(lastActiveAt)
        if elapsed < 300 { return L10n.instructorProfileActiveNow }
        if elapsed < 3600 { return String(format: L10n.instructorProfileActiveMinFmt, Int(elapsed / 60)) }
        if elapsed < 86_400 { return String(format: L10n.instructorProfileActiveHourFmt, Int(elapsed / 3600)) }
        return String(format: L10n.instructorProfileActiveDayFmt, Int(elapsed / 86_400))
    }

    func load() async {
        isLoading = true
        await fetch()
        isLoading = false
        startPolling()
    }

    /// Sends a message with an optional pre-uploaded attachment. Either
    /// text or an attachment is required — matches the backend
    /// `messages_body_or_attachment_check` CHECK constraint.
    /// `voiceDurationSeconds` is required when `attachment.attachmentType ==
    /// "VOICE"` and ignored otherwise (the server enforces this).
    func send(body: String,
              attachment: ChatAttachmentUpload? = nil,
              voiceDurationSeconds: Int? = nil) async {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSending, !trimmed.isEmpty || attachment != nil else { return }
        isSending = true
        struct Body: Encodable {
            let body: String?
            let attachment_type: String?
            let attachment_key: String?
            let attachment_name: String?
            let attachment_size_bytes: Int64?
            let attachment_duration_seconds: Int?
        }
        let request = APIRequest(
            path: "/v1/student/messages/instructors/\(instructorId)/messages",
            method: .POST,
            body: Body(
                body: trimmed.isEmpty ? nil : trimmed,
                attachment_type: attachment?.attachmentType,
                attachment_key: attachment?.attachmentKey,
                attachment_name: attachment?.attachmentName,
                attachment_size_bytes: attachment?.attachmentSizeBytes,
                attachment_duration_seconds: voiceDurationSeconds))
        if let msg: DirectMessage = try? await AuthInterceptor.shared.execute(request) {
            messages.append(msg)
        }
        isSending = false
        // Catch up the thread id so subsequent polls hit the by-thread
        // path next time it's needed; the by-instructor GET is fine
        // either way.
        await fetch()
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                if Task.isCancelled { break }
                await fetch()
            }
        }
    }

    private struct Envelope: Decodable {
        let threadId: String?
        let instructorId: String
        let instructorName: String
        let instructorAvatarUrl: String?
        /// Instructor's account heartbeat, feeding `activityLabel`. Optional:
        /// null for an instructor never seen since the column was added, and
        /// absent entirely on a backend predating 2026-08 — both mean "no
        /// indicator", not "offline".
        let lastActiveAt: Date?
        let messages: [DirectMessage]
        enum CodingKeys: String, CodingKey {
            case threadId = "thread_id"
            case instructorId = "instructor_id"
            case instructorName = "instructor_name"
            case instructorAvatarUrl = "instructor_avatar_url"
            case lastActiveAt = "last_active_at"
            case messages
        }
    }

    private func fetch() async {
        // Messages-tab entry supplies an explicit threadId so the load
        // hits the by-thread endpoint, which resets the unread counter.
        // The instructor-profile entry leaves it nil and loads by
        // instructor id, since the thread may not exist yet. Both
        // responses share the same envelope shape (the thread response's
        // extra `instructor_initials` field is simply ignored here).
        let path = initialThreadId.map {
            "/v1/student/messages/threads/\($0)/messages"
        } ?? "/v1/student/messages/instructors/\(instructorId)/messages"
        let request = APIRequest(path: path)
        if let env: Envelope = try? await AuthInterceptor.shared.execute(request) {
            messages = env.messages
            instructorName = env.instructorName
            threadId = env.threadId
            lastActiveAt = env.lastActiveAt
            // Only adopt a non-nil server value so a response that omits
            // the avatar doesn't blank out a caller-seeded picture.
            if let avatar = env.instructorAvatarUrl {
                instructorAvatarUrl = avatar
            }
        }
    }
}

// MARK: - Image preview
//
// Wraps the presigned URL so `fullScreenCover(item:)` has an Identifiable
// handle. URL itself isn't reliably Identifiable across iOS versions.
struct ImagePreviewItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// Full-screen tap-to-zoom image viewer for sent + received image
/// attachments in chat. Pinch to zoom, drag to pan when zoomed, tap
/// the close button (or double-tap the image) to reset / dismiss.
/// Deliberately always-dark in both themes — a lightbox needs a black
/// matte behind the photo, so its chrome stays fixed white.
struct ImagePreviewView: View {
    let url: URL
    let onClose: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = max(1.0, min(5.0, lastScale * value))
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                    if scale <= 1.0 {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            offset = .zero
                                            lastOffset = .zero
                                        }
                                    }
                                }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    guard scale > 1.0 else { return }
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height)
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                scale = 1.0
                                lastScale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                case .failure:
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(.white.opacity(0.6))
                default:
                    ProgressView().tint(.white)
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.18))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 18)
                    .padding(.top, 18)
                }
                Spacer()
            }
        }
        .statusBarHidden(true)
    }
}
