@preconcurrency import GoogleUserMessagingPlatform
import UIKit

/// Google UMP wrapper: asks for GDPR/TCF consent where it is required (EEA, UK, Switzerland)
/// and exposes the privacy-options form for Settings.
@MainActor
enum ConsentManager {
    /// Refreshes consent info and shows the consent form if the user must answer it.
    /// Returns whether ads may be requested. Errors fall back to the last known state.
    static func gatherConsent() async -> Bool {
        let parameters = RequestParameters()
        #if DEBUG
        if AdConfig.debugForceEEA {
            let debug = DebugSettings()
            debug.geography = .EEA
            parameters.debugSettings = debug
        }
        #endif

        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: parameters)
            if let presenter = UIApplication.topViewController() {
                try await ConsentForm.loadAndPresentIfRequired(from: presenter)
            }
        } catch {
            #if DEBUG
            print("UMP consent error: \(error.localizedDescription)")
            #endif
        }
        return ConsentInformation.shared.canRequestAds
    }

    static var canRequestAds: Bool {
        ConsentInformation.shared.canRequestAds
    }

    /// True when the user is in a region where they must be able to change their choice later.
    static var isPrivacyOptionsRequired: Bool {
        ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    static func presentPrivacyOptions() async {
        guard let presenter = UIApplication.topViewController() else { return }
        do {
            try await ConsentForm.presentPrivacyOptionsForm(from: presenter)
        } catch {
            #if DEBUG
            print("UMP privacy options error: \(error.localizedDescription)")
            #endif
        }
    }

    /// UMP decided no consent is needed here (outside GDPR regions). Used by `TcfConsentSignals`
    /// when UMP wrote no `IABTCF_gdprApplies` value.
    static var isConsentNotRequired: Bool {
        ConsentInformation.shared.consentStatus == .notRequired
    }
}

extension UIApplication {
    /// The view controller at the top of the key window, used to present consent forms and full-screen ads.
    @MainActor
    static func topViewController() -> UIViewController? {
        let window = shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
