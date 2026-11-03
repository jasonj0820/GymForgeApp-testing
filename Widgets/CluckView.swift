import SwiftUI

/// Sergeant Cluck, drawn in code (100×100 design grid) so the app and the widget share him.
/// MK11.1: `animated` (in the app only — widgets stay still) adds a gentle bob, blinks and accessory motion.
struct CluckView: View {
    let mood: CluckMood
    var animated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if animated && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                canvas(time: timeline.date.timeIntervalSinceReferenceDate)
            }
        } else {
            canvas(time: nil)
        }
    }

    private func canvas(time: Double?) -> some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 100
            context.translateBy(x: (size.width - 100 * scale) / 2, y: (size.height - 100 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            CluckDrawing.draw(&context, mood: mood, time: time)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Sergeant Cluck, \(mood.title)")
    }
}

extension CluckMood {
    /// Widget / card background tint.
    var tint: Color {
        switch self {
        case .celebrating: return .yellow
        case .proud: return .green
        case .chill: return .teal
        case .watching: return .orange
        case .annoyed: return .orange
        case .furious: return .red
        case .doomed: return .gray
        case .sulking: return .purple
        case .suspicious: return .brown
        case .impressed: return .mint
        case .smug: return .indigo
        case .worried: return .cyan
        case .relieved: return .green
        case .sleepy: return .indigo
        case .analytical: return .blue
        case .lockedIn: return .red
        case .protective: return .cyan
        case .empathetic: return .pink
        }
    }
}

/// Sergeant Cluck: a chicken in a drill-sergeant hat (100×100 design grid).
/// MK11.1: back to the chicken, with every mood (MK11 + MK11.1) and their accessories.
enum CluckDrawing {
    private static let outline = Color(white: 0.15)
    private static let feather = Color(white: 0.98)
    private static let beakColor = Color(red: 1.0, green: 0.62, blue: 0.1)
    private static let red = Color(red: 0.88, green: 0.12, blue: 0.12)
    private static let gold = Color(red: 0.95, green: 0.78, blue: 0.25)
    private static let hatColor = Color(red: 0.45, green: 0.32, blue: 0.16)
    private static let hatBand = Color(red: 0.25, green: 0.17, blue: 0.08)
    private static let mouthDark = Color(red: 0.45, green: 0.05, blue: 0.05)

