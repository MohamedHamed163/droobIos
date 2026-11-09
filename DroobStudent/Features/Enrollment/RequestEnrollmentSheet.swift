import SwiftUI

// MARK: - Request to Enroll sheet
//
// Bottom sheet hosted from the Course Detail enroll button. In `.create`
// mode it opens a new PENDING enrollment request with an optional note,
// then swaps to a "Request Sent" confirmation. In `.edit` mode it lets the
// student amend the note on an existing PENDING request or withdraw it
// (Cancel Request). Approval — not payment — grants access, so there's no
// price or checkout copy here.

/// Outcome of a `RequestEnrollmentSheet` submit. Create can now resolve two
/// ways: a normal PENDING request shows the "Request Sent" confirmation, while
/// an already-APPROVED response (the backend auto-approves on create in testing
/// mode) means the student is enrolled immediately — the sheet skips the
/// confirmation and hands off to the host to route to the Courses tab. Edit
/// mode only ever reports `.saved` / `.failed`.
enum RequestEnrollmentResult {
    case requestSent
    case autoEnrolled
    case saved
    case failed
}

struct RequestEnrollmentSheet: View {
    enum Mode { case create, edit }

    let mode: Mode
    let courseTitle: String
    let instructorName: String
    let coverUrl: String?
    let existingNote: String?
    /// Create the request, or save the edited note. Reports how it resolved.
    let onSubmit: (String?) async -> RequestEnrollmentResult
    /// Withdraw the pending request. Only used in `.edit` mode.
    let onCancelRequest: (() async -> Bool)?
    /// Invoked when create came back already APPROVED — the host closes the
    /// sheet and routes to the Courses tab. Falls back to `onClose` when nil.
    let onAutoEnrolled: (() -> Void)?
    let onClose: () -> Void

    @State private var note: String
    @State private var submitting: Bool = false
    @State private var cancelling: Bool = false
    @State private var succeeded: Bool = false
    @State private var showCancelConfirm: Bool = false
    @State private var errorMessage: String? = nil
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code

    private let maxLength: Int = 500

    init(mode: Mode,
         courseTitle: String,
         instructorName: String,
         coverUrl: String?,
         existingNote: String?,
         onSubmit: @escaping (String?) async -> RequestEnrollmentResult,
         onCancelRequest: (() async -> Bool)? = nil,
         onAutoEnrolled: (() -> Void)? = nil,
         onClose: @escaping () -> Void) {
        self.mode = mode
        self.courseTitle = courseTitle
        self.instructorName = instructorName
        self.coverUrl = coverUrl
        self.existingNote = existingNote
        self.onSubmit = onSubmit
        self.onCancelRequest = onCancelRequest
        self.onAutoEnrolled = onAutoEnrolled
        self.onClose = onClose
        _note = State(initialValue: existingNote ?? "")
    }

