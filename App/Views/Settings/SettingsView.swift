import SwiftUI
import UserNotifications

#if os(iOS)
  import UIKit
#endif

struct SettingsView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.openURL) private var openURL
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage(AppPreferenceKeys.sendTypingIndicators) private var sendTypingIndicators = true
  @AppStorage(AppPreferenceKeys.notificationPreviews) private var notificationPreviews = true
  @AppStorage(AppPreferenceKeys.notificationSounds) private var notificationSounds = true
  @AppStorage(AppPreferenceKeys.reduceInterfaceMotion) private var reduceInterfaceMotion = false
  @AppStorage(AppPreferenceKeys.compactMessages) private var compactMessages = false
  @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

  var showNavigationTitle = true
  var detailPresentation = false

  var body: some View {
    ZStack {
      AppBackdrop()
      ScrollView {
        VStack(spacing: 18) {
          if let user = model.session?.user { ProfileSettingsHeader(user: user) }
          responsiveSettings
        }
        .frame(maxWidth: detailPresentation ? 900 : 820)
        .padding(.horizontal, detailPresentation ? 24 : 18)
        .padding(.top, 18)
        .padding(.bottom, 36)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.automatic)
    }
    .modifier(OptionalNavigationTitle(enabled: showNavigationTitle, title: "You"))
    .task { await refreshNotificationStatus() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { await refreshNotificationStatus() } }
    }
  }

  @ViewBuilder private var responsiveSettings: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .top, spacing: 18) {
        VStack(spacing: 18) {
          chatCard
          notificationsCard
        }
        .frame(minWidth: 290, maxWidth: .infinity, alignment: .top)

        VStack(spacing: 18) {
          connectionCard
          aboutCard
          accountCard
        }
        .frame(minWidth: 290, maxWidth: .infinity, alignment: .top)
      }

      VStack(spacing: 18) {
        chatCard
        notificationsCard
        connectionCard
        aboutCard
        accountCard
      }
    }
  }

  private var chatCard: some View {
    SettingsCard(
      title: "Chat", symbol: "bubble.left.and.text.bubble.right",
      subtitle: "Typing, spacing, and motion."
    ) {
      SettingsToggleRow(
        title: "Typing indicators", detail: "Let people know while you are composing a message.",
        isOn: $sendTypingIndicators)
      SettingsDivider()
      SettingsToggleRow(
        title: "Compact messages", detail: "Reduce vertical spacing in busy conversations.",
        isOn: $compactMessages)
      SettingsDivider()
      SettingsToggleRow(
        title: "Reduce interface motion",
        detail: "Use simpler transitions in addition to system Reduce Motion.",
        isOn: $reduceInterfaceMotion)
    }
  }

  private var notificationsCard: some View {
    SettingsCard(
      title: "Notifications", symbol: "bell.badge",
      subtitle: "Choose how new messages appear."
    ) {
      SettingsToggleRow(
        title: "Message previews", detail: "Include message text in local notification banners.",
        isOn: $notificationPreviews)
      SettingsDivider()
      SettingsToggleRow(
        title: "Sounds", detail: "Play the system notification sound for new messages.",
        isOn: $notificationSounds)
      SettingsDivider()
      if notificationStatus == .authorized || notificationStatus == .provisional {
        SettingsValueRow(title: "System alerts", value: "Enabled", symbol: "checkmark.circle.fill")
      } else if notificationStatus == .denied {
        SettingsActionRow(
          title: "System alerts", detail: "Notifications are off in System Settings.",
          symbol: "bell.slash", actionTitle: "Settings"
        ) {
          openNotificationSettings()
        }
      } else {
        SettingsActionRow(
          title: "System alerts", detail: "Allow alerts and badges for new messages.",
          symbol: "bell.badge.fill", actionTitle: "Enable"
        ) {
          Task {
            await NotificationCoordinator.shared.requestAuthorization()
            await refreshNotificationStatus()
          }
        }
      }
    }
  }

  private var connectionCard: some View {
    SettingsCard(
      title: "Connection", symbol: "network",
      subtitle: "Messages sync with plainwi.re."
    ) {
      SettingsValueRow(title: "Server", value: "plainwi.re", symbol: "lock.shield")
      SettingsDivider()
      SettingsValueRow(title: "Realtime", value: realtimeLabel, symbol: realtimeSymbol)
      if let date = model.lastSyncAt {
        SettingsDivider()
        SettingsValueRow(
          title: "Last sync", value: date.formatted(date: .omitted, time: .standard),
          symbol: "arrow.triangle.2.circlepath")
      }
      SettingsDivider()
      SettingsActionRow(
        title: "Sync now", detail: "Refresh conversations, servers, friends, and account state.",
        symbol: "arrow.clockwise", actionTitle: "Sync"
      ) {
        Task { await model.refresh() }
      }
    }
  }

  private var aboutCard: some View {
    SettingsCard(
      title: "About", symbol: "info.circle",
      subtitle: "Plainwire for iPhone, iPad, and Mac."
    ) {
      SettingsValueRow(
        title: "Version", value: PlainwireClientInfo.version, symbol: "number")
      SettingsDivider()
      SettingsActionRow(
        title: "Website", detail: "plainwi.re", symbol: "globe", actionTitle: "Open"
      ) {
        if let url = URL(string: "https://plainwi.re") { openURL(url) }
      }
    }
  }

  private var accountCard: some View {
    SettingsCard(
      title: "Account", symbol: "person.crop.circle",
      subtitle: "Signing out removes the active Plainwire session from this app."
    ) {
      Button(role: .destructive) {
        Task { await model.logout() }
      } label: {
        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
          .frame(maxWidth: .infinity)
      }
      .adaptiveGlassButton()
      .tint(.red)
      .controlSize(.large)
    }
  }

  private var realtimeLabel: String {
    switch model.realtimeState {
    case .stopped: "Idle"
    case .connecting: "Connecting"
    case .connected: "Connected"
    case .reconnecting: "Reconnecting"
    case .failed: "Offline"
    }
  }

  private var realtimeSymbol: String {
    switch model.realtimeState {
    case .connected: "bolt.horizontal.circle.fill"
    case .connecting, .reconnecting: "arrow.triangle.2.circlepath.circle"
    case .failed: "wifi.exclamationmark"
    case .stopped: "pause.circle"
    }
  }

  private func refreshNotificationStatus() async {
    notificationStatus = await NotificationCoordinator.shared.authorizationStatus()
  }

  private func openNotificationSettings() {
    #if os(iOS)
      let address = UIApplication.openSettingsURLString
    #else
      let address = "x-apple.systempreferences:com.apple.preference.notifications"
    #endif
    if let url = URL(string: address) { openURL(url) }
  }
}

