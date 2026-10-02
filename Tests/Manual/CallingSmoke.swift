import Foundation
import AVFoundation
@preconcurrency import WebRTC

// Compile with Sources/PlainwireCore/*.swift and App/Calling/{CallController,NativeCallPeer}.swift.
// Uses a local WebRTC pair; no Plainwire account or network server is required.
@main struct CallingSmoke {
  @MainActor static func main() async throws {
    let call = CallController()
    var commands: [[String: JSONValue]] = []
    call.send = { commands.append($0) }
    call.userID = 8
    call.receive(.init(type: "call_incoming", payload: ["conversation_id": .int(42), "invite_id": .string("invite-1")]))
    try check(call.incoming?.id == 42, "Incoming call was not shown")
    call.receive(.init(type: "call_incoming", payload: ["conversation_id": .int(99), "invite_id": .string("second-invite")]))
    try await waitUntil { commands.contains { $0["invite_id"] == .string("second-invite") } }
    try check(call.incoming?.id == 42, "Second invitation replaced the unanswered call")
    call.receive(.init(type: "call_cancelled", payload: ["conversation_id": .int(42), "invite_id": .string("older-invite")]))
    try check(call.incoming?.token == "invite-1", "Stale invitation token dismissed a new call")
    await call.decline()
    try check(commands.last?["type"] == .string("call_decline") && commands.last?["invite_id"] == .string("invite-1"), "Decline lost the invitation token")

    call.requestMicrophone = { false }
    call.start(kind: .direct, id: 42, title: "Alice", userID: 8)
    try await waitUntil { call.room == nil }
    try check(call.error?.contains("microphone") == true, "Permission denial was not visible")
    try check(!commands.contains { $0["type"] == .string("call_ring") }, "Caller rang before microphone permission")

    // Teardown during an outstanding permission request must not resurrect media.
    call.requestMicrophone = { try? await Task.sleep(for: .milliseconds(100)); return true }
    call.start(kind: .voice, id: 9, title: "Lounge", userID: 8)
    await call.end()
    try await Task.sleep(for: .milliseconds(150))
    try check(call.room == nil && call.localVideo == nil && call.peers.isEmpty, "Cancelled startup resurrected media")

    // A dead socket must invalidate startup before its permission result arrives.
    call.start(kind: .voice, id: 9, title: "Lounge", userID: 8)
    try await Task.sleep(for: .milliseconds(20))
    call.connectionChanged(.reconnecting(1))
    try await Task.sleep(for: .milliseconds(150))
    try check(call.room?.id == 9 && call.localVideo == nil, "Disconnected startup restored capture")
    call.connectionChanged(.connected)
    try await Task.sleep(for: .milliseconds(20))
    call.connectionChanged(.reconnecting(1))
    try await Task.sleep(for: .milliseconds(150))
    try check(call.room?.id == 9 && call.localVideo == nil, "A second disconnect restored capture during reconnect")
    await call.end()

    call.receive(.init(type: "call_incoming", payload: ["conversation_id": .int(42)]))
    call.receive(.init(type: "call_cancelled", payload: ["conversation_id": .int(99)]))
    try check(call.incoming?.id == 42, "A late event dismissed another call")
    call.receive(.init(type: "call_cancelled", payload: ["conversation_id": .int(42)]))
    try check(call.incoming == nil, "Cancelled invitation remained visible")
    call.reset()

    call.requestMicrophone = { true }
    call.loadConfiguration = { .object(["iceServers": .array([])]) }
    call.start(kind: .direct, id: 42, title: "Alice", userID: 8)
    try await waitUntil { commands.last?["type"] == .string("call_ring") }
    call.receive(.init(type: "call_state", payload: ["conversation_id": .int(42), "users": .array([.object(["user_id": .int(8)])])]))
    try check(call.joined, "Own roster seat was not joined")
    call.toggleMute()
    call.toggleDeafen()
    try check(call.deafened && call.muted, "Deafen did not mute")
    call.toggleDeafen()
    try check(!call.deafened && call.muted, "Undeafen lost the earlier mute state")
    call.toggleMute()
    call.toggleDeafen()
    call.toggleDeafen()
    try check(!call.muted && !call.deafened, "Undeafen did not restore an unmuted microphone")
    call.receive(.init(type: "call_incoming", payload: ["conversation_id": .int(99), "invite_id": .string("busy-invite")]))
    try await waitUntil { commands.contains { $0["invite_id"] == .string("busy-invite") } }
    try check(call.room?.id == 42 && call.incoming == nil, "Busy invitation replaced the current call")
    call.receive(.init(type: "error", payload: ["rtc_kind": .string("call"), "rtc_id": .int(99), "error": .string("forbidden")]))
    try check(call.room?.id == 42, "Unrelated room error ended a call")
    call.connectionChanged(.reconnecting(1))
    call.connectionChanged(.connected)
    try await waitUntil { commands.last?["type"] == .string("call_join") }
    try check(call.room?.id == 42, "Reconnect lost the room")
    call.requestCamera = { try? await Task.sleep(for: .milliseconds(100)); return false }
    let cameraToggle = Task { await call.toggleVideo() }
    try await Task.sleep(for: .milliseconds(20))
    call.receive(.init(type: "access_revoked", payload: ["scope": .string("direct"), "conversation_id": .int(42)]))
    try check(call.room == nil && call.localVideo == nil && call.peers.isEmpty, "Revocation left capture or transports alive")
    call.reset()
    await cameraToggle.value
    try check(call.error == nil && !call.videoEnabled, "A stale camera permission result restored call state")

    // Real native SDP/ICE negotiation tests the WebRTC callback thread hops.
    RTCInitializeSSL()
    let factory = RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(), decoderFactory: RTCDefaultVideoDecoderFactory())
    let config = RTCConfiguration()
    config.sdpSemantics = .unifiedPlan
    config.iceServers = []
    let audioSource = factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
    let audio = factory.audioTrack(with: audioSource, trackId: "smoke-audio")
    audio.isEnabled = false
    let video = factory.videoTrack(with: factory.videoSource(), trackId: "smoke-video")
    video.isEnabled = false
    guard let higher = NativeCallPeer(userID: 7, offerer: true, factory: factory, configuration: config, audio: audio, video: video),
      let lower = NativeCallPeer(userID: 8, offerer: false, factory: factory, configuration: config, audio: audio, video: video) else { throw SmokeError.failed("Native peer creation failed") }
    var failures: [String] = []
    higher.onError = { failures.append($0) }
    lower.onError = { failures.append($0) }
    higher.sendSignal = { [weak lower] signal in lower?.enqueue(signal) }
    lower.sendSignal = { [weak higher] signal in higher?.enqueue(signal) }
    // Both sides asking at once must still produce only one offerer.
    lower.negotiate()
    higher.negotiate()
    try await waitUntil { higher.connection.remoteDescription != nil && lower.connection.remoteDescription != nil }
    try check(failures.isEmpty, "Native signaling failed: \(failures)")
    try check(higher.connection.localDescription?.type == .offer && lower.connection.localDescription?.type == .answer, "Offer roles diverged")
    try check(higher.connection.remoteDescription?.sdp.contains("m=audio") == true, "Native audio was not negotiated")
    try await waitUntil { higher.connected && lower.connected }
    lower.remoteAudioEnabled = false
    try check(lower.connection.receivers.compactMap { $0.track as? RTCAudioTrack }.allSatisfy { !$0.isEnabled }, "Deafen did not disable incoming audio")
    higher.close(); lower.close()
    higher.enqueue(["kind": .string("renegotiate")])
    try await Task.sleep(for: .milliseconds(50))
    try check(higher.connection.signalingState == .closed && lower.connection.signalingState == .closed, "Teardown left native transports open")
    print("Calling smoke passed: invitations, permission denial, startup cancellation, native SDP/ICE connection, deafen, and teardown.")
  }

  @MainActor private static func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<500 {
      if condition() { return }
      try await Task.sleep(for: .milliseconds(20))
    }
    throw SmokeError.failed("Timed out waiting for native calling")
  }
  private static func check(_ condition: Bool, _ message: String) throws {
    if !condition { throw SmokeError.failed(message) }
  }
  enum SmokeError: Error { case failed(String) }
}
