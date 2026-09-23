import Foundation
import UserNotifications

#if os(iOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

@MainActor
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
  static let shared = NotificationCoordinator()

  private var configured = false
  private var openHandler: ((URL) -> Void)?
  private var notifiedMessageIDs = Set<PlainwireID>()

  func configure(openHandler: @escaping (URL) -> Void) {
    self.openHandler = openHandler
    guard !configured else { return }
    configured = true
    UNUserNotificationCenter.current().delegate = self
  }

  func requestAuthorization() async {
    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [
      .alert, .badge, .sound,
    ])
  }

  func authorizationStatus() async -> UNAuthorizationStatus {
    await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
  }

  func notifyMessage(_ message: PWMessage, roomTitle: String?, selectedRoom: String?) {
    let messageRoom = "\(message.scope):\(message.scopeId)"
    guard message.userId > 0,
      !(applicationIsActive && selectedRoom == messageRoom)
    else { return }
    guard notifiedMessageIDs.insert(message.id).inserted else { return }
    if notifiedMessageIDs.count > 512 { notifiedMessageIDs = [message.id] }

    let defaults = UserDefaults.standard
    let showsPreview = defaults.bool(forKey: AppPreferenceKeys.notificationPreviews)
    let playsSound = defaults.bool(forKey: AppPreferenceKeys.notificationSounds)

    let content = UNMutableNotificationContent()
    content.title = roomTitle ?? message.displayName
    content.subtitle = roomTitle == nil ? "" : message.displayName
    content.body = showsPreview ? previewText(for: message) : "New message"
    content.sound = playsSound ? .default : nil
    content.threadIdentifier = messageRoom
    content.userInfo = ["scope": message.scope, "scope_id": message.scopeId]

    UNUserNotificationCenter.current().add(
      UNNotificationRequest(
        identifier: "message-\(message.id)",
        content: content,
        trigger: nil))
  }

  func updateBadgeCount(_ count: Int) {
    Task {
      try? await UNUserNotificationCenter.current().setBadgeCount(count)
    }
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    let playsSound = UserDefaults.standard.bool(forKey: AppPreferenceKeys.notificationSounds)
    return playsSound ? [.banner, .sound] : [.banner]
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    let info = response.notification.request.content.userInfo
    guard let scope = info["scope"] as? String else { return }

    let id: Int64?
    if let value = info["scope_id"] as? Int64 {
      id = value
    } else if let value = info["scope_id"] as? Int {
      id = Int64(value)
    } else if let value = info["scope_id"] as? NSNumber {
      id = value.int64Value
    } else {
      id = nil
    }
    guard let id, id > 0 else { return }

    let route = scope == "direct" ? "dm" : "channel"
    guard let url = URL(string: "plainwire://\(route)/\(id)") else { return }
    await MainActor.run { NotificationCoordinator.shared.openHandler?(url) }
  }

  private func previewText(for message: PWMessage) -> String {
    let value = message.body
      .replacingOccurrences(
        of: #"(?s)\|\|.*?\|\|"#, with: "Spoiler",
        options: .regularExpression)
      .replacingOccurrences(
        of: #"data:image/[A-Za-z0-9.+-]+;base64,[A-Za-z0-9+/=\r\n]{32,}"#,
        with: "Photo",
        options: [.regularExpression, .caseInsensitive]
      )
      .replacingOccurrences(
        of: #"!\[[^\]]*\]\([^\)]+\)"#, with: "Photo", options: .regularExpression
      )
      .replacingOccurrences(
        of: #"\[[^\]]+\]\([^\)]+\)"#, with: "Attachment", options: .regularExpression
      )
      .replacingOccurrences(of: #"[\r\n\t ]+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? "New message" : String(value.prefix(180))
  }

  private var applicationIsActive: Bool {
    #if os(iOS)
      UIApplication.shared.applicationState == .active
    #elseif os(macOS)
      NSApp.isActive
    #else
      true
    #endif
  }
}
