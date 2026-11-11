import SwiftUI
import UIKit

/// The private "More Training" app-inside-the-app. Locks itself whenever you leave, except while a timer
/// runs (MK17): then it stays open, keeps the screen awake and shows the timer on the Lock Screen.
struct MTRootView: View {
    @EnvironmentObject private var vault: MTVault
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            NavigationStack { MTLogView().toolbar { closeButton } }
                .tabItem { Label("Today", systemImage: "checkmark.circle") }
            NavigationStack { MTStatsView().toolbar { closeButton } }
                .tabItem { Label("Progress", systemImage: "calendar") }
            NavigationStack { MTMeasureView().toolbar { closeButton } }
                .tabItem { Label("Measure", systemImage: "ruler") }
            NavigationStack { MTPhotosView().toolbar { closeButton } }
                .tabItem { Label("Photos", systemImage: "photo.on.rectangle") }
            NavigationStack { MTSettingsView().toolbar { closeButton } }
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(.indigo)
        // Hide content in the app switcher; lock as soon as the app goes to the background (not mid-timer).
        .overlay {
            if scenePhase != .active {
                ZStack {
                    Rectangle().fill(.ultraThickMaterial)
                    Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(.secondary)
                }
                .ignoresSafeArea()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, !vault.stayOpenForTimer() { close() }
            if phase == .active { vault.returnedToApp() }
        }
        .onAppear {
            MTPrivacyCover.shared.start()
            keepAwake(vault.data.timerRunning)
        }
        // The screen doesn't auto-lock while a timer runs, open or minimised.
        .onChange(of: vault.data.timerRunning) { _, busy in keepAwake(busy) }
        .onDisappear { keepAwake(false) }
        .onChange(of: vault.isUnlocked) { _, unlocked in
            if !unlocked { dismiss() }
        }
    }

    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                close()
            } label: {
                Label("Lock", systemImage: "lock.fill")
            }
        }
    }

    private func close() {
        vault.lock()
        dismiss()
    }

    private func keepAwake(_ on: Bool) {
        UIApplication.shared.isIdleTimerDisabled = on
    }
}

/// An opaque window above everything (including sheets and full-screen photos) while the app isn't
/// active and More Training is unlocked, so nothing private shows in the app switcher.
@MainActor
final class MTPrivacyCover {
    static let shared = MTPrivacyCover()
    private var window: UIWindow?
    private var observers: [NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { MTPrivacyCover.shared.show() }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { MTPrivacyCover.shared.hide() }
        })
    }

    private func show() {
        guard window == nil, MTVault.shared.isUnlocked,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState != .unattached }) else { return }
        let controller = UIViewController()
        controller.view.backgroundColor = .systemBackground
        let lock = UIImageView(image: UIImage(systemName: "lock.fill"))
        lock.tintColor = .secondaryLabel
        lock.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .largeTitle)
        lock.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(lock)
        NSLayoutConstraint.activate([
            lock.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor),
            lock.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor)
        ])
        let cover = UIWindow(windowScene: scene)
        cover.windowLevel = .alert + 1
        cover.rootViewController = controller
        cover.isHidden = false
        window = cover
    }

    private func hide() {
        window?.isHidden = true
        window = nil
    }
}
