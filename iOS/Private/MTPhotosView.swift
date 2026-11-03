import SwiftUI
import UIKit
import PhotosUI
import Photos
import ImageIO

/// Progress photos taken with an in-app camera. They're encrypted inside GymForge and
/// never saved to the Photos library or iCloud.
struct MTPhotosView: View {
    @EnvironmentObject private var vault: MTVault
    @State private var showingCamera = false
    @State private var burstImages: [UIImage] = []
    @State private var viewing: MTPhoto?
    @State private var comparing = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var importing: [MTImportItem] = []
    /// nil = All photos.
    @State private var folderFilter: UUID?
    @State private var showUnfiled = false
    @State private var naming: MTFolderNaming?
    @State private var folderToDelete: MTPhotoFolder?

    /// Three equal columns; every tile is the same square size.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    private var visiblePhotos: [MTPhoto] {
        let all = vault.data.photos.sorted { $0.date > $1.date }
        if showUnfiled { return all.filter { $0.folderID == nil } }
        guard let folderFilter else { return all }
        return all.filter { $0.folderID == folderFilter }
    }

    private var currentFolderName: String? { vault.folderName(folderFilter) }

    var body: some View {
        ScrollView {
            folderBar
            if visiblePhotos.isEmpty {
                ContentUnavailableView(currentFolderName.map { "Nothing in \($0) yet" } ?? "No photos", systemImage: "camera",
                                       description: Text(currentFolderName == nil
                                                         ? "Photos you take here stay encrypted inside GymForge — they never go to your Photos library."
                                                         : "Photos you take or import while this folder is open go straight into it."))
                    .padding(.top, 40)
            } else {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(visiblePhotos) { photo in
                        Button {
                            viewing = photo
                        } label: {
                            tile(photo)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { moveMenu(photo) }
                    }
                }
                .padding(6)
            }
        }
        .navigationTitle(currentFolderName ?? (showUnfiled ? "Unfiled" : "Photos"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PhotosPicker(selection: $pickerItems, matching: .images, photoLibrary: .shared()) {
                    Image(systemName: "square.and.arrow.down")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    comparing = true
                } label: {
                    Image(systemName: "rectangle.split.2x1")
                }
                .disabled(vault.data.photos.count < 2)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCamera = true
                } label: {
                    Image(systemName: "camera.fill")
                }
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
            }
        }
        .onAppear { vault.seedPhotoFoldersIfNeeded() }
        .fullScreenCover(isPresented: $showingCamera) {
            MTCameraView(ghost: ghostImage) { images in
                showingCamera = false
                if images.count == 1 {
                    vault.addPhoto(images[0], folderID: folderFilter)
                } else if images.count > 1 {
                    // Let the camera finish closing before the picker opens.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { burstImages = images }
                }
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var loaded: [MTImportItem] = []
                for item in items {
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { continue }
                    loaded.append(MTImportItem(image: image, date: MTImportItem.captureDate(from: data) ?? .now,
                                               assetID: item.itemIdentifier))
                }
                pickerItems = []
                importing = loaded
            }
        }
        .sheet(isPresented: Binding(
            get: { !importing.isEmpty },
            set: { if !$0 { importing = [] } }
        )) {
            NavigationStack { MTImportPhotosView(items: importing, folderID: folderFilter) { importing = [] } }
                .environmentObject(vault)
        }
        .fullScreenCover(isPresented: $comparing) {
            MTCompareView(startFolder: folderFilter)
                .environmentObject(vault)
        }
        .sheet(isPresented: Binding(
            get: { !burstImages.isEmpty },
            set: { if !$0 { burstImages = [] } }
        )) {
            MTBurstPickerView(images: burstImages) { keep in
                for image in keep { vault.addPhoto(image, folderID: folderFilter) }
                burstImages = []
            }
        }
        .fullScreenCover(item: $viewing) { photo in
            MTPhotoViewer(photo: photo)
                .environmentObject(vault)
        }
        .sheet(item: $naming) { request in
            MTFolderNameSheet(request: request) { name in
                if let id = request.folderID {
                    vault.renamePhotoFolder(id, to: name)
                } else if let folder = vault.addPhotoFolder(named: name) {
                    folderFilter = folder.id
                    showUnfiled = false
                }
            }
            .presentationDetents([.height(220)])
        }
        .confirmationDialog("Delete folder \"\(folderToDelete?.name ?? "")\"?", isPresented: Binding(
            get: { folderToDelete != nil },
            set: { if !$0 { folderToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete folder", role: .destructive) {
                if let folder = folderToDelete {
                    vault.deletePhotoFolder(folder.id)
                    if folderFilter == folder.id { folderFilter = nil }
                }
                folderToDelete = nil
            }
        } message: {
            Text("The photos inside are kept — they move to Unfiled.")
        }
    }

    // MARK: Folder bar

    private var folderBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", count: vault.data.photos.count, selected: folderFilter == nil && !showUnfiled) {
                    folderFilter = nil; showUnfiled = false
                }
                ForEach(vault.data.folderList) { folder in
                    chip(folder.name, count: vault.data.photos.filter { $0.folderID == folder.id }.count,
                         selected: folderFilter == folder.id) {
                        folderFilter = folder.id; showUnfiled = false
                    }
                    .contextMenu {
                        Button { naming = MTFolderNaming(folderID: folder.id, name: folder.name) } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button(role: .destructive) { folderToDelete = folder } label: {
                            Label("Delete folder", systemImage: "trash")
                        }
                    }
                }
                let unfiled = vault.data.photos.filter { $0.folderID == nil }.count
                if unfiled > 0 && !vault.data.folderList.isEmpty {
                    chip("Unfiled", count: unfiled, selected: showUnfiled) {
                        folderFilter = nil; showUnfiled = true
                    }
                }
                Button {
                    naming = MTFolderNaming(folderID: nil, name: "")
                } label: {
                    Label("Folder", systemImage: "plus")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().stroke(Color.secondary.opacity(0.4)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
        }
    }

    private func chip(_ title: String, count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title).font(.subheadline.bold())
                Text("\(count)").font(.caption.monospacedDigit()).opacity(0.7)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(selected ? Color.accentColor : Color.secondary.opacity(0.15)))
            .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: Tiles

    private func tile(_ photo: MTPhoto) -> some View {
        // A fixed square; the photo fills it and is cropped, so it can't spill into neighbours.
        Color.gray.opacity(0.15)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = vault.thumbnail(photo.id) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .overlay(alignment: .bottomLeading) {
                Text(photo.date.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.caption2.bold())
                    .padding(4)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                    .padding(4)
            }
            .overlay(alignment: .topTrailing) {
                // In "All", show which folder each photo is in.
                if folderFilter == nil && !showUnfiled, let name = vault.folderName(photo.folderID) {
                    Text(name)
                        .font(.caption2.bold())
                        .lineLimit(1)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func moveMenu(_ photo: MTPhoto) -> some View {
        MTMoveToFolderMenu(photo: photo)
        Button(role: .destructive) { vault.deletePhoto(photo.id) } label: {
            Label("Delete photo", systemImage: "trash")
        }
    }
}

extension MTPhotosView {
    /// Faint copy of your latest photo (in the open folder) shown in the camera so angle and distance match.
    var ghostImage: UIImage? {
        guard vault.data.settings.showGhost else { return nil }
        let pool = folderFilter.map { id in vault.data.photos.filter { $0.folderID == id } } ?? vault.data.photos
        guard let latest = (pool.isEmpty ? vault.data.photos : pool).max(by: { $0.date < $1.date }) else { return nil }
        return vault.fullImage(latest.id)
    }
}

/// "Move to folder" submenu used on tiles and in the viewer.
struct MTMoveToFolderMenu: View {
    @EnvironmentObject private var vault: MTVault
    let photo: MTPhoto

    var body: some View {
        Menu {
            ForEach(vault.data.folderList) { folder in
                Button {
                    vault.movePhoto(photo.id, to: folder.id)
                } label: {
                    if currentFolder == folder.id { Label(folder.name, systemImage: "checkmark") } else { Text(folder.name) }
                }
            }
            Button {
                vault.movePhoto(photo.id, to: nil)
            } label: {
                if currentFolder == nil { Label("No folder", systemImage: "checkmark") } else { Text("No folder") }
            }
        } label: {
            Label("Move to folder", systemImage: "folder")
        }
    }

    /// Read live so the checkmark is right after a move.
    private var currentFolder: UUID? {
        vault.data.photos.first { $0.id == photo.id }?.folderID
    }
}

struct MTFolderNaming: Identifiable {
    let id = UUID()
    /// nil = creating a new folder.
    let folderID: UUID?
    let name: String
}

struct MTFolderNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    let request: MTFolderNaming
    let onSave: (String) -> Void
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("Folder name (e.g. Pump)", text: $name)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(save)
            }
            .navigationTitle(request.folderID == nil ? "New folder" : "Rename folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { name = request.name; focused = true }
        }
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onSave(name)
        dismiss()
    }
}

