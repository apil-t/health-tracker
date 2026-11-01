import SwiftUI
import Charts

// Reusable building blocks. Each maps to one widget/component when porting.

struct Screen<Content: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) { content }
                .padding(.horizontal, 22)
                .padding(.bottom)
        }
        .background(Color(.systemGroupedBackground))
    }
}

/// Big number with a small unit beside it, e.g. "68 bpm".
struct Reading: View {
    let value: String
    let unit: String
    var font: Font = .title2
    var unitFont: Font = .caption2

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(font).fontWeight(.semibold)
            Text(unit).font(unitFont).foregroundStyle(.secondary)
        }
    }
}

struct Stat: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Reading(value: value, unit: unit)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Meter: View {
    let fraction: Double
    var color = Color.accentColor
    var height: CGFloat = 5
    var showsTrack = true

    var body: some View {
        Capsule()
            .fill(showsTrack ? Color(.tertiarySystemFill) : .clear)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule().fill(color).frame(width: geo.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(height: height)
            .accessibilityElement()
            .accessibilityValue(Format.percent(fraction))
    }
}

struct Ring<Label: View>: View {
    let fraction: Double
    var size: CGFloat = 100
    @ViewBuilder var label: Label

    var body: some View {
        ZStack {
            Circle().inset(by: 4).stroke(Color(.tertiarySystemFill), lineWidth: 7)
            Circle().inset(by: 4).trim(from: 0, to: min(fraction, 1))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) { label }
        }
        .frame(width: size, height: size)
    }
}

struct SectionHeading: View {
    let title: String
    var trailing: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title).font(.title3).fontWeight(.semibold)
            Spacer()
            if let trailing {
                Group {
                    if let action { Button(trailing, action: action) } else { Text(trailing) }
                }
                .font(.caption).fontWeight(.semibold).foregroundStyle(.tint)
            }
        }
        .padding(.top, 4)
    }
}

/// Label whose icon is tinted separately from its text.
struct TintedLabel: View {
    let title: String
    let systemImage: String
    var tint = Color.accentColor

    var body: some View {
        Label { Text(title) } icon: { Image(systemName: systemImage).foregroundStyle(tint) }
    }
}

struct InsightCard: View {
    let insight: Insight
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TintedLabel(title: insight.title, systemImage: systemImage).font(.footnote.weight(.semibold))
            Text(insight.message).font(.caption).foregroundStyle(.secondary)
        }
        .card(.accentColor)
    }
}

struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
    }
}

struct WorkoutIcon: View {
    let kind: Workout.Kind

    var body: some View {
        Image(systemName: kind.symbol)
            .foregroundStyle(kind.color)
            .frame(width: 44, height: 44)
            .background(kind.color.opacity(0.12), in: .rect(cornerRadius: 14))
    }
}

struct DateSelector: View {
    @Binding var dayOffset: Int

    private var date: Date { Calendar.current.date(byAdding: .day, value: dayOffset, to: .now)! }

    var body: some View {
        HStack {
            Button("Previous day", systemImage: "chevron.left") { dayOffset -= 1 }
                .labelStyle(.iconOnly)
            Spacer()
            TintedLabel(
                title: dayOffset == 0
                    ? "Today, " + date.formatted(.dateTime.day().month(.wide))
                    : date.formatted(.dateTime.weekday(.wide).day().month(.wide)),
                systemImage: "calendar"
            )
            .font(.footnote.weight(.medium))
            Spacer()
            Button("Next day", systemImage: "chevron.right") { dayOffset += 1 }
                .labelStyle(.iconOnly)
                .disabled(dayOffset == 0)
        }
        .tint(.secondary)
    }
}

struct Sparkline: View {
    let values: [Double]
    let color: Color
    var smooth = false

    var body: some View {
        Chart(values.indices, id: \.self) { i in
            LineMark(x: .value("Sample", i), y: .value("Value", values[i]))
                .interpolationMethod(smooth ? .catmullRom : .linear)
                .lineStyle(StrokeStyle(lineWidth: 2))
        }
        .foregroundStyle(color)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
    }
}

/// Create/edit sheet chrome: cancel (xmark) and save (checkmark) in the toolbar.
struct FormSheet<Content: View>: View {
    let title: String
    let canSave: Bool
    let onSave: () -> Void
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form { content }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", systemImage: "xmark") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", systemImage: "checkmark") { onSave(); dismiss() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canSave)
                    }
                }
        }
    }
}

/// Daily bars with a dashed goal line, above average / best / goal-met figures. Higher is better.
struct TrendCard: View {
    let days: [DaySummary]
    let value: (DaySummary) -> Int?
    let goal: Int
    let color: Color
    /// Full value for the figures ("8,246", "7h 42m").
    let format: (Int) -> String
    /// Short value for the axis ("8K", "7h").
    let axisFormat: (Int) -> String

    var body: some View {
        let values = days.map(value)
        let stats = HealthRules.trendStats(values, goal: goal)

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Stat(label: "Daily average", value: format(stats.average), unit: "")
                Stat(label: "Best day", value: format(stats.best), unit: "")
                Stat(label: "Goal met", value: "\(stats.daysMeetingGoal)", unit: "of \(stats.daysWithData) days")
            }
            Chart {
                ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                    if let v = values[i] {
                        BarMark(x: .value("Day", day.day, unit: .day), y: .value("Value", v))
                            .foregroundStyle(v >= goal ? color : color.opacity(0.4))
                            .cornerRadius(days.count > 31 ? 1 : 4)
                    }
                }
                RuleMark(y: .value("Goal", goal))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary)
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { mark in
                    AxisGridLine()
                    AxisValueLabel { if let v = mark.as(Int.self) { Text(axisFormat(v)) } }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: days.count <= 7 ? 7 : 5)) { _ in
                    AxisValueLabel(format: days.count <= 7 ? .dateTime.weekday(.narrow) : .dateTime.day().month(.abbreviated))
                }
            }
            .frame(height: 180)
        }
        .card(padding: 18)
    }
}
