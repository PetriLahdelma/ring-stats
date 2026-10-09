import RingStatsCore
import RingStatsOura

/// The one place the app names a provider module. Everything else works
/// through `HealthProvider` and `ProviderDescriptor`, and a test keeps the
/// `RingStatsOura` import confined to this file. There is one provider
/// today; a second one adds a persisted choice here and nowhere else.
enum ProviderRegistry {
    static let defaultProviderID = OuraProvider.descriptor.id
    static let defaultDisplayName = OuraProvider.descriptor.displayName

    @MainActor static func makeDefault() -> any HealthProvider {
        OuraProvider()
    }
}
