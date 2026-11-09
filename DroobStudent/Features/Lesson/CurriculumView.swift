import SwiftUI

struct CurriculumView: View {
    let course: CourseDetail
    @Environment(\.appLocale) private var locale
    @Environment(\.dismiss) private var dismiss

    @State private var expandedSectionIds: Set<String> = []

    var body: some View {
        ZStack {
            MyCoursesPalette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                progressBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(course.sections.enumerated()), id: \.element.id) { idx, section in
                            SectionAccordion(
                                index: idx + 1,
                                section: section,
                                course: course,
                                locale: locale,
                                isExpanded: expandedSectionIds.contains(section.id)
                            ) {
                                toggleSection(section.id)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { expandFirstIncomplete() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(MyCoursesPalette.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.courseDetailCurriculumTitle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                Text(course.localizedTitle(locale: locale))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(MyCoursesPalette.muted)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(course.completedLessonCount)/\(course.lessonCount)".bidiIsolated)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(MyCoursesPalette.accent)
        }
        .padding(.horizontal, 16)
        .padding(.top, 56)
        .padding(.bottom, 12)
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(MyCoursesPalette.stroke).frame(height: 5)
                    Capsule()
                        .fill(LinearGradient.droobBrand)
                        .frame(width: max(0, geo.size.width * CGFloat(course.progressPct / 100)), height: 5)
                }
            }
            .frame(height: 5)
            Text("\(Int(course.progressPct))%".bidiIsolated + " " + L10n.enrolledPercentComplete)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(MyCoursesPalette.muted)
        }
    }

    // MARK: - Helpers

    private func toggleSection(_ id: String) {
        if expandedSectionIds.contains(id) {
            expandedSectionIds.remove(id)
        } else {
            expandedSectionIds.insert(id)
        }
    }

    private func expandFirstIncomplete() {
        if let first = course.sections.first(where: { !$0.isCompleted }) {
            expandedSectionIds.insert(first.id)
        } else if let first = course.sections.first {
            expandedSectionIds.insert(first.id)
        }
    }
}

// MARK: - Section Accordion

struct SectionAccordion: View {
    let index: Int
    let section: CourseSection
    let course: CourseDetail
    let locale: String
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    sectionStatusIcon
                        .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(L10n.courseModule) \(index)".bidiIsolated)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(MyCoursesPalette.muted)
                            .tracking(0.6)
                        Text(section.localizedTitle(locale: locale))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer()