    private static func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h))
    }

    private static func poly(_ points: [(CGFloat, CGFloat)]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.0, y: first.1))
        for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.0, y: point.1)) }
        path.closeSubpath()
        return path
    }

    private static func line(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat)) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: a.0, y: a.1))
        path.addLine(to: CGPoint(x: b.0, y: b.1))
        return path
    }

    private static func curve(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat), control: (CGFloat, CGFloat)) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: a.0, y: a.1))
        path.addQuadCurve(to: CGPoint(x: b.0, y: b.1), control: CGPoint(x: control.0, y: control.1))
        return path
    }

    static func draw(_ ctx: inout GraphicsContext, mood: CluckMood, time: Double? = nil) {
        let angry = mood == .annoyed || mood == .furious
        let happy = [.celebrating, .proud, .impressed, .relieved].contains(mood)
        // MK11.1: subtle motion — a slow bob (faster and tighter when locked in) and a blink every ~4 s.
        if let time {
            let speed = mood == .lockedIn ? 3.2 : 1.6
            ctx.translateBy(x: 0, y: CGFloat(sin(time * speed)) * (mood == .lockedIn ? 0.6 : 1.0))
        }
        let blinking = time.map { $0.truncatingRemainder(dividingBy: 4.3) < 0.14 } ?? false

        // Wings (raised and flapping when furious or celebrating; one wing up to guard when protective)
        let wingsUp = mood == .furious || mood == .celebrating
        let flap = time.map { CGFloat(sin($0 * 6)) * 2 } ?? 0
        let leftWing = wingsUp || mood == .protective ? poly([(22, 60), (4, 40 + flap), (10, 66)]) : oval(12, 56, 14, 24)
        let rightWing = wingsUp ? poly([(78, 60), (96, 40 + flap), (90, 66)]) : oval(74, 56, 14, 24)
        for wing in [leftWing, rightWing] {
            ctx.fill(wing, with: .color(feather))
            ctx.stroke(wing, with: .color(outline), lineWidth: 1.5)
        }

        // Body / head
        let body = oval(20, 24, 60, 68)
        ctx.fill(body, with: .color(feather))
        ctx.stroke(body, with: .color(outline), lineWidth: 1.8)

        // Cheeks
        if angry || happy || mood == .empathetic {
            let blush = angry ? red.opacity(mood == .furious ? 0.55 : 0.35) : Color.pink.opacity(0.35)
            ctx.fill(oval(24, 54, 11, 6), with: .color(blush))
            ctx.fill(oval(65, 54, 11, 6), with: .color(blush))
        }

        drawEyes(&ctx, mood: mood, blinking: blinking)

        // Eyebrows
        let brows: [((CGFloat, CGFloat), (CGFloat, CGFloat))]
        switch mood {
        case .annoyed, .furious:
            brows = [((29, 35), (45, 41)), ((55, 41), (71, 35))]
        case .watching, .suspicious:
            brows = [((30, 39), (45, 39)), ((55, 35), (70, 31))]
        case .doomed, .sulking, .worried, .empathetic:
            brows = [((30, 41), (45, 36)), ((55, 36), (70, 41))]
        case .lockedIn, .protective:
            brows = [((29, 37), (45, 40)), ((55, 40), (71, 37))]
        case .analytical:
            brows = [((30, 38), (45, 38)), ((55, 35), (70, 36))]
        case .smug:
            brows = [((30, 37), (45, 37)), ((55, 33), (70, 35))]
        default:
            brows = [((30, 38), (45, 36)), ((55, 36), (70, 38))]
        }
        for (a, b) in brows {
            ctx.stroke(line(a, b), with: .color(outline),
                       style: StrokeStyle(lineWidth: mood == .furious ? 4.2 : 3, lineCap: .round))
        }

        // Wattle
        ctx.fill(oval(46, 64, 7, 11), with: .color(red))

        drawBeak(&ctx, mood: mood)

        // Drill-sergeant campaign hat
        let crown = poly([(31, 27), (37, 12), (45, 16), (50, 7), (55, 16), (63, 12), (69, 27)])
        ctx.fill(crown, with: .color(hatColor))
        ctx.stroke(crown, with: .color(outline), lineWidth: 1.2)
        ctx.fill(Path(CGRect(x: 32, y: 22, width: 36, height: 4)), with: .color(hatBand))
        let brim = oval(16, 24, 68, 9)
        ctx.fill(brim, with: .color(hatColor))
        ctx.stroke(brim, with: .color(outline), lineWidth: 1.2)

        drawAccessory(&ctx, mood: mood, time: time)

        // Extras
        switch mood {
        case .furious:
            for (a, b) in [((80, 8), (84, 14)), ((90, 8), (86, 14)), ((80, 22), (84, 16)), ((90, 22), (86, 16))] as [((CGFloat, CGFloat), (CGFloat, CGFloat))] {
                ctx.stroke(line(a, b), with: .color(red), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            }
        case .doomed, .watching, .worried:
            let drop = poly([(78, 34), (74, 42), (82, 42)])
            ctx.fill(drop, with: .color(.blue.opacity(0.7)))
            ctx.fill(oval(74, 39, 8, 7), with: .color(.blue.opacity(0.7)))
        case .celebrating, .impressed:
            let confetti: [(CGFloat, CGFloat, Color)] = [(8, 14, .pink), (88, 10, .blue), (14, 90, .green),
                                                         (86, 86, .orange), (6, 46, .purple), (94, 50, .yellow)]
            for (x, y, color) in confetti {
                ctx.fill(Path(CGRect(x: x, y: y, width: 5, height: 5)), with: .color(color))
            }
        case .sulking, .sleepy:
            ctx.draw(Text("z").font(.system(size: 12, weight: .bold)).foregroundStyle(outline), at: CGPoint(x: 84, y: 30))
            ctx.draw(Text("z").font(.system(size: 9, weight: .bold)).foregroundStyle(outline), at: CGPoint(x: 91, y: 21))
        case .suspicious:
            ctx.draw(Text("?").font(.system(size: 16, weight: .heavy)).foregroundStyle(outline), at: CGPoint(x: 86, y: 26))
        case .relieved:
            ctx.stroke(curve((78, 40), (90, 34), control: (86, 42)), with: .color(.blue.opacity(0.6)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))
        default:
            break
        }
    }

    /// Open beak when shouting or cheering, a small "o" yawn when sleepy, a crooked one when smug.
    private static func drawBeak(_ ctx: inout GraphicsContext, mood: CluckMood) {
        switch mood {
        case .furious, .annoyed, .celebrating:
            ctx.fill(oval(44, 55, 12, 12), with: .color(mouthDark))
            for part in [poly([(43, 54), (57, 54), (50, 60)]), poly([(45, 64), (55, 64), (50, 70)])] {
                ctx.fill(part, with: .color(beakColor))
                ctx.stroke(part, with: .color(outline), lineWidth: 1)
            }
        case .sleepy:
            ctx.fill(oval(46, 57, 8, 8), with: .color(mouthDark))
            for part in [poly([(44, 55), (56, 55), (50, 59)]), poly([(46, 64), (54, 64), (50, 67)])] {
                ctx.fill(part, with: .color(beakColor))
                ctx.stroke(part, with: .color(outline), lineWidth: 1)
            }
        case .smug:
            let beak = poly([(43, 56), (57, 54), (51, 65)])
            ctx.fill(beak, with: .color(beakColor))
            ctx.stroke(beak, with: .color(outline), lineWidth: 1)
        default:
            let beak = poly([(43, 55), (57, 55), (50, 65)])
            ctx.fill(beak, with: .color(beakColor))
            ctx.stroke(beak, with: .color(outline), lineWidth: 1)
        }
    }

    /// MK11.1: one accessory per new mood (Impressed and Smug get theirs too).
    private static func drawAccessory(_ ctx: inout GraphicsContext, mood: CluckMood, time: Double?) {
        let wave = CGFloat(sin((time ?? 0) * 2.4))
        switch mood {
        case .analytical:
            // Round glasses and a clipboard under the wing
            for x in [38, 62] as [CGFloat] {
                ctx.stroke(oval(x - 9, 39, 18, 18), with: .color(outline), lineWidth: 1.6)
            }
            ctx.stroke(line((47, 48), (53, 48)), with: .color(outline), lineWidth: 1.4)
            let board = Path(roundedRect: CGRect(x: 72, y: 66, width: 20, height: 26), cornerRadius: 2)
            ctx.fill(board, with: .color(Color(red: 0.62, green: 0.45, blue: 0.25)))
            ctx.fill(Path(CGRect(x: 74, y: 70, width: 16, height: 20)), with: .color(.white))
            ctx.fill(Path(roundedRect: CGRect(x: 78, y: 64, width: 8, height: 4), cornerRadius: 1), with: .color(.gray))
            for row in 0..<3 {
                let y = 75 + CGFloat(row) * 5
                ctx.stroke(line((76, y), (88 - (time == nil ? 0 : 2 * abs(wave)), y)), with: .color(.blue.opacity(0.7)), lineWidth: 1.2)
            }
        case .lockedIn:
            // Red sweatband under the brim and a whistle on a lanyard
            ctx.fill(Path(roundedRect: CGRect(x: 25, y: 32, width: 50, height: 5), cornerRadius: 2), with: .color(red))
            ctx.stroke(curve((38, 66), (58, 80), control: (44, 84)), with: .color(.gray), lineWidth: 1)
            let whistle = Path(roundedRect: CGRect(x: 56, y: 78, width: 9, height: 5), cornerRadius: 2)
            ctx.fill(whistle, with: .color(Color(white: 0.75)))
            ctx.stroke(whistle, with: .color(outline), lineWidth: 0.8)
        case .impressed:
            // Medal on the chest, swinging a little
            let swing = time == nil ? 0 : wave * 1.2
            ctx.stroke(line((58, 70), (62 + swing, 80)), with: .color(.blue), lineWidth: 2.4)
            ctx.stroke(line((66, 70), (62 + swing, 80)), with: .color(.red), lineWidth: 2.4)
            let medal = oval(58 + swing, 79, 8, 8)
            ctx.fill(medal, with: .color(gold))
            ctx.stroke(medal, with: .color(outline), lineWidth: 1)
        case .smug:
            // Aviator shades, with a glint that sweeps across now and then
            for x in [38, 62] as [CGFloat] {
                let lens = poly([(x - 9, 42), (x + 9, 42), (x + 8, 50), (x, 54), (x - 8, 50)])
                ctx.fill(lens, with: .color(Color(white: 0.12)))
                ctx.stroke(lens, with: .color(Color(white: 0.6)), lineWidth: 0.8)
            }
            ctx.stroke(line((47, 43), (53, 43)), with: .color(Color(white: 0.6)), lineWidth: 1.2)
            if let time {
                let glint = CGFloat(time.truncatingRemainder(dividingBy: 3.5) / 3.5)
                if glint < 0.3 {
                    let x = 30 + glint / 0.3 * 16
                    ctx.stroke(line((x, 44), (x + 3, 48)), with: .color(.white.opacity(0.8)), lineWidth: 1.2)
                }
            }
        case .protective:
            // Shield held up on the raised wing
            let lift = time == nil ? 0 : wave * 0.8
            let shield = poly([(2, 50 + lift), (20, 50 + lift), (20, 64 + lift), (11, 74 + lift), (2, 64 + lift)])
            ctx.fill(shield, with: .color(Color(red: 0.2, green: 0.45, blue: 0.75)))
            ctx.stroke(shield, with: .color(outline), lineWidth: 1.2)
            ctx.stroke(line((11, 54 + lift), (11, 68 + lift)), with: .color(.white), lineWidth: 2.4)
            ctx.stroke(line((5, 60 + lift), (17, 60 + lift)), with: .color(.white), lineWidth: 2.4)
        case .empathetic:
            // A floating heart that beats softly
            let beat = time == nil ? 1 : 1 + 0.08 * max(wave, 0)
            var heart = Path()
            heart.move(to: CGPoint(x: 86, y: 40))
            heart.addCurve(to: CGPoint(x: 86, y: 28), control1: CGPoint(x: 76, y: 34), control2: CGPoint(x: 80, y: 24))
            heart.addCurve(to: CGPoint(x: 86, y: 40), control1: CGPoint(x: 92, y: 24), control2: CGPoint(x: 96, y: 34))
            let center = CGAffineTransform(translationX: 86, y: 33).scaledBy(x: beat, y: beat).translatedBy(x: -86, y: -33)
            ctx.fill(heart.applying(center), with: .color(.pink))
        default:
            break
        }
    }

    private static func drawEyes(_ ctx: inout GraphicsContext, mood: CluckMood, blinking: Bool = false) {
        let centers: [CGFloat] = [38, 62]
        let y: CGFloat = 48
        if blinking && mood != .smug {
            for x in centers {
                ctx.stroke(line((x - 6, y), (x + 6, y)), with: .color(outline), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            }
            return
        }
        switch mood {
        case .celebrating, .proud, .impressed, .relieved:
            // Happy closed eyes ∩
            for x in centers {
                ctx.stroke(curve((x - 6, y + 3), (x + 6, y + 3), control: (x, y - 6)), with: .color(outline),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        case .sleepy:
            for x in centers {
                ctx.stroke(curve((x - 6, y), (x + 6, y), control: (x, y + 4)), with: .color(outline),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        default:
            let radius: CGFloat = mood == .furious ? 6.5 : 7
            for x in centers {
                let eye = oval(x - radius, y - radius, radius * 2, radius * 2)
                ctx.fill(eye, with: .color(.white))
                ctx.stroke(eye, with: .color(outline), lineWidth: 1.4)
                var dx: CGFloat = 0, dy: CGFloat = 0
                if mood == .furious || mood == .annoyed { dx = x < 50 ? 1.5 : -1.5 }   // glaring in
                if mood == .doomed || mood == .worried || mood == .empathetic { dy = 2.5 }   // looking down
                if mood == .watching || mood == .suspicious { dx = 2.5 }            // side-eye
                if mood == .analytical { dy = -1.5 }                                 // thinking
                let pupil: CGFloat = mood == .furious ? 2.6 : 3.3
                ctx.fill(oval(x - pupil + dx, y - pupil + dy, pupil * 2, pupil * 2), with: .color(outline))
                if [.sulking, .doomed, .suspicious, .smug, .lockedIn].contains(mood) {
                    // Heavy lids
                    var lidLayer = ctx
                    lidLayer.clip(to: eye)
                    lidLayer.fill(Path(CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius)),
                                  with: .color(feather))
                    ctx.stroke(line((x - radius, y), (x + radius, y)), with: .color(outline), lineWidth: 1.6)
                }
            }
        }
    }
}
