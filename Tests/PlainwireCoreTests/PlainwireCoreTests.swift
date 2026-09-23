import Foundation
import Testing

@testable import PlainwireCore

@Test func apiURLPreservesBasePathAndEncodesQuery() throws {
  let config = PlainwireConfiguration(baseURL: URL(string: "https://example.test/plainwire")!)
  let url = try config.apiURL(
    "messages",
    query: [
      URLQueryItem(name: "scope", value: "direct"), URLQueryItem(name: "scope_id", value: "42"),
    ])
  #expect(
    url.absoluteString == "https://example.test/plainwire/api/messages?scope=direct&scope_id=42")
  #expect(config.websocketURL.absoluteString == "wss://example.test/plainwire/ws")
}

@Test func messageDecodingMatchesBackendWireShape() throws {
  let json = """
    {"id":91,"scope":"direct","scope_id":4,"user_id":7,"username":"robert","display_name":"Robert","avatar_url":"/api/media/a","body":"hello","reply_to_id":null,"created_at":10,"edited_at":null,"deleted_at":null,"kind":"text","role_color":"#99aab5","reactions":[{"emoji":"👍","count":2,"me":true}]}
    """
  let message = try JSONDecoder().decode(PWMessage.self, from: Data(json.utf8))
  #expect(message.id == 91)
  #expect(message.scopeId == 4)
  #expect(message.reactions.first?.count == 2)
  #expect(message.replyToId == nil)
}

@Test func syncSnapshotDecoding() throws {
  let json =
    #"{"now":1000,"since":0,"notifications":[],"conversations":[{"id":1,"name":"","avatar_url":"","owner_id":1,"created_at":1,"updated_at":2,"last_read_message_id":0,"muted":false,"request_state":"accepted","group_role":"member","member_count":2,"last_body":"hey","last_message_id":9,"unread":1,"last_sender_id":2,"last_sender_name":"A","last_sender_username":"a","peer_id":2,"peer_name":"A","peer_avatar_url":"","peer_username":"a"}],"servers":[],"friends":[],"sync_degraded":false,"sync_warnings":[]}"#
  let snapshot = try JSONDecoder().decode(PWSyncSnapshot.self, from: Data(json.utf8))
  #expect(snapshot.conversations.count == 1)
  #expect(snapshot.conversations[0].unread == 1)
  #expect(snapshot.syncDegraded == false)
}

@Test func realtimeEventDecodesNestedMessage() throws {
  let text = """
    {"type":"message_created","scope":"channel","scope_id":22,"message":{"id":100,"scope":"channel","scope_id":22,"user_id":7,"username":"robert","display_name":"Robert","avatar_url":"","body":"yo","reply_to_id":null,"created_at":10,"edited_at":null,"deleted_at":null,"kind":"text","role_color":"#fff","reactions":[]}}
    """
  let value = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
  let object = try #require(value.objectValue)
  let type = try #require(object["type"]?.stringValue)
  let event = PlainwireRealtimeEvent(type: type, payload: object)
  #expect(event.scope == "channel")
  #expect(event.scopeID == 22)
  #expect(event.message?.body == "yo")
}

@Test func typingEventAccessorsMatchBackendWireShape() throws {
  let text =
    #"{"type":"typing","scope":"direct","scope_id":44,"user_id":7,"username":"robert","display_name":"Robert","avatar_url":"","active":true,"ts":1234}"#
  let value = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
  let object = try #require(value.objectValue)
  let event = PlainwireRealtimeEvent(type: "typing", payload: object)
  #expect(event.scope == "direct")
  #expect(event.scopeID == 44)
  #expect(event.userID == 7)
  #expect(event.displayName == "Robert")
  #expect(event.active == true)
}

@Test func mediaURLRejectsUnsafeSchemes() {
  let config = PlainwireConfiguration(baseURL: URL(string: "https://plainwire.example")!)
  #expect(
    config.mediaURL("/api/files/12")?.absoluteString == "https://plainwire.example/api/files/12")
  #expect(config.mediaURL("https://cdn.example/avatar.png")?.scheme == "https")
  #expect(config.mediaURL("file:///etc/passwd") == nil)
  #expect(config.mediaURL("javascript:alert(1)") == nil)
}

@Test func presenceStateAccessorsMatchBackendWireShape() throws {
  let text = #"{"type":"presence_state","statuses":{"7":"online","9":"away"}}"#
  let value = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
  let object = try #require(value.objectValue)
  let event = PlainwireRealtimeEvent(type: "presence_state", payload: object)
  #expect(event.statuses[7] == "online")
  #expect(event.statuses[9] == "away")
}

@Test func mediaURLRejectsCredentialsAndExternalPlaintextHTTP() {
  let config = PlainwireConfiguration(baseURL: URL(string: "https://plainwire.example")!)
  #expect(config.mediaURL("https://user:pass@cdn.example/avatar.png") == nil)
  #expect(config.mediaURL("http://cdn.example/avatar.png") == nil)
  #expect(config.mediaURL("http://127.0.0.1:8080/avatar.png")?.scheme == "http")
}

@Test func reactionEventAccessorsMatchBackendWireShape() throws {
  let text =
    #"{"type":"message_reaction_changed","message_id":91,"emoji":"🔥","count":3,"added":true,"user_id":7}"#
  let value = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
  let object = try #require(value.objectValue)
  let event = PlainwireRealtimeEvent(type: "message_reaction_changed", payload: object)
  #expect(event.messageID == 91)
  #expect(event.emoji == "🔥")
  #expect(event.reactionCount == 3)
  #expect(event.reactionAdded == true)
  #expect(event.userID == 7)
}

@Test func accountAndInvitePayloadsDecodeFromBackend() throws {
  let sessions = #"[{"id":31,"current":true,"created_at":1000,"last_seen":2000,"expires_at":3000}]"#
  let decodedSessions = try JSONDecoder().decode([PWAccountSession].self, from: Data(sessions.utf8))
  #expect(decodedSessions.first?.current == true)
  #expect(decodedSessions.first?.lastSeen == 2000)

  let invite = #"{"code":"abc-123","expires_at":3000,"max_uses":0}"#
  let decodedInvite = try JSONDecoder().decode(PWInvite.self, from: Data(invite.utf8))
  #expect(decodedInvite.code == "abc-123")
  #expect(decodedInvite.channelId == nil)

  let profile = #"{"user":{"id":7,"username":"robert","display_name":"Robert","bio":"Hello","avatar_url":"","banner_url":"","status":"online","theme":"system","created_at":1000,"last_seen":2000},"relationship":{"status":"none"}}"#
  let decodedProfile = try JSONDecoder().decode(PWProfile.self, from: Data(profile.utf8))
  #expect(decodedProfile.user.email == nil)
  #expect(decodedProfile.user.displayName == "Robert")
}
