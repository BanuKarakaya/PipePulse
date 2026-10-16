import Foundation
import UserNotifications

protocol PipelineNotificationSending: Sendable {
    func requestAuthorization() async
    func notifyIfNeeded(for pipeline: Pipeline) async
}

struct NoopPipelineNotificationService: PipelineNotificationSending {
    func requestAuthorization() async {}
    func notifyIfNeeded(for pipeline: Pipeline) async {}
}

final class MacNotificationService: PipelineNotificationSending, @unchecked Sendable {
    // Swift Package executables launched directly from Xcode do not always
    // have an .app bundle. UserNotifications requires a bundled application,
    // so safely disable notifications until the app is packaged as an .app.
    private let center: UNUserNotificationCenter?
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var notifiedPipelineIDs: Set<UUID>

    init(defaults: UserDefaults = .standard) {
        self.center = Bundle.main.bundleURL.pathExtension == "app"
            ? UNUserNotificationCenter.current()
            : nil
        self.defaults = defaults
        let stored = defaults.stringArray(forKey: "notifiedPipelineIDs") ?? []
        self.notifiedPipelineIDs = Set(stored.compactMap(UUID.init(uuidString:)))
    }

    func requestAuthorization() async {
        guard let center else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func notifyIfNeeded(for pipeline: Pipeline) async {
        guard let center else { return }
        guard pipeline.status == .failed else { return }
        guard markAsNotifiedIfNeeded(pipeline.id) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Pipeline failed"
        content.body = "\(pipeline.name) on \(pipeline.branch) needs attention."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: pipeline.id.uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )
        try? await center.add(request)
    }

    private func markAsNotifiedIfNeeded(_ id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !notifiedPipelineIDs.contains(id) else { return false }
        notifiedPipelineIDs.insert(id)
        defaults.set(notifiedPipelineIDs.map(\.uuidString), forKey: "notifiedPipelineIDs")
        return true
    }
}
