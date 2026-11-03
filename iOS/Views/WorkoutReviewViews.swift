import AVFoundation
import Charts
import SwiftUI

/// MK10.1: the coach's brief after a workout — a one-line rating, a few sentences, and "Read aloud".
struct CoachBriefSection: View {
    @EnvironmentObject private var store: PhoneAppStore
    let log: WorkoutLog
    @ObservedObject private var speaker = BriefSpeaker.shared

    var body: some View {
        let brief = store.brief(for: log)
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(brief.rating)
                    .font(.title3.bold())
                    .foregroundStyle(ratingColor(brief.rating))
                ForEach(brief.lines, id: \.self) { line in
                    Text(line).font(.subheadline)
                }
                Button {
                    speaker.toggle(brief.spoken)
                } label: {
                    Label(speaker.isSpeaking ? "Stop" : "Read aloud", systemImage: speaker.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Coach · \(store.profile.coachStyle.title)")
        }
        .onDisappear { speaker.stop() }
    }

    private func ratingColor(_ rating: String) -> Color {
        if rating.hasPrefix("Strong") { return .green }
        if rating.hasPrefix("Solid") || rating.hasPrefix("Easy") { return .blue }
        if rating.hasPrefix("Mixed") { return .orange }
        return .red
    }
}

/// Peak / average / vs your usual, the graph with a mark for every set, zones, and which lift pushed it highest.
struct HeartRateSection: View {
    @EnvironmentObject private var store: PhoneAppStore
    let log: WorkoutLog

    var body: some View {
        let summary = HeartRateAnalysis.summary(for: log, logs: store.workoutLogs, maxHeartRate: store.estimatedMaxHeartRate)
        if summary.peak != nil || !summary.exercisePeaks.isEmpty {
            Section {
                HStack(spacing: 0) {
                    figure("Peak", summary.peak.map { "\($0)" } ?? "–", color: .red)
                    figure("Average", summary.average.map { "\($0)" } ?? "–", color: .primary)
                    figure("Usual peak", summary.usualPeak.map { "\($0)" } ?? "–", color: .secondary)
                }
                if let peak = summary.peak, let usual = summary.usualPeak, abs(peak - usual) >= 5 {
                    Text(peak > usual
                         ? "Peak \(peak - usual) bpm higher than your usual \(log.routineName) — a harder session (or less rest)."
                         : "Peak \(usual - peak) bpm lower than your usual \(log.routineName) — easier on the heart today.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let series = log.heartRateSeries, series.count >= 3 {
                    chart(series)
                }
                if summary.zoneSeconds.reduce(0, +) > 60 {
                    zones(summary.zoneSeconds)
                }
                ForEach(summary.exercisePeaks.prefix(6), id: \.name) { item in
                    HStack {
                        Text(item.name).font(.subheadline)
                        Spacer()
                        Text("\(item.peak) bpm").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Heart rate")
            } footer: {
                Text(log.heartRateSeries == nil ? "The graph needs the Watch app to record the workout." : "Grey lines are your sets.")
            }
        }
    }

    private func figure(_ title: String, _ value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.bold().monospacedDigit()).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func chart(_ series: [HeartRatePoint]) -> some View {
        let setMinutes = log.exercises.flatMap(\.sets).map { $0.completedAt.timeIntervalSince(log.startedAt) / 60 }
            .filter { $0 >= 0 }
        let low = (series.map(\.bpm).min() ?? 60) - 10
        let high = (series.map(\.bpm).max() ?? 180) + 5
        return Chart {
            ForEach(setMinutes, id: \.self) { minute in
                RuleMark(x: .value("Set", minute))
                    .foregroundStyle(Color.secondary.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
            ForEach(series, id: \.t) { point in
                LineMark(x: .value("Minutes", Double(point.t) / 60), y: .value("bpm", point.bpm))
                    .foregroundStyle(.red)
                    .interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: low...high)
        .chartXAxisLabel("min")
        .frame(height: 170)
    }

    private func zones(_ seconds: [Double]) -> some View {
        let total = seconds.reduce(0, +)
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(0..<min(5, seconds.count), id: \.self) { index in
                HStack {
                    Text("Zone \(index + 1)").font(.caption).frame(width: 52, alignment: .leading)
                    SwiftUI.ProgressView(value: seconds[index], total: total)
                        .tint([Color.gray, .blue, .green, .orange, .red][index])
                    Text(GFFormat.duration(seconds[index])).font(.caption.monospacedDigit()).frame(width: 52, alignment: .trailing)
                }
            }
        }
    }
}

/// Reads the brief out (the coach's voice; stops if you leave the screen).
@MainActor
final class BriefSpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = BriefSpeaker()
    @Published private(set) var isSpeaking = false
    private let synthesizer = AVSpeechSynthesizer()

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggle(_ text: String) {
        if isSpeaking { stop(); return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-AU") ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        guard isSpeaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
        finished()
    }

    private func finished() {
        isSpeaking = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }
}
