import SwiftUI
import AuthenticationServices

/// Connect / sync / disconnect Google Health (where Fitbit data now lives).
struct GoogleHealthCard: View {
    @Environment(HealthStore.self) private var store
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var isShowingOptions = false

    var body: some View {
        Button {
            if store.isConnected { isShowingOptions = true } else { Task { await connect() } }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "watch.analog").font(.title3).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.isConnected ? "\(store.deviceName) via Google Health" : "Connect Google Health")
                        .font(.footnote.weight(.medium))
                    Text(status).font(.caption2).foregroundStyle(.secondary)
                    if let error = store.syncError {
                        Text(error).font(.caption2).foregroundStyle(.red)
                    }
                }
                Spacer()
                if store.isSyncing { ProgressView() } else { Chevron() }
            }
            .card()
        }
        .buttonStyle(.plain)
        .disabled(store.isSyncing)
        .confirmationDialog("Google Health", isPresented: $isShowingOptions) {
            Button("Sync now") { Task { await store.sync() } }
            Button("Disconnect", role: .destructive) { store.disconnect() }
        }
    }

    private var status: String {
        if store.isSyncing { return "Syncing…" }
        guard store.isConnected else { return "Showing sample data · Tap to sign in with Google" }
        guard let lastSync = store.lastSync else { return "Connected · Not synced yet" }
        return "Connected · Last synced \(lastSync.formatted(.relative(presentation: .named)))"
    }

    private func connect() async {
        do {
            let callback = try await webAuthenticationSession.authenticate(
                using: store.beginSignIn(),
                callback: .customScheme(GoogleAuth.callbackScheme),
                preferredBrowserSession: .shared,
                additionalHeaderFields: [:]
            )
            await store.completeSignIn(callbackURL: callback)
        } catch {
            // The user closed the Google sheet; nothing to report.
        }
    }
}
