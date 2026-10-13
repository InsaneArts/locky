import SwiftUI

/// The Lock Screen's gauges, drawn at any size: SwiftUI's own accessory styles have one fixed size, and a
/// scaled one blurs.
///
/// - "circular": an open arc with a marker at the value, the value in the middle, and a symbol or the range
///   in the gap at the bottom (`accessoryCircular`).
/// - "capacity": a closed ring filled to the value, the value in the middle (`accessoryCircularCapacity`).
/// - "linear": a track with a marker at the value (`accessoryLinear`).
/// - "linear-capacity": a bar filled to the value (`accessoryLinearCapacity`).
struct GaugeView: View {
    let fraction: Double
    let style: String
    /// The diameter of a circular gauge, or the width of a linear one, in points before scaling.
    let size: Double
    let tint: AnyShapeStyle
    let valueLabel: String?
    let icon: String?
    let label: String?
    let minLabel: String?
    let maxLabel: String?
    let weight: Font.Weight
    @Environment(\.lockyStyle) private var lockyStyle

    var body: some View {
        switch style {
        case "linear", "linear-capacity": linear
        default: circular
        }
    }

    private var value: CGFloat { CGFloat(min(max(fraction, 0), 1)) }

    private var circular: some View {
        let diameter = lockyStyle.s(size)
        let line = diameter * 0.095
        let open = style != "capacity"
        // The open gauge leaves a quarter of the circle free at the bottom, for its symbol or range.
        let gap = open ? 0.25 : 0.0
        return ZStack {
            if open {
                arc(from: 0, to: 1, gap: gap).stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .opacity(0.9)
                marker(diameter: diameter, line: line, angle: angle(at: value, gap: gap))
            } else {
                Circle().stroke(tint, lineWidth: line).opacity(0.3)
                Circle().trim(from: 0, to: value)
                    .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                if let valueLabel {
                    Text(valueLabel)
                        .font(.system(size: diameter * (valueLabel.count > 3 ? 0.26 : 0.34), weight: open ? .regular : weight))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .padding(.horizontal, line * 1.6)
                }
            }
            if open {
                bottom(diameter: diameter)
                    .frame(width: diameter * 0.5)
                    .offset(y: diameter * 0.31)
            }
        }
        // The track takes the tint; the labels stay the text color.
        .foregroundStyle(lockyStyle.color("fg"))
        .frame(width: diameter, height: diameter)
        .compositingGroup()
    }

    @ViewBuilder private func bottom(diameter: CGFloat) -> some View {
        if let icon {
            Image(systemName: icon).font(.system(size: diameter * 0.19, weight: .semibold))
        } else if minLabel != nil || maxLabel != nil {
            HStack(spacing: 0) {
                Text(minLabel ?? "")
                Spacer(minLength: 2)
                Text(maxLabel ?? "")
            }
            .font(.system(size: diameter * 0.16, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        } else if let label {
            Text(label).font(.system(size: diameter * 0.15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    /// The angle, in degrees clockwise from 12 o'clock, of `value` on an arc that leaves `gap` free at the bottom.
    private func angle(at value: CGFloat, gap: Double) -> Double {
        let sweep = 360 * (1 - gap)
        return -sweep / 2 + sweep * Double(value)
    }

    private func arc(from start: CGFloat, to end: CGFloat, gap: Double) -> some Shape {
        Circle()
            .trim(from: gap / 2 + (1 - gap) * start, to: gap / 2 + (1 - gap) * end)
            .rotation(.degrees(90))
    }

    /// Apple's marker: a dot in the track's color with a ring cut out around it, so it reads on any track.
    private func marker(diameter: CGFloat, line: CGFloat, angle: Double) -> some View {
        let radius = diameter / 2
        let radians = angle * .pi / 180
        return Circle()
            .fill(lockyStyle.color("fg"))
            .frame(width: line * 1.25, height: line * 1.25)
            .padding(line * 0.45)
            .background(Circle().fill(.black).blendMode(.destinationOut))
            .offset(x: radius * sin(radians), y: -radius * cos(radians))
    }

    private var linear: some View {
        let width = lockyStyle.s(size)
        let line = lockyStyle.s(6)
        return VStack(alignment: .leading, spacing: lockyStyle.s(4)) {
            if label != nil || icon != nil || valueLabel != nil {
                HStack(spacing: lockyStyle.s(4)) {
                    if let icon { Image(systemName: icon) }
                    if let label { Text(label) }
                    Spacer(minLength: 0)
                    if let valueLabel { Text(valueLabel).monospacedDigit() }
                }
                .font(.system(size: lockyStyle.s(13), weight: .semibold))
                .lineLimit(1)
            }
            ZStack(alignment: .leading) {
                if style == "linear" {
                    Capsule().fill(tint).opacity(0.9)
                    Circle().fill(lockyStyle.color("fg"))
                        .frame(width: line * 1.25, height: line * 1.25)
                        .padding(line * 0.45)
                        .background(Circle().fill(.black).blendMode(.destinationOut))
                        .offset(x: (width - line * 2.15) * value)
                } else {
                    Capsule().fill(tint).opacity(0.3)
                    Capsule().fill(tint).frame(width: max(line, width * value))
                }
            }
            .frame(width: width, height: line)
            if minLabel != nil || maxLabel != nil {
                HStack {
                    Text(minLabel ?? "")
                    Spacer(minLength: 0)
                    Text(maxLabel ?? "")
                }
                .font(.system(size: lockyStyle.s(11), weight: .semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
        .frame(width: width)
        .compositingGroup()
    }
}
