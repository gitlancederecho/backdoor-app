import SwiftUI

struct OverviewView: View {
    var taskVM: TaskViewModel
    var adminVM: AdminViewModel
    @Environment(LanguageManager.self) private var lang

    private var total: Int { taskVM.tasks.count }
    private var done: Int  { taskVM.tasks.filter { $0.status == .completed }.count }
    private var open: Int  { total - done }
    private var pct: Int   { total == 0 ? 0 : Int(Double(done) / Double(total) * 100) }

    private var perStaff: [(staff: Staff, assigned: Int, done: Int, rate: Int)] {
        adminVM.allStaff
            .filter(\.isActive)
            .map { s in
                let assigned = taskVM.tasks.filter { $0.assignedTo == s.id }
                let doneCount = assigned.filter { $0.status == .completed }.count
                let rate = assigned.isEmpty ? 0 : Int(Double(doneCount) / Double(assigned.count) * 100)
                return (s, assigned.count, doneCount, rate)
            }
            .sorted { $0.rate > $1.rate }
    }

    var body: some View {
        let _ = lang.current
        ScrollView {
            VStack(spacing: 16) {
                // Stats row
                HStack(spacing: 10) {
                    StatCard(label: tr("stat_total"), value: "\(total)", color: .white)
                    StatCard(label: tr("stat_done"), value: "\(done) · \(pct)%", color: .statusDone)
                    StatCard(label: tr("stat_open"), value: "\(open)", color: open > 0 ? .statusPending : .gray)
                }
                .padding(.horizontal, 16)

                // Per staff
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("per_staff_today"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.gray)
                        .tracking(1.2)
                        .padding(.horizontal, 16)

                    ForEach(perStaff, id: \.staff.id) { row in
                        HStack(spacing: 12) {
                            AvatarView(initials: row.staff.initials, url: row.staff.avatarUrl, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.staff.name)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                Text("\(row.done)/\(row.assigned) tasks · \(row.rate)%")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3).fill(Color.bgElevated)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.bdAccent)
                                        .frame(width: geo.size.width * CGFloat(row.rate) / 100)
                                }
                            }
                            .frame(width: 64, height: 6)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.bdBorder))
                        .padding(.horizontal, 16)
                    }
                }

                Spacer().frame(height: 24)
            }
            .padding(.top, 16)
        }
    }
}

private struct StatCard: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundColor(.gray)
            Text(value).font(.title3.bold()).foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .cardStyle()
    }
}
