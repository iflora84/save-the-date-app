import SwiftUI

enum CycleCopy {
    /// App Review treats a cycle predictor that sounds like contraception as a
    /// medical device, so the disclaimer sits next to every prediction.
    static let disclaimer: String = "Predictions are estimates from your own log. Don't use them for contraception or medical decisions."
    static let discreetFooter: String = "Lock-screen reminders say “Cycle reminder” instead of mentioning your period."
}

/// The editor's fields for a Cycle date, replacing the usual "When" section.
struct CycleEditorSection: View {
    @Binding var lastStart: Date
    @Binding var cycleLength: Int
    @Binding var periodLength: Int
    @Binding var discreet: Bool

    var body: some View {
        Section {
            DatePicker("Last period started", selection: $lastStart, in: ...Date(), displayedComponents: .date)
            Stepper(value: $cycleLength, in: CycleData.cycleLengthRange) {
                LabeledContent("Usual cycle", value: "\(cycleLength) days")
            }
            Stepper(value: $periodLength, in: CycleData.periodLengthRange) {
                LabeledContent("Period lasts", value: "\(periodLength) days")
            }
            Toggle("Discreet reminders", isOn: $discreet)
        } header: {
            Text("Cycle")
        } footer: {
            Text(CycleCopy.discreetFooter + " " + CycleCopy.disclaimer)
        }
    }
}

/// On a Cycle date's page: log a start, see the prediction and the history.
struct CycleCard: View {
    let occasion: Occasion
    let onChange: (Occasion) -> Void
    @State private var otherDay: Date = Date()

    init(occasion: Occasion, onChange: @escaping (Occasion) -> Void) {
        self.occasion = occasion
        self.onChange = onChange
    }

    var body: some View {
        if let cycle = occasion.cycle {
            content(cycle)
        }
    }

    private var today: CalendarDay {
        return CalendarDay(date: Date(), calendar: .current)
    }

    private func content(_ cycle: CycleData) -> some View {
        let loggedToday = cycle.starts.contains(today)
        return VStack(alignment: .leading, spacing: 14) {
            Text("Period tracking")
                .font(Theme.display(20, weight: .semibold))
            Text(statusText(cycle))
                .foregroundStyle(.secondary)
            Button(loggedToday ? "Logged for today" : "My period started today") {
                log(today)
            }
            .buttonStyle(PillButtonStyle(.primary))
            .disabled(loggedToday)
            HStack {
                DatePicker("Another day", selection: $otherDay, in: ...Date(), displayedComponents: .date)
                Button("Add") {
                    log(CalendarDay(date: otherDay, calendar: .current))
                }
                .buttonStyle(.borderless)
            }
            Text(statsText(cycle))
                .font(.footnote)
                .foregroundStyle(.secondary)
            history(cycle)
            Text(CycleCopy.disclaimer)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private func history(_ cycle: CycleData) -> some View {
        let recent = Array(cycle.starts.suffix(6).reversed())
        return VStack(alignment: .leading, spacing: 10) {
            Text("History")
                .font(Theme.font(15, weight: .semibold))
            ForEach(recent, id: \.self) { start in
                HStack {
                    Text(dayText(start))
                    Spacer()
                    Text(lengthText(after: start, in: cycle))
                        .foregroundStyle(.secondary)
                    // The last remaining start stays, or there would be nothing to predict from.
                    if cycle.starts.count > 1 {
                        Button {
                            remove(start)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Color.red)
                        .accessibilityLabel("Remove \(dayText(start))")
                    }
                }
                .font(.subheadline)
            }
        }
    }

    private func statusText(_ cycle: CycleData) -> String {
        let calendar = Calendar.current
        guard let status = OccasionMath.cycleStatus(cycle, today: Date(), calendar: calendar),
              let next = OccasionMath.nextPeriodStart(cycle, calendar: calendar) else {
            return "Log a start to see the next one."
        }
        let nextText = next.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        switch status {
        case .inPeriod(let day):
            return "Day \(day) of your period. The next one is expected around \(nextText)."
        case .upcoming(let days):
            if days == 0 {
                return "Your next period is expected today."
            }
            return "Next period expected \(nextText), in \(days) \(days == 1 ? "day" : "days")."
        case .late(let days):
            return "Your period is \(days) \(days == 1 ? "day" : "days") later than expected. Log it when it starts."
        }
    }

    private func statsText(_ cycle: CycleData) -> String {
        let predicted = OccasionMath.predictedCycleLength(cycle, calendar: .current)
        let logged = cycle.starts.count == 1 ? "1 start logged" : "\(cycle.starts.count) starts logged"
        return "Cycle \(predicted) days · Period \(cycle.periodLength) days · \(logged)"
    }

    private func dayText(_ day: CalendarDay) -> String {
        guard let date = day.date(calendar: .current) else { return "" }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private func lengthText(after start: CalendarDay, in cycle: CycleData) -> String {
        let calendar = Calendar.current
        guard let index = cycle.starts.firstIndex(of: start), index + 1 < cycle.starts.count,
              let from = start.date(calendar: calendar),
              let to = cycle.starts[index + 1].date(calendar: calendar),
              let days = calendar.dateComponents([.day], from: from, to: to).day else {
            return "current"
        }
        return "\(days) days"
    }

    private func log(_ day: CalendarDay) {
        var updated = occasion
        updated.cycle?.log(day)
        if let last = updated.cycle?.starts.last {
            updated.month = last.month
            updated.day = last.day
        }
        onChange(updated)
    }

    private func remove(_ day: CalendarDay) {
        var updated = occasion
        updated.cycle?.remove(day)
        if let last = updated.cycle?.starts.last {
            updated.month = last.month
            updated.day = last.day
        }
        onChange(updated)
    }
}
