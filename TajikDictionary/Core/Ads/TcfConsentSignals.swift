import Foundation

/// The IAB TCF values UMP stores in UserDefaults, translated into each network's switch.
/// Same rules as the Android app. Google's classic iOS SDK reads TCF itself; Yandex only takes
/// one boolean, so it is derived here before the first Yandex request.
struct TcfConsentSignals: Sendable, Equatable {
    var gdprApplies: Int?
    var purposeConsents: String?
    var additionalConsent: String?

    /// Yandex's Google Additional Consent ID (not an IAB GVL vendor ID).
    static let yandexAdditionalConsentId = 1033

    static func from(_ defaults: UserDefaults = .standard) -> TcfConsentSignals {
        // UMP writes gdprApplies as an integer; read it as NSNumber so a missing key stays nil.
        TcfConsentSignals(
            gdprApplies: (defaults.object(forKey: "IABTCF_gdprApplies") as? NSNumber)?.intValue,
            purposeConsents: defaults.string(forKey: "IABTCF_PurposeConsents"),
            additionalConsent: defaults.string(forKey: "IABTCF_AddtlConsent")
        )
    }

    /// TCF purpose 1: store and/or access information on a device.
    func allowsStorage(consentNotRequired: Bool) -> Bool {
        switch gdprApplies {
        case 0: return true
        case 1: return hasConsent(for: 1)
        default: return consentNotRequired
        }
    }

    /// Yandex may use personal data: storage, plus Yandex in Google's Additional Consent list when GDPR applies.
    func allowsYandex(consentNotRequired: Bool) -> Bool {
        guard allowsStorage(consentNotRequired: consentNotRequired) else { return false }
        guard gdprApplies == 1 else { return true }
        return hasAdditionalConsent(for: Self.yandexAdditionalConsentId)
    }

    /// Personalized ads need purposes 3 and 4 on top of purpose 1. Anything less still serves
    /// ads, just non-personalized ones.
    func allowsPersonalization(consentNotRequired: Bool) -> Bool {
        guard gdprApplies == 1 else { return consentNotRequired || gdprApplies == 0 }
        return allowsStorage(consentNotRequired: consentNotRequired)
            && hasConsent(for: 3)
            && hasConsent(for: 4)
    }

    private func hasConsent(for oneBasedId: Int) -> Bool {
        guard let purposeConsents, purposeConsents.count >= oneBasedId else { return false }
        return Array(purposeConsents)[oneBasedId - 1] == "1"
    }

    /// AC strings look like `2~1033.89~dv.…`; the second `~` field lists the consented vendors.
    private func hasAdditionalConsent(for vendorId: Int) -> Bool {
        let fields = (additionalConsent ?? "").split(separator: "~", omittingEmptySubsequences: false)
        guard fields.count >= 2 else { return false }
        return fields[1].split(separator: ".").contains { Int($0) == vendorId }
    }
}
