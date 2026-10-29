import Foundation

/// A dotted app version such as "0.9.10", compared number by number so "0.9.10" > "0.9.2".
/// Missing parts count as 0, so "1.0" equals "1.0.0".
struct AppVersion: Comparable, CustomStringConvertible {
    private let parts: [Int]
    let description: String

    init?(_ string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
        self.parts = parts.compactMap(\.self)
        description = string
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        compare(lhs, rhs) == 0
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        compare(lhs, rhs) < 0
    }

    private static func compare(_ lhs: AppVersion, _ rhs: AppVersion) -> Int {
        for index in 0 ..< max(lhs.parts.count, rhs.parts.count) {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right ? -1 : 1 }
        }
        return 0
    }
}

/// When the Home card offers an update.
enum UpdatePolicy {
    /// Shows when the store has a newer version than the one installed, unless the user dismissed
    /// that version or a newer one. An unknown version never shows the card.
    static func shouldShow(installed: AppVersion?, store: AppVersion?, dismissed: AppVersion?) -> Bool {
        guard let installed, let store, store > installed else { return false }
        guard let dismissed else { return true }
        return store > dismissed
    }
}
