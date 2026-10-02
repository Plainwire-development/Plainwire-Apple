import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Keeps a floating call panel reachable after dragging, resizing, or rotating.
public struct PWCallPanelLayout: Equatable, Sendable {
  public let size: CGSize
  public let origin: CGPoint

  public init(container: CGSize, preferredSize: CGSize, origin: CGPoint? = nil) {
    let width = container.width.isFinite ? max(1, container.width) : 1
    let height = container.height.isFinite ? max(1, container.height) : 1
    let inset: CGFloat = min(12, max(0, (min(width, height) - 1) / 2))
    let availableWidth = max(1, width - inset * 2)
    let availableHeight = max(1, height - inset * 2)
    size = CGSize(width: min(availableWidth, max(320, preferredSize.width.isFinite ? preferredSize.width : 480)),
      height: min(availableHeight, max(100, preferredSize.height.isFinite ? preferredSize.height : 380)))
    let maximumX = max(inset, width - size.width - inset)
    let maximumY = max(inset, height - size.height - inset)
    let requested = origin ?? CGPoint(x: maximumX, y: maximumY)
    self.origin = CGPoint(x: min(maximumX, max(inset, requested.x.isFinite ? requested.x : maximumX)),
      y: min(maximumY, max(inset, requested.y.isFinite ? requested.y : maximumY)))
  }
}

/// One fixed anchor per pointer interaction. A moving view must not become the
/// coordinate space for the next event, or the panel will chase the pointer.
public struct PWCallPanelInteraction: Sendable {
  public enum Kind: Sendable { case move, resize }
  public let anchor: PWCallPanelLayout
  public let kind: Kind
  public init(anchor: PWCallPanelLayout, kind: Kind) { self.anchor = anchor; self.kind = kind }
  public func layout(translation: CGSize, container: CGSize) -> PWCallPanelLayout {
    switch kind {
    case .move:
      return PWCallPanelLayout(container: container, preferredSize: anchor.size,
        origin: CGPoint(x: anchor.origin.x + translation.width, y: anchor.origin.y + translation.height))
    case .resize:
      return PWCallPanelLayout(container: container,
        preferredSize: CGSize(width: anchor.size.width + translation.width, height: max(280, anchor.size.height + translation.height)),
        origin: anchor.origin)
    }
  }
}

public struct PWCallPresenceSnapshot: Hashable, Sendable {
  public let conversationID: PlainwireID
  public let active: Bool
  public let participants: [PWCallParticipant]
  public init?(_ event: PlainwireRealtimeEvent) {
    guard event.type == "call_presence", let id = event.conversationID, id > 0,
      let active = event.active else { return nil }
    if active && event.payload["users"]?.arrayValue == nil { return nil }
    conversationID = id
    self.active = active
    participants = PWCallParticipant.roster(event.payload["users"]?.arrayValue ?? [])
  }
}

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
  public static func roster(_ values: [JSONValue]) -> [Self] {
    var seen = Set<PlainwireID>()
    return values.compactMap(Self.init).filter { seen.insert($0.id).inserted }
  }
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
