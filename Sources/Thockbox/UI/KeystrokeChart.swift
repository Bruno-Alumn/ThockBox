import Charts
import SwiftUI

/// Keystrokes per day for the last week, in the settings window.
struct KeystrokeChart: View {
    @ObservedObject var store: StatsStore

    var body: some View {
        Chart(store.shown.lastWeek()) { day in
            BarMark(x: .value("Day", day.date, unit: .day),
                    y: .value("Keystrokes", day.count))
                .foregroundStyle(Color.thockCoral)
                .cornerRadius(3)
                // VoiceOver reads each bar as "Monday, 1,234 keystrokes".
                .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide)))
                .accessibilityValue(Self.spoken(day.count))
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) {
                AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let count = value.as(Int.self) { Text(count, format: .number.notation(.compactName)) }
                }
            }
        }
        .frame(height: 110)
    }

    static func spoken(_ count: Int) -> String {
        count == 1 ? "1 keystroke" : "\(count.formatted()) keystrokes"
    }
}

/// Today's keystrokes by hour, to see when you type most.
struct HourlyChart: View {
    @ObservedObject var store: StatsStore

    var body: some View {
        Chart(Array(store.shown.todayByHour.enumerated()), id: \.offset) { hour, count in
            BarMark(x: .value("Hour", hour), y: .value("Keystrokes", count))
                .foregroundStyle(Color.thockCoral)
                .cornerRadius(2)
                .accessibilityLabel(Self.hourName(hour))
                .accessibilityValue(KeystrokeChart.spoken(count))
        }
        .chartXScale(domain: -0.5...23.5)
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18]) { value in
                AxisValueLabel {
                    if let hour = value.as(Int.self) { Text(Self.hourName(hour)) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let count = value.as(Int.self) { Text(count, format: .number.notation(.compactName)) }
                }
            }
        }
        .frame(height: 90)
    }

    /// "6 AM" or "18", whichever the user's clock uses.
    static func hourName(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(.dateTime.hour())
    }
}
