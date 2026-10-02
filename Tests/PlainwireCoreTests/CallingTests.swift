import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import PlainwireCore

@Test func panelInteractionsUseOneAnchorAcrossEveryPointerEvent() {
  let container = CGSize(width: 1000, height: 800)
  let anchor = PWCallPanelLayout(container: container, preferredSize: CGSize(width: 480, height: 380), origin: CGPoint(x: 100, y: 100))
  let move = PWCallPanelInteraction(anchor: anchor, kind: .move)
  #expect(move.layout(translation: CGSize(width: 50, height: 30), container: container).origin.x == 150)
  #expect(move.layout(translation: CGSize(width: 51, height: 31), container: container).origin.x == 151)
  #expect(move.layout(translation: CGSize(width: -1000, height: -1000), container: container).origin.x == 12)
  #expect(move.layout(translation: .zero, container: container) == anchor)
  let resize = PWCallPanelInteraction(anchor: anchor, kind: .resize)
  #expect(resize.layout(translation: CGSize(width: 80, height: 40), container: container).size.width == 560)
  #expect(resize.layout(translation: CGSize(width: 81, height: 41), container: container).size.width == 561)
  #expect(resize.layout(translation: CGSize(width: -900, height: -900), container: container).size.height == 280)
}

@Test func panelLayoutRejectsNonFiniteOrTransientGeometry() {
  for container in [CGSize.zero, CGSize(width: 8, height: 6), CGSize(width: CGFloat.nan, height: CGFloat.infinity)] {
    let fitted = PWCallPanelLayout(container: container, preferredSize: CGSize(width: CGFloat.infinity, height: CGFloat.nan), origin: CGPoint(x: CGFloat.nan, y: CGFloat.infinity))
    #expect(fitted.size.width.isFinite && fitted.size.width > 0)
    #expect(fitted.size.height.isFinite && fitted.size.height > 0)
    #expect(fitted.origin.x.isFinite && fitted.origin.y.isFinite)
  }
}

@Test func callPresenceMatchesTheAccountWideServerSnapshot() {
  let event = PlainwireRealtimeEvent(type: "call_presence", payload: [
    "conversation_id": .int(42), "active": .bool(true),
    "users": .array([.object(["user_id": .int(8)]), .object(["user_id": .int(8)]), .object(["user_id": .int(7)])]),
  ])
  let snapshot = PWCallPresenceSnapshot(event)
  #expect(snapshot?.conversationID == 42 && snapshot?.active == true)
  #expect(snapshot?.participants.map(\.id) == [8, 7])
  #expect(PWCallPresenceSnapshot(.init(type: "call_presence", payload: ["conversation_id": .int(42), "active": .bool(true)])) == nil)
  #expect(PWCallPresenceSnapshot(.init(type: "call_presence", payload: ["conversation_id": .int(42), "active": .bool(false)]))?.active == false)
}

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
