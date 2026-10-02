import Foundation

/// Presence comes from the current socket, never from a saved profile preference.
public struct PWPresence: Equatable, Sendable {
  private var statuses: [PlainwireID: String] = [:]
  private var platforms: [PlainwireID: String] = [:]
  private var watchedUsers: Set<PlainwireID> = []
  private var snapshotUsers: Set<PlainwireID> = []

  public init() {}

  public mutating func reset(keepingWatch: Bool = false) {
    statuses.removeAll()
    platforms.removeAll()
    snapshotUsers.removeAll()
    if !keepingWatch { watchedUsers.removeAll() }
  }

  public mutating func retainUsers(_ ids: Set<PlainwireID>) {
    watchedUsers = ids
    snapshotUsers.formIntersection(ids)
    statuses = statuses.filter { ids.contains($0.key) }
    platforms = platforms.filter { ids.contains($0.key) }
  }

  public mutating func apply(_ event: PlainwireRealtimeEvent) {
    switch event.type {
    case "presence_state":
      guard event.payload["statuses"]?.objectValue != nil || event.payload["online"]?.arrayValue != nil else { return }
      // A new watch snapshot replaces the previous one, including absent users.
      statuses = event.statuses.mapValues(Self.normalizedStatus)
      platforms = event.platforms.filter { Self.isPresent(statuses[$0.key]) }
      // The server omits offline users. Only a completed watch snapshot is
      // evidence that a missing user is offline; newly watched users still wait.
      snapshotUsers = watchedUsers
    case "presence_online", "presence_status":
      guard let id = event.userID else { return }
      // The online event itself is evidence; status events require a status.
      guard let status = event.status ?? (event.type == "presence_online" ? "online" : nil) else { return }
      statuses[id] = Self.normalizedStatus(status)
      platforms[id] = Self.isPresent(statuses[id]) ? event.platform : nil
    case "presence_offline":
      guard let id = event.userID else { return }
      statuses[id] = "offline"
      platforms[id] = nil
    default: break
    }
  }

  public func status(for id: PlainwireID) -> String? {
    statuses[id] ?? (snapshotUsers.contains(id) ? "offline" : nil)
  }
  public func platform(for id: PlainwireID) -> String? { platforms[id] }

  private static func normalizedStatus(_ status: String) -> String {
    let status = status.lowercased()
    return ["online", "away", "busy", "offline"].contains(status) ? status : "offline"
  }

  private static func isPresent(_ status: String?) -> Bool {
    status == "online" || status == "away" || status == "busy"
  }
}
