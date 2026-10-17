import SwiftUI

/// A minimal price line.
///
/// Declared `nonisolated` so SwiftUI is free to evaluate `path(in:)` and
/// animate `animatableData` off the main actor. Render-time code in this module
/// (shapes, layouts, visual effects) follows the same rule: pure value types
/// with no access to app state.
nonisolated public struct Sparkline: Shape {
    public var values: [Double]

    public init(values: [Double]) {
        self.values = values
    }

    public func path(in rect: CGRect) -> Path {
        guard values.count > 1, let low = values.min(), let high = values.max() else {
            return Path()
        }
        let span = max(high - low, .ulpOfOne)
        let step = rect.width / CGFloat(values.count - 1)

        return Path { path in
            for (index, value) in values.enumerated() {
                let point = CGPoint(
                    x: rect.minX + CGFloat(index) * step,
                    y: rect.maxY - CGFloat((value - low) / span) * rect.height
                )
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
    }
}

#Preview {
    Sparkline(values: [3, 4, 3.5, 5, 4.8, 6, 5.5, 7])
        .stroke(.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        .frame(height: 80)
        .padding()
}
