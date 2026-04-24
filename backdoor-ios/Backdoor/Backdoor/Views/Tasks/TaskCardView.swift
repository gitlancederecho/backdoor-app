import SwiftUI

struct TaskCardView: View {
    let task: DailyTask
    @Environment(LanguageManager.self) private var lang

    private var displayTitle: String {
        lang.pick(en: task.task?.title ?? "Task", ja: task.task?.titleJa)
    }

    private var statusLabel: String {
        switch task.status {
        case .pending:     return tr("status_pending")
        case .in_progress: return tr("status_in_progress")
        case .completed:   return tr("status_completed")
        }
    }

    private var timeChipText: String? {
        let startText = task.startTime.map(TimeOfDay.displayString)
        let endText = task.endTime.map(TimeOfDay.displayString)
        switch (startText, endText) {
        case (nil, nil):         return nil
        case (let s?, nil):      return s
        case (nil, let e?):      return "\(tr("by_prefix")) \(e)"
        case (let s?, let e?):   return "\(s)–\(e)"
        }
    }

    var body: some View {
        let _ = lang.current
        HStack(alignment: .top, spacing: 12) {
            StatusDot(status: task.status)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(displayTitle)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    if let chip = timeChipText {
                        Text(chip)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.bdAccent.opacity(0.15))
                            .foregroundColor(.bdAccent)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 6) {
                    if let assignee = task.assignee {
                        HStack(spacing: 6) {
                            AvatarView(initials: assignee.initials, url: assignee.avatarUrl, size: 18)
                            Text(assignee.name)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .staffProfileLink(assignee)
                        Text("·").foregroundColor(Color.gray.opacity(0.5)).font(.caption)
                    }
                    Text(statusLabel)
                        .font(.caption)
                        .foregroundColor(.gray)
                    if let completedAt = task.completedAt {
                        Text("·").foregroundColor(Color.gray.opacity(0.5)).font(.caption)
                        Text(formattedTime(completedAt))
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }

                if let note = task.note, !note.isEmpty {
                    Text("\"\(note)\"")
                        .font(.caption)
                        .foregroundColor(Color.gray.opacity(0.7))
                        .lineLimit(2)
                }
            }

            Spacer()

            if let url = task.photoUrl, let imageURL = URL(string: url) {
                AsyncImage(url: imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.bgElevated
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.bdBorder))
            }
        }
        .padding(16)
        .cardStyle()
        .opacity(task.status == .completed ? 0.65 : 1)
    }
}
