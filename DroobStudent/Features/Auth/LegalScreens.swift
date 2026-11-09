import SwiftUI

// MARK: - Terms of Service
//
// Reachable from the inline link in RegisterView's terms paragraph. The
// body content is placeholder copy — replace with the finalised legal
// text when it's signed off. Layout mirrors the other auth screens:
// edge-to-edge chip bar, back link, large italic title, scrollable body.

struct TermsOfServiceView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code

    var body: some View {
        LegalScrollScreen(
            backLabel: L10n.registerBack,
            title: L10n.legalTermsTitle,
            updatedAt: L10n.legalTermsUpdated,
            sections: TermsContent.sections(forArabic: appLocale == "ar"),
            onBack: { dismiss() }
        )
    }
}

// MARK: - Privacy Policy

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code

    var body: some View {
        LegalScrollScreen(
            backLabel: L10n.registerBack,
            title: L10n.legalPrivacyTitle,
            updatedAt: L10n.legalPrivacyUpdated,
            sections: PrivacyContent.sections(forArabic: appLocale == "ar"),
            onBack: { dismiss() }
        )
    }
}

// MARK: - Shared chrome
//
// One scrolling "legal document" layout used by both Terms and Privacy.
// Header → updated-at footnote → section list. Sections render as bolded
// heading + flowing body paragraph so future copy edits stay a string
// change instead of a view rebuild.

struct LegalSection {
    let heading: String
    let body: String
}

private struct LegalScrollScreen: View {
    let backLabel: String
    let title: String
    let updatedAt: String
    let sections: [LegalSection]
    let onBack: () -> Void

    @AppStorage("appLocale") private var appLocale: String = AppLocaleDefault.code

