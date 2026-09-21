import SwiftUI

/// A month heatmap. Each date is a circle whose fill strength is that day's
/// completion; tapping one opens the full day in a bottom sheet.
struct CalendarTab: View {
    @EnvironmentObject private var app: AppData
    @State private var month: Date = Calendar.current.startOfDay(for: Date())
    @State private var selected: DateKeyItem?

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: RT.sectionSpacing) {
                    monthCard
                    legend
                    monthSummary

                    Color.clear.frame(height: RT.tabBarClearance)
                }
                .padding(.horizontal, RT.screenPadding)
                .padding(.top, 8)
            }
            .routineScreen()
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $selected) { item in
                NavigationStack {
                    DayDetailView(dateKey: item.key).environmentObject(app)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(RT.background)
            }
        }
    }

    // MARK: Month

    private var monthCard: some View {
        VStack(spacing: 18) {
            monthHeader
            weekdayHeader
            grid
        }
        .card(padding: nil)
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
    }

    private var monthHeader: some View {
        HStack {
            Button {
                Haptics.selection()
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: RT.minTarget, height: RT.minTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(RT.accent)
            .accessibilityLabel("Previous month")

            Spacer()

            Text(monthTitle)
                .font(.title3.weight(.bold))
                .foregroundStyle(RT.label)
                .contentTransition(.numericText())
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button {
                Haptics.selection()
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .frame(width: RT.minTarget, height: RT.minTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(RT.accent)
            .accessibilityLabel("Next month")
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 8) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(RT.tertiaryLabel)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                if let day = day {
                    dayCell(day)
                } else {
                    Color.clear.aspectRatio(1, contentMode: .fit)
                }
            }
        }
        .animation(.routineSpring, value: month)
    }

    private func dayCell(_ date: Date) -> some View {
        let key = DateKey.string(from: date, calendar: calendar)
        let completion = app.completion(for: key)
        let isToday = key == app.todayKey
        let isFuture = date > calendar.startOfDay(for: Date())
        let state: DayState = isFuture ? .noData : completion.state
        let missingTimes = !isFuture && app.prayerTimes(on: key) == nil

        // Heatmap: stronger fill the closer the day got to finished.
        let strength: Double = {
            guard !isFuture else { return 0 }
            switch state {
            case .complete: return 1
            case .partial: return max(0.22, completion.fraction * 0.85)
            case .missed: return 0.28
            case .noData: return 0
            }
        }()
        let fill: Color = state == .missed ? .red : RT.done

        return Button {
            Haptics.selection()
            selected = DateKeyItem(key)
        } label: {
            ZStack {
                Circle().fill(fill.opacity(strength))
                if strength == 0 {
                    Circle().fill(Color.white.opacity(isFuture ? 0.03 : 0.06))
                }
                if isToday {
                    Circle().strokeBorder(RT.accent, lineWidth: 2)
                }

                VStack(spacing: 2) {
                    Text("\(calendar.component(.day, from: date))")
                        .font(.footnote.weight(isToday ? .bold : .medium))
                        .foregroundStyle(strength > 0.6 ? Color.black : RT.label.opacity(isFuture ? 0.35 : 1))
                        .monospacedDigit()

                    Circle()
                        .fill(missingTimes ? RT.prayer : Color.clear)
                        .frame(width: 4, height: 4)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(key: key, date: date, state: state,
                                               completion: completion,
                                               isFuture: isFuture,
                                               missingTimes: missingTimes))
    }

    private func accessibilityLabel(key: String, date: Date, state: DayState,
                                    completion: DayCompletion, isFuture: Bool,
                                    missingTimes: Bool) -> String {
        var parts = [DateKey.longDisplay(key, calendar: calendar)]
        if isFuture {
            parts.append("upcoming")
        } else {
            parts.append("\(completion.percent) percent, \(state.displayName)")
        }
        if missingTimes { parts.append("prayer times not entered") }
        return parts.joined(separator: ", ")
    }

    // MARK: Legend and summary

    private var legend: some View {
        HStack(spacing: 8) {
            legendPill(.complete, "Complete")
            legendPill(.partial, "Partial")
            legendPill(.missed, "Missed")
            legendPill(.noData, "No data")
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Legend: green complete, yellow partial, red missed, grey no data")
    }

    private func legendPill(_ state: DayState, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(state.color).frame(width: 7, height: 7)
            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(RT.secondaryLabel)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RT.surface, in: Capsule())
    }

    private var monthSummary: some View {
        let keys = gridDays.compactMap { $0 }.map { DateKey.string(from: $0, calendar: calendar) }
        let past = keys.filter { key in
            guard let date = DateKey.date(from: key, calendar: calendar) else { return false }
            return date <= calendar.startOfDay(for: Date())
        }
        let completions = past.map { app.completion(for: $0) }
        let complete = completions.filter { $0.state == .complete }.count
        let partial = completions.filter { $0.state == .partial }.count
        let missingTimes = past.filter { app.prayerTimes(on: $0) == nil }.count

        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader("This month")
            VStack(spacing: 12) {
                summaryRow("Days complete", "\(complete)")
                Divider().overlay(RT.hairline)
                summaryRow("Days partial", "\(partial)")
                Divider().overlay(RT.hairline)
                summaryRow("Missing prayer times", "\(missingTimes)",
                           tint: missingTimes > 0 ? RT.prayer : RT.secondaryLabel)
            }
            .card()
        }
    }

    private func summaryRow(_ title: String, _ value: String, tint: Color = RT.secondaryLabel) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(RT.label)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(tint)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Month maths

    private var monthTitle: String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "MMMM yyyy"
        return f.string(from: month)
    }

    private var weekdaySymbols: [String] {
        let f = DateFormatter()
        f.calendar = calendar
        let symbols = f.veryShortStandaloneWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Leading nils pad the first week.
    private var gridDays: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let firstOfMonth = interval.start
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        let padding = (weekday - calendar.firstWeekday + 7) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: month)?.count ?? 30

        var result: [Date?] = Array(repeating: nil, count: padding)
        for offset in 0..<dayCount {
            result.append(calendar.date(byAdding: .day, value: offset, to: firstOfMonth))
        }
        return result
    }

    private func shiftMonth(_ delta: Int) {
        if let moved = calendar.date(byAdding: .month, value: delta, to: month) {
            withAnimation(.routineSpring) { month = moved }
        }
    }
}
