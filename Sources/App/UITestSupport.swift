import Foundation

/// Only for automated UI tests (launch argument "-uitest"): start from a clean slate, skip the
/// intro and the notification prompt. Never active in normal use.
enum UITestSupport {
    static var isActive: Bool { CommandLine.arguments.contains("-uitest") }

    static func prepare() {
        guard isActive else { return }
        let d = UserDefaults.standard
        if let id = Bundle.main.bundleIdentifier { d.removePersistentDomain(forName: id) }
        d.set(true, forKey: "onboarded")
        d.set("حمد", forKey: "userName")
        d.set(CommandLine.arguments.contains("-lang-en") ? "en" : "ar", forKey: "language")
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        for f in ["appointments.json", "tasks.json", "deleted.json", "items.json"] {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(f))
        }
    }
}