                    Text("\(section.completedLessonCount)/\(section.lessonCount)".bidiIsolated)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(MyCoursesPalette.muted)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(MyCoursesPalette.muted)
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            // Lesson rows + optional quiz row
            if isExpanded {
                Divider()
                    .background(MyCoursesPalette.stroke)
                    .padding(.horizontal, 14)

                ForEach(Array(section.lessons.enumerated()), id: \.element.id) { lessonIdx, lesson in
                    lessonRow(lesson: lesson, index: lessonIdx + 1, sectionIndex: index)
                    Divider()
                        .background(MyCoursesPalette.stroke)
                        .padding(.leading, 56)
                }

                ForEach(section.moduleQuizzes) { quiz in
                    if course.enrolled {
                        NavigationLink {
                            QuizView(
                                courseId: course.id,
                                quizId: quiz.id,
                                sectionId: section.id,
                                sectionTitleEn: section.titleEn,
                                sectionTitleAr: section.titleAr
                            )
                        } label: {
                            quizRow(quiz)
                        }
                        .buttonStyle(.plain)
                    } else {
                        quizRowLocked(quiz)
                    }
                }
            }
        }
        .background(MyCoursesPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(MyCoursesPalette.stroke, lineWidth: 1))
    }

    @ViewBuilder
    private func lessonRow(lesson: LessonSummary, index: Int, sectionIndex: Int) -> some View {
        if course.enrolled && lesson.isVideo {
            NavigationLink {
                LessonPlayerView(
                    courseId: course.id,
                    lessonId: lesson.id,
                    lessonTitleEn: lesson.titleEn,
                    lessonTitleAr: lesson.titleAr,
                    sectionTitleEn: section.titleEn,
                    sectionTitleAr: section.titleAr,
                    lessonNumber: "\(sectionIndex).\(index)",
                    alreadyCompleted: lesson.completed,
                    instructorName: course.instructorName
                )
            } label: {
                CurriculumLessonRow(lesson: lesson, locale: locale, locked: false)
            }
            .buttonStyle(.plain)
        } else if course.enrolled && !lesson.isVideo {
            NavigationLink {
                LessonDocumentsView(
                    courseId: course.id,
                    lessonId: lesson.id,
                    title: lesson.localizedTitle(locale: locale),
                    alreadyCompleted: lesson.completed
                )
            } label: {
                CurriculumLessonRow(lesson: lesson, locale: locale, locked: false)
            }
            .buttonStyle(.plain)
        } else {
            CurriculumLessonRow(lesson: lesson, locale: locale, locked: true)
        }
    }

    private func quizRow(_ quiz: SectionQuiz) -> some View {
        let title = quiz.localizedTitle(locale: locale)
        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.droobGold.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(MyCoursesPalette.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title.isEmpty ? L10n.curriculumModuleQuiz : title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Text(quiz.questionCount > 0
                     ? L10n.curriculumQuizQuestions(quiz.questionCount)
                     : L10n.curriculumQuizPrompt)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(MyCoursesPalette.muted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(MyCoursesPalette.muted)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
    }

    private func quizRowLocked(_ quiz: SectionQuiz) -> some View {
        let title = quiz.localizedTitle(locale: locale)
        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(MyCoursesPalette.stroke)
                    .frame(width: 32, height: 32)
                Image(systemName: "lock.fill")
                    .font(.system(size: 13))
                    .foregroundColor(MyCoursesPalette.muted)
            }
            Text(title.isEmpty ? L10n.curriculumModuleQuiz : title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(MyCoursesPalette.muted)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
    }

    private var sectionStatusIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(iconBackground)
            if section.isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(MyCoursesPalette.success)
            } else {
                Text("\(index)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(iconForeground)
            }
        }
    }

    private var iconBackground: Color {
        if section.isCompleted { return MyCoursesPalette.success.opacity(0.15) }
        if section.isInProgress { return Color.droobGold.opacity(0.15) }
        return MyCoursesPalette.stroke
    }

    private var iconForeground: Color {
        if section.isInProgress { return MyCoursesPalette.accent }
        return MyCoursesPalette.muted
    }
}

// MARK: - Curriculum Lesson Row

struct CurriculumLessonRow: View {
    let lesson: LessonSummary
    let locale: String
    let locked: Bool

    var body: some View {
        HStack(spacing: 14) {
            // Status icon
            ZStack {
                Circle()
                    .fill(circleBackground)
                    .frame(width: 32, height: 32)
                Image(systemName: rowIcon)
                    .font(.system(size: 13, weight: lesson.completed ? .bold : .medium))
                    .foregroundColor(rowIconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.localizedTitle(locale: locale))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(locked ? MyCoursesPalette.muted : .primary)
                    .lineLimit(2)

                if let dur = lesson.durationSeconds, dur > 0 {
                    Text(formatDuration(dur))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(MyCoursesPalette.muted)
                } else {
                    Text(lesson.isVideo ? L10n.videoLesson : L10n.documentLesson)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(MyCoursesPalette.muted)
                }
            }

            Spacer()

            if !locked {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(MyCoursesPalette.muted)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
    }

    private var rowIcon: String {
        if locked { return "lock.fill" }
        if lesson.completed { return "checkmark" }
        return lesson.isVideo ? "play.fill" : "doc.text.fill"
    }

    private var circleBackground: Color {
        if locked { return MyCoursesPalette.stroke }
        if lesson.completed { return MyCoursesPalette.success.opacity(0.15) }
        return Color.droobGold.opacity(0.12)
    }

    private var rowIconColor: Color {
        if locked { return MyCoursesPalette.muted }
        if lesson.completed { return MyCoursesPalette.success }
        return MyCoursesPalette.accent
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
