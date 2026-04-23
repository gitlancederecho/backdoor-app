import SwiftUI

/// Admin UI for setting the weekly operating schedule (open/close/closed per day).
struct HoursAdminView: View {
    @Environment(VenueViewModel.self) private var venue
    @Environment(LanguageManager.self) private var lang

    @State private var editingDay: VenueDay?
    @State private var editingTimezone = false
    @State private var prepBufferMinutes: Int = 240
    @State private var graceMinutes: Int = 120
    @State private var isSaving = false

    private let weekdayKeys = [
        "weekday_mon", "weekday_tue", "weekday_wed", "weekday_thu",
        "weekday_fri", "weekday_sat", "weekday_sun"
    ]

    var body: some View {
        let _ = lang.current
        ScrollView {
            VStack(spacing: 16) {
                // Hint
                Text(tr("hours_hint"))
                    .font(.caption)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                // Timezone
                VStack(alignment: .leading, spacing: 10) {
                    Text(tr("timezone"))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.gray)
                        .tracking(1.2)
                    Text(tr("timezone_hint"))
                        .font(.caption2)
                        .foregroundColor(.gray)
                    timezoneRow()
                }
                .padding(.horizontal, 16)

                // Weekday rows
                LazyVStack(spacing: 8) {
                    ForEach(venue.schedule) { day in
                        dayRow(day)
                            .padding(.horizontal, 16)
                    }
                }

                // Prep buffer
                VStack(alignment: .leading, spacing: 10) {
                    Text(tr("prep_buffer"))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.gray)
                        .tracking(1.2)
                    Text(tr("prep_buffer_hint"))
                        .font(.caption2)
                        .foregroundColor(.gray)

                    Stepper(value: $prepBufferMinutes, in: 0...720, step: 30) {
                        Text(durationLabel(prepBufferMinutes))
                            .foregroundColor(.white)
                            .font(.system(size: 15, weight: .medium))
                    }
                    .padding(14)
                    .cardStyle()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                // Grace period (overtime)
                VStack(alignment: .leading, spacing: 10) {
                    Text(tr("grace_period"))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.gray)
                        .tracking(1.2)
                    Text(tr("grace_period_hint"))
                        .font(.caption2)
                        .foregroundColor(.gray)

                    Stepper(value: $graceMinutes, in: 0...480, step: 15) {
                        Text(durationLabel(graceMinutes))
                            .foregroundColor(.white)
                            .font(.system(size: 15, weight: .medium))
                    }
                    .padding(14)
                    .cardStyle()
                }
                .padding(.horizontal, 16)

                // Save button (for both settings)
                Button {
                    Task {
                        isSaving = true
                        try? await venue.updateSettings(
                            prepBufferMinutes: Int16(prepBufferMinutes),
                            gracePeriodMinutes: Int16(graceMinutes)
                        )
                        isSaving = false
                    }
                } label: {
                    if isSaving { ProgressView().tint(.black) }
                    else { Text(tr("save")) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSaving || (
                    prepBufferMinutes == Int(venue.settings.prepBufferMinutes)
                    && graceMinutes == Int(venue.settings.gracePeriodMinutes)
                ))
                .padding(.horizontal, 16)

                Spacer().frame(height: 24)
            }
            .padding(.top, 8)
        }
        .sheet(item: $editingDay) { day in
            DayScheduleSheet(day: day)
                .environment(venue)
                .environment(lang)
        }
        .sheet(isPresented: $editingTimezone) {
            TimezonePickerSheet(current: venue.settings.timezone)
                .environment(venue)
                .environment(lang)
        }
        .onAppear {
            prepBufferMinutes = Int(venue.settings.prepBufferMinutes)
            graceMinutes = Int(venue.settings.gracePeriodMinutes)
        }
        .onChange(of: venue.settings.prepBufferMinutes) { _, new in
            prepBufferMinutes = Int(new)
        }
        .onChange(of: venue.settings.gracePeriodMinutes) { _, new in
            graceMinutes = Int(new)
        }
    }

    private func durationLabel(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }

    @ViewBuilder
    private func timezoneRow() -> some View {
        let tzId = venue.settings.timezone
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tzId)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                if let offset = TimezoneUtil.offsetLabel(for: tzId) {
                    Text(offset)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            Spacer()
            Button(tr("edit")) { editingTimezone = true }
                .font(.subheadline)
                .foregroundColor(.bdAccent)
        }
        .padding(14)
        .cardStyle()
    }

    @ViewBuilder
    private func dayRow(_ day: VenueDay) -> some View {
        HStack(spacing: 12) {
            // Day name
            Text(tr(weekdayKeys[Int(day.weekday) - 1]))
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 80, alignment: .leading)

            // Status/hours
            if day.isClosed {
                Text(tr("closed"))
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.statusPending.opacity(0.15))
                    .foregroundColor(.statusPending)
                    .clipShape(Capsule())
            } else if let o = day.openTime, let c = day.closeTime {
                Text("\(TimeOfDay.displayString(from: o)) – \(TimeOfDay.displayString(from: c))\(day.closesNextCalendarDay ? " +1" : "")")
                    .font(.subheadline)
                    .foregroundColor(.white)
            } else {
                Text("—").foregroundColor(.gray)
            }

            Spacer()

            Button(tr("edit")) { editingDay = day }
                .font(.subheadline)
                .foregroundColor(.bdAccent)
        }
        .padding(14)
        .cardStyle()
    }
}

