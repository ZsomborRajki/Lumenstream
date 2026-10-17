import SwiftUI

/// A slow, dark mesh gradient that sits behind every screen so Liquid Glass has
/// something to refract.
///
/// The colors are animated with `TimelineView` on a coarse schedule rather
/// than with state, so nothing else in the hierarchy re-renders when it moves.
public struct AmbientBackground: View {
    public init() {}

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate / 12
            MeshGradient(
                width: 3,
                height: 3,
                points: Self.points(phase: phase),
                colors: Self.colors
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private static let colors: [Color] = [
        .indigo, .black, .teal,
        .black, .purple.opacity(0.6), .black,
        .cyan.opacity(0.5), .black, .indigo,
    ]

    private static func points(phase: Double) -> [SIMD2<Float>] {
        let drift = Float(sin(phase)) * 0.12
        return [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.5], [0.5 + drift, 0.5 - drift], [1, 0.5],
            [0, 1], [0.5, 1], [1, 1],
        ]
    }
}

#Preview {
    AmbientBackground()
}
