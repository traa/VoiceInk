import Foundation
import Testing
@testable import VoiceInk

struct SpanishCardGateTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let longText = "this is a perfectly fine sentence"

    private func evaluate(
        text: String? = nil, isEnabled: Bool = true, hasProvider: Bool = true,
        pausedUntil: Date? = nil, lastCardShownAt: Date? = nil, bundleID: String? = "com.apple.TextEdit"
    ) -> SpanishCardGate.Decision {
        SpanishCardGate.evaluate(
            text: text ?? longText, isEnabled: isEnabled, hasProvider: hasProvider,
            pausedUntil: pausedUntil ?? .distantPast, lastCardShownAt: lastCardShownAt ?? .distantPast,
            frontmostBundleID: bundleID, now: now)
    }

    @Test func showsWhenEverythingPasses() { #expect(evaluate() == .show) }
    @Test func disabled() { #expect(evaluate(isEnabled: false) == .skip(.disabled)) }
    @Test func noProvider() { #expect(evaluate(hasProvider: false) == .skip(.noProvider)) }
    @Test func paused() { #expect(evaluate(pausedUntil: now.addingTimeInterval(1)) == .skip(.paused)) }
    @Test func pauseExpired() { #expect(evaluate(pausedUntil: now) == .show) }
    @Test func inCallApp() { #expect(evaluate(bundleID: "us.zoom.xos") == .skip(.inCallApp)) }
    @Test func unknownOrNilBundleShows() {
        #expect(evaluate(bundleID: "com.example.app") == .show)
        #expect(evaluate(bundleID: nil) == .show)
    }
    @Test func wordBoundary() {
        #expect(evaluate(text: "one two three") == .show)
        #expect(evaluate(text: "one two") == .skip(.tooShort))
    }
    @Test func cooldownBoundary() {
        #expect(evaluate(lastCardShownAt: now.addingTimeInterval(-59)) == .skip(.coolingDown))
        #expect(evaluate(lastCardShownAt: now.addingTimeInterval(-60)) == .show)
    }
}
