import SwiftUI

@main struct MyApp: App {
    @State private var store = HealthStore()

    var body: some Scene {
        WindowGroup {
            RootTabView().environment(store)
        }
    }
}