/// Compare two photos — side by side, or overlaid with a fade slider. Each side has its own
/// folder, so you can put e.g. Measurement next to Pump, or an old Pump next to a new one.
struct MTCompareView: View {
    @EnvironmentObject private var vault: MTVault
    @Environment(\.dismiss) private var dismiss
    var startFolder: UUID? = nil

    @State private var leftFolder: UUID?
    @State private var rightFolder: UUID?
    @State private var leftID: UUID?
    @State private var rightID: UUID?
    @State private var overlay = false
    @State private var blend = 0.5
    @State private var zoom = MTZoomState()
    @State private var didSetUp = false

    private func photos(in folder: UUID?) -> [MTPhoto] {
        let all = vault.data.photos.sorted { $0.date < $1.date }
        guard let folder else { return all }
        return all.filter { $0.folderID == folder }
    }

    private func photoItem(_ id: UUID?) -> MTPhoto? {
        id.flatMap { id in vault.data.photos.first { $0.id == id } }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Mode", selection: $overlay) {
                    Text("Side by side").tag(false)
                    Text("Overlay").tag(true)
                }
                .pickerStyle(.segmented)

                HStack(alignment: .top) {
                    sidePicker(title: overlay ? "Before" : "Left", folder: $leftFolder, selection: $leftID, other: rightID)
                    Spacer()
                    Button {
                        let folder = leftFolder, id = leftID
                        leftFolder = rightFolder; leftID = rightID
                        rightFolder = folder; rightID = id
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                    }
                    .padding(.top, 14)
                    Spacer()
                    sidePicker(title: overlay ? "After" : "Right", folder: $rightFolder, selection: $rightID, other: leftID)
                }

