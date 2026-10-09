import Foundation

/// A source of health data behind one boundary: sign-in, the metrics it can
/// supply, fetching a snapshot, and revoking access. Providers are compiled
/// into the app rather than loaded as plugins.
package protocol HealthProvider: Sendable {
    var descriptor: ProviderDescriptor { get }
    /// Sign-in, connection state, and revocation.
    var account: any OAuthServicing { get }
    /// Fetches the requested metrics and the battery as one snapshot.
    var snapshots: any SnapshotFetching { get }
}

/// What a provider is and what it supports, as plain data the app can reason
/// about without knowing the provider's API.
package struct ProviderDescriptor: Sendable, Equatable {
    package let id: ProviderID
    package let displayName: String
    package let capabilities: ProviderCapabilities
    /// The permission each supported metric needs.
    package let metricScopes: [Metric: AuthorizationScope]
    /// Permissions requested whatever metrics are shown, such as battery access.
    package let baseScopes: Set<AuthorizationScope>
    /// Where the user creates the application whose credentials they bring.
    package let developerPortal: URL?

    package init(
        id: ProviderID,
        displayName: String,
        capabilities: ProviderCapabilities,
        metricScopes: [Metric: AuthorizationScope],
        baseScopes: Set<AuthorizationScope>,
        developerPortal: URL? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.capabilities = capabilities
        self.metricScopes = metricScopes
        self.baseScopes = baseScopes
        self.developerPortal = developerPortal
    }

    /// The permissions to request for the given metrics. Unsupported metrics
    /// add nothing.
    package func scopes(for metrics: Set<Metric>) -> Set<AuthorizationScope> {
        Set(metrics.compactMap { metricScopes[$0] }).union(baseScopes)
    }

    /// The requested metrics this provider can supply.
    package func supported(_ metrics: Set<Metric>) -> Set<Metric> {
        metrics.intersection(capabilities.supportedMetrics)
    }
}

package struct ProviderID: RawRepresentable, Hashable, Sendable {
    package let rawValue: String

    package init(rawValue: String) {
        self.rawValue = rawValue
    }
}

package struct ProviderCapabilities: Sendable, Equatable {
    package let supportedMetrics: Set<Metric>
    package let reportsBattery: Bool
    /// Whether the provider offers a sandbox with synthetic data that tests
    /// have been verified against.
    package let hasSandbox: Bool

    package init(supportedMetrics: Set<Metric>, reportsBattery: Bool, hasSandbox: Bool) {
        self.supportedMetrics = supportedMetrics
        self.reportsBattery = reportsBattery
        self.hasSandbox = hasSandbox
    }
}

/// An OAuth scope name. It is created only from a string literal, so a scope
/// recorded in diagnostics cannot carry runtime text such as a token.
package struct AuthorizationScope: Hashable, Sendable {
    package let rawValue: String

    package init(_ literal: StaticString) {
        self.rawValue = "\(literal)"
    }
}

package protocol AccessTokenProviding: Sendable {
    func accessToken(forceRefresh: Bool) async throws -> String
    func invalidateAuthorization() async throws
}

package protocol OAuthServicing: AccessTokenProviding {
    var startupError: RingStatsError? { get async }
    var isConfigured: Bool { get async }
    var isConnected: Bool { get async }
    func configure(_ credentials: ClientCredentials) async throws
    /// Revokes remote access and removes every locally saved secret.
    func disconnect() async throws
    func authorizationRequest(state: String, scopes: Set<AuthorizationScope>) async throws -> URL
    func exchange(code: String) async throws
}

package protocol SnapshotFetching: Sendable {
    func fetchSnapshot(metrics: Set<Metric>, now: Date) async throws -> HealthSnapshot
}
