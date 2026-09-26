import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var snapshot = HealthSnapshot.empty
    @Published private(set) var connected = false
    @Published private(set) var configured = false
    @Published private(set) var loading = false
    @Published var errorMessage: String?

    private let auth: OAuthClient
    private let api: OuraAPI

    init() {
        let auth = OAuthClient()
        self.auth = auth
        self.api = OuraAPI(auth: auth)
        Task { await updateConnectionState() }
    }

    func updateConnectionState() async {
        configured = await auth.isConfigured
        connected = await auth.isConnected
    }

    func refresh() async {
        await updateConnectionState()
        guard connected, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            snapshot = try await api.fetchSnapshot()
            errorMessage = nil
        } catch {
            snapshot = .empty
            errorMessage = error.localizedDescription
        }
    }

    func connect(clientID: String, clientSecret: String) async {
        loading = true
        defer { loading = false }
        do {
            let trimmedID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedID.isEmpty, !trimmedSecret.isEmpty else { throw RingStatsError.notConfigured }
            try await auth.configure(ClientCredentials(clientID: trimmedID, clientSecret: trimmedSecret))
            try await authorizeConfiguredApplication()
            await updateConnectionState()
            snapshot = try await api.fetchSnapshot()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            await updateConnectionState()
        }
    }

    func reauthorize() async {
        loading = true
        connected = false
        snapshot = .empty
        defer { loading = false }
        do {
            try await auth.clearAuthorization()
            try await authorizeConfiguredApplication()
            await updateConnectionState()
            snapshot = try await api.fetchSnapshot()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            await updateConnectionState()
        }
    }

    func disconnect() async {
        connected = false
        snapshot = .empty
        do {
            try await auth.disconnect()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        await updateConnectionState()
    }

    private func authorizeConfiguredApplication() async throws {
        let state = UUID().uuidString
        let browserURL = try await auth.authorizationRequest(state: state)
        let server = CallbackServer(expectedState: state)
        try await server.start()
        NSWorkspace.shared.open(browserURL)
        let callback = try await withThrowingTaskGroup(of: URL.self) { group in
            group.addTask { try await server.waitForCallback() }
            group.addTask {
                try await Task.sleep(for: .seconds(300))
                throw RingStatsError.callback("Oura authorization timed out. Start the connection again.")
            }
            guard let first = try await group.next() else {
                throw RingStatsError.callback("Oura authorization did not complete.")
            }
            group.cancelAll()
            return first
        }
        guard callback.path == "/oauth/callback" else { throw RingStatsError.callback("Unexpected callback path.") }
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let returnedState = items.first(where: { $0.name == "state" })?.value
        guard returnedState == state else { throw RingStatsError.callback("The connection state did not match.") }
        if let oauthError = items.first(where: { $0.name == "error" })?.value {
            throw RingStatsError.callback("Oura authorization failed: \(oauthError)")
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw RingStatsError.callback("Oura did not return an authorization code.")
        }
        try await auth.exchange(code: code)
    }
}
