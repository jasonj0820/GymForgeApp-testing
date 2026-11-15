import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @EnvironmentObject private var dayfold: DayfoldStore
    @State private var showRoutine = false
    @State private var tab: String
    @State private var showWhatsNew = false

    /// MK23: which tab opens first (demo screens ask for a specific one).
    init(startTab: String = "today") {
        _tab = State(initialValue: startTab)
    }

    var body: some View {
        tabs
            // MK23: once per new build.
            .sheet(isPresented: $showWhatsNew) {
                NavigationStack { WhatsNewView(asSheet: true) }
            }
            .onChange(of: tab) { _, new in Usage.opened("Tab: " + new.capitalized) }
            // MK10: runs / basketball recorded on the iPhone.
            .modifier(PhoneRecorderPresenter(recorder: store.phoneRecorder))
            .fullScreenCover(isPresented: Binding(
                get: { store.showWorkout && store.activeWorkout != nil },
                set: { store.showWorkout = $0 }
            )) {
                NavigationStack { PhoneActiveWorkoutView() }
                    .environmentObject(store)
            }
            .sheet(item: $store.summaryLog) { log in
                NavigationStack { WorkoutSummaryView(log: log) }
                    .environmentObject(store)
            }
            .sheet(item: $store.cardioSummary) { session in
                NavigationStack {
                    Group {
                        if session.kind == .run {
                            RunDetailView(session: session)
                        } else {
                            BasketballDetailView(session: session)
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { store.cardioSummary = nil }
                        }
                    }
                }
                .environmentObject(store)
            }
            .sheet(isPresented: $store.showWeeklyReview) {
                NavigationStack {
                    WeeklyReviewView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { store.showWeeklyReview = false }
                            }
                        }
                }
                .environmentObject(store)
            }
            // Tapping the Sunday-night notification opens the review (also on a cold launch).
            .onReceive(NotificationCenter.default.publisher(for: .openWeeklyReview)) { _ in
                PhoneAppDelegate.pendingReview = false
                store.showWeeklyReview = true
            }
            // MK22: a routine reminder (or the Routine quick action) opens the routine over whatever tab you're on.
            .sheet(isPresented: $showRoutine) {
                NavigationStack {
                    RoutineScreen()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showRoutine = false }
                            }
                        }
                }
                .environmentObject(store)
                .environmentObject(dayfold)
            }
            .onReceive(NotificationCenter.default.publisher(for: .dayfoldOpenRoutine)) { _ in
                showRoutine = true
            }
            .alert("Something needs attention", isPresented: Binding(
                get: { dayfold.errorMessage != nil },
                set: { if !$0 { dayfold.errorMessage = nil } }
            )) {
                Button("OK") { dayfold.errorMessage = nil }
            } message: {
                Text(dayfold.errorMessage ?? "")
            }
            .onAppear {
                Usage.opened("Tab: " + tab.capitalized)
                if WhatsNewView.isDue {
                    // A brand-new install has nothing "new" to be told about.
                    if store.workoutLogs.isEmpty { WhatsNewView.markSeen() } else { showWhatsNew = true }
                }
                if PhoneAppDelegate.pendingReview {
                    PhoneAppDelegate.pendingReview = false
                    store.showWeeklyReview = true
                }
            }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            NavigationStack { TodayView() }
                .tabItem { Label("Today", systemImage: "bolt.heart") }
                .tag("today")
            NavigationStack { RoutinesView() }
                .tabItem { Label("Workouts", systemImage: "list.bullet.rectangle") }
                .tag("workouts")
            NavigationStack { ExerciseProgressView() }
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }
                .tag("progress")
            NavigationStack { BodyView() }
                .tabItem { Label("Body", systemImage: "figure") }
                .tag("body")
            NavigationStack { CoachView() }
                .tabItem { Label("Coach", systemImage: "sparkles") }
                .tag("coach")
        }
    }
}

/// Shared card styling.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

struct InsightRow: View {
    let insight: CoachInsight

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title).font(.headline)
                Text(insight.message).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