    var body: some View {
        ZStack(alignment: .top) {
            AuthFigmaColors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 22)

                        AuthBackLink(label: backLabel, action: onBack)
                            .padding(.bottom, 14)

                        Text(title)
                            .font(BrandFont.display(size: 30, isArabic: appLocale == "ar"))
                            .tracking(appLocale == "ar" ? 0 : -1.2)
                            .foregroundColor(AuthFigmaColors.textPrimary)
                            .padding(.bottom, 8)

                        Text(updatedAt)
                            .font(BrandFont.display(size: 13, isArabic: appLocale == "ar"))
                            .foregroundColor(AuthFigmaColors.muted)
                            .padding(.bottom, 28)

                        ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                            Text(section.heading)
                                .font(BrandFont.display(size: 17, isArabic: appLocale == "ar"))
                                .foregroundColor(AuthFigmaColors.textPrimary)
                                .padding(.bottom, 6)

                            Text(section.body)
                                .font(BrandFont.display(size: 15, isArabic: appLocale == "ar"))
                                .foregroundColor(AuthFigmaColors.muted)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.bottom, 22)
                        }

                        Color.clear.frame(height: 32)
                    }
                    .padding(.horizontal, 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Placeholder legal copy
//
// Plain-language drafts that explain what each section will eventually
// cover. Swap each `body` string for the final legal text once it's
// signed off; the headings and section count can stay.

private enum TermsContent {
    static func sections(forArabic ar: Bool) -> [LegalSection] {
        ar ? [
            LegalSection(heading: "١. قبولك للشروط",
                         body: "باستخدامك تطبيق دروب فإنك توافق على هذه الشروط. إذا لم توافق عليها، يُرجى عدم استخدام الخدمة."),
            LegalSection(heading: "٢. حسابك",
                         body: "أنت مسؤول عن الحفاظ على سرية بيانات حسابك، وعن جميع الأنشطة التي تتمّ من خلاله."),
            LegalSection(heading: "٣. المحتوى التعليمي",
                         body: "الدورات والمواد متاحة لاستخدامك الشخصي فقط. لا يجوز إعادة بيعها أو إعادة توزيعها دون إذن خطي مسبق."),
            LegalSection(heading: "٤. المدفوعات والاسترداد",
                         body: "تُحَصَّل رسوم الاشتراك مقدمًا. سياسة الاسترداد تتبع الإطار الزمني وشروط الأهلية المنصوص عليها في صفحة الدعم."),
            LegalSection(heading: "٥. إنهاء الخدمة",
                         body: "نحتفظ بحق تعليق أو إنهاء أي حساب يخالف هذه الشروط أو يضرّ بمستخدمي المنصة."),
            LegalSection(heading: "٦. حدود المسؤولية",
                         body: "نقدّم الخدمة \"كما هي\" دون أي ضمانات صريحة. لا نتحمّل أي خسارة غير مباشرة أو تبعية ناتجة عن استخدام التطبيق."),
            LegalSection(heading: "٧. التغييرات على الشروط",
                         body: "قد نحدّث هذه الشروط من حين لآخر. سنخطرك بالتعديلات الجوهرية عبر التطبيق أو البريد الإلكتروني."),
            LegalSection(heading: "٨. التواصل",
                         body: "للاستفسار راسلنا على info@droob-sa.net."),
        ] : [
            LegalSection(heading: "1. Acceptance",
                         body: "By using Droob you agree to these Terms. If you don't, please don't use the service."),
            LegalSection(heading: "2. Your Account",
                         body: "You're responsible for keeping your account credentials confidential and for all activity that happens under your account."),
            LegalSection(heading: "3. Course Content",
                         body: "Courses and materials are licensed for your personal use only. You may not resell, redistribute, or share access without written permission."),
            LegalSection(heading: "4. Payments & Refunds",
                         body: "Subscription fees are billed in advance. Refund eligibility follows the timeline outlined on our support page."),
            LegalSection(heading: "5. Termination",
                         body: "We may suspend or terminate accounts that violate these Terms or that we reasonably believe are harmful to other learners."),
            LegalSection(heading: "6. Liability",
                         body: "The service is provided \"as is\" without warranties. We are not liable for indirect or consequential losses arising from use of the app."),
            LegalSection(heading: "7. Changes",
                         body: "We may update these Terms from time to time. We'll notify you of material changes via in-app messaging or email."),
            LegalSection(heading: "8. Contact",
                         body: "Questions? Write to info@droob-sa.net."),
        ]
    }
}

private enum PrivacyContent {
    static func sections(forArabic ar: Bool) -> [LegalSection] {
        ar ? [
            LegalSection(heading: "البيانات التي نجمعها",
                         body: "نجمع البيانات التي تقدّمها عند إنشاء الحساب (الاسم، البريد، الموقع المفضّل) ومعلومات الاستخدام التي تساعدنا على تحسين الخدمة."),
            LegalSection(heading: "كيف نستخدم بياناتك",
                         body: "نستخدم البيانات لإدارة حسابك، تخصيص المحتوى التعليمي، إرسال إشعارات الدورات، وحماية المنصة من الاحتيال."),
            LegalSection(heading: "المشاركة مع أطراف ثالثة",
                         body: "لا نبيع بياناتك الشخصية. نشاركها فقط مع مقدّمي الخدمات الضروريين لتشغيل المنصة (مثل بوابات الدفع، مزوّدي البريد) وفق اتفاقيات سرية."),
            LegalSection(heading: "الاحتفاظ بالبيانات",
                         body: "نحتفظ ببياناتك طوال فترة نشاط الحساب. يمكنك طلب حذف الحساب وبياناته في أي وقت."),
            LegalSection(heading: "حقوقك",
                         body: "لك الحق في الاطلاع على بياناتك، تصحيحها، أو حذفها. للاستفسار راسلنا على info@droob-sa.net."),
            LegalSection(heading: "الأمان",
                         body: "نستخدم تشفير TLS أثناء النقل وتخزينًا آمنًا للبيانات الحسّاسة. لا توجد طريقة آمنة بنسبة 100٪ ولكنّنا نطبّق أفضل الممارسات الصناعية."),
            LegalSection(heading: "التحديثات",
                         body: "قد نحدّث هذه السياسة. سنُخطرك بأي تغييرات جوهرية عبر التطبيق أو البريد."),
        ] : [
            LegalSection(heading: "What We Collect",
                         body: "Information you provide at signup (name, email, preferred locale) and usage information that helps us improve the service."),
            LegalSection(heading: "How We Use It",
                         body: "To run your account, personalise course recommendations, send relevant notifications, and protect the platform from fraud."),
            LegalSection(heading: "Sharing",
                         body: "We don't sell your personal data. We share only with service providers that run essential platform features (payments, email delivery) under confidentiality agreements."),
            LegalSection(heading: "Retention",
                         body: "We keep your data while your account is active. You can request account deletion at any time."),
            LegalSection(heading: "Your Rights",
                         body: "You can request to access, correct, or delete your personal data. Write to info@droob-sa.net."),
            LegalSection(heading: "Security",
                         body: "We use TLS in transit and encrypted storage for sensitive fields. No method is 100% secure, but we follow industry-standard practices."),
            LegalSection(heading: "Updates",
                         body: "We may update this policy from time to time. We'll notify you of material changes."),
        ]
    }
}
