import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public actor PlainwireAPIClient {
  public static let defaultUploadLimit: Int64 = 262_144_000

  private let configuration: PlainwireConfiguration
  private let session: URLSession
  private var csrfToken: String?

  public init(
    configuration: PlainwireConfiguration = PlainwireConfiguration(), session: URLSession? = nil
  ) {
    self.configuration = configuration
    if let session {
      self.session = session
    } else {
      let config = URLSessionConfiguration.default
      config.timeoutIntervalForRequest = 30
      config.timeoutIntervalForResource = 120
      #if !canImport(FoundationNetworking)
        config.waitsForConnectivity = true
      #endif
      config.httpCookieAcceptPolicy = .always
      config.httpCookieStorage = .shared
      config.urlCache = URLCache(
        memoryCapacity: 16 * 1024 * 1024, diskCapacity: 96 * 1024 * 1024, diskPath: nil)
      config.requestCachePolicy = .useProtocolCachePolicy
      config.httpAdditionalHeaders = [
        "Accept": "application/json", "User-Agent": PlainwireClientInfo.userAgent,
      ]
      self.session = URLSession(configuration: config)
    }
  }

  public func currentCSRFToken() -> String? { csrfToken }

  @discardableResult
  public func restoreSession() async throws -> PWSession {
    let session: PWSession = try await get("me")
    csrfToken = session.csrf
    return session
  }

  @discardableResult
  public func login(username: String, password: String) async throws -> PWSession {
    let body = LoginRequest(username: username, password: password)
    let result: PWSession = try await request(
      method: "POST", path: "login", body: body, requiresCSRF: false)
    csrfToken = result.csrf
    return result
  }

  @discardableResult
  public func register(username: String, displayName: String, password: String) async throws
    -> PWSession
  {
    let body = RegisterRequest(username: username, displayName: displayName, password: password)
    let result: PWSession = try await request(
      method: "POST", path: "register", body: body, requiresCSRF: false)
    csrfToken = result.csrf
    return result
  }

  public func logout() async throws {
    let _: EmptyPayload? = try await requestAllowingEmpty(
      method: "POST", path: "logout", body: Optional<EmptyPayload>.none, requiresCSRF: true)
    csrfToken = nil
  }

  public func sync(since: Int64? = nil) async throws -> PWSyncSnapshot {
    var query: [URLQueryItem] = []
    if let since { query.append(URLQueryItem(name: "since", value: String(since))) }
    return try await get("sync", query: query)
  }

  public func conversations() async throws -> [PWConversation] { try await get("conversations") }
  public func friends() async throws -> [PWFriend] { try await get("friends") }
  public func servers() async throws -> [PWServer] { try await get("servers") }
  public func conversation(id: PlainwireID) async throws -> PWConversationDetail {
    try await get("conversation/\(id)")
  }
  public func createConversation(userIDs: [PlainwireID], name: String = "") async throws
    -> PWCreatedConversation
  {
    try await request(
      method: "POST", path: "conversations",
      body: CreateConversationRequest(name: name, userIds: userIDs))
  }
  public func server(id: PlainwireID) async throws -> PWServerDetail {
    try await get("server/\(id)")
  }
  public func rtcConfiguration() async throws -> PWRTCConfiguration { try await get("rtc-config") }

  public func messages(
    scope: String, id: PlainwireID, before: PlainwireID? = nil, after: PlainwireID? = nil
  ) async throws -> [PWMessage] {
    var query = [
      URLQueryItem(name: "scope", value: scope), URLQueryItem(name: "scope_id", value: String(id)),
    ]
    if let before { query.append(URLQueryItem(name: "before", value: String(before))) }
    if let after { query.append(URLQueryItem(name: "after", value: String(after))) }
    return try await get("messages", query: query)
  }

  public func sendMessage(scope: String, id: PlainwireID, body: String, replyTo: PlainwireID? = nil)
    async throws -> PWMessage
  {
    let payload = MessageRequest(body: body, replyToId: replyTo)
    switch scope {
    case "direct":
      return try await request(method: "POST", path: "conversation/\(id)/messages", body: payload)
    case "channel":
      return try await request(method: "POST", path: "channels/\(id)/messages", body: payload)
    default:
      throw PlainwireAPIError.server(status: 400, code: "unsupported_message_scope", message: nil)
    }
  }

  public func markConversationRead(_ id: PlainwireID) async throws {
    let _: EmptyPayload? = try await requestAllowingEmpty(
      method: "POST", path: "conversation/\(id)/read", body: Optional<EmptyPayload>.none)
  }

  public func editMessage(id: PlainwireID, body: String) async throws -> PWMessage {
    try await request(
      method: "POST", path: "edit_message/\(id)", body: EditMessageRequest(body: body))
  }

  public func deleteMessage(id: PlainwireID) async throws {
    let _: EmptyPayload? = try await requestAllowingEmpty(
      method: "POST", path: "delete_message/\(id)", body: Optional<EmptyPayload>.none)
  }

  public func toggleReaction(messageID: PlainwireID, emoji: String) async throws -> PWReactionChange
  {
    try await request(
      method: "POST", path: "message/\(messageID)/reactions", body: ReactionRequest(emoji: emoji))
  }

  public func searchUsers(_ query: String) async throws -> [PWUser] {
    try await get("users", query: [URLQueryItem(name: "q", value: query)])
  }

  public func requestFriend(userID: PlainwireID) async throws {
    let _: EmptyPayload? = try await requestAllowingEmpty(
      method: "POST", path: "friends/request", body: UserIDRequest(userId: userID))
  }

  public func acceptFriend(userID: PlainwireID) async throws {
    let _: EmptyPayload? = try await requestAllowingEmpty(
      method: "POST", path: "friends/accept", body: UserIDRequest(userId: userID))
  }

  public func removeFriend(userID: PlainwireID) async throws {
    let _: EmptyPayload? = try await requestAllowingEmpty(
      method: "POST", path: "friends/remove", body: UserIDRequest(userId: userID))
  }

  public func upload(
    fileURL: URL, contentType: String = "application/octet-stream",
    maxBytes: Int64 = defaultUploadLimit
  ) async throws -> PWUpload {
    let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .nameKey, .isRegularFileKey])
    guard values.isRegularFile == true, let sizeValue = values.fileSize else {
      throw PlainwireAPIError.invalidFile
    }
    let size = Int64(sizeValue)
    guard size <= maxBytes else { throw PlainwireAPIError.uploadTooLarge(size) }
    guard let csrfToken else { throw PlainwireAPIError.notAuthenticated }

    var request = URLRequest(url: try configuration.apiURL("uploads"))
    request.httpMethod = "POST"
    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    request.setValue(
      Self.percentEncodedFilename(values.name ?? fileURL.lastPathComponent),
      forHTTPHeaderField: "X-File-Name")
    request.setValue(String(size), forHTTPHeaderField: "Content-Length")
    request.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-Token")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    do {
      let (data, response) = try await session.upload(for: request, fromFile: fileURL)
      return try decodeEnvelope(PWUpload.self, data: data, response: response)
    } catch let error as PlainwireAPIError {
      throw error
    } catch {
      throw PlainwireAPIError.transport(error.localizedDescription)
    }
  }

  public func resolveMediaURL(_ value: String) -> URL? { configuration.mediaURL(value) }

  private static func percentEncodedFilename(_ value: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "file"
  }

  private func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = []) async throws
    -> T
  {
    try await request(
      method: "GET", path: path, query: query, body: Optional<EmptyPayload>.none,
      requiresCSRF: false)
  }

  private func request<T: Decodable & Sendable, Body: Encodable & Sendable>(
    method: String, path: String, query: [URLQueryItem] = [], body: Body?, requiresCSRF: Bool = true
  ) async throws -> T {
    guard
      let value: T = try await requestAllowingEmpty(
        method: method, path: path, query: query, body: body, requiresCSRF: requiresCSRF)
    else {
      throw PlainwireAPIError.invalidResponse
    }
    return value
  }

  private func requestAllowingEmpty<T: Decodable & Sendable, Body: Encodable & Sendable>(
    method: String, path: String, query: [URLQueryItem] = [], body: Body?, requiresCSRF: Bool = true
  ) async throws -> T? {
    var request = URLRequest(url: try configuration.apiURL(path, query: query))
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if method != "GET", requiresCSRF {
      guard let csrfToken else { throw PlainwireAPIError.notAuthenticated }
      request.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-Token")
    }
    if let body {
      request.httpBody = try JSONEncoder.plainwire.encode(body)
      request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
    }

    do {
      let (data, response) = try await session.data(for: request)
      let http = try validatedHTTP(response)
      if http.statusCode == 401 { throw PlainwireAPIError.notAuthenticated }
      if (200..<300).contains(http.statusCode) {
        if data.isEmpty { return nil }
        if T.self == EmptyPayload.self,
          let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          raw["ok"] as? Bool == true, raw["data"] == nil
        {
          return EmptyPayload() as? T
        }
        return try decodeEnvelopeOptional(T.self, data: data, response: response)
      }
      throw decodeServerError(data: data, status: http.statusCode)
    } catch let error as PlainwireAPIError {
      throw error
    } catch let error as DecodingError {
      throw PlainwireAPIError.decoding(String(describing: error))
    } catch {
      throw PlainwireAPIError.transport(error.localizedDescription)
    }
  }

  private func decodeEnvelope<T: Decodable>(_ type: T.Type, data: Data, response: URLResponse)
    throws -> T
  {
    guard let value = try decodeEnvelopeOptional(type, data: data, response: response) else {
      throw PlainwireAPIError.invalidResponse
    }
    return value
  }

  private func decodeEnvelopeOptional<T: Decodable>(
    _ type: T.Type, data: Data, response: URLResponse
  ) throws -> T? {
    let http = try validatedHTTP(response)
    guard (200..<300).contains(http.statusCode) else {
      throw decodeServerError(data: data, status: http.statusCode)
    }
    let envelope = try JSONDecoder.plainwire.decode(APIEnvelope<T>.self, from: data)
    guard envelope.ok else {
      throw PlainwireAPIError.server(
        status: http.statusCode, code: envelope.error ?? "unknown_error", message: envelope.message)
    }
    return envelope.data
  }

  private func validatedHTTP(_ response: URLResponse) throws -> HTTPURLResponse {
    guard let http = response as? HTTPURLResponse else { throw PlainwireAPIError.invalidResponse }
    return http
  }

  private func decodeServerError(data: Data, status: Int) -> PlainwireAPIError {
    if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
      let code =
        object["error"] as? String ?? object["code"] as? String
        ?? HTTPURLResponse.localizedString(forStatusCode: status)
      let message = object["message"] as? String
      return .server(status: status, code: code, message: message)
    }
    return .server(
      status: status, code: HTTPURLResponse.localizedString(forStatusCode: status), message: nil)
  }
}

extension JSONEncoder {
  fileprivate static var plainwire: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    return encoder
  }
}

extension JSONDecoder {
  fileprivate static var plainwire: JSONDecoder { JSONDecoder() }
}

private struct LoginRequest: Encodable, Sendable {
  let username: String
  let password: String
}
private struct RegisterRequest: Encodable, Sendable {
  let username: String
  let displayName: String
  let password: String
  enum CodingKeys: String, CodingKey {
    case username, password
    case displayName = "display_name"
  }
}
private struct MessageRequest: Encodable, Sendable {
  let body: String
  let replyToId: PlainwireID?
  enum CodingKeys: String, CodingKey {
    case body
    case replyToId = "reply_to_id"
  }
}
private struct EditMessageRequest: Encodable, Sendable { let body: String }
private struct ReactionRequest: Encodable, Sendable { let emoji: String }
private struct CreateConversationRequest: Encodable, Sendable {
  let name: String
  let userIds: [PlainwireID]
  enum CodingKeys: String, CodingKey {
    case name
    case userIds = "user_ids"
  }
}
private struct UserIDRequest: Encodable, Sendable {
  let userId: PlainwireID
  enum CodingKeys: String, CodingKey { case userId = "user_id" }
}
