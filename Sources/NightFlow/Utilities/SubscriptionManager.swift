import Foundation

/// Paywall gate, stubbed from day one (project rule #4) so a Pro tier can be added
/// later without refactoring. Everything is free at launch: isPro is hard-true for now.
/// When RevenueCat is wired up (Phase 5+), this is the only place that changes.
final class SubscriptionManager {

    static let shared = SubscriptionManager()
    private init() {}

    /// v1: everyone gets full value. Flip to real entitlement checks later.
    var isPro: Bool { true }

    /// Feature gate helper for future paid features. Currently always allows.
    func isEnabled(_ feature: ProFeature) -> Bool {
        return isPro
    }

    enum ProFeature {
        case circadianTimeline
        case redMode
        case appWhitelist
        case emergencyColor
        case customShortcuts
        case researchSection
    }
}
