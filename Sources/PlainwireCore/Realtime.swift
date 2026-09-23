import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public enum PlainwireRealtimeState: Equatable, Sendable {
  case stopped
  case connecting
  case connected
  case reconnecting(Int)
  case failed(String)
}

public struct PlainwireRealtimeEvent: Sendable, Hashable {
  public let type: String
  public let payload: [String: JSONValue]

  public init(type: String, payload: [String: JSONValue]) {
    self.type = type
    self.payload = payload
  }

  public var message: PWMessage? { decode("message", as: PWMessage.self) }
  public var session: PWSession? { decode("session", as: PWSession.self) }
  public var scope: String? { payload["scope"]?.stringValue }
  public var scopeID: PlainwireID? { payload["scope_id"]?.intValue }
  public var conversationID: PlainwireID? { payload["conversation_id"]?.intValue }
  public var channelID: PlainwireID? { payload["channel_id"]?.intValue }
  public var messageID: PlainwireID? { payload["message_id"]?.intValue ?? message?.id }
  public var userID: PlainwireID? { payload["user_id"]?.intValue }
  public var emoji: String? { payload["emoji"]?.stringValue }
  public var reactionCount: Int? { payload["count"]?.intValue.map { Int($0) } }
  public var reactionAdded: Bool? { payload["added"]?.boolValue }
  public var displayName: String? { payload["display_name"]?.stringValue }
  public var username: String? { payload["username"]?.stringValue }
  public var active: Bool? { payload["active"]?.boolValue }
  public var status: String? { payload["status"]?.stringValue }
  public var platform: String? {
    payload["client_platform"]?.stringValue ?? payload["platform"]?.stringValue
  }
  public var statuses: [PlainwireID: String] {
    guard let object = payload["statuses"]?.objectValue else { return [:] }
    var result: [PlainwireID: String] = [:]
    result.reserveCapacity(object.count)
    for (key, value) in object {
      if let id = Int64(key), let status = value.stringValue { result[id] = status }
    }
    return result
  }
  public var platforms: [PlainwireID: String] {
    guard let object = payload["platforms"]?.objectValue else { return [:] }
    var result: [PlainwireID: String] = [:]
    for (key, value) in object {
      if let id = Int64(key), let platform = value.stringValue { result[id] = platform }
    }
    return result
  }

  public func decode<T: Decodable>(_ key: String, as type: T.Type) -> T? {
    guard let value = payload[key], let data = try? JSONEncoder().encode(value) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }
}

