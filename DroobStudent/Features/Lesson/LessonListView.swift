import SwiftUI

struct LessonListView: View {
    let course: CourseDetail
    @Environment(\.appLocale) private var locale

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(course.sections) { section in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(section.localizedTitle(locale: locale))
                            .font(.droobHeadline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray5))

                        ForEach(section.lessons) { lesson in
                            lessonRow(lesson, section: section)
                        }
                    }
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
            .padding(.top, 8)
        }
        .navigationTitle(L10n.lessons)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func lessonRow(_ lesson: LessonSummary, section: CourseSection) -> some View {
        if course.enrolled && lesson.isVideo {
            NavigationLink {
                LessonDocumentsView(courseId: course.id, lessonId: lesson.id, title: lesson.localizedTitle(locale: locale))
            } label: {
                LessonListRow(lesson: lesson, locale: locale, locked: false)
            }
            .buttonStyle(.plain)
        } else if course.enrolled {
            NavigationLink {
                LessonDocumentsView(courseId: course.id, lessonId: lesson.id, title: lesson.localizedTitle(locale: locale))
            } label: {
                LessonListRow(lesson: lesson, locale: locale, locked: false)
            }
            .buttonStyle(.plain)
        } else {
            LessonListRow(lesson: lesson, locale: locale, locked: true)
        }
        if lesson.id != section.lessons.last?.id {
            Divider().padding(.leading, 56)
        }
    }
}

struct LessonListRow: View {
    let lesson: LessonSummary
    let locale: String
    let locked: Bool

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(locked ? Color(.systemGray5) : Color.droobPrimary.opacity(0.1))
                    .frame(width: 40, height: 40)
                Image(systemName: lesson.isVideo
                      ? (locked ? "lock.fill" : "play.fill")
                      : "doc.text.fill")
                    // `droobPrimary` resolves to the raw gold in light mode,
                    // which is ~2:1 on a system background. Gold as ink goes
                    // through the adaptive accent; the 10% wash behind it is
                    // a fill and keeps the asset colour.
                    .foregroundColor(locked ? .secondary : MyCoursesPalette.accent)
                    .font(.system(size: 16))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.localizedTitle(locale: locale))
                    .font(.droobSubheadline)
                    .foregroundColor(locked ? .secondary : .primary)
                Text(lesson.isVideo ? L10n.videoLesson : L10n.textLesson)
                    .font(.droobCaption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !locked {
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
}
