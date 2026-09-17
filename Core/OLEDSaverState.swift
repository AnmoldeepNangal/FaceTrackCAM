import Foundation

/// A one-shot countdown per stream. Client status updates must never re-arm it.
struct OLEDSaverState {
    private(set) var enabled = false
    private(set) var streaming = false
    private(set) var dimmed = false
    private(set) var deadline: TimeInterval?

    mutating func setAuto(_ enabled: Bool, now: TimeInterval) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        dimmed = false
        deadline = enabled && streaming ? now + 30 : nil
    }

    mutating func setStreaming(_ streaming: Bool, now: TimeInterval) {
        guard self.streaming != streaming else { return }
        self.streaming = streaming
        dimmed = false
        deadline = enabled && streaming ? now + 30 : nil
    }

    mutating func wake() {
        dimmed = false
        deadline = nil
    }

    mutating func advance(to now: TimeInterval) {
        guard enabled, streaming, let deadline, now >= deadline else { return }
        dimmed = true
        self.deadline = nil
    }
}

