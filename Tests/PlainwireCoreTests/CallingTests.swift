import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import PlainwireCore

@Test func floatingPanelStaysReachableAfterDraggingAndWindowResizing() {
  let container = CGSize(width: 920, height: 620)
  let preferred = CGSize(width: 480, height: 380)
  let dock = PWCallPanelLayout(container: container, preferredSize: preferred)
  #expect(dock.origin.x == 428 && dock.origin.y == 228)
  let dragged = PWCallPanelLayout(container: container, preferredSize: preferred, origin: CGPoint(x: -500, y: 2000))
  #expect(dragged.origin.x == 12 && dragged.origin.y == 228)
  let phone = PWCallPanelLayout(container: CGSize(width: 320, height: 480), preferredSize: CGSize(width: 1200, height: 900), origin: dock.origin)
  #expect(phone.size.width == 296 && phone.size.height == 456)
  #expect(phone.origin.x == 12 && phone.origin.y == 12)
  let minimum = PWCallPanelLayout(container: container, preferredSize: CGSize(width: -10, height: -20))
  #expect(minimum.size.width == 320 && minimum.size.height == 100)
  let enlarged = PWCallPanelLayout(container: container, preferredSize: CGSize(width: 720, height: 520), origin: dock.origin)
  #expect(enlarged.origin.x + enlarged.size.width <= container.width - 12)
  #expect(enlarged.origin.y + enlarged.size.height <= container.height - 12)
}

@Test func callEventsAreScopedToKindAndRoom() {
  let call = PWCallRoom(kind: .direct, id: 42)
  #expect(call.matches(.init(type: "call_state", payload: ["conversation_id": .string("42")])))
  #expect(!call.matches(.init(type: "call_ended", payload: ["conversation_id": .int(41)])))
  #expect(!call.matches(.init(type: "voice_state", payload: ["channel_id": .int(42)])))
  #expect(!call.matches(.init(type: "call_signal", payload: [:])))
  #expect(call.matches(.init(type: "error", payload: ["rtc_kind": .string("call"), "rtc_id": .int(42)])))
  #expect(!call.matches(.init(type: "error", payload: ["rtc_kind": .string("voice"), "rtc_id": .int(42)])))
}

@Test func revocationOnlyEndsTheAffectedCall() {
  let call = PWCallRoom(kind: .direct, id: 42)
  let voice = PWCallRoom(kind: .voice, id: 9)
  let directRevocation = PlainwireRealtimeEvent(type: "access_revoked", payload: ["scope": .string("direct"), "conversation_id": .int(42)])
  #expect(call.accessRevoked(by: directRevocation))
  #expect(!voice.accessRevoked(by: directRevocation))
  let serverRevocation = PlainwireRealtimeEvent(type: "access_revoked", payload: ["scope": .string("server"), "channel_ids": .array([.string("9"), .int(10)])])
  #expect(voice.accessRevoked(by: serverRevocation))
  #expect(!call.accessRevoked(by: serverRevocation))
  #expect(!PWCallRoom(kind: .voice, id: 11).accessRevoked(by: serverRevocation))
}

@Test func callCommandsUseTheExistingServerProtocol() {
  #expect(PWCallRoom(kind: .direct, id: 42).command("accept") == ["type": .string("call_accept"), "conversation_id": .int(42)])
  #expect(PWCallRoom(kind: .voice, id: 9).command("join") == ["type": .string("voice_join"), "channel_id": .int(9)])
}

@Test func callRostersAcceptTheServerProfileShape() {
  let participant = PWCallParticipant(.object([
    "user_id": .string("7"), "profile": .object(["id": .int(7), "display_name": .string("Alice")]),
    "muted": .bool(true), "deafened": .bool(true), "screen": .bool(true), "reconnecting": .bool(true),
  ]))
  #expect(participant?.id == 7)
  #expect(participant?.name == "Alice")
  #expect(participant?.muted == true && participant?.deafened == true)
  #expect(participant?.sharingVideo == true && participant?.reconnecting == true)
  #expect(PWCallParticipant(.object(["user_id": .int(0)])) == nil)
  #expect(PWCallParticipant(.object(["user_id": .null])) == nil)
}
