import Foundation
import Observation
@preconcurrency import WebRTC

/// A single native DTLS/SRTP transport. WebRTC callbacks arrive on its worker
/// threads; only the explicit delegate hops below touch observable UI state.
@MainActor @Observable
final class NativeCallPeer: NSObject {
  let userID: PlainwireID
  let offerer: Bool
  @ObservationIgnored let connection: RTCPeerConnection
  @ObservationIgnored private var work: Task<Void, Never>?
  @ObservationIgnored private var pendingCandidates: [RTCIceCandidate] = []
  @ObservationIgnored private var localCandidates: [RTCIceCandidate] = []
  @ObservationIgnored private var descriptionSent = false
  @ObservationIgnored private var closed = false
  @ObservationIgnored var sendSignal: (([String: JSONValue]) async throws -> Void)?
  @ObservationIgnored var onError: ((String) -> Void)?
  var remoteVideo: RTCVideoTrack?
  var connected = false
  var failed = false
  var remoteAudioEnabled = true {
    didSet { (connection.receivers.compactMap { $0.track as? RTCAudioTrack }).forEach { $0.isEnabled = remoteAudioEnabled } }
  }

  init?(userID: PlainwireID, offerer: Bool, factory: RTCPeerConnectionFactory,
        configuration: RTCConfiguration, audio: RTCAudioTrack, video: RTCVideoTrack) {
    guard let connection = factory.peerConnection(with: configuration,
      constraints: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil), delegate: nil) else { return nil }
    self.userID = userID
    self.offerer = offerer
    self.connection = connection
    super.init()
    connection.delegate = self
    connection.add(audio, streamIds: ["plainwire"])
    connection.add(video, streamIds: ["plainwire"])
  }

  func enqueue(_ signal: [String: JSONValue]) {
    let previous = work
    work = Task { [weak self] in
      await previous?.value
      guard let self, !self.closed, !Task.isCancelled else { return }
      do { try await self.apply(signal) }
      catch { if !self.closed, !Task.isCancelled { self.failed = true; self.onError?("Could not connect call media. Try reconnecting.") } }
    }
  }

  func negotiate(restart: Bool = false) {
    enqueue(["kind": .string("renegotiate"), "restart": .bool(restart)])
  }

  private func apply(_ signal: [String: JSONValue]) async throws {
    switch signal["kind"]?.stringValue {
    case "renegotiate":
      guard offerer, connection.signalingState == .stable else { return }
      descriptionSent = false
      let constraints = RTCMediaConstraints(mandatoryConstraints: signal["restart"]?.boolValue == true ? ["IceRestart": "true"] : nil, optionalConstraints: nil)
      let description: RTCSessionDescription = try await withCheckedThrowingContinuation { continuation in
        connection.offer(for: constraints) { @Sendable description, error in
          if let description { continuation.resume(returning: description) }
          else { continuation.resume(throwing: error ?? PlainwireAPIError.invalidResponse) }
        }
      }
      guard !closed else { return }
      try await publish(description, kind: "offer")
    case "offer", "answer":
      guard let object = signal["sdp"]?.objectValue, let sdp = object["sdp"]?.stringValue,
        let type = object["type"]?.stringValue, ["offer", "answer"].contains(type) else { return }
      if type == "offer", offerer { return }
      if type == "answer", connection.signalingState != .haveLocalOffer { return }
      if type == "offer", connection.signalingState != .stable { return }
      let remote = RTCSessionDescription(type: type == "offer" ? .offer : .answer, sdp: sdp)
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        connection.setRemoteDescription(remote) { @Sendable error in
          if let error { continuation.resume(throwing: error) } else { continuation.resume() }
        }
      }
      guard !closed else { return }
      for candidate in pendingCandidates { try await add(candidate) }
      pendingCandidates.removeAll()
      updateRemoteTracks()
      if type == "offer" {
        descriptionSent = false
        let answer: RTCSessionDescription = try await withCheckedThrowingContinuation { continuation in
          connection.answer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)) { @Sendable answer, error in
            if let answer { continuation.resume(returning: answer) }
            else { continuation.resume(throwing: error ?? PlainwireAPIError.invalidResponse) }
          }
        }
        guard !closed else { return }
        try await publish(answer, kind: "answer")
      }
    case "candidate":
      guard let object = signal["candidate"]?.objectValue,
        let sdp = object["candidate"]?.stringValue,
        let index = object["sdpMLineIndex"]?.intValue, let checkedIndex = Int32(exactly: index) else { return }
      let candidate = RTCIceCandidate(sdp: sdp, sdpMLineIndex: checkedIndex, sdpMid: object["sdpMid"]?.stringValue)
      if connection.remoteDescription != nil { try await add(candidate) }
      else if pendingCandidates.count < 128 { pendingCandidates.append(candidate) }
    default: break
    }
  }

  private func add(_ candidate: RTCIceCandidate) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      connection.add(candidate) { @Sendable error in
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
      }
    }
  }

  private func publish(_ description: RTCSessionDescription, kind: String) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      connection.setLocalDescription(description) { @Sendable error in
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
      }
    }
    guard !closed else { return }
    try await sendSignal?(["kind": .string(kind), "sdp": .object(["type": .string(kind), "sdp": .string(description.sdp)])])
    guard !closed else { return }
    descriptionSent = true
    let candidates = localCandidates
    localCandidates.removeAll()
    for candidate in candidates { try await sendCandidate(candidate) }
  }

  private func sendCandidate(_ candidate: RTCIceCandidate) async throws {
    guard !closed else { return }
    try await sendSignal?(["kind": .string("candidate"), "candidate": .object([
      "candidate": .string(candidate.sdp), "sdpMLineIndex": .int(Int64(candidate.sdpMLineIndex)),
      "sdpMid": candidate.sdpMid.map(JSONValue.string) ?? .null,
    ])])
  }

  private func updateRemoteTracks() {
    remoteVideo = connection.receivers.compactMap { $0.track as? RTCVideoTrack }.first
    connection.receivers.compactMap { $0.track as? RTCAudioTrack }.forEach { $0.isEnabled = remoteAudioEnabled }
  }

  func close() {
    closed = true
    work?.cancel()
    work = nil
    pendingCandidates.removeAll()
    localCandidates.removeAll()
    connection.delegate = nil
    connection.close()
    remoteVideo = nil
    connected = false
  }
}

extension NativeCallPeer: RTCPeerConnectionDelegate {
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
  nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
    Task { @MainActor [weak self] in
      guard let self, !self.closed else { return }
      self.connected = newState == .connected || newState == .completed
      self.failed = newState == .failed
      self.updateRemoteTracks()
      if newState == .failed {
        self.onError?("Call audio disconnected. Reconnect to try again.")
        if self.offerer { self.negotiate(restart: true) }
        else { try? await self.sendSignal?(["kind": .string("renegotiate")]) }
      }
    }
  }
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
    Task { @MainActor [weak self] in
      guard let self, !self.closed else { return }
      if self.descriptionSent { try? await self.sendCandidate(candidate) }
      else if self.localCandidates.count < 128 { self.localCandidates.append(candidate) }
    }
  }
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams: [RTCMediaStream]) {
    Task { @MainActor [weak self] in
      guard let self, !self.closed else { return }
      self.updateRemoteTracks()
    }
  }
}
