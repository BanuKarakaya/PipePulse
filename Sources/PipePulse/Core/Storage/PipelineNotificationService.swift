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
    private let center = UNUserNotificationCenter.current()
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var notifiedPipelineIDs: Set<UUID>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.stringArray(forKey: "notifiedPipelineIDs") ?? []
        self.notifiedPipelineIDs = Set(stored.compactMap(UUID.init(uuidString:)))
    }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func notifyIfNeeded(for pipeline: Pipeline) async {
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
