import Foundation
import Testing
@testable import PlainwireCore

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