private struct ProfileSettingsHeader: View {
  @Environment(AppModel.self) private var model
  let user: PWUser

  var body: some View {
    HStack(spacing: 16) {
      RemoteAvatar(
        url: model.mediaURL(user.avatarURL), fallback: String(user.displayName.prefix(1)), size: 64)
      VStack(alignment: .leading, spacing: 4) {
        Text(user.displayName)
          .font(.title2.weight(.bold))
          .lineLimit(1)
        Text("@\(user.username)")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        if !user.status.isEmpty {
          Text(user.status)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }
      Spacer(minLength: 12)
      ConnectionMiniPill()
    }
    .padding(18)
    .settingsSurface(cornerRadius: 24)
  }
}

private struct ConnectionMiniPill: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    HStack(spacing: 6) {
      Circle().fill(color).frame(width: 7, height: 7)
      Text(label).font(.caption.weight(.medium))
    }
    .foregroundStyle(.secondary)
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .adaptiveGlass(cornerRadius: 14)
    .accessibilityElement(children: .combine)
  }

  private var color: Color { model.realtimeState == .connected ? .green : .orange }
  private var label: String { model.realtimeState == .connected ? "Connected" : "Connecting" }
}

private struct SettingsCard<Content: View>: View {
  let title: String
  let symbol: String
  let subtitle: String
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: symbol)
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(Color.accentColor)
          .frame(width: 30, height: 30)
          .background(
            Color.accentColor.opacity(0.11),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        VStack(alignment: .leading, spacing: 3) {
          Text(title).font(.headline)
          Text(subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(
            horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
      }
      .padding(.bottom, 15)

      content()
    }
    .padding(17)
    .settingsSurface(cornerRadius: 22)
  }
}

private struct SettingsToggleRow: View {
  let title: String
  let detail: String
  @Binding var isOn: Bool

  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.subheadline.weight(.medium))
        Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(
          horizontal: false, vertical: true)
      }
      Spacer(minLength: 12)
      Toggle(title, isOn: $isOn)
        .labelsHidden()
        .adaptiveGlassToggle()
        .fixedSize()
    }
    .padding(.vertical, 7)
  }
}

private struct SettingsValueRow: View {
  let title: String
  let value: String
  let symbol: String

  var body: some View {
    HStack(spacing: 11) {
      Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 20)
      Text(title).font(.subheadline)
      Spacer(minLength: 12)
      Text(value)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
    }
    .padding(.vertical, 7)
  }
}

private struct SettingsActionRow: View {
  let title: String
  let detail: String
  let symbol: String
  let actionTitle: String
  let action: () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 14) {
      Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 20)
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.subheadline.weight(.medium))
        Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(
          horizontal: false, vertical: true)
      }
      Spacer(minLength: 12)
      Button(actionTitle, action: action)
        .adaptiveGlassButton()
        .controlSize(.small)
    }
    .padding(.vertical, 7)
  }
}

private struct SettingsDivider: View {
  var body: some View { Divider().opacity(0.45).padding(.vertical, 4) }
}

extension View {
  fileprivate func settingsSurface(cornerRadius: CGFloat) -> some View {
    self
      .background(
        .regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .stroke(.primary.opacity(0.075), lineWidth: 0.5)
      }
  }
}

private struct OptionalNavigationTitle: ViewModifier {
  let enabled: Bool
  let title: String

  @ViewBuilder func body(content: Content) -> some View {
    if enabled { content.navigationTitle(title) } else { content }
  }
}
