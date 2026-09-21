import SwiftUI

/// A month grid. Each date is coloured by its completion state; tapping one
/// opens the full day, which stays editable however far in the past it is.
struct CalendarTab: View {
    @EnvironmentObject private var app: AppData
    @State private var month: Date = Calendar.current.startOfDay(for: Date())
    @State private var selected: DateKeyItem?

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthHeader
                    weekdayHeader
                    grid
                    legend
                }
                .padding()
            }
            .navigationTitle("Calendar")
            .sheet(item: $selected) { item in
                NavigationStack {
                    DayDetailView(dateKey: item.key)
                        .environmentObject(app)
                }
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(monthTitle).font(.headline)
            Spacer()
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
        }
    }

    private var weekdayHeader: some View {
        HStack {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                if let day = day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let key = DateKey.string(from: date, calendar: calendar)
        let completion = app.completion(for: key)
        let isToday = key == app.todayKey
        let isFuture = date > calendar.startOfDay(for: Date())
        let state: DayState = isFuture ? .noData : completion.state

        return Button {
            selected = DateKeyItem(key)
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.footnote)
                    .foregroundColor(.primary)
                Circle()
                    .fill(state.color)
                    .frame(width: 8, height: 8)
                if app.prayerTimes(on: key) == nil {
                    Text("·").font(.caption2).foregroundColor(.orange)
                } else {
                    Text(" ").font(.caption2)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(isToday ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            legendRow(.complete, "Complete (100%)")
            legendRow(.partial, "Partial")
            legendRow(.missed, "Missed")
            legendRow(.noData, "No data")
            Label("A small dot means that date has no prayer times.",
                  systemImage: "exclamationmark.circle")
                .font(.caption2)
                .foregroundColor(.orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendRow(_ state: DayState, _ text: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(state.color).frame(width: 8, height: 8)
            Text(text).font(.caption)
        }
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
            month = moved
        }
    }
}
