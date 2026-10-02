import Foundation
import Observation
import AVFoundation
@preconcurrency import WebRTC

@MainActor @Observable
final class CallController {
  typealias Kind = PWCallRoom.Kind
  struct Invitation {
    let id: PlainwireID
    let title: String
    let token: String?
  }
  @ObservationIgnored var send: (([String: JSONValue]) async throws -> Void)?
  @ObservationIgnored var loadConfiguration: (() async throws -> JSONValue)?
  @ObservationIgnored var requestMicrophone: () async -> Bool = { await AVCaptureDevice.requestAccess(for: .audio) }
  @ObservationIgnored var requestCamera: () async -> Bool = { await AVCaptureDevice.requestAccess(for: .video) }
  @ObservationIgnored private var relayRefreshSeconds = 240
  @ObservationIgnored private var startup: Task<Void, Never>?
  @ObservationIgnored private var deadline: Task<Void, Never>?
  @ObservationIgnored private var relayRefresh: Task<Void, Never>?
  @ObservationIgnored private var generation = 0
  @ObservationIgnored private var audio: RTCAudioTrack?
  @ObservationIgnored private var camera: RTCCameraVideoCapturer?
  @ObservationIgnored private var configuration = RTCConfiguration()
  @ObservationIgnored private var earlySignals: [PlainwireID: [[String: JSONValue]]] = [:]
  @ObservationIgnored private var action = "ring"
  @ObservationIgnored private var inviteToken: String?
  @ObservationIgnored private var awaitingReconnect = false
  @ObservationIgnored private var mutedBeforeDeafen = false
  @ObservationIgnored private var cameraChanging = false
  @ObservationIgnored private static let factory: RTCPeerConnectionFactory = {
    RTCInitializeSSL()
    return RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(), decoderFactory: RTCDefaultVideoDecoderFactory())
  }()

  private(set) var room: PWCallRoom?
  private(set) var incoming: Invitation?
  private(set) var title = ""
  private(set) var status = ""
  private(set) var joined = false
  private(set) var muted = false
  private(set) var deafened = false
  private(set) var videoEnabled = false
  private(set) var participants: [PWCallParticipant] = []
  private(set) var peers: [PlainwireID: NativeCallPeer] = [:]
  private(set) var localVideo: RTCVideoTrack?
  private(set) var startedAt: Date?
  var userID: PlainwireID = 0
  var error: String?
  var expanded = false
  var hasCall: Bool { room != nil || incoming != nil }
  var mediaConnected: Bool { peers.values.contains { $0.connected } }

  func start(kind: Kind, id: PlainwireID, title: String, userID: PlainwireID,
             accepting token: String? = nil, answer: Bool = false) {
    guard id > 0, userID > 0 else { return }
    guard room == nil else { expanded = true; error = "End your current call before starting another."; return }
    guard incoming == nil || answer else { error = "Answer or decline the incoming call first."; return }
    incoming = nil
    deadline?.cancel()
    self.userID = userID
    self.title = title
    room = PWCallRoom(kind: kind, id: id)
    action = kind == .voice ? "join" : answer ? "accept" : "ring"
    inviteToken = token
    error = nil
    status = "Preparing microphone…"
    expanded = true
    begin()
  }

  private func begin() {
    startup?.cancel()
    generation += 1
    let epoch = generation
    startup = Task { [weak self] in
      guard let self, let room = self.room else { return }
      do {
        if self.audio == nil {
          guard await self.requestMicrophone() else {
            throw PlainwireAPIError.transport("Allow microphone access in System Settings to join a call.")
          }
          guard self.generation == epoch, !Task.isCancelled else { return }
          #if os(iOS)
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try audioSession.setActive(true)
          #endif
          self.audio = Self.factory.audioTrack(with: Self.factory.audioSource(with:
            RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)), trackId: "plainwire-audio")
          let source = Self.factory.videoSource()
          self.camera = RTCCameraVideoCapturer(delegate: source)
          self.localVideo = Self.factory.videoTrack(with: source, trackId: "plainwire-video")
          self.localVideo?.isEnabled = false
          self.audio?.isEnabled = !self.muted
        }
        try await self.refreshConfiguration(epoch: epoch)
        guard self.generation == epoch, !Task.isCancelled else { return }
        var command = room.command(self.joined ? "join" : self.action)
        if self.action == "accept", let token = self.inviteToken { command["invite_id"] = .string(token) }
        self.status = self.joined ? "Reconnecting…" : self.action == "ring" ? "Calling…" : "Joining…"
        try await self.send?(command)
        guard self.generation == epoch, !Task.isCancelled else { return }
        if !self.joined || (room.kind == .direct && self.participants.count < 2) {
          self.setDeadline(seconds: self.action == "ring" ? 60 : 30, epoch: epoch)
        }
        self.relayRefresh?.cancel()
        self.relayRefresh = Task { [weak self] in
          while !Task.isCancelled {
            let delay = self?.relayRefreshSeconds ?? 240
            try? await Task.sleep(for: .seconds(delay))
            guard let self, self.generation == epoch, !Task.isCancelled else { return }
            do { try await self.refreshConfiguration(epoch: epoch) }
            catch { self.error = "Could not refresh the call relay. Reconnect if audio stops." }
          }
        }
      } catch {
        guard self.generation == epoch, !Task.isCancelled else { return }
        await self.finish(with: error.localizedDescription)
      }
    }
  }

  private func refreshConfiguration(epoch: Int) async throws {
    guard let value = try await loadConfiguration?(), let object = value.objectValue,
      let servers = object["iceServers"]?.arrayValue else { throw PlainwireAPIError.invalidResponse }
    guard generation == epoch, !Task.isCancelled else { return }
    let config = RTCConfiguration()
    config.sdpSemantics = .unifiedPlan
    config.bundlePolicy = .maxBundle
    config.continualGatheringPolicy = .gatherContinually
    config.iceTransportPolicy = object["iceTransportPolicy"]?.stringValue == "relay" ? .relay : .all
    config.iceServers = servers.compactMap { value in
      guard let server = value.objectValue else { return nil }
      let urls = server["urls"]?.arrayValue?.compactMap(\.stringValue) ?? server["urls"]?.stringValue.map { [$0] } ?? []
      guard !urls.isEmpty else { return nil }
      return RTCIceServer(urlStrings: urls, username: server["username"]?.stringValue,
        credential: server["credential"]?.stringValue)
    }
    let lifetime = object["turnTtlSeconds"]?.intValue ?? 3600
    let suggested = object["refreshAfterSeconds"]?.intValue ?? 240
    relayRefreshSeconds = Int(max(15, min(240, suggested, lifetime / 2)))
    configuration = config
    peers.values.forEach { _ = $0.connection.setConfiguration(config) }
  }

  private func setDeadline(seconds: Int, epoch: Int) {
    deadline?.cancel()
    deadline = Task { [weak self] in
      try? await Task.sleep(for: .seconds(seconds))
      guard let self, self.generation == epoch, !Task.isCancelled else { return }
      await self.finish(with: "The call did not connect. Please try again.")
    }
  }

  func answer() {
    guard let invitation = incoming else { return }
    start(kind: .direct, id: invitation.id, title: invitation.title, userID: userID,
      accepting: invitation.token, answer: true)
  }

  func decline() async {
    guard let invitation = incoming else { return }
    incoming = nil
    deadline?.cancel()
    var command = PWCallRoom(kind: .direct, id: invitation.id).command("decline")
    if let token = invitation.token { command["invite_id"] = .string(token) }
    try? await send?(command)
  }

  func receive(_ event: PlainwireRealtimeEvent, title: String? = nil) {
    if event.type == "call_incoming", let id = event.conversationID, id > 0 {
      if let room {
        if room.kind == .direct, room.id == id { return }
        // Preserve an existing call when a second caller rings.
        var command = PWCallRoom(kind: .direct, id: id).command("decline")
        if let token = event.payload["invite_id"]?.stringValue { command["invite_id"] = .string(token) }
        Task { try? await send?(command) }
        return
      }
      incoming = Invitation(id: id, title: title ?? event.payload["call_title"]?.stringValue
        ?? event.payload["display_name"]?.stringValue ?? "Incoming call", token: event.payload["invite_id"]?.stringValue)
      error = nil
      deadline?.cancel()
      deadline = Task { [weak self] in
        try? await Task.sleep(for: .seconds(60))
        guard !Task.isCancelled else { return }
        await self?.decline()
      }
      return
    }
    let ended = ["call_declined", "call_cancelled", "call_missed", "call_ended", "call_superseded", "voice_superseded", "call_ejected", "voice_ejected"]
    if let incoming, event.conversationID == incoming.id,
      ended.contains(event.type) || event.type == "call_accepted" {
      self.incoming = nil
      deadline?.cancel()
    }
    guard let room else { return }
    if room.accessRevoked(by: event) {
      reset()
      error = "Your access to this call changed."
      return
    }
    guard room.matches(event) else { return }
    if ended.contains(event.type) { reset(); return }
    if event.type == "error" {
      let messages = ["forbidden": "You cannot join this call.", "room_full": "This call is full.",
        "no_active_call": "This call has ended.", "no_peers": "There is nobody else to call.",
        "unavailable": "Calling is temporarily unavailable."]
      let message = messages[event.payload["error"]?.stringValue ?? ""] ?? "Could not join the call."
      let epoch = generation
      Task { [weak self] in
        guard let self, self.generation == epoch else { return }
        await self.finish(with: message)
      }
      return
    }
    if event.type == "call_ringing" { status = "Ringing…" }
    if event.type == "call_accepted" { status = "Connecting…"; action = "join"; inviteToken = nil }
    if event.type == "call_state" || event.type == "voice_state" {
      participants = (event.payload["users"]?.arrayValue ?? []).compactMap(PWCallParticipant.init)
      guard participants.contains(where: { $0.id == userID }) else { return }
      let firstJoin = !joined || awaitingReconnect
      joined = true
      awaitingReconnect = false
      status = room.kind == .voice ? "Voice channel" : participants.count > 1 ? "Connected" : "Waiting for others…"
      if participants.count > 1 || room.kind == .voice { deadline?.cancel() }
      if startedAt == nil, participants.count > 1 || room.kind == .voice { startedAt = Date() }
      let roster = Set(participants.filter { $0.id != userID && !$0.reconnecting }.map(\.id))
      for id in Array(peers.keys) where !roster.contains(id) { removePeer(id) }
      for id in roster {
        if let peer = ensurePeer(id), peer.connection.remoteDescription == nil {
          if peer.offerer { peer.negotiate() }
          else { signal(id, ["kind": .string("renegotiate")]) }
        }
      }
      if firstJoin { publishState() }
    }
    if event.type.hasSuffix("_peer_joined"), let id = event.userID, id != userID {
      removePeer(id)
      if let peer = ensurePeer(id), peer.offerer { peer.negotiate() }
    }
    if event.type.hasSuffix("_peer_left"), let id = event.userID {
      if id == userID { reset(); return }
      removePeer(id)
      participants.removeAll { $0.id == id }
    }
    if event.type.hasSuffix("_signal"), let signal = event.payload["signal"]?.objectValue,
      let id = event.payload["from_user_id"]?.intValue ?? event.userID, id > 0, id != userID {
      if let peer = peers[id] { peer.enqueue(signal) }
      else if ["offer", "renegotiate"].contains(signal["kind"]?.stringValue ?? ""), let peer = ensurePeer(id) { peer.enqueue(signal) }
      else if signal["kind"]?.stringValue == "candidate", earlySignals.count < 64, earlySignals[id, default: []].count < 128 {
        earlySignals[id, default: []].append(signal)
      }
    }
  }

  private func ensurePeer(_ id: PlainwireID) -> NativeCallPeer? {
    if let existing = peers[id] { return existing }
    guard let room, let audio, let video = localVideo,
      let peer = NativeCallPeer(userID: id, offerer: userID > id, factory: Self.factory,
        configuration: configuration, audio: audio, video: video) else { return nil }
    let epoch = generation
    peer.sendSignal = { [weak self, weak peer] signal in
      guard let self, let peer, self.generation == epoch, self.peers[id] === peer else { return }
      var payload = room.command("signal")
      payload["to_user_id"] = .int(id)
      payload["signal"] = .object(signal)
      try await self.send?(payload)
    }
    peer.onError = { [weak self] message in self?.error = message }
    peer.remoteAudioEnabled = !deafened
    peers[id] = peer
    for signal in earlySignals.removeValue(forKey: id) ?? [] { peer.enqueue(signal) }
    return peer
  }

  private func signal(_ id: PlainwireID, _ signal: [String: JSONValue]) {
    guard let room else { return }
    let epoch = generation
    var payload = room.command("signal")
    payload["to_user_id"] = .int(id)
    payload["signal"] = .object(signal)
    Task { [weak self] in
      guard let self, self.generation == epoch else { return }
      do { try await self.send?(payload) } catch { if self.generation == epoch { self.error = error.localizedDescription } }
    }
  }

  private func removePeer(_ id: PlainwireID) {
    peers.removeValue(forKey: id)?.close()
    earlySignals[id] = nil
  }

  func toggleMute() {
    guard !deafened else { return }
    muted.toggle()
    audio?.isEnabled = !muted
    publishState()
  }
  func toggleDeafen() {
    if deafened { deafened = false; muted = mutedBeforeDeafen }
    else { mutedBeforeDeafen = muted; deafened = true; muted = true }
    audio?.isEnabled = !muted
    peers.values.forEach { $0.remoteAudioEnabled = !deafened }
    publishState()
  }
  private func publishState() {
    guard joined, let room else { return }
    let epoch = generation
    var command = room.command("state")
    command["patch"] = .object(["muted": .bool(muted), "deafened": .bool(deafened), "screen": .bool(videoEnabled)])
    Task { [weak self] in
      guard let self, self.generation == epoch else { return }
      try? await self.send?(command)
    }
  }

  func toggleVideo() async {
    guard room != nil, !cameraChanging else { return }
    let epoch = generation
    cameraChanging = true
    defer { if generation == epoch { cameraChanging = false } }
    if videoEnabled {
      localVideo?.isEnabled = false
      videoEnabled = false
      await stopCamera()
    } else {
      let permitted = await requestCamera()
      guard generation == epoch else { return }
      guard permitted else {
        error = "Allow camera access in System Settings to share video."
        return
      }
      guard generation == epoch, let camera else { return }
      let devices = RTCCameraVideoCapturer.captureDevices()
      guard let device = devices.first(where: { $0.position == .front }) ?? devices.first,
        let format = RTCCameraVideoCapturer.supportedFormats(for: device).filter({
          CMVideoFormatDescriptionGetDimensions($0.formatDescription).width <= 1280
        }).max(by: { CMVideoFormatDescriptionGetDimensions($0.formatDescription).width < CMVideoFormatDescriptionGetDimensions($1.formatDescription).width }) else {
        error = "No supported camera is available."
        return
      }
      do {
        let fps = min(30, Int(format.videoSupportedFrameRateRanges.first?.maxFrameRate ?? 30))
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
          camera.startCapture(with: device, format: format, fps: fps) { @Sendable error in
            if let error { continuation.resume(throwing: error) } else { continuation.resume() }
          }
        }
        guard generation == epoch else { await camera.stopCapture(); return }
        localVideo?.isEnabled = true
        videoEnabled = true
      } catch { if generation == epoch { self.error = "Could not start the camera: \(error.localizedDescription)" } }
    }
    guard generation == epoch else { return }
    publishState()
  }
  private func stopCamera() async {
    guard let camera else { return }
    await withCheckedContinuation { continuation in camera.stopCapture { @Sendable in continuation.resume() } }
  }

  func connectionChanged(_ state: PlainwireRealtimeState) {
    guard room != nil else { return }
    if state != .connected {
      awaitingReconnect = true
      status = "Reconnecting…"
      peers.values.forEach { $0.close() }
      peers.removeAll()
      earlySignals.removeAll()
    } else if awaitingReconnect { begin() }
  }
  func reconnect() { guard room != nil else { return }; peers.values.forEach { $0.close() }; peers.removeAll(); awaitingReconnect = true; error = nil; begin() }

  private func finish(with message: String) async {
    let epoch = generation
    await end()
    guard generation == epoch + 1, !hasCall else { return }
    error = message
  }

  func end() async {
    var command = room?.command(room?.kind == .voice ? "leave" : joined ? "leave" : "cancel")
    if let invitation = incoming {
      command = PWCallRoom(kind: .direct, id: invitation.id).command("decline")
      if let token = invitation.token { command?["invite_id"] = .string(token) }
    }
    // Release capture synchronously before any socket await, so a new call
    // cannot be mistaken for the call that this hang-up is ending.
    reset()
    if let command { try? await send?(command) }
  }
  func reset() {
    generation += 1
    startup?.cancel(); startup = nil
    deadline?.cancel(); deadline = nil
    relayRefresh?.cancel(); relayRefresh = nil
    audio?.isEnabled = false
    audio = nil
    localVideo?.isEnabled = false
    camera?.stopCapture()
    camera = nil
    localVideo = nil
    peers.values.forEach { $0.close() }
    peers.removeAll()
    earlySignals.removeAll()
    room = nil; incoming = nil; participants = []
    error = nil
    joined = false; awaitingReconnect = false
    muted = false; deafened = false; mutedBeforeDeafen = false
    videoEnabled = false; cameraChanging = false
    startedAt = nil; inviteToken = nil; expanded = false
    #if os(iOS)
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    #endif
  }
}
