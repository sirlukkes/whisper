import Foundation
import Cocoa
import ServiceManagement

/// Registers/unregisters the app as a login item via `SMAppService.mainApp` (macOS 13+).
///
/// The enabled state is NOT persisted in UserDefaults on purpose: the system is the single
/// source of truth (the user can toggle it from System Settings → Login Items too), so we
/// always read `SMAppService.mainApp.status` and refresh on demand.
final class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    /// Mirrors the system state; refreshed on init, on every change and when the UI asks.
    @Published private(set) var isEnabled: Bool = false

    /// Last error message from register/unregister, for inline display in the UI.
    @Published private(set) var lastError: String? = nil

    private init() {
        refresh()
    }

    /// Re-reads the login-item status from the system.
    func refresh() {
        isEnabled = (SMAppService.mainApp.status == .enabled)
    }

    /// Enables or disables launch at login. Errors surface in `lastError` and `isEnabled` is
    /// re-read from the system afterwards so the UI never lies.
    func setEnabled(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = error.localizedDescription
            NSLog("LaunchAtLogin: %@ failed: %@", enabled ? "register" : "unregister", error.localizedDescription)
        }
        refresh()
    }

    /// True when the current launch was triggered by the login-item mechanism.
    ///
    /// launchd delivers an `kAEOpenApplication` Apple Event whose `keyAEPropData` parameter
    /// is `keyAELaunchedAsLogInItem`. Must be called from `applicationDidFinishLaunching`,
    /// while the launching event is still the current one.
    static func launchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == kCoreEventClass,
              event.eventID == kAEOpenApplication,
              let prop = event.paramDescriptor(forKeyword: keyAEPropData) else {
            return false
        }
        return prop.enumCodeValue == keyAELaunchedAsLogInItem
    }
}