                let left = leftID.flatMap { vault.fullImage($0) }
                let right = rightID.flatMap { vault.fullImage($0) }
                if overlay {
                    MTZoomable(state: $zoom) {
                        ZStack {
                            if let left { Image(uiImage: left).resizable().scaledToFit() }
                            if let right { Image(uiImage: right).resizable().scaledToFit().opacity(blend) }
                        }
                    }
                    .frame(maxHeight: .infinity)
                    HStack {
                        Text("Before").font(.caption)
                        Slider(value: $blend, in: 0...1)
                        Text("After").font(.caption)
                    }
                } else {
                    // Both sides share one zoom, so you look at the same spot on each.
                    HStack(spacing: 6) {
                        pane(left, label: label(for: leftID))
                        pane(right, label: label(for: rightID))
                    }
                    .frame(maxHeight: .infinity)
                }
                if zoom.isZoomed {
                    Button("Reset zoom") { withAnimation(.spring(duration: 0.3)) { zoom = MTZoomState() } }
                        .font(.footnote.bold())
                } else {
                    Text("Pinch or double-tap to zoom — both photos zoom together")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .onChange(of: overlay) { zoom = MTZoomState() }
            .onAppear(perform: setUp)
        }
    }

    @ViewBuilder
    private func pane(_ image: UIImage?, label: String?) -> some View {
        ZStack(alignment: .top) {
            if let image {
                MTZoomable(state: $zoom) { Image(uiImage: image).resizable().scaledToFit() }
            } else {
                Color.secondary.opacity(0.1)
                    .overlay { Text("No photo").font(.caption).foregroundStyle(.secondary) }
            }
            if let label {
                Text(label)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
    }

    private func label(for id: UUID?) -> String? {
        guard let photo = photoItem(id) else { return nil }
        let date = photo.date.formatted(.dateTime.day().month(.abbreviated))
        return vault.folderName(photo.folderID).map { "\($0) · \(date)" } ?? date
    }

    /// Folder menu, then a date menu for the photos in that folder.
    private func sidePicker(title: String, folder: Binding<UUID?>, selection: Binding<UUID?>, other: UUID?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Menu {
                Button("All photos") { choose(folder: nil, for: folder, selection: selection, near: other) }
                ForEach(vault.data.folderList) { item in
                    Button(item.name) { choose(folder: item.id, for: folder, selection: selection, near: other) }
                }
            } label: {
                Label(vault.folderName(folder.wrappedValue) ?? "All photos", systemImage: "folder")
                    .font(.subheadline.bold())
                    .lineLimit(1)
            }
            Menu {
                ForEach(photos(in: folder.wrappedValue).reversed()) { item in
                    Button {
                        selection.wrappedValue = item.id
                    } label: {
                        let text = item.date.formatted(date: .abbreviated, time: .shortened)
                        if selection.wrappedValue == item.id { Label(text, systemImage: "checkmark") } else { Text(text) }
                    }
                }
            } label: {
                Text(photoItem(selection.wrappedValue)?.date.formatted(date: .abbreviated, time: .omitted) ?? "Choose")
                    .font(.subheadline)
            }
            .disabled(photos(in: folder.wrappedValue).isEmpty)
        }
    }

    /// Switching folder picks the photo closest in time to the other side — so Measurement
    /// and Pump from the same session line up automatically.
    private func choose(folder newFolder: UUID?, for folder: Binding<UUID?>, selection: Binding<UUID?>, near other: UUID?) {
        folder.wrappedValue = newFolder
        let pool = photos(in: newFolder)
        if let target = photoItem(other)?.date {
            selection.wrappedValue = pool.filter { $0.id != other }
                .min { abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target)) }?.id
                ?? pool.last?.id
        } else {
            selection.wrappedValue = pool.last?.id
        }
    }

    private func setUp() {
        guard !didSetUp else { return }
        didSetUp = true
        let filled = vault.data.folderList.filter { folder in vault.data.photos.contains { $0.folderID == folder.id } }
        if let startFolder, photos(in: startFolder).count >= 2 {
            // Opened from inside a folder: oldest vs newest in that folder.
            leftFolder = startFolder; rightFolder = startFolder
            leftID = photos(in: startFolder).first?.id
            rightID = photos(in: startFolder).last?.id
        } else if filled.count >= 2 {
            // Two folders in use: latest of the first next to the closest one from the second.
            leftFolder = filled[0].id
            leftID = photos(in: filled[0].id).last?.id
            choose(folder: filled[1].id, for: $rightFolder, selection: $rightID, near: leftID)
        } else {
            leftID = photos(in: nil).first?.id
            rightID = photos(in: nil).last?.id
        }
    }
}

