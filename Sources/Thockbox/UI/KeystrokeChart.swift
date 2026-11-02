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
