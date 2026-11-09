import SwiftUI

struct LessonCompleteView: View {
    let result: LessonCompleteApiResponse
    let locale: String
    let onNextLesson: ((String) -> Void)?
    let onBackToCourse: () -> Void

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Checkmark
                ZStack {
                    Circle()
                        .fill(MyCoursesPalette.success.opacity(0.15))
                        .frame(width: 100, height: 100)
                    Image(systemName: "checkmark")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundColor(MyCoursesPalette.success)
                }
                .padding(.bottom, 24)

                Text(L10n.lessonCompleteTitle)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.primary)
                    .padding(.bottom, 6)

                // XP pill
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(MyCoursesPalette.accent)
                    Text(L10n.lessonCompleteXp(result.xpEarned))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.accent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.droobGold.opacity(0.12))
                .clipShape(Capsule())
                .padding(.bottom, 32)

                // Progress ring
                progressRing
                    .padding(.bottom, 40)

                Spacer()

                // Buttons
                VStack(spacing: 12) {
                    if let nextId = result.nextLessonId, let onNext = onNextLesson {
                        // Primary, then the other language, then the generic
                        // label. Under the Arabic lock the old `?? "Next Lesson"`
                        // was the ONLY fallback, so a lesson whose `title_ar` the
                        // instructor left blank put an English title on the
                        // button — or, with the English branch dead, nothing.
                        let nextTitle = (locale == "ar"
                            ? (result.nextLessonTitleAr ?? result.nextLessonTitleEn)
                            : (result.nextLessonTitleEn ?? result.nextLessonTitleAr))
                            ?? L10n.lessonCompleteNextLesson
                        Button {
                            onNext(nextId)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 13, weight: .bold))
                                Text(nextTitle)
                                    .font(.system(size: 16, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundColor(Color(red: 0.10, green: 0.07, blue: 0.04))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(LinearGradient.droobBrand)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        onBackToCourse()
                    } label: {
                        Text(L10n.lessonCompleteBackToCourse)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(MyCoursesPalette.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(MyCoursesPalette.surface)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(MyCoursesPalette.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(MyCoursesPalette.stroke, lineWidth: 8)
                .frame(width: 110, height: 110)
            Circle()
                .trim(from: 0, to: CGFloat(result.progressPct / 100))
                .stroke(LinearGradient.droobBrand, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 110, height: 110)
            VStack(spacing: 2) {
                Text("\(Int(result.progressPct))%")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)
                Text(L10n.lessonCompleteProgressLabel)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(MyCoursesPalette.muted)
            }
        }
    }
}
