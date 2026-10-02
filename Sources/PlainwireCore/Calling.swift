import Foundation

/// The room identity accompanies every server event. Never apply a late event
/// from a previous room to the current call.
public struct PWCallRoom: Hashable, Sendable {
  public enum Kind: String, Sendable { case direct = "call", voice }
  public let kind: Kind
  public let id: PlainwireID
  public init(kind: Kind, id: PlainwireID) { self.kind = kind; self.id = id }
  public var idKey: String { kind == .voice ? "channel_id" : "conversation_id" }
  public func command(_ action: String) -> [String: JSONValue] {
    ["type": .string("\(kind.rawValue)_\(action)"), idKey: .int(id)]
  }
  public func matches(_ event: PlainwireRealtimeEvent) -> Bool {
    if event.type == "error" {
      return event.payload["rtc_kind"]?.stringValue == kind.rawValue
        && event.payload["rtc_id"]?.intValue == id
    }
    return event.type.hasPrefix("\(kind.rawValue)_") && event.payload[idKey]?.intValue == id
  }
  public func accessRevoked(by event: PlainwireRealtimeEvent) -> Bool {
    guard event.type == "access_revoked" else { return false }
    if kind == .direct { return event.scope == "direct" && event.conversationID == id }
    return event.scope == "server" && (event.payload["channel_ids"]?.arrayValue ?? []).contains { $0.intValue == id }
  }
}

public struct PWCallParticipant: Identifiable, Hashable, Sendable {
  public let id: PlainwireID
  public let name: String
  public let muted: Bool
  public let deafened: Bool
  public let reconnecting: Bool
  public let sharingVideo: Bool
  public init?(_ value: JSONValue) {
    guard let object = value.objectValue else { return nil }
    let profile = object["profile"]?.objectValue ?? [:]
    guard let id = object["user_id"]?.intValue ?? object["userId"]?.intValue ?? profile["id"]?.intValue, id > 0 else { return nil }
    self.id = id
    name = profile["display_name"]?.stringValue ?? object["display_name"]?.stringValue
      ?? profile["username"]?.stringValue ?? object["username"]?.stringValue ?? "Participant"
    muted = object["muted"]?.boolValue ?? false
    deafened = object["deafened"]?.boolValue ?? false
    reconnecting = object["reconnecting"]?.boolValue ?? false
    sharingVideo = object["screen"]?.boolValue ?? object["video"]?.boolValue ?? false
  }
}