public actor PlainwireRealtimeClient {
  private let configuration: PlainwireConfiguration
  private let session: URLSession
  private var webSocket: URLSessionWebSocketTask?
  private var receiveTask: Task<Void, Never>?
  private var reconnectTask: Task<Void, Never>?
  private var heartbeatTask: Task<Void, Never>?
  private var shouldRun = false
  private var attempt = 0
  private var desiredSubscriptions = Set<String>()
  private var desiredPresence = Set<PlainwireID>()

  private var eventContinuations: [UUID: AsyncStream<PlainwireRealtimeEvent>.Continuation] = [:]
  private var stateContinuations: [UUID: AsyncStream<PlainwireRealtimeState>.Continuation] = [:]
  private(set) public var state: PlainwireRealtimeState = .stopped

  public init(
    configuration: PlainwireConfiguration = PlainwireConfiguration(), session: URLSession? = nil
  ) {
    self.configuration = configuration
    if let session {
      self.session = session
    } else {
      let config = URLSessionConfiguration.default
      config.httpCookieStorage = .shared
      config.httpCookieAcceptPolicy = .always
      config.timeoutIntervalForRequest = 30
      config.timeoutIntervalForResource = 300
      config.httpAdditionalHeaders = ["User-Agent": PlainwireClientInfo.userAgent]
      self.session = URLSession(configuration: config)
    }
  }

  public func events() -> AsyncStream<PlainwireRealtimeEvent> {
    AsyncStream(bufferingPolicy: .bufferingNewest(512)) { continuation in
      let id = UUID()
      eventContinuations[id] = continuation
      continuation.onTermination = { [weak self] _ in
        Task { await self?.removeEventContinuation(id) }
      }
    }
  }

  public func states() -> AsyncStream<PlainwireRealtimeState> {
    AsyncStream(bufferingPolicy: .bufferingNewest(16)) { continuation in
      let id = UUID()
      stateContinuations[id] = continuation
      continuation.yield(state)
      continuation.onTermination = { [weak self] _ in
        Task { await self?.removeStateContinuation(id) }
      }
    }
  }

  public func start() {
    guard !shouldRun else { return }
    shouldRun = true
    attempt = 0
    connect()
  }

  public func stop() {
    shouldRun = false
    reconnectTask?.cancel()
    reconnectTask = nil
    heartbeatTask?.cancel()
    heartbeatTask = nil
    receiveTask?.cancel()
    receiveTask = nil
    webSocket?.cancel(with: .goingAway, reason: nil)
    webSocket = nil
    setState(.stopped)
  }

  public func subscribe(_ key: String) async {
    guard isValidSubscription(key) else { return }
    desiredSubscriptions.insert(key)
    if state == .connected {
      try? await sendObject(["type": .string("subscribe"), "key": .string(key)])
    }
  }

  public func setSubscriptions(_ keys: Set<String>) async {
    desiredSubscriptions = Set(keys.filter(isValidSubscription))
    guard state == .connected else { return }
    try? await sendObject(["type": .string("unsubscribe_all")])
    for key in desiredSubscriptions.sorted() {
      try? await sendObject(["type": .string("subscribe"), "key": .string(key)])
    }
  }

  public func unsubscribeAll() async {
    desiredSubscriptions.removeAll()
    if state == .connected { try? await sendObject(["type": .string("unsubscribe_all")]) }
  }

  public func watchPresence(_ userIDs: [PlainwireID]) async {
    desiredPresence = Set(userIDs.filter { $0 > 0 }.prefix(2_000))
    if state == .connected { await sendPresenceWatch() }
  }

  public func sendTyping(scope: String, id: PlainwireID, active: Bool) async {
    guard ["direct", "channel", "thread"].contains(scope), id > 0, state == .connected else {
      return
    }
    try? await sendObject([
      "type": .string("typing"), "scope": .string(scope), "scope_id": .int(id),
      "active": .bool(active),
    ])
  }

  public func send(_ payload: [String: JSONValue]) async throws {
    try await sendObject(payload)
  }

  private func connect() {
    guard shouldRun, webSocket == nil else { return }
    setState(attempt == 0 ? .connecting : .reconnecting(attempt))

    var request = URLRequest(url: configuration.websocketURL)
    request.timeoutInterval = 30
    request.setValue(configuration.originHeader, forHTTPHeaderField: "Origin")
    request.setValue(PlainwireClientInfo.userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue(PlainwireClientInfo.platform, forHTTPHeaderField: "X-Plainwire-Client-Platform")
    let socket = session.webSocketTask(with: request)
    webSocket = socket
    socket.resume()

    receiveTask?.cancel()
    receiveTask = Task { [weak self] in await self?.receiveLoop(socket) }
  }

  private func receiveLoop(_ socket: URLSessionWebSocketTask) async {
    while shouldRun, webSocket === socket, !Task.isCancelled {
      do {
        let message = try await socket.receive()
        let data: Data
        switch message {
        case .string(let text): data = Data(text.utf8)
        case .data(let value): data = value
        @unknown default: continue
        }
        guard let object = try JSONDecoder().decode(JSONValue.self, from: data).objectValue,
          let type = object["type"]?.stringValue
        else { continue }
        if type == "hello" {
          attempt = 0
          setState(.connected)
          startHeartbeat()
          await restoreDesiredState()
        }
        broadcast(PlainwireRealtimeEvent(type: type, payload: object))
      } catch {
        if shouldRun, webSocket === socket { scheduleReconnect(reason: error.localizedDescription) }
        return
      }
    }
  }

  private func scheduleReconnect(reason: String) {
    receiveTask?.cancel()
    receiveTask = nil
    webSocket?.cancel(with: .goingAway, reason: nil)
    webSocket = nil
    guard shouldRun else {
      setState(.stopped)
      return
    }
    attempt = min(attempt + 1, 10)
    setState(.reconnecting(attempt))
    reconnectTask?.cancel()
    let delay = min(pow(1.7, Double(attempt - 1)), 20.0) + Double.random(in: 0...0.7)
    reconnectTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(delay))
      guard !Task.isCancelled else { return }
      await self?.connectAfterDelay()
    }
    if attempt >= 10 { setState(.failed(reason)) }
  }

  private func connectAfterDelay() { if shouldRun { connect() } }

  private func startHeartbeat() {
    heartbeatTask?.cancel()
    heartbeatTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(45))
        guard !Task.isCancelled, let self else { return }
        do { try await self.sendObject(["type": .string("ping")]) } catch { return }
      }
    }
  }

  private func restoreDesiredState() async {
    for key in desiredSubscriptions.sorted() {
      try? await sendObject(["type": .string("subscribe"), "key": .string(key)])
    }
    await sendPresenceWatch()
  }

  private func sendPresenceWatch() async {
    guard !desiredPresence.isEmpty else { return }
    let ids = desiredPresence.sorted().map(JSONValue.int)
    try? await sendObject(["type": .string("presence_watch"), "user_ids": .array(ids)])
  }

  private func sendObject(_ object: [String: JSONValue]) async throws {
    guard let socket = webSocket, state == .connected else {
      throw PlainwireAPIError.transport("Realtime connection is offline.")
    }
    let data = try JSONEncoder().encode(JSONValue.object(object))
    guard let text = String(data: data, encoding: .utf8) else {
      throw PlainwireAPIError.invalidResponse
    }
    do { try await socket.send(.string(text)) } catch {
      scheduleReconnect(reason: error.localizedDescription)
      throw PlainwireAPIError.transport(error.localizedDescription)
    }
  }

  private func isValidSubscription(_ value: String) -> Bool {
    guard value.utf8.count <= 128 else { return false }
    let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
    guard parts.count == 2, ["direct", "channel", "thread", "forum", "server"].contains(parts[0]),
      Int64(parts[1]) != nil
    else { return false }
    return true
  }

  private func setState(_ newValue: PlainwireRealtimeState) {
    state = newValue
    for continuation in stateContinuations.values { continuation.yield(newValue) }
  }

  private func broadcast(_ event: PlainwireRealtimeEvent) {
    for continuation in eventContinuations.values { continuation.yield(event) }
  }

  private func removeEventContinuation(_ id: UUID) { eventContinuations.removeValue(forKey: id) }
  private func removeStateContinuation(_ id: UUID) { stateContinuations.removeValue(forKey: id) }
}