struct MTPhotoViewer: View {
    @EnvironmentObject private var vault: MTVault
    @Environment(\.dismiss) private var dismiss
    let photo: MTPhoto
    @State private var confirmDelete = false
    @State private var zoom = MTZoomState()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image = vault.fullImage(photo.id) {
                    MTZoomable(state: $zoom) {
                        Image(uiImage: image).resizable().scaledToFit()
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
                VStack {
                    Spacer()
                    if zoom.isZoomed {
                        Button {
                            withAnimation(.spring(duration: 0.3)) { zoom = MTZoomState() }
                        } label: {
                            Label(String(format: "%.1fx · Reset", Double(zoom.scale)), systemImage: "arrow.down.right.and.arrow.up.left")
                                .font(.footnote.bold())
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.25))
                    } else {
                        Text("Pinch or double-tap to zoom")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.bottom, 12)
            }
            .navigationTitle(photo.date.formatted(date: .abbreviated, time: .shortened))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        MTMoveToFolderMenu(photo: photo)
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("Delete photo", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(photo.date.formatted(date: .abbreviated, time: .shortened)).font(.subheadline.bold())
                        if let folder = vault.folderName(vault.data.photos.first(where: { $0.id == photo.id })?.folderID) {
                            Text(folder).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .confirmationDialog("Delete this photo?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    vault.deletePhoto(photo.id)
                    dismiss()
                }
            }
        }
    }
}

