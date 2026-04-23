import SwiftUI

struct TaskEditorSheet: View {
    let task: TaskTemplate?
    @Bindable var adminVM: AdminViewModel
    @Environment(AuthViewModel.self) private var auth
    @Environment(LanguageManager.self) private var lang
    @Environment(VenueViewModel.self) private var venue
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var titleJa = ""
    @State private var category: Category = .opening
    @State private var assignedTo: UUID? = nil
    @State private var isRecurring = true
    @State private var recurrenceType: RecurrenceType = .daily
    @State private var days: Set<Int> = []
    @State private var priority: Priority = .normal
    @State private var hasStartTime = false
    @State private var startTime: Date = defaultTime(hour: 17)
    @State private var hasEndTime = false
    @State private var endTime: Date = defaultTime(hour: 18)
    @State private var isSaving = false
    @State private var error: String?

    private static func defaultTime(hour: Int) -> Date {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = 0
        return Calendar.current.date(from: comps) ?? Date()
    }

    private var isNew: Bool { task == nil }
    private let weekdays = ["M","T","W","T","F","S","S"]

    private func priorityLabel(_ p: Priority) -> String {
        switch p {
        case .low: return tr("priority_low")
        case .normal: return tr("priority_normal")
        case .high: return tr("priority_high")
        }
    }

    private func recurrenceLabel(_ r: RecurrenceType) -> String {
        switch r {
        case .daily: return tr("repeat_daily")
        case .weekly: return tr("repeat_weekly")
        case .monthly: return tr("repeat_monthly")
        }
    }

    var body: some View {
        let _ = lang.current
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        field(tr("title_en")) {
                            TextField("e.g. Wipe bar top", text: $title)
                                .inputStyle()
                        }
                        field(tr("title_ja")) {
                            TextField("例: バーカウンターを拭く", text: $titleJa)
                                .inputStyle()
                        }

                        field(tr("category")) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Category.allCases, id: \.self) { cat in
                                        chipButton(cat.localized, selected: category == cat) { category = cat }
                                    }
                                }
                            }
                        }

                        field(tr("priority")) {
                            HStack(spacing: 8) {
                                ForEach(Priority.allCases, id: \.self) { p in
                                    chipButton(priorityLabel(p), selected: priority == p) { priority = p }
                                }
                            }
                        }

                        field(tr("assign_to")) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    chipButton(tr("assign_anyone"), selected: assignedTo == nil) { assignedTo = nil }
                                    ForEach(adminVM.allStaff.filter(\.isActive)) { s in
                                        chipButton(s.name, selected: assignedTo == s.id) { assignedTo = s.id }
                                    }
                                }
                            }
                        }

                        // Time window (optional)
                        VStack(alignment: .leading, spacing: 10) {
                            Text(tr("time_window_optional"))
                                .font(.caption)
                                .foregroundColor(.gray)
                                .padding(.horizontal, 4)

                            HStack(spacing: 12) {
                                Toggle(tr("start_time"), isOn: $hasStartTime)
                                    .tint(.bdAccent)
                                Spacer()
                                if hasStartTime {
                                    DatePicker("", selection: $startTime, displayedComponents: .hourAndMinute)
                                        .labelsHidden()
                                        .colorScheme(.dark)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.bgElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                            HStack(spacing: 12) {
                                Toggle(tr("end_time"), isOn: $hasEndTime)
                                    .tint(.bdAccent)
                                Spacer()
                                if hasEndTime {
                                    DatePicker("", selection: $endTime, displayedComponents: .hourAndMinute)
                                        .labelsHidden()
                                        .colorScheme(.dark)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.bgElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                            if hasStartTime && hasEndTime && startTime >= endTime {
                                Text(tr("end_after_start"))
                                    .font(.caption2)
                                    .foregroundColor(.statusPending)
                                    .padding(.horizontal, 4)
                            }
                        }

                        Toggle(tr("recurring"), isOn: $isRecurring)
                            .tint(.bdAccent)
                            .padding(.horizontal, 4)

                        if isRecurring {
                            field(tr("repeats")) {
                                HStack(spacing: 8) {
                                    ForEach(RecurrenceType.allCases, id: \.self) { r in
                                        chipButton(recurrenceLabel(r), selected: recurrenceType == r) { recurrenceType = r }
                                    }
                                }
                            }

                            if recurrenceType == .weekly {
                                field(tr("days")) {
                                    HStack(spacing: 6) {
                                        ForEach(1...7, id: \.self) { n in
                                            let selected = days.contains(n)
                                            Button(weekdays[n - 1]) {
                                                if selected { days.remove(n) } else { days.insert(n) }
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(selected ? Color.bdAccent : Color.bgElevated)
                                            .foregroundColor(selected ? .black : .gray)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .font(.system(size: 13, weight: .medium))
                                        }
                                    }
                                }
                            }
                        }

                        if let error {
                            Text(error).font(.caption).foregroundColor(.statusPending)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(isNew ? tr("new_task") : tr("edit_task"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bgCard, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("cancel")) { dismiss() }.foregroundColor(.gray)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? tr("create") : tr("save")) { Task { await save() } }
                        .foregroundColor(.bdAccent)
                        .disabled(title.isEmpty || isSaving)
                }
            }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
        .onAppear { populate() }
    }

    private func populate() {
        guard let t = task else { return }
        title = t.title
        titleJa = t.titleJa ?? ""
        category = t.category
        assignedTo = t.assignedTo
        isRecurring = t.isRecurring
        recurrenceType = t.recurrenceType ?? .daily
        days = Set(t.recurrenceDays ?? [])
        priority = t.priority

        if let s = t.startTime, let (h, m) = TimeOfDay.parse(s) {
            hasStartTime = true
            startTime = Self.makeDate(hour: h, minute: m)
        } else {
            hasStartTime = false
        }
        if let e = t.endTime, let (h, m) = TimeOfDay.parse(e) {
            hasEndTime = true
            endTime = Self.makeDate(hour: h, minute: m)
        } else {
            hasEndTime = false
        }
    }

    private static func makeDate(hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps) ?? Date()
    }

    private func save() async {
        isSaving = true
        error = nil
        let newTask = NewTask(
            title: title.trimmingCharacters(in: .whitespaces),
            titleJa: titleJa.trimmingCharacters(in: .whitespaces).isEmpty ? nil : titleJa,
            category: category,
            assignedTo: assignedTo,
            isRecurring: isRecurring,
            recurrenceType: isRecurring ? recurrenceType : nil,
            recurrenceDays: isRecurring && recurrenceType != .daily ? days.sorted() : [],
            priority: priority,
            createdBy: auth.staff?.id,
            startTime: hasStartTime ? TimeOfDay.dbString(from: startTime) : nil,
            endTime: hasEndTime ? TimeOfDay.dbString(from: endTime) : nil
        )
        let bd = BusinessDay.currentBusinessDayISO(schedule: venue.schedule, settings: venue.settings)
        do {
            if let t = task {
                try await adminVM.updateTask(id: t.id, newTask, businessDay: bd)
            } else {
                try await adminVM.createTask(newTask, businessDay: bd)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundColor(.gray)
            content()
        }
    }

    @ViewBuilder
    private func chipButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .font(.subheadline)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(selected ? Color.bdAccent : Color.bgElevated)
            .foregroundColor(selected ? .black : .gray)
            .clipShape(Capsule())
    }
}
