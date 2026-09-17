import ActivityKit
import Foundation

struct StreamActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startedAt: Date
    }
    var name: String
}