/// Camera that hands the image straight back — nothing is written to the photo library.
/// In-app camera: nothing is written to the photo library. Optional ghost overlay of your last
/// photo, a self-timer (3/5/10 s) and burst mode (5 shots) so you can shoot hands-free from a stand.
struct MTCameraView: UIViewControllerRepresentable {
    var ghost: UIImage? = nil
    /// Every photo taken in this session (empty = cancelled).
    let onFinish: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.showsCameraControls = false
        picker.delegate = context.coordinator
        picker.loadViewIfNeeded()
        context.coordinator.picker = picker
        picker.cameraOverlayView = context.coordinator.makeOverlay(bounds: UIScreen.main.bounds, ghost: ghost)
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: ([UIImage]) -> Void
        weak var picker: UIImagePickerController?
        private var timerSeconds = 0
        private var burst = false
        private var captured: [UIImage] = []
        private var remaining = 0
        private var busy = false
        private let countdownLabel = UILabel()
        private let timerButton = UIButton(type: .system)
        private let burstButton = UIButton(type: .system)
        private let shutterButton = UIButton(type: .custom)
        private let statusLabel = UILabel()

        init(onFinish: @escaping ([UIImage]) -> Void) { self.onFinish = onFinish }

        func makeOverlay(bounds: CGRect, ghost: UIImage?) -> UIView {
            let overlay = PassthroughView(frame: bounds)
            overlay.backgroundColor = .clear

            if let ghost {
                let previewHeight = bounds.width * 4 / 3
                let top = max(0, (bounds.height - previewHeight) / 2 - 40)
                let imageView = UIImageView(image: ghost)
                imageView.frame = CGRect(x: 0, y: top, width: bounds.width, height: previewHeight)
                imageView.contentMode = .scaleAspectFill
                imageView.clipsToBounds = true
                imageView.alpha = 0.3
                imageView.isUserInteractionEnabled = false
                overlay.addSubview(imageView)
            }

            countdownLabel.frame = CGRect(x: 0, y: bounds.midY - 80, width: bounds.width, height: 160)
            countdownLabel.textAlignment = .center
            countdownLabel.font = .systemFont(ofSize: 120, weight: .heavy)
            countdownLabel.textColor = .white
            countdownLabel.layer.shadowColor = UIColor.black.cgColor
            countdownLabel.layer.shadowOpacity = 0.6
            countdownLabel.layer.shadowRadius = 6
            countdownLabel.isHidden = true
            overlay.addSubview(countdownLabel)

            let barHeight: CGFloat = 150
            let bar = UIView(frame: CGRect(x: 0, y: bounds.height - barHeight, width: bounds.width, height: barHeight))
            bar.backgroundColor = UIColor.black.withAlphaComponent(0.55)
            overlay.addSubview(bar)

            statusLabel.frame = CGRect(x: 0, y: 8, width: bounds.width, height: 18)
            statusLabel.textAlignment = .center
            statusLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            statusLabel.textColor = .white
            bar.addSubview(statusLabel)

            let shutterSize: CGFloat = 74
            shutterButton.frame = CGRect(x: (bounds.width - shutterSize) / 2, y: 34, width: shutterSize, height: shutterSize)
            shutterButton.backgroundColor = .white
            shutterButton.layer.cornerRadius = shutterSize / 2
            shutterButton.layer.borderWidth = 5
            shutterButton.layer.borderColor = UIColor.lightGray.cgColor
            shutterButton.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)
            bar.addSubview(shutterButton)

            let cancel = UIButton(type: .system)
            cancel.setTitle("Cancel", for: .normal)
            cancel.tintColor = .white
            cancel.titleLabel?.font = .systemFont(ofSize: 17)
            cancel.frame = CGRect(x: 16, y: 54, width: 80, height: 34)
            cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
            bar.addSubview(cancel)

