import SwiftUI
import UIKit

/// A set was just logged: shows the pop-up tick on the workout screen.
struct SetTick: Identifiable, Equatable {
    let id: UUID
    let isPR: Bool
    /// "Bench Press done" on an exercise's last set, "All sets done" at the end.
    let caption: String?

    static let animationKey = "tick.animation"
    static let hapticKey = "tick.haptic"

    static var animationEnabled: Bool { UserDefaults.standard.object(forKey: animationKey) as? Bool ?? true }
    static var hapticEnabled: Bool { UserDefaults.standard.object(forKey: hapticKey) as? Bool ?? true }

    /// Two quick taps (iOS's "success" pattern). PRs get an extra heavy thump after it.
    @MainActor
    static func playHaptic(pr: Bool) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
        guard pr else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            let thump = UIImpactFeedbackGenerator(style: .heavy)
            thump.impactOccurred(intensity: 1)
        }
    }
}

/// Green circle pops in and the tick draws itself in the middle (gold + confetti for a PR).
/// Never blocks taps; with Reduce Motion on it simply fades in and out.
struct SetTickOverlay: View {
    let tick: SetTick
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scale: CGFloat = 0.4
    @State private var drawn: CGFloat = 0
    @State private var opacity: Double = 0
    @State private var burst = false

    private var color: Color { tick.isPR ? Color(red: 1.0, green: 0.78, blue: 0.1) : .green }
    private var holdTime: Double { tick.isPR || tick.caption != nil ? 1.1 : 0.55 }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                if tick.isPR && !reduceMotion {
                    ConfettiBurst(fired: burst)
                }
                Circle()
                    .fill(color.gradient)
                    .frame(width: 128, height: 128)
                    .shadow(color: color.opacity(0.45), radius: 18)
                TickShape()
                    .trim(from: 0, to: drawn)
                    .stroke(.white, style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
                    .frame(width: 62, height: 48)
                if tick.isPR {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(y: -44)
                        .opacity(drawn)
                }
            }
            .scaleEffect(scale)

            if let text = label {
                Text(text)
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .opacity(opacity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "Set logged")
        .onAppear(perform: run)
    }

    private var label: String? {
        switch (tick.isPR, tick.caption) {
        case (true, let caption?): return "New PR · \(caption) ✓"
        case (true, nil): return "New PR!"
        case (false, let caption?): return "\(caption) ✓"
        default: return nil
        }
    }

    private func run() {
        if reduceMotion {
            scale = 1
            drawn = 1
            withAnimation(.easeIn(duration: 0.15)) { opacity = 1 }
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) {
                scale = 1
                opacity = 1
            }
            withAnimation(.easeOut(duration: 0.32).delay(0.12)) { drawn = 1 }
            if tick.isPR {
                withAnimation(.easeOut(duration: 0.9).delay(0.1)) { burst = true }
            }
        }
        // Fade out later, in its own transaction (setting it now would cancel the fade-in).
        let reduce = reduceMotion
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(holdTime * 1_000_000_000))
            withAnimation(.easeIn(duration: 0.25)) {
                opacity = 0
                if !reduce { scale = 1.08 }
            }
        }
    }
}

/// ✓ drawn as one path, so it can be traced with `trim`.
struct TickShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// Little pieces flying out from the tick for a PR.
private struct ConfettiBurst: View {
    let fired: Bool
    private static let colors: [Color] = [.yellow, .orange, .pink, .green, .blue, .purple, .red]
    private static let pieces: [(angle: Double, distance: CGFloat, size: CGFloat, spin: Double)] =
        (0..<28).map { index in
            let angle = Double(index) / 28 * 2 * .pi + Double(index % 3) * 0.09
            let distance = CGFloat(110 + (index * 37) % 70)
            let size = CGFloat(6 + (index * 5) % 6)
            return (angle, distance, size, Double((index * 53) % 360))
        }

    var body: some View {
        ZStack {
            ForEach(Self.pieces.indices, id: \.self) { index in
                let piece = Self.pieces[index]
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Self.colors[index % Self.colors.count])
                    .frame(width: piece.size, height: piece.size * 1.6)
                    .rotationEffect(.degrees(fired ? piece.spin + 240 : piece.spin))
                    .offset(x: fired ? cos(piece.angle) * piece.distance : 0,
                            y: fired ? sin(piece.angle) * piece.distance + 30 : 0)
                    .opacity(fired ? 0 : 1)
            }
        }
    }
}
