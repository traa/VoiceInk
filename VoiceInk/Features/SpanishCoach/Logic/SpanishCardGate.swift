import Foundation

enum SpanishCardGate {
    static let minimumWords = 3
    static let cooldown: TimeInterval = 60
    static let callAppBundleIDs: Set<String> = [
        "us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams", "com.apple.FaceTime",
    ]

    enum Reason: Equatable { case disabled, paused, tooShort, coolingDown, inCallApp, noProvider }
    enum Decision: Equatable { case show, skip(Reason) }

    static func evaluate(
        text: String, isEnabled: Bool, hasProvider: Bool, pausedUntil: Date,
        lastCardShownAt: Date, frontmostBundleID: String?, now: Date
    ) -> Decision {
        if !isEnabled { return .skip(.disabled) }
        if !hasProvider { return .skip(.noProvider) }
        if now < pausedUntil { return .skip(.paused) }
        if WordCounter.count(in: text) < minimumWords { return .skip(.tooShort) }
        if let frontmostBundleID, callAppBundleIDs.contains(frontmostBundleID) { return .skip(.inCallApp) }
        if now.timeIntervalSince(lastCardShownAt) < cooldown { return .skip(.coolingDown) }
        return .show
    }
}
