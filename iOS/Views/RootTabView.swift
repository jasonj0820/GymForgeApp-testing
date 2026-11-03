import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var store: PhoneAppStore

    var body: some View {
        tabs
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
            .onAppear {
                if PhoneAppDelegate.pendingReview {
                    PhoneAppDelegate.pendingReview = false
                    store.showWeeklyReview = true
                }
            }
    }

    private var tabs: some View {
        TabView {
            NavigationStack {
                TodayView()
                    .toolbar {
                        // MK12: switch to the Dayfold half (also: long-press the app icon).
                        ToolbarItem(placement: .topBarLeading) {
                            Button { AppLink.open(URL(string: "gymforge://dayfold")!) } label: {
                                Label("Dayfold", systemImage: "checklist")
                            }
                        }
                    }
            }
                .tabItem { Label("Today", systemImage: "bolt.heart") }
            NavigationStack { RoutinesView() }
                .tabItem { Label("Workouts", systemImage: "list.bullet.rectangle") }
            NavigationStack { ExerciseProgressView() }
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }
            NavigationStack { BodyView() }
                .tabItem { Label("Body", systemImage: "figure") }
            NavigationStack { CoachView() }
                .tabItem { Label("Coach", systemImage: "sparkles") }
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
