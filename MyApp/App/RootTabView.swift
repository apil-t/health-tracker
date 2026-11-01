import SwiftUI

struct RootTabView: View {
    @Environment(HealthStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    /// Launch with `-screen stress` (heart, steps, sleep, activity, intake, profile) to open that screen; used for README screenshots.
    private static let launchScreen = UserDefaults.standard.string(forKey: "screen") ?? ""
    @State private var tab = ["activity", "intake", "profile"].contains(launchScreen) ? launchScreen : "home"
    @State private var showLaunchDetail = ["heart", "stress", "steps", "sleep"].contains(launchScreen)

    var body: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house", value: "home") {
                NavigationStack {
                    HomeView().navigationDestination(isPresented: $showLaunchDetail) {
                        switch Self.launchScreen {
                        case "heart": HeartRateView()
                        case "stress": StressView()
                        case "steps": StepsView()
                        default: SleepView()
                        }
                    }
                }
            }
            Tab("Activity", systemImage: "waveform.path.ecg", value: "activity") { NavigationStack { ActivityView() } }
            Tab("Intake", systemImage: "fork.knife", value: "intake") { NavigationStack { IntakeView() } }
            Tab("Profile", systemImage: "person", value: "profile") { NavigationStack { ProfileView() } }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { Task { await store.sync() } }
            if phase == .background { store.save() }
        }
    }
}

#Preview {
    RootTabView().environment(HealthStore())
}
