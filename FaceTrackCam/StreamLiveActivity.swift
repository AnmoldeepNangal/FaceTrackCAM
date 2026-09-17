import ActivityKit
import Foundation

/// Serialized on the main queue alongside the camera's published stream status.
final class StreamLiveActivity {
    private var activity: Activity<StreamActivityAttributes>?

    func setStreaming(_ running: Bool, since: Date?) {
        if running {
            guard activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            let state = StreamActivityAttributes.ContentState(startedAt: since ?? Date())
            do {
                activity = try Activity.request(attributes: StreamActivityAttributes(name: "FacePull"),
                    content: ActivityContent(state: state, staleDate: nil), pushType: nil)
            } catch {
                // Live Activities can be disabled by the system; streaming must still work.
                NSLog("Live Activity unavailable: %@", error.localizedDescription)
            }
        } else {
            let previous = activity
            activity = nil
            Task {
                if let previous { await previous.end(nil, dismissalPolicy: .immediate) }
            }
        }
    }
}

