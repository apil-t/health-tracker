import SwiftUI

struct RootTabView: View {
    @Environment(HealthStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") { NavigationStack { HomeView() } }
            Tab("Activity", systemImage: "waveform.path.ecg") { NavigationStack { ActivityView() } }
            Tab("Intake", systemImage: "fork.knife") { NavigationStack { IntakeView() } }
            Tab("Profile", systemImage: "person") { NavigationStack { ProfileView() } }
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