            let flip = UIButton(type: .system)
            flip.setImage(UIImage(systemName: "arrow.triangle.2.circlepath.camera"), for: .normal)
            flip.tintColor = .white
            flip.frame = CGRect(x: bounds.width - 60, y: 52, width: 44, height: 38)
            flip.addTarget(self, action: #selector(flipTapped), for: .touchUpInside)
            bar.addSubview(flip)

            for (button, x) in [(timerButton, bounds.width / 2 - 140), (burstButton, bounds.width / 2 + 60)] {
                button.tintColor = .white
                button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
                button.frame = CGRect(x: x, y: 112, width: 80, height: 30)
                bar.addSubview(button)
            }
            timerButton.addTarget(self, action: #selector(timerTapped), for: .touchUpInside)
            burstButton.addTarget(self, action: #selector(burstTapped), for: .touchUpInside)
            refreshLabels()
            return overlay
        }

        private func refreshLabels() {
            timerButton.setTitle(timerSeconds == 0 ? "⏱ Off" : "⏱ \(timerSeconds)s", for: .normal)
            burstButton.setTitle(burst ? "Burst ×5" : "Single", for: .normal)
            statusLabel.text = captured.isEmpty ? "Set the phone on a stand, then tap the shutter" : "\(captured.count) taken"
        }

        @objc private func timerTapped() {
            let options = [0, 3, 5, 10]
            timerSeconds = options[((options.firstIndex(of: timerSeconds) ?? 0) + 1) % options.count]
            refreshLabels()
        }

        @objc private func burstTapped() {
            burst.toggle()
            refreshLabels()
        }

        @objc private func flipTapped() {
            guard let picker else { return }
            picker.cameraDevice = picker.cameraDevice == .rear ? .front : .rear
        }

        @objc private func cancelTapped() {
            onFinish(captured)
        }

        @objc private func shutterTapped() {
            guard !busy else { return }
            busy = true
            shutterButton.alpha = 0.4
            countdown(timerSeconds)
        }

        private func countdown(_ seconds: Int) {
            if seconds <= 0 {
                countdownLabel.isHidden = true
                remaining = burst ? 5 : 1
                captureNext()
                return
            }
            countdownLabel.isHidden = false
            countdownLabel.text = "\(seconds)"
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.countdown(seconds - 1) }
        }

        private func captureNext() {
            guard remaining > 0, let picker else { finishedRound(); return }
            remaining -= 1
            picker.takePicture()
        }

        private func finishedRound() {
            busy = false
            shutterButton.alpha = 1
            refreshLabels()
            // Single shot without a timer: done straight away. Otherwise go to the picker.
            onFinish(captured)
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { captured.append(image) }
            refreshLabels()
            if remaining > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.captureNext() }
            } else {
                finishedRound()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(captured)
        }
    }
}

/// Lets touches through to the camera preview except on the controls.
private final class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

/// After a burst: pick which shots to keep (the rest are discarded, never saved anywhere).
struct MTBurstPickerView: View {
    let images: [UIImage]
    let onKeep: ([UIImage]) -> Void
    @State private var selected: Set<Int> = []

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 2)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(images.indices, id: \.self) { index in
                        Color.black
                            .aspectRatio(3.0 / 4.0, contentMode: .fit)
                            .overlay {
                                Image(uiImage: images[index]).resizable().scaledToFill()
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: selected.contains(index) ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundStyle(selected.contains(index) ? Color.green : Color.white)
                                    .shadow(radius: 2)
                                    .padding(8)
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                            .onTapGesture {
                                if selected.contains(index) { selected.remove(index) } else { selected.insert(index) }
                            }
                    }
                }
                .padding(8)
            }
            .navigationTitle("Keep which?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Discard all") { onKeep([]) } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Keep \(selected.count)") {
                        onKeep(selected.sorted().map { images[$0] })
                    }
                    .disabled(selected.isEmpty)
                }
            }
            .onAppear { if selected.isEmpty, !images.isEmpty { selected = [images.count / 2] } }
        }
    }
}

// MARK: - Importing existing photos

struct MTImportItem: Identifiable {
    let id = UUID()
    let image: UIImage
    var date: Date
    let assetID: String?

    /// Date the photo was taken, from its EXIF data.
    static func captureDate(from data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let text = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: text)
    }
}

/// Review dates, save into the encrypted vault, then optionally delete the originals from Photos.
struct MTImportPhotosView: View {
    @EnvironmentObject private var vault: MTVault
    @State var items: [MTImportItem]
    @State var folderID: UUID?
    let onDone: () -> Void
    @State private var saved = false
    @State private var resultText: String?

