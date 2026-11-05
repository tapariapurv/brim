import Foundation

enum RefreshSetting {
    static let key = "refreshIntervalMinutes"
    static let defaultMinutes = 5
    static let minuteOptions = [1, 2, 5, 10, 15, 30, 60]

    static var interval: TimeInterval {
        let minutes = UserDefaults.standard.integer(forKey: key)
        return TimeInterval((minuteOptions.contains(minutes) ? minutes : defaultMinutes) * 60)
    }

    /// A forced refresh lets the next pass skip an account, so working refreshes can leave its values
    /// about two intervals old.
    static var stalenessThreshold: TimeInterval { interval * 2 }

    static let failureBackoffBase: TimeInterval = 5 * 60
    static let failureBackoffCap: TimeInterval = 60 * 60

    static let secondaryReadInterval: TimeInterval = 60 * 60
    static let forcedResetGrantsMinimumAge: TimeInterval = 15 * 60
}
