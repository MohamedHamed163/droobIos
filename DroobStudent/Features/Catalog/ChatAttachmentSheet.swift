import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Picked attachment payload
//
// The bridge between picker (PhotosPicker or UIDocumentPicker) and the
// chat composer's upload step. Carries the raw bytes the iOS already
// loaded plus the metadata the multipart upload needs (filename,
// content type). Kept value-typed so the composer can hold one in
// `@State` while showing the in-flight preview.

struct PickedAttachment: Equatable {
    let data: Data
    let filename: String
    let contentType: String
    let isImage: Bool
}

// MARK: - Attachment sheet
//
// Bottom sheet hosted from the chat composer's "+" button. Matches the
// figma's "SEND AN ATTACHMENT" sheet: two large tiles (Gallery /
// Documents) with descriptive subtitles, then a Cancel button. The
// "Recent" thumbnail row in the figma is intentionally left out for v1
// — implementing a recent-files cache is a bigger lift than the rest
// of the sheet and isn't load-bearing for the demo.
//
// The sheet doesn't actually do the upload — it surfaces a
// `PickedAttachment` through the `onPicked` callback and dismisses;
// the host owns the upload + send pipeline so error UI lives in the
// composer rather than the sheet.

struct ChatAttachmentSheet: View {
    let onPicked: (PickedAttachment) -> Void
    let onClose: () -> Void

    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code
    @State private var photoSelection: PhotosPickerItem? = nil
    @State private var showDocumentPicker = false

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()
            VStack(spacing: 18) {
                grabBar
                header
                tileRow
                Spacer()
                cancelButton
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        // PhotosPicker loads the selected item's transferable bytes as
        // soon as `photoSelection` changes — we hand them off through
        // `onPicked` then close ourselves so the host sees the picked
        // payload immediately.
        .onChange(of: photoSelection) { newValue in
            guard let newValue else { return }
            Task { await deliverPhoto(newValue) }
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker(onPicked: { picked in
                onPicked(picked)
                onClose()
            })
        }
    }

    private var grabBar: some View {
        Capsule()
            .fill(MyCoursesPalette.muted.opacity(0.4))
            .frame(width: 40, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 2)
    }

    private var header: some View {
        Text(L10n.chatAttachmentTitle)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(MyCoursesPalette.muted)
            .tracking(2.0)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tileRow: some View {
        HStack(spacing: 14) {
            // Gallery — uses Apple's PhotosPicker for system photo
            // library access, which doesn't need an entitlement.
            PhotosPicker(
                selection: $photoSelection,
                matching: .images,
                photoLibrary: .shared()) {
                    tile(icon: "photo",
                         iconTint: Color(red: 0.52, green: 0.30, blue: 0.95),
                         title: L10n.chatAttachmentGalleryTitle,
                         subtitle: L10n.chatAttachmentGallerySubtitle)
                }
                .buttonStyle(.plain)

            Button { showDocumentPicker = true } label: {
                tile(icon: "doc.text",
                     iconTint: Color(red: 0.20, green: 0.55, blue: 1.0),
                     title: L10n.chatAttachmentDocumentsTitle,
                     subtitle: L10n.chatAttachmentDocumentsSubtitle)
            }
            .buttonStyle(.plain)
        }
    }

    /// Single tile (Gallery / Documents). Square-ish — fills width
    /// equally and lets text wrap so longer translations don't truncate.
    private func tile(icon: String, iconTint: Color, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(iconTint.opacity(0.18))
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(iconTint)
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(MyCoursesPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(MyCoursesPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MyCoursesPalette.stroke, lineWidth: 1))
    }

    private var cancelButton: some View {
        Button(action: onClose) {
            Text(L10n.chatAttachmentCancel)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(MyCoursesPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(MyCoursesPalette.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Photo delivery

    /// Pulls the selected photo's data + UTI out of the PhotosPickerItem
    /// and hands it to the host. UTI → MIME conversion goes through
    /// `UTType.preferredMIMEType` so the server sees the right
    /// `Content-Type` header for the image format the user actually
    /// picked (heic vs jpeg vs png).
    private func deliverPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let typeIdentifier = item.supportedContentTypes.first
        let mime = typeIdentifier?.preferredMIMEType ?? "image/jpeg"
        let ext = typeIdentifier?.preferredFilenameExtension ?? "jpg"
        let name = "photo-\(Int(Date().timeIntervalSince1970)).\(ext)"
        await MainActor.run {
            onPicked(PickedAttachment(
                data: data, filename: name,
                contentType: mime, isImage: true))
            onClose()
        }
    }
}

// MARK: - Document picker bridge
//
// UIKit's UIDocumentPickerViewController is what we want for arbitrary
// files; SwiftUI doesn't ship a first-party SwiftUI wrapper for it. The
// bridge here is the minimum viable bridge — security-scoped URL
// access, read bytes off disk, hand over to the host.

/// UIKit document-picker bridge. Lifted to `internal` so other surfaces
/// — currently the Study Rooms documents tab's "Add" flow — can present
/// the same picker without re-implementing the security-scoped-URL
/// dance. Kept here (next to `ChatAttachmentSheet`) rather than moved
/// into Core so the two callers ship in lockstep with the chat
/// attachment changes that motivated this picker in the first place.
struct DocumentPicker: UIViewControllerRepresentable {
    let onPicked: (PickedAttachment) -> Void

    /// What the picker is allowed to open. Defaulted to the chat/study-room
    /// attachment allow-list so the two original call sites read exactly as
    /// they did before; Ask Droob AI's worksheet intake overrides it with
    /// `[.pdf, .image]`, which is a different question ("something with
    /// homework in it") than "something worth attaching to a message".
    var contentTypes: [UTType] = DocumentPicker.attachmentTypes

    /// Allow-list mirrors the backend MIME allow-list — PDF, common office
    /// types, plain text. Audio/video are out for now.
    static let attachmentTypes: [UTType] = [
        .pdf, .plainText, .commaSeparatedText,
        UTType("com.microsoft.word.doc") ?? .item,
        UTType("org.openxmlformats.wordprocessingml.document") ?? .item,
        UTType("com.microsoft.powerpoint.ppt") ?? .item,
        UTType("org.openxmlformats.presentationml.presentation") ?? .item,
        UTType("com.microsoft.excel.xls") ?? .item,
        UTType("org.openxmlformats.spreadsheetml.sheet") ?? .item
    ]

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController,
                                context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPicked: (PickedAttachment) -> Void
        init(onPicked: @escaping (PickedAttachment) -> Void) { self.onPicked = onPicked }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            guard let url = urls.first else { return }
            // Documents from outside the app sandbox arrive as
            // security-scoped resources; we must explicitly start
            // access before reading or `try Data(contentsOf:)` fails
            // silently with empty data.
            let didStart = url.startAccessingSecurityScopedResource()
            defer {
                if didStart { url.stopAccessingSecurityScopedResource() }
            }
            guard let data = try? Data(contentsOf: url) else { return }
            let utType = UTType(filenameExtension: url.pathExtension)
            let mime = utType?.preferredMIMEType ?? "application/octet-stream"
            onPicked(PickedAttachment(
                data: data,
                filename: url.lastPathComponent,
                contentType: mime,
                isImage: utType?.conforms(to: .image) ?? false))
        }
    }
}
