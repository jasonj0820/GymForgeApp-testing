import AVFoundation
import Foundation
import MediaPlayer
import SwiftUI
import UniformTypeIdentifiers

/// A motivational speech you imported (an audio file copied into the app).
struct SpeechTrack: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var fileName: String
    var duration: Double
    /// Where you stopped last time (resumes there).
    var position: Double?
}

/// Plays your imported speeches. Nothing plays until you press play. Your music pauses while a speech
/// plays and is told it can resume when the speech pauses or ends. Lock Screen / Control Center controls work.
@MainActor
final class SpeechPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = SpeechPlayer()

    @Published private(set) var tracks: [SpeechTrack] = []
    @Published private(set) var currentID: UUID?
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsed: Double = 0
    @Published var lastError: String?

    private var player: AVAudioPlayer?
    private var ticker: Timer?
    private var tickCount = 0
    private var remoteReady = false
    /// Latest duck; an older restore timer is ignored.
    private var duckToken = UUID()

    var current: SpeechTrack? { tracks.first { $0.id == currentID } }

    private override init() {
        super.init()
        load()
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { note in
            let began = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
            MainActor.assumeIsolated {
                if began { SpeechPlayer.shared.interrupted() }
            }
        }
        // Headphones / AirPods disconnected: pause instead of blasting through the speaker.
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
            MainActor.assumeIsolated {
                if reason, SpeechPlayer.shared.isPlaying { SpeechPlayer.shared.pause() }
            }
        }
    }

    // MARK: Library

    private static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Speeches", isDirectory: true)
    }
    private static var indexURL: URL { folder.appendingPathComponent("speeches.json") }

    private func url(for track: SpeechTrack) -> URL { Self.folder.appendingPathComponent(track.fileName) }

    private func load() {
        guard let data = try? Data(contentsOf: Self.indexURL),
              let saved = try? JSONDecoder().decode([SpeechTrack].self, from: data) else { return }
        tracks = saved.filter { FileManager.default.fileExists(atPath: url(for: $0).path) }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(tracks).write(to: Self.indexURL, options: .atomic)
        } catch {
            lastError = "Couldn't save the speech list: \(error.localizedDescription)"
        }
    }

    /// Copies audio files you picked (Files app) into the app.
    func importFiles(_ urls: [URL]) {
        lastError = nil
        var added = 0
        for source in urls {
            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }
            do {
                try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
                let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension
                let name = UUID().uuidString + "." + ext
                let destination = Self.folder.appendingPathComponent(name)
                try FileManager.default.copyItem(at: source, to: destination)
                let duration = (try? AVAudioPlayer(contentsOf: destination).duration) ?? 0
                guard duration > 0 else {
                    try? FileManager.default.removeItem(at: destination)
                    lastError = "\(source.lastPathComponent) isn't a playable audio file."
                    continue
                }
                tracks.append(SpeechTrack(id: UUID(), title: source.deletingPathExtension().lastPathComponent,
                                          fileName: name, duration: duration))
                added += 1
            } catch {
                lastError = "Couldn't import \(source.lastPathComponent): \(error.localizedDescription)"
            }
        }
        if added > 0 { save() }
    }

    func delete(at offsets: IndexSet) {
        for index in offsets {
            let track = tracks[index]
            if track.id == currentID { stop() }
            try? FileManager.default.removeItem(at: url(for: track))
        }
        tracks.remove(atOffsets: offsets)
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        tracks.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[index].title = trimmed
        save()
        updateNowPlaying()
    }

    // MARK: Playback

    func play(_ track: SpeechTrack) {
        lastError = nil
        savePosition()
        player?.stop()
        do {
            // .spokenAudio without mixing: other apps' music pauses while the speech plays.
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)
            let newPlayer = try AVAudioPlayer(contentsOf: url(for: track))
            newPlayer.delegate = self
            var start = track.position ?? 0
            if start > newPlayer.duration - 3 { start = 0 }
            newPlayer.currentTime = start
            newPlayer.prepareToPlay()
            newPlayer.play()
            player = newPlayer
            currentID = track.id
            isPlaying = true
            elapsed = start
            startTicker()
            setUpRemoteCommands()
            updateNowPlaying()
        } catch {
            lastError = "Couldn't play \(track.title): \(error.localizedDescription)"
            isPlaying = false
        }
    }

    func togglePlay() {
        if isPlaying {
            pause()
        } else if let player, current != nil {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [])
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
            isPlaying = true
            startTicker()
            updateNowPlaying()
        } else if let first = current ?? tracks.first {
            play(first)
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        savePosition()
        stopTicker()
        updateNowPlaying()
        releaseSession()
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentID = nil
        elapsed = 0
        stopTicker()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        releaseSession()
    }

    func next() { step(1) }
    /// Back to the start of this speech, or (near the start) the previous one.
    func previous() {
        if elapsed > 5 { seek(to: 0) } else { step(-1) }
    }

    private func step(_ offset: Int) {
        guard !tracks.isEmpty else { return }
        let index = tracks.firstIndex { $0.id == currentID } ?? -1
        let target = ((index + offset) % tracks.count + tracks.count) % tracks.count
        var track = tracks[target]
        track.position = 0
        play(track)
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        player.currentTime = max(0, min(seconds, player.duration))
        elapsed = player.currentTime
        updateNowPlaying()
    }

    /// The rest-end chime / announcement plays over the speech: turn it down until it's finished
    /// (`unduck()` from the announcement; the timer is only a fallback).
    func duck(for seconds: Double) {
        guard isPlaying, let player else { return }
        player.setVolume(0.2, fadeDuration: 0.25)
        let token = UUID()
        duckToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            MainActor.assumeIsolated {
                if SpeechPlayer.shared.duckToken == token { SpeechPlayer.shared.unduck() }
            }
        }
    }

    func unduck() {
        duckToken = UUID()
        player?.setVolume(1, fadeDuration: 0.6)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.finished() }
    }

    private func finished() {
        if let index = tracks.firstIndex(where: { $0.id == currentID }) {
            tracks[index].position = nil
            save()
        }
        isPlaying = false
        elapsed = 0
        stopTicker()
        updateNowPlaying()
        releaseSession()
    }

    private func interrupted() {
        guard isPlaying else { return }
        isPlaying = false
        savePosition()
        stopTicker()
        updateNowPlaying()
    }

    private func savePosition() {
        guard let player, let index = tracks.firstIndex(where: { $0.id == currentID }) else { return }
        tracks[index].position = player.currentTime
        save()
    }

    /// Lets your music app know it can resume (not while the rest chime / voice is still playing).
    private func releaseSession() {
        guard !RestSound.isSounding else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated {
                let shared = SpeechPlayer.shared
                shared.elapsed = shared.player?.currentTime ?? 0
                // Remember where you are every ~10 s, in case the app is closed mid-speech.
                shared.tickCount += 1
                if shared.tickCount % 20 == 0 { shared.savePosition() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)   // keeps ticking while a list scrolls
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    // MARK: Lock Screen / Control Center

    private func setUpRemoteCommands() {
        guard !remoteReady else { return }
        remoteReady = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { _ in
            Task { @MainActor in if !SpeechPlayer.shared.isPlaying { SpeechPlayer.shared.togglePlay() } }
            return .success
        }
        center.pauseCommand.addTarget { _ in
            Task { @MainActor in SpeechPlayer.shared.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in SpeechPlayer.shared.togglePlay() }
            return .success
        }
        center.nextTrackCommand.addTarget { _ in
            Task { @MainActor in SpeechPlayer.shared.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { _ in
            Task { @MainActor in SpeechPlayer.shared.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let time = event.positionTime
            Task { @MainActor in SpeechPlayer.shared.seek(to: time) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let track = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: "Splitday",
            MPMediaItemPropertyPlaybackDuration: player?.duration ?? track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player?.currentTime ?? 0,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
    }
}

// MARK: - Views

/// Compact player on the workout screen.
struct SpeechMiniPlayer: View {
    @ObservedObject private var player = SpeechPlayer.shared
    @State private var showLibrary = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                player.togglePlay()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 30))
            }
            .buttonStyle(.borderless)
            .disabled(player.tracks.isEmpty)

            VStack(alignment: .leading, spacing: 2) {
                Text(player.current?.title ?? (player.tracks.isEmpty ? "No speeches yet" : "Motivational speeches"))
                    .font(.subheadline.bold())
                    .lineLimit(1)
                if let track = player.current {
                    SwiftUI.ProgressView(value: min(player.elapsed, max(track.duration, 1)), total: max(track.duration, 1))
                } else {
                    Text(player.tracks.isEmpty ? "Import audio files to play them here" : "\(player.tracks.count) ready · tap play")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if player.current != nil {
                Button { player.next() } label: { Image(systemName: "forward.fill") }
                    .buttonStyle(.borderless)
            }
            Button { showLibrary = true } label: { Image(systemName: "music.note.list") }
                .buttonStyle(.borderless)
        }
        .sheet(isPresented: $showLibrary) {
            NavigationStack { SpeechLibraryView() }
        }
    }
}

/// Your imported speeches: import, play, rename, reorder, delete.
struct SpeechLibraryView: View {
    @ObservedObject private var player = SpeechPlayer.shared
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var renaming: SpeechTrack?
    @State private var newTitle = ""

    var body: some View {
        List {
            Section {
                if player.tracks.isEmpty {
                    Text("Import mp3 / m4a files from the Files app. They're copied into Splitday and play offline.")
                        .foregroundStyle(.secondary)
                }
                ForEach(player.tracks) { track in
                    Button {
                        if player.currentID == track.id { player.togglePlay() } else { player.play(track) }
                    } label: {
                        HStack {
                            Image(systemName: player.currentID == track.id && player.isPlaying ? "speaker.wave.2.fill" : "play.fill")
                                .foregroundStyle(.tint)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title).foregroundStyle(.primary).lineLimit(2)
                                Text(GFFormat.duration(track.duration) + ((track.position ?? 0) > 3 ? " · resumes at \(GFFormat.duration(track.position ?? 0))" : ""))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button("Rename") {
                            newTitle = track.title
                            renaming = track
                        }
                        .tint(.blue)
                    }
                }
                .onDelete { player.delete(at: $0) }
                .onMove { player.move(from: $0, to: $1) }
            } footer: {
                Text("Nothing plays until you press play. Your music pauses while a speech plays; the rest-timer chime plays over it. Controls also appear on the Lock Screen.")
            }
            if let error = player.lastError {
                Section { Text(error).foregroundStyle(.red).font(.footnote) }
            }
        }
        .navigationTitle("Speeches")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .primaryAction) {
                Button { importing = true } label: { Label("Import", systemImage: "plus") }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { player.importFiles(urls) }
        }
        .alert("Rename speech", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $newTitle)
            Button("Save") {
                if let track = renaming { player.rename(track.id, to: newTitle) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }
}
