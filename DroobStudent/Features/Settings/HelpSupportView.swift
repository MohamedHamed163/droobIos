import SwiftUI
import MessageUI

// MARK: - Help & Support (1.4.4)
//
// A single "Email Support" row that opens the system mail composer prefilled
// to support@droob.co. If no mail account is configured we fall back to a
// `mailto:` URL so the row still does something useful.

private let supportEmail = "support@droob.co"

struct HelpSupportView: View {
    @State private var showComposer = false
    @State private var composerResult: String? = nil

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    SettingsScreenHeader(title: L10n.helpSupportTitle)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 10) {
                        SettingsSectionLabel(text: L10n.helpContactUsSection)
                        SettingsCard {
                            Button {
                                openSupport()
                            } label: {
                                ProfileNavRow(
                                    icon: "envelope.fill",
                                    title: L10n.helpEmailSupport,
                                    subtitle: supportEmail)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showComposer) {
            MailComposeView(
                recipients: [supportEmail],
                subject: L10n.helpEmailSubject,
                body: "")
        }
    }

    private func openSupport() {
        if MFMailComposeViewController.canSendMail() {
            showComposer = true
        } else if let url = URL(string: "mailto:\(supportEmail)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - System mail composer wrapper

struct MailComposeView: UIViewControllerRepresentable {
    let recipients: [String]
    let subject: String
    let body: String
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients(recipients)
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        return vc
    }

    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            dismiss()
        }
    }
}
