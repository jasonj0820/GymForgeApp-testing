import PhotosUI
import SwiftUI

/// MK24 (88): physique photos by pose, with last time's photo as a ghost outline while you line up,
/// and two dates side by side.
struct ProgressPhotosView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @ObservedObject private var photos = ProgressPhotoStore.shared
    @State private var pose: ProgressPhotoStore.Pose = .front
    @State private var showCamera = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var viewing: ProgressPhotoStore.Entry?
    @State private var exportFiles: [URL] = []

    private var latestWeight: Double? { store.healthKit.bodyWeight.max { $0.date < $1.date }?.value }

    var body: some View {
        let list = photos.entries(pose)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Pose", selection: $pose) {
                    ForEach(ProgressPhotoStore.Pose.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if let problem = photos.problem {
                    Label(problem, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
                }
                HStack {
                    Button { showCamera = true } label: { Label("Take", systemImage: "camera.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                    PhotosPicker(selection: $picked, maxSelectionCount: 10, matching: .images) {
                        Label("Import", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                if list.count >= 2 {
                    NavigationLink { PhotoCompareView(pose: pose) } label: {
                        Label("Compare two dates", systemImage: "rectangle.split.2x1").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                if list.isEmpty {
                    ContentUnavailableView("No \(pose.title.lowercased()) photos yet", systemImage: "figure.stand",
                                           description: Text("Same spot, same light, same time of day. Next time, the last photo shows faintly so you can line up the same pose."))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                        ForEach(list.reversed()) { entry in
                            Button { viewing = entry } label: { PhotoThumb(entry: entry) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) { photos.delete(entry) } label: { Label("Delete", systemImage: "trash") }
                                }
                        }
                    }
                }
                Text("Encrypted on this iPhone and never added to Photos or iCloud. They aren't in backups: use Export (top right) to keep copies, especially before re-installing with another Apple ID.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Progress photos")
        .toolbar {
            if !photos.entries.isEmpty {
                Button {
                    exportFiles = photos.exportFiles()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Export all photos")
            }
        }
        .sheet(isPresented: Binding(get: { !exportFiles.isEmpty }, set: { if !$0 { exportFiles = [] } })) {
            ShareSheet(items: exportFiles)
        }
        .fullScreenCover(isPresented: $showCamera) {
            MTCameraView(ghost: photos.entries(pose).last.flatMap { photos.image($0) }) { images in
                showCamera = false
                for image in images { photos.add(image, pose: pose, weightKg: latestWeight) }
                if !images.isEmpty { Haptics.success() }
            }
            .ignoresSafeArea()
        }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        photos.add(image, pose: pose, weightKg: nil)
                    }
                }
                picked = []
            }
        }
        .sheet(item: $viewing) { entry in
            NavigationStack {
                ZStack {
                    Color.black.ignoresSafeArea()
                    if let image = photos.image(entry) { Image(uiImage: image).resizable().scaledToFit() }
                }
                .navigationTitle(entry.date.formatted(date: .abbreviated, time: .omitted))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { viewing = nil } } }
            }
        }
    }
}

private struct PhotoThumb: View {
    @ObservedObject private var photos = ProgressPhotoStore.shared
    let entry: ProgressPhotoStore.Entry

    var body: some View {
        VStack(spacing: 3) {
            Group {
                if let image = photos.image(entry) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color.gray.opacity(0.2)
                }
            }
            .frame(height: 140)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(entry.date.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits)))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// Two dates side by side (oldest and newest to start), with the weight on each day if known.
struct PhotoCompareView: View {
    @ObservedObject private var photos = ProgressPhotoStore.shared
    let pose: ProgressPhotoStore.Pose
    @State private var left = 0
    @State private var right = 0

    var body: some View {
        let list = photos.entries(pose)
        VStack(spacing: 12) {
            if list.count >= 2 {
                HStack(spacing: 6) {
                    side(list[min(left, list.count - 1)])
                    side(list[min(right, list.count - 1)])
                }
                picker("Left", $left, list)
                picker("Right", $right, list)
            }
        }
        .padding()
        .navigationTitle("\(pose.title): compare")
        .onAppear { left = 0; right = max(list.count - 1, 0) }
    }

    private func side(_ entry: ProgressPhotoStore.Entry) -> some View {
        VStack(spacing: 4) {
            if let image = photos.image(entry) {
                Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 10))
            }
            Text(entry.date.formatted(date: .abbreviated, time: .omitted)).font(.caption.bold())
            if let kg = entry.weightKg { Text("\(GFFormat.kg(kg)) kg").font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity)
    }

    private func picker(_ title: String, _ selection: Binding<Int>, _ list: [ProgressPhotoStore.Entry]) -> some View {
        Picker(title, selection: selection) {
            ForEach(Array(list.enumerated()), id: \.element.id) { index, entry in
                Text(entry.date.formatted(date: .abbreviated, time: .omitted)).tag(index)
            }
        }
        .pickerStyle(.menu)
    }
}

/// The system share sheet for a list of files.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
