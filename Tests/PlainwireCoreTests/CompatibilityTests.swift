import Foundation
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PlainwireCore

@Test func emptyAndBlockedConversationPreviewsDecode() throws {
  // The LEFT JOIN in the reference backend returns last_body: null for empty
  // conversations and hides blocked previews the same way.
  let data = Data(#"{"id":12,"owner_id":4,"name":null,"avatar_url":null,"created_at":10,"updated_at":10,"last_body":null,"last_message_id":null,"peer_id":0,"peer_name":null,"peer_avatar_url":null,"peer_username":null}"#.utf8)
  let conversation = try JSONDecoder().decode(PWConversation.self, from: data)
  #expect(conversation.lastBody == "")
  #expect(conversation.peerName == "")
  #expect(conversation.unread == 0)
  #expect(conversation.requestState == "accepted")
  #expect(conversation.lastMessageId == nil)
}

@Test func nullableLegacyMetadataDoesNotBreakSync() throws {
  let data = Data(#"{"now":9,"since":0,"conversations":[{"id":12,"owner_id":4,"last_body":null}],"servers":[{"id":3,"owner_id":4,"name":"Server","description":null,"role":null,"permissions":null}],"friends":[{"user":{"id":4,"username":"alice","display_name":null,"bio":null,"avatar_url":null,"banner_url":null,"theme":null,"status":null}}]}"#.utf8)
  let snapshot = try JSONDecoder().decode(PWSyncSnapshot.self, from: data)
  #expect(snapshot.conversations.count == 1)
  #expect(snapshot.servers.first?.description == "")
  #expect(snapshot.friends.first?.user.theme == "system")
  #expect(snapshot.notifications.isEmpty)
  #expect(!snapshot.syncDegraded)
}

@Test func legacyServerAndGroupDetailsDecode() throws {
  let user = #"{"id":4,"username":"alice"}"#
  let group = "{\"conversation\":{\"id\":1,\"owner_id\":4},\"members\":[{\"user\":\(user)}]}"
  let conversation = try JSONDecoder().decode(PWConversationDetail.self, from: Data(group.utf8))
  #expect(conversation.members.first?.nickname == "")
  #expect(conversation.members.first?.groupRole == "member")
  let server = #"{"server":{"id":3,"owner_id":4},"channels":[{"id":9,"server_id":3,"name":"general","topic":null,"category_id":null}],"members":[],"categories":null}"#
  let detail = try JSONDecoder().decode(PWServerDetail.self, from: Data(server.utf8))
  #expect(detail.categories.isEmpty)
  #expect(detail.channels.first?.slowmodeSeconds == 0)
  #expect(detail.channels.first?.kind == "text")
}

@Test func messageMetadataIsOptionalButIdentityAndContentAreRequired() throws {
  let minimal = #"{"id":"9223372036854775806","scope":"direct","scope_id":"4","user_id":"7","body":"hello","created_at":9,"avatar_url":null,"role_color":null,"reactions":null}"#
  let message = try JSONDecoder().decode(PWMessage.self, from: Data(minimal.utf8))
  #expect(message.id == 9_223_372_036_854_775_806)
  #expect(message.scopeId == 4)
  #expect(message.reactions.isEmpty)
  #expect(message.kind == "text")
  #expect(!message.pinned)
  #expect(!message.isBot)
  for broken in [
    #"{"scope":"direct","scope_id":4,"user_id":7,"body":"hello"}"#,
    #"{"id":1,"scope":"direct","scope_id":4,"user_id":7,"body":null}"#,
    #"{"id":"9223372036854775808","scope":"direct","scope_id":4,"user_id":7,"body":"hello"}"#,
    #"{"id":1,"scope":"direct","scope_id":"wrong","user_id":7,"body":"hello"}"#,
  ] {
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(PWMessage.self, from: Data(broken.utf8)) }
  }
}

@Test func currentMessageExtrasAndContextDecode() throws {
  let message = #"{"id":9,"scope":"channel","scope_id":3,"user_id":4,"body":"hello","pinned":true,"is_bot":true,"forwarded_from":{"id":7,"user_id":4,"display_name":"Alice","body":"snapshot"}}"#
  let data = Data("{\"target_id\":9,\"scope\":\"channel\",\"scope_id\":3,\"messages\":[\(message)]}".utf8)
  let context = try JSONDecoder().decode(PWMessageContext.self, from: data)
  #expect(context.targetId == 9)
  #expect(context.messages.first?.pinned == true)
  #expect(context.messages.first?.isBot == true)
  #expect(context.messages.first?.forwardedFrom?.body == "snapshot")
}

private final class FixtureResponses: @unchecked Sendable {
  typealias Handler = @Sendable (URLRequest) -> (Int, String)
  private let lock = NSLock()
  private var handlers: [String: Handler] = [:]
  func insert(_ host: String, handler: @escaping Handler) { lock.withLock { handlers[host] = handler } }
  func remove(_ host: String) { _ = lock.withLock { handlers.removeValue(forKey: host) } }
  func response(for request: URLRequest) -> (Int, String) {
    let handler = lock.withLock { handlers[request.url?.host ?? ""] }
    return handler?(request) ?? (500, #"{"ok":false,"error":"fixture_missing"}"#)
  }
}

private final class FixtureURLProtocol: URLProtocol {
  static let responses = FixtureResponses()
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let (status, body) = Self.responses.response(for: request)
    let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

private func withFixture<T: Sendable>(
  _ handler: @escaping FixtureResponses.Handler,
  operation: (PlainwireAPIClient) async throws -> T
) async throws -> T {
  let host = "fixture-\(UUID().uuidString.lowercased()).example"
  FixtureURLProtocol.responses.insert(host, handler: handler)
  defer { FixtureURLProtocol.responses.remove(host) }
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [FixtureURLProtocol.self]
  configuration.httpCookieStorage = nil
  let session = URLSession(configuration: configuration)
  defer { session.invalidateAndCancel() }
  let client = PlainwireAPIClient(configuration: PlainwireConfiguration(baseURL: URL(string: "https://\(host)")!), session: session)
  return try await operation(client)
}

private let fixtureSession = #"{"ok":true,"data":{"user":{"id":4,"username":"alice"},"csrf":"fixture-csrf","server_time":9}}"#

@Test func successfulCommandsWithoutDataAreAcceptedAndCSRFIsSent() async throws {
  try await withFixture({ request in
    if request.url?.path == "/api/me" { return (200, fixtureSession) }
    #expect(request.value(forHTTPHeaderField: "X-CSRF-Token") == "fixture-csrf")
    #expect(request.httpMethod != "GET")
    return (200, #"{"ok":true}"#)
  }) { client in
    _ = try await client.restoreSession()
    try await client.revokeInvite(serverID: 3, code: "abc")
    try await client.markNotificationsSeen()
    try await client.clearNotifications()
    try await client.setPinned(messageID: 9, pinned: true)
    try await client.addConversationMembers(id: 12, userIDs: [7])
    try await client.conversationAction(id: 12, action: .accept)
    try await client.deleteMessage(id: 9)
    try await client.markConversationRead(12)
  }
}

@Test func emptyCommandResponsesAreAcceptedButMissingTypedDataIsRejected() async throws {
  try await withFixture({ request in
    if request.url?.path == "/api/me" { return (200, fixtureSession) }
    return (204, "")
  }) { client in
    _ = try await client.restoreSession()
    try await client.clearNotifications()
    await #expect(throws: PlainwireAPIError.invalidResponse) { try await client.server(id: 3) }
  }
}

@Test func wrongPasswordIsNotReportedAsExpiredSession() async throws {
  try await withFixture({ request in
    request.url?.path == "/api/me" ? (200, fixtureSession) : (401, #"{"ok":false,"error":"bad_password"}"#)
  }) { client in
    _ = try await client.restoreSession()
    await #expect(throws: PlainwireAPIError.server(status: 401, code: "bad_password", message: nil)) {
      try await client.changePassword(current: "wrong", new: "example-password")
    }
  }
}

@Test func loginErrorsAndSessionExpirationRemainDistinct() async throws {
  try await withFixture({ request in
    request.url?.path == "/api/login"
      ? (401, #"{"ok":false,"error":"invalid_credentials"}"#)
      : (401, #"{"ok":false,"error":"not_authenticated"}"#)
  }) { client in
    await #expect(throws: PlainwireAPIError.server(status: 401, code: "invalid_credentials", message: nil)) {
      try await client.login(username: "alice", password: "incorrect")
    }
    await #expect(throws: PlainwireAPIError.notAuthenticated) { try await client.restoreSession() }
  }
}

@Test func malformedResponseReportsEndpointAndField() async throws {
  try await withFixture({ _ in (200, #"{"ok":true,"data":{"user":{"username":"alice"},"csrf":"x","server_time":9}}"#) }) { client in
    do {
      _ = try await client.restoreSession()
      Issue.record("Missing user identity must fail")
    } catch let error as PlainwireAPIError {
      guard case .decoding(let detail) = error else { Issue.record("Expected decoding error"); return }
      #expect(detail == "me: data.user.id")
    }
  }
}

@Test func failedCommandsNeverBecomeSuccess() async throws {
  try await withFixture({ request in
    if request.url?.path == "/api/me" { return (200, fixtureSession) }
    return (403, #"{"ok":false,"error":"forbidden"}"#)
  }) { client in
    _ = try await client.restoreSession()
    await #expect(throws: PlainwireAPIError.server(status: 403, code: "forbidden", message: nil)) {
      try await client.revokeInvite(serverID: 3, code: "abc")
    }
  }
}

@Test func searchAndContextEndpointsUseReferencePaths() async throws {
  try await withFixture({ request in
    let path = request.url?.path
    if path == "/api/search/messages" {
      let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
      #expect(query?.first(where: { $0.name == "q" })?.value == "hello & world")
      #expect(query?.first(where: { $0.name == "before" })?.value == "91")
      return (200, #"{"ok":true,"data":{"messages":[],"query":"hello & world","index":{"complete":false}}}"#)
    }
    #expect(path == "/api/message/9/context")
    return (200, #"{"ok":true,"data":{"target_id":9,"scope":"channel","scope_id":3,"messages":[]}}"#)
  }) { client in
    let search = try await client.searchMessages("hello & world", before: 91)
    #expect(!search.indexingComplete)
    let context = try await client.messageContext(id: 9)
    #expect(context.targetId == 9)
  }
}


@Test func arbitraryJSONNumbersCannotTrapOrTruncateIdentifiers() {
  #expect(JSONValue.double(.infinity).intValue == nil)
  #expect(JSONValue.double(.nan).intValue == nil)
  #expect(JSONValue.double(1e100).intValue == nil)
  #expect(JSONValue.double(1.5).intValue == nil)
  #expect(JSONValue.double(42).intValue == 42)
}

@Test func fencedCodePreservesWhitespaceAndUnclosedBlocks() {
  let blocks = PWMessageText.blocks("Before\n```swift\n  let x = 1\n\nprint(x)\n```\nAfter")
  #expect(blocks.count == 3)
  #expect(blocks[1].kind == .code(language: "swift"))
  #expect(blocks[1].text == "  let x = 1\n\nprint(x)")
  let unclosed = PWMessageText.blocks("```\nsecret")
  #expect(unclosed.first?.kind == .code(language: ""))
  #expect(unclosed.first?.text == "secret")
}

@Test func spoilerCodeIsRedactedBeforeRendering() {
  let source = "Public ||```\nsecret\n```|| end"
  let redacted = PWMessageText.redactingSpoilers(source)
  #expect(redacted == "Public [Spoiler] end")
  #expect(!PWMessageText.blocks(redacted).contains { $0.text.contains("secret") })
}

@Test func mixedAttachmentsKeepOrderAndUnicodeText() {
  let parsed = PWMessageText.parseBody("👋 hello ![photo](/api/files/a.png) [document.pdf](/api/files/b) [clip.mov](/api/files/c)")
  #expect(parsed.text == "👋 hello")
  #expect(parsed.attachments.map(\.name) == ["photo", "document.pdf", "clip.mov"])
  #expect(parsed.attachments.map(\.kind) == [.image, .file, .video])
}

@Test func imagesInsideSpoilerSentencesRemainHidden() {
  let parsed = PWMessageText.parseBody("Visible ||secret ![image](/api/files/a.png) text||")
  #expect(parsed.attachments.count == 1)
  #expect(parsed.attachments.first?.isSpoiler == true)
  #expect(PWMessageText.redactingSpoilers(parsed.text) == "Visible [Spoiler]")
  let isolated = PWMessageText.parseBody("||![image](/api/files/a.png)||")
  #expect(isolated.text.isEmpty)
  #expect(isolated.attachments.first?.isSpoiler == true)
}

@Test func attachmentsWrittenInCodeStayLiteral() {
  let body = "```markdown\n![image](/api/files/a.png)\n```\n`![inline](/api/files/b.png)`"
  let parsed = PWMessageText.parseBody(body)
  #expect(parsed.attachments.isEmpty)
  #expect(parsed.text == body)
}

@Test func voiceNotesAndOrdinaryLinksStayDistinct() {
  let parsed = PWMessageText.parseBody("[Voice note.m4a](/api/files/a#plainwire-voice-note) [site](https://example.com)")
  #expect(parsed.attachments.first?.kind == .voice)
  #expect(parsed.text == "[site](https://example.com)")
}