// MARK: - Per-day editor sheet

private struct DayScheduleSheet: View {
    let day: VenueDay
    @Environment(VenueViewModel.self) private var venue
    @Environment(LanguageManager.self) private var lang
    @Environment(\.dismiss) private var dismiss

    @State private var isClosed = false
    @State private var openTime = Date()
    @State private var closeTime = Date()
    @State private var isSaving = false
    @State private var error: String?

    private let weekdayKeys = [
        "weekday_mon", "weekday_tue", "weekday_wed", "weekday_thu",
        "weekday_fri", "weekday_sat", "weekday_sun"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        Toggle(tr("closed_day"), isOn: $isClosed)
                            .tint(.bdAccent)
                            .padding(.horizontal, 4)

                        if !isClosed {
                            field(tr("open_time")) {
                                DatePicker("", selection: $openTime, displayedComponents: .hourAndMinute)
                                    .datePickerStyle(.wheel)
                                    .labelsHidden()
                                    .frame(maxHeight: 130)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.bgElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .colorScheme(.dark)
                            }
                            field(tr("close_time")) {
                                DatePicker("", selection: $closeTime, displayedComponents: .hourAndMinute)
                                    .datePickerStyle(.wheel)
                                    .labelsHidden()
                                    .frame(maxHeight: 130)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.bgElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .colorScheme(.dark)
                            }
                            Text(tr("close_next_day_hint"))
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }

                        if let error {
                            Text(error).font(.caption).foregroundColor(.statusPending)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(tr(weekdayKeys[Int(day.weekday) - 1]))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bgCard, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("cancel")) { dismiss() }.foregroundColor(.gray)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("save")) { Task { await save() } }
                        .foregroundColor(.bdAccent)
                        .disabled(isSaving)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { populate() }
    }

    private func populate() {
        isClosed = day.isClosed
        if let ot = day.openTime, let (h, m) = TimeOfDay.parse(ot) {
            openTime = Self.makeDate(h: h, m: m)
        } else {
            openTime = Self.makeDate(h: 17, m: 0)
        }
        if let ct = day.closeTime, let (h, m) = TimeOfDay.parse(ct) {
            closeTime = Self.makeDate(h: h, m: m)
        } else {
            closeTime = Self.makeDate(h: 3, m: 0)
        }
    }

    private static func makeDate(h: Int, m: Int) -> Date {
        var c = DateComponents()
        c.hour = h
        c.minute = m
        return Calendar.current.date(from: c) ?? Date()
    }

    private func save() async {
        isSaving = true
        error = nil
        let upsert = VenueDayUpsert(
            weekday: day.weekday,
            isClosed: isClosed,
            openTime: isClosed ? nil : TimeOfDay.dbString(from: openTime),
            closeTime: isClosed ? nil : TimeOfDay.dbString(from: closeTime)
        )
        do {
            try await venue.upsertDay(upsert)
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
}

// MARK: - Timezone utilities

enum TimezoneUtil {
    /// "JST · UTC+9" or "UTC-03:30" — returns nil for unknown identifiers.
    static func offsetLabel(for identifier: String) -> String? {
        guard let tz = TimeZone(identifier: identifier) else { return nil }
        let seconds = tz.secondsFromGMT()
        let h = seconds / 3600
        let m = abs(seconds % 3600) / 60
        let sign = seconds >= 0 ? "+" : "-"
        let offset = m == 0
            ? "UTC\(sign)\(abs(h))"
            : "UTC\(sign)\(abs(h)):\(String(format: "%02d", m))"
        let abbr = tz.abbreviation() ?? ""
        return abbr.isEmpty ? offset : "\(abbr) · \(offset)"
    }
}

// MARK: - Timezone picker sheet

private struct TimezonePickerSheet: View {
    let current: String
    @Environment(VenueViewModel.self) private var venue
    @Environment(LanguageManager.self) private var lang
    @Environment(\.dismiss) private var dismiss

    @State private var selected: String = ""
    @State private var query = ""
    @State private var isSaving = false

    private var filtered: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers.sorted()
        guard !query.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                List {
                    ForEach(filtered, id: \.self) { tz in
                        row(tz)
                            .listRowBackground(Color.bgCard)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .searchable(text: $query, prompt: tr("search_timezone"))
            .navigationTitle(tr("timezone"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bgCard, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("cancel")) { dismiss() }.foregroundColor(.gray)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("save")) { Task { await save() } }
                        .foregroundColor(.bdAccent)
                        .disabled(isSaving || selected == current)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { selected = current }
    }

    @ViewBuilder
    private func row(_ tz: String) -> some View {
        Button { selected = tz } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tz).foregroundColor(.white)
                    if let offset = TimezoneUtil.offsetLabel(for: tz) {
                        Text(offset).font(.caption).foregroundColor(.gray)
                    }
                }
                Spacer()
                if selected == tz {
                    Image(systemName: "checkmark").foregroundColor(.bdAccent)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        try? await venue.updateSettings(timezone: selected)
        isSaving = false
        dismiss()
    }
}