    var body: some View {
        Form {
            if !saved {
                Section {
                    ForEach($items) { $item in
                        HStack(spacing: 12) {
                            Image(uiImage: item.image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            DatePicker("Date", selection: $item.date, in: ...Date(), displayedComponents: .date)
                                .labelsHidden()
                        }
                    }
                } header: {
                    Text("\(items.count) photo\(items.count == 1 ? "" : "s") to import")
                }
                Section {
                    Picker("Folder", selection: $folderID) {
                        Text("No folder").tag(UUID?.none)
                        ForEach(vault.data.folderList) { folder in
                            Text(folder.name).tag(UUID?.some(folder.id))
                        }
                    }
                } footer: {
                    Text("Dates come from when each photo was taken — adjust them if needed so comparisons line up.")
                }
            } else {
                Section {
                    Label("Imported into the encrypted vault.", systemImage: "lock.fill")
                    let originals = items.compactMap(\.assetID)
                    if !originals.isEmpty {
                        Button("Delete the originals from Photos", role: .destructive) {
                            Task { await deleteOriginals(originals) }
                        }
                    }
                    if let resultText {
                        Text(resultText).font(.footnote).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("iOS will ask you to confirm. Deleted photos go to Photos' \"Recently Deleted\" album for 30 days — empty it there to remove them completely.")
                }
            }
        }
        .navigationTitle("Import photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if saved {
                    Button("Done") { onDone() }
                } else {
                    Button("Import") {
                        for item in items { vault.addPhoto(item.image, date: item.date, folderID: folderID) }
                        saved = true
                    }
                    .bold()
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                if !saved { Button("Cancel") { onDone() } }
            }
        }
    }

    private func deleteOriginals(_ ids: [String]) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            resultText = "GymForge doesn't have permission to manage your Photos library."
            return
        }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        guard assets.count > 0 else {
            resultText = "Couldn't find the originals."
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            resultText = "Originals deleted."
        } catch {
            resultText = "Originals were kept."
        }
    }
}

// MARK: - Zoom

struct MTZoomState: Equatable {
    var scale: CGFloat = 1
    var offset: CGSize = .zero
    var isZoomed: Bool { scale > 1.01 }
}

/// Pinch to zoom (around your fingers), drag to pan while zoomed, double-tap to
/// zoom into a spot or back out. Pass the same state to several views to zoom them together.
struct MTZoomable<Content: View>: View {
    @Binding var state: MTZoomState
    var maxScale: CGFloat = 8
    @ViewBuilder var content: () -> Content

    @State private var pinchBase: MTZoomState?
    @State private var dragBase: CGSize?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            content()
                .frame(width: size.width, height: size.height)
                .scaleEffect(state.scale)
                .offset(state.offset)
                .frame(width: size.width, height: size.height)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture(count: 2, coordinateSpace: .local) { location in
                    withAnimation(.spring(duration: 0.3)) {
                        if state.isZoomed {
                            state = MTZoomState()
                        } else {
                            let scale: CGFloat = 3
                            let c = CGPoint(x: location.x - size.width / 2, y: location.y - size.height / 2)
                            state = clamped(MTZoomState(scale: scale,
                                                        offset: CGSize(width: -c.x * (scale - 1), height: -c.y * (scale - 1))),
                                            in: size)
                        }
                    }
                }
                .gesture(magnify(in: size).simultaneously(with: pan(in: size)))
        }
    }

    private func magnify(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if pinchBase == nil { pinchBase = state }
                guard let base = pinchBase else { return }
                let newScale = min(max(base.scale * value.magnification, 1), maxScale)
                let factor = newScale / base.scale
                // Keep the point between your fingers in place while zooming.
                let c = CGPoint(x: value.startLocation.x - size.width / 2, y: value.startLocation.y - size.height / 2)
                state = MTZoomState(scale: newScale,
                                    offset: CGSize(width: c.x - (c.x - base.offset.width) * factor,
                                                   height: c.y - (c.y - base.offset.height) * factor))
            }
            .onEnded { _ in
                pinchBase = nil
                withAnimation(.spring(duration: 0.3)) { state = clamped(state, in: size) }
            }
    }

    private func pan(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard state.isZoomed, pinchBase == nil else { return }
                if dragBase == nil { dragBase = state.offset }
                guard let base = dragBase else { return }
                state.offset = CGSize(width: base.width + value.translation.width,
                                      height: base.height + value.translation.height)
            }
            .onEnded { _ in
                dragBase = nil
                withAnimation(.spring(duration: 0.3)) { state = clamped(state, in: size) }
            }
    }

    private func clamped(_ zoom: MTZoomState, in size: CGSize) -> MTZoomState {
        guard zoom.isZoomed else { return MTZoomState() }
        let maxX = size.width * (zoom.scale - 1) / 2
        let maxY = size.height * (zoom.scale - 1) / 2
        return MTZoomState(scale: zoom.scale,
                           offset: CGSize(width: min(max(zoom.offset.width, -maxX), maxX),
                                          height: min(max(zoom.offset.height, -maxY), maxY)))
    }
}
