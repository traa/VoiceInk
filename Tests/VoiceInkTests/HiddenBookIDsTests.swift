import Foundation
import Testing
@testable import VoiceInk

struct HiddenBookIDsTests {
    @Test func roundTripsIDs() {
        let hidden = HiddenBookIDs(ids: ["builtin.iliad", "builtin.odyssey"])
        let decoded = HiddenBookIDs(rawValue: hidden.rawValue)
        #expect(decoded == hidden)
        #expect(decoded?.ids == ["builtin.iliad", "builtin.odyssey"])
    }

    @Test func emptyRawValueIsEmptySet() {
        #expect(HiddenBookIDs(rawValue: "")?.ids == [])
    }

    @Test func garbageRawValueIsEmptySet() {
        #expect(HiddenBookIDs(rawValue: "{not json")?.ids == [])
        #expect(HiddenBookIDs(rawValue: "{\"a\":1}")?.ids == [])
    }

    @Test func rawValueIsSortedJSON() {
        let hidden = HiddenBookIDs(ids: ["builtin.odyssey", "builtin.iliad", "builtin.animal-farm"])
        #expect(hidden.rawValue == #"["builtin.animal-farm","builtin.iliad","builtin.odyssey"]"#)
        #expect(HiddenBookIDs(ids: ["builtin.iliad", "builtin.odyssey"]).rawValue
            == HiddenBookIDs(ids: ["builtin.odyssey", "builtin.iliad"]).rawValue)
    }

    @Test func defaultIsEmpty() {
        #expect(HiddenBookIDs().ids.isEmpty)
    }
}
