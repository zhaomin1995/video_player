import Foundation

class ResumeManager {
    private static let storageKey = "AwesomePlayer_ResumePositions"
    private static let orderKey = "AwesomePlayer_ResumeOrder"
    private static let maxEntries = 100

    private static let minDuration: Double = 180
    private static let minPercent: Double = 0.05
    private static let maxPercent: Double = 0.95
    private static let minAbsoluteTime: Double = 60
    private static let minRemainingTime: Double = 60

    static func savedPosition(for url: URL) -> Double? {
        let dict = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: Double] ?? [:]
        return dict[url.path]
    }

    static func savePosition(_ position: Double, duration: Double, for url: URL) {
        guard shouldStore(position: position, duration: duration) else { return }

        var dict = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: Double] ?? [:]
        var order = UserDefaults.standard.stringArray(forKey: orderKey) ?? []

        dict[url.path] = position
        order.removeAll { $0 == url.path }
        order.append(url.path)

        // FIFO eviction: remove oldest entries
        while dict.count > maxEntries && !order.isEmpty {
            let oldest = order.removeFirst()
            dict.removeValue(forKey: oldest)
        }

        UserDefaults.standard.set(dict, forKey: storageKey)
        UserDefaults.standard.set(order, forKey: orderKey)
    }

    static func clearPosition(for url: URL) {
        var dict = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: Double] ?? [:]
        var order = UserDefaults.standard.stringArray(forKey: orderKey) ?? []
        dict.removeValue(forKey: url.path)
        order.removeAll { $0 == url.path }
        UserDefaults.standard.set(dict, forKey: storageKey)
        UserDefaults.standard.set(order, forKey: orderKey)
    }

    private static func shouldStore(position: Double, duration: Double) -> Bool {
        guard duration >= minDuration else { return false }
        let percent = position / duration
        guard percent >= minPercent && percent <= maxPercent else { return false }
        guard position >= minAbsoluteTime else { return false }
        guard (duration - position) >= minRemainingTime else { return false }
        return true
    }
}
