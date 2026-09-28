import IdasenKit
import SwiftUI

/// A compact elevation drawing. Only position changes redraw its geometry;
/// connection timestamps, logs and speed updates do not affect this view.
struct DeskIllustration: View, Equatable {
    var heightMM: Double?
    var targetMM: Double?
    var scale: HeightScale
    var accent: Color
    var isMoving: Bool
    var unit: LengthUnit

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let floor = proxy.size.height - 32
            let travel = floor - 90
            let fraction = scale.fraction(forMillimeters: heightMM ?? scale.minimumMM)
            let top = floor - 65 - travel * fraction
            let left = width * 0.08
            let right = width * 0.72
            let rail = width - 34

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    var ground = Path()
                    ground.move(to: CGPoint(x: 0, y: floor))
                    ground.addLine(to: CGPoint(x: size.width, y: floor))
                    context.stroke(ground, with: .color(.secondary.opacity(0.18)), lineWidth: 1)
                    var ticks = Path()
                    for index in 0...10 {
                        let y = floor - 65 - travel * Double(index) / 10
                        ticks.move(to: CGPoint(x: rail, y: y))
                        ticks.addLine(to: CGPoint(x: rail + (index % 5 == 0 ? 12 : 6), y: y))
                    }
                    context.stroke(ticks, with: .color(.secondary.opacity(0.35)), lineWidth: 1)
                }

                // Two telescoping columns with a fixed lower sleeve.
                ForEach([0.18, 0.82], id: \.self) { position in
                    let x = left + (right - left) * position
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.primary.opacity(0.16))
                        .frame(width: 12, height: max(20, floor - top - 10))
                        .offset(x: x, y: top + 10)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.primary.opacity(0.12))
                        .frame(width: 18, height: 49)
                        .offset(x: x - 3, y: floor - 53)
                    Capsule()
                        .fill(.primary.opacity(0.26))
                        .frame(width: 52, height: 6)
                        .offset(x: x - 20, y: floor - 6)
                }

                RoundedRectangle(cornerRadius: 4)
                    .fill(accent)
                    .frame(width: right - left, height: 10)
                    .offset(x: left, y: top)
                // Screen and stand travel with the work surface.
                RoundedRectangle(cornerRadius: 6)
                    .fill(.primary.opacity(0.07))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.22), lineWidth: 2))
                    .frame(width: 86, height: 52)
                    .offset(x: (left + right) / 2 - 43, y: top - 67)
                Rectangle().fill(.primary.opacity(0.22))
                    .frame(width: 4, height: 15)
                    .offset(x: (left + right) / 2 - 2, y: top - 15)
                Capsule().fill(.primary.opacity(0.22))
                    .frame(width: 32, height: 3)
                    .offset(x: (left + right) / 2 - 16, y: top - 3)

                Capsule().fill(accent)
                    .frame(width: 20, height: 3)
                    .offset(x: rail - 4, y: top + 3)

                if let targetMM, abs(targetMM - (heightMM ?? targetMM)) > 4 {
                    let targetY = floor - 65 - travel * scale.fraction(forMillimeters: targetMM)
                    Path { path in
                        path.move(to: CGPoint(x: left, y: targetY))
                        path.addLine(to: CGPoint(x: rail, y: targetY))
                    }
                    .stroke(accent.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }

                Text(unit.format(millimeters: scale.maximumMM))
                    .offset(x: rail - 36, y: floor - 65 - travel - 24)
                Text(unit.format(millimeters: scale.minimumMM))
                    .offset(x: rail - 36, y: floor - 65 + 16)
                Text(isMoving ? "Adjusting your workspace" : "Ready for your next position")
                    .frame(width: width, alignment: .center)
                    .offset(y: floor + 14)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Desk height")
        .accessibilityValue(heightMM.map { unit.format(millimeters: $0) } ?? "Unknown")
    }
}
