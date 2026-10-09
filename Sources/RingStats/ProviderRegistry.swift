import RingStatsCore
import RingStatsOura

/// The one place the app names a provider module. Everything else works
/// through `HealthProvider` and `ProviderDescriptor`, and a test keeps the
/// `RingStatsOura` import confined to this file.
enum ProviderRegistry {
    static let defaultProviderID = OuraProvider.descriptor.id
    static let defaultDisplayName = OuraProvider.descriptor.displayName

    private static let providers: [ProviderID: @MainActor () -> any HealthProvider] = [
        OuraProvider.descriptor.id: { OuraProvider() },
    ]

    @MainActor static func makeDefault() -> any HealthProvider {
        providers[defaultProviderID]!()
    }
}
