import Foundation

struct AppPreferences: Sendable {
    static let suiteName = "com.pipepulse.preferences"

    var refreshInterval: RefreshInterval = .oneMinute
    var notificationsEnabled = true
    var isOnboardingComplete = false
}

enum RefreshInterval: Int, CaseIterable, Identifiable, Sendable {
    case manual = 0
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .manual: "Manual"
        case .oneMinute: "Every minute"
        case .fiveMinutes: "Every 5 minutes"
        case .fifteenMinutes: "Every 15 minutes"
        }
    }
}