    private var overLimit: Bool { note.count > maxLength }
    private var busy: Bool { submitting || cancelling }

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()
            if succeeded {
                successView.transition(.opacity)
            } else {
                editView.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: succeeded)
        .confirmationDialog(
            L10n.enrollRequestCancelConfirmTitle,
            isPresented: $showCancelConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.enrollRequestCancelConfirmYes, role: .destructive) {
                Task { await runCancel() }
            }
            Button(L10n.enrollRequestCancelConfirmNo, role: .cancel) {}
        } message: {
            Text(L10n.enrollRequestCancelConfirmMessage)
        }
    }

    // MARK: - Edit state

    private var editView: some View {
        VStack(alignment: .leading, spacing: 18) {
            headerTile
            Divider().overlay(MyCoursesPalette.stroke)

            VStack(spacing: 6) {
                Text(mode == .create
                     ? L10n.enrollRequestSheetTitleCreate
                     : L10n.enrollRequestSheetTitleEdit)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)
                Text(mode == .create
                     ? L10n.enrollRequestSheetPromptCreate
                     : L10n.enrollRequestSheetPromptEdit)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(MyCoursesPalette.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)

            noteField

            if let err = errorMessage {
                Text(err)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            submitButton
                .padding(.top, 2)

            if mode == .edit {
                Button {
                    showCancelConfirm = true
                } label: {
                    HStack(spacing: 6) {
                        if cancelling { ProgressView().tint(.red) }
                        Text(L10n.enrollRequestCancelRequest)
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.red.opacity(0.9))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }

            Button(action: onClose) {
                Text(L10n.enrollRequestClose)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(MyCoursesPalette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // MARK: Header tile

    private var headerTile: some View {
        HStack(spacing: 12) {
            coverThumb
            VStack(alignment: .leading, spacing: 2) {
                Text(courseTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(instructorName)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(MyCoursesPalette.muted)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var coverThumb: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Group {
            if let urlString = coverUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: coverPlaceholder
                    }
                }
            } else {
                coverPlaceholder
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(shape)
        .overlay(shape.stroke(MyCoursesPalette.stroke, lineWidth: 1))
    }

    private var coverPlaceholder: some View {
        ZStack {
            LinearGradient.droobBrand
            Image(systemName: "book.closed.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color(red: 0.08, green: 0.06, blue: 0.04))
        }
    }

    // MARK: Note field

    private var noteField: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return ZStack(alignment: .topLeading) {
            TextEditor(text: $note)
                .modifier(EnrollHiddenScrollBackground())
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 26)
                .frame(minHeight: 120)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.primary)

            if note.isEmpty {
                Text(L10n.enrollRequestNotePlaceholder)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(MyCoursesPalette.muted)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
                    .allowsHitTesting(false)
            }

            counterLabel
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .allowsHitTesting(false)
        }
        .background(MyCoursesPalette.surface)
        .clipShape(shape)
        .overlay(shape.stroke(overLimit ? Color.red.opacity(0.85) : MyCoursesPalette.stroke,
                              lineWidth: overLimit ? 1.5 : 1))
    }

    private var counterLabel: some View {
        HStack(spacing: 2) {
            Text("\(note.count)")
                .foregroundColor(overLimit ? Color.red : MyCoursesPalette.muted)
            Text(" / \(maxLength)")
                .foregroundColor(MyCoursesPalette.muted)
        }
        .font(.system(size: 12, weight: .semibold))
    }

    // MARK: Submit

    private var submitButton: some View {
        Button {
            Task { await runSubmit() }
        } label: {
            HStack(spacing: 8) {
                if submitting {
                    ProgressView().tint(Color(red: 0.08, green: 0.06, blue: 0.04))
                }
                Text(mode == .create
                     ? L10n.enrollRequestSubmitCreate
                     : L10n.enrollRequestSubmitEdit)
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundColor(Color(red: 0.08, green: 0.06, blue: 0.04))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(LinearGradient.droobBrand.opacity(submitDisabled ? 0.4 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(submitDisabled)
    }

    private var submitDisabled: Bool { busy || overLimit }

    private func runSubmit() async {
        guard !submitDisabled else { return }
        submitting = true
        errorMessage = nil
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: String? = trimmed.isEmpty ? nil : trimmed
        let result = await onSubmit(payload)
        submitting = false
        switch result {
        case .requestSent:
            withAnimation { succeeded = true }
        case .autoEnrolled:
            // Backend auto-approved — the student is already enrolled, so skip
            // the "Request Sent" confirmation and let the host route them.
            (onAutoEnrolled ?? onClose)()
        case .saved:
            onClose()
        case .failed:
            errorMessage = L10n.coursesGenericError
        }
    }

    private func runCancel() async {
        guard let onCancelRequest else { return }
        cancelling = true
        errorMessage = nil
        let ok = await onCancelRequest()
        cancelling = false
        if ok {
            onClose()
        } else {
            errorMessage = L10n.coursesGenericError
        }
    }

    // MARK: - Success state (create only)

    private var successView: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(MyCoursesPalette.success.opacity(0.16))
                    .frame(width: 84, height: 84)
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(MyCoursesPalette.success)
            }
            .padding(.top, 8)

            VStack(spacing: 6) {
                Text(L10n.enrollRequestSuccessTitle)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)
                Text(L10n.enrollRequestSuccessSubtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(MyCoursesPalette.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }

            headerTile
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MyCoursesPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(MyCoursesPalette.stroke, lineWidth: 1))
                .padding(.top, 4)

            Spacer(minLength: 0)

            Button(action: onClose) {
                HStack(spacing: 8) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text(L10n.enrollRequestBackToCourse)
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundColor(Color(red: 0.08, green: 0.06, blue: 0.04))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(LinearGradient.droobBrand)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }
}

// MARK: - Scroll background helper

private struct EnrollHiddenScrollBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}
