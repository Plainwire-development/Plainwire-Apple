import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

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
  @State private var activeSheet: SettingsSheet?

  private enum SettingsSheet: String, Identifiable {
    case profile, account
    var id: String { rawValue }
  }

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
    .sheet(item: $activeSheet) { sheet in
      switch sheet {
      case .profile:
        if let user = model.session?.user { ProfileEditorSheet(user: user) }
      case .account:
        AccountSecuritySheet()
      }
    }
  }

  @ViewBuilder private var responsiveSettings: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .top, spacing: 18) {
        VStack(spacing: 18) {
          profileCard
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
        profileCard
        chatCard
        notificationsCard
        connectionCard
        aboutCard
        accountCard
      }
    }
  }

  private var profileCard: some View {
    SettingsCard(title: "Profile", symbol: "person.crop.circle", subtitle: "Your public identity on Plainwire.") {
      SettingsActionRow(
        title: "Edit profile", detail: "Name, bio, status, avatar, and banner.",
        symbol: "person.crop.circle.badge.checkmark", actionTitle: "Edit"
      ) { activeSheet = .profile }
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
      title: "Account", symbol: "lock.shield",
      subtitle: "Manage your identity and signed-in sessions."
    ) {
      SettingsActionRow(
        title: "Security and sessions", detail: "Username, email, password, and active sessions.",
        symbol: "key.horizontal", actionTitle: "Manage"
      ) { activeSheet = .account }
      SettingsDivider()
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

private struct ProfileEditorSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var displayName: String
  @State private var bio: String
  @State private var status: String
  @State private var avatarURL: String
  @State private var bannerURL: String
  @State private var theme: String
  @State private var pickingImage = false
  @State private var imageField: String = "avatar"
  @State private var saving = false

  init(user: PWUser) {
    _displayName = State(initialValue: user.displayName)
    _bio = State(initialValue: user.bio)
    _status = State(initialValue: user.status)
    _avatarURL = State(initialValue: user.avatarURL)
    _bannerURL = State(initialValue: user.bannerURL)
    _theme = State(initialValue: user.theme)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Identity") {
          TextField("Display name", text: $displayName)
            .textContentType(.name)
          TextField("Status", text: $status)
          TextField("Bio", text: $bio, axis: .vertical).lineLimit(3...7)
        }
        Section("Images") {
          HStack {
            RemoteAvatar(url: model.mediaURL(avatarURL), fallback: String(displayName.prefix(1)), size: 56)
            Spacer()
            Button("Choose avatar") { imageField = "avatar"; pickingImage = true }
          }
          if let url = model.mediaURL(bannerURL) {
            AsyncImage(url: url) { image in
              image.resizable().scaledToFill()
            } placeholder: { Color.secondary.opacity(0.12) }
            .frame(height: 110).clipped().cornerRadius(12)
          }
          Button("Choose banner") { imageField = "banner"; pickingImage = true }
          Button("Remove avatar", role: .destructive) { avatarURL = "" }
          Button("Remove banner", role: .destructive) { bannerURL = "" }
        }
        Section("Appearance") {
          Picker("Theme", selection: $theme) {
            Text("System").tag("system")
            Text("Light").tag("light")
            Text("Dark").tag("dark")
          }
        }
      }
      .navigationTitle("Edit Profile")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { Task { await save() } }
            .disabled(saving || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
    .frame(minWidth: 400, idealWidth: 520, minHeight: 480)
    .fileImporter(isPresented: $pickingImage, allowedContentTypes: [.image]) { result in
      guard case .success(let url) = result else { return }
      let field = imageField
      Task {
        if let upload = await model.upload(url) {
          if field == "avatar" { avatarURL = upload.url } else { bannerURL = upload.url }
        }
      }
    }
  }

  private func save() async {
    saving = true
    defer { saving = false }
    if await model.saveProfile(
      displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
      bio: bio, status: status, avatarURL: avatarURL, bannerURL: bannerURL, theme: theme
    ) { dismiss() }
  }
}

private struct AccountSecuritySheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var username = ""
  @State private var usernamePassword = ""
  @State private var email = ""
  @State private var emailPassword = ""
  @State private var currentPassword = ""
  @State private var newPassword = ""
  @State private var confirmPassword = ""
  @State private var sessions: [PWAccountSession] = []
  @State private var busy = false
  @State private var notice = ""
  @State private var confirmLogoutOthers = false
  @State private var accountPassword = ""
  @State private var accountConfirmation = ""
  @State private var accountAction: AccountAction = .disable
  @State private var showingAccountConfirmation = false

  private enum AccountAction: String {
    case disable, delete
  }

  var body: some View {
    NavigationStack {
      Form {
        if !notice.isEmpty {
          Section { Label(notice, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
        }
        Section("Username") {
          TextField("Username", text: $username)
            .autocorrectionDisabled()
          SecureField("Current password", text: $usernamePassword)
          Button("Change username") { Task { await changeUsername() } }
            .disabled(busy || username.isEmpty || usernamePassword.isEmpty)
        }
        Section("Email and recovery") {
          TextField("Email", text: $email)
            .textContentType(.emailAddress)
            .autocorrectionDisabled()
          if let user = model.session?.user, user.email?.isEmpty == false {
            Label(user.emailVerified == true ? "Verified" : "Verification pending",
                  systemImage: user.emailVerified == true ? "checkmark.seal.fill" : "envelope.badge")
              .foregroundStyle(.secondary)
          }
          SecureField("Current password", text: $emailPassword)
          Button("Save email") { Task { await saveEmail() } }
            .disabled(busy || email.isEmpty || emailPassword.isEmpty)
          if model.session?.user.email?.isEmpty == false {
            Button("Resend verification") { Task { await resendEmail() } }
              .disabled(busy)
            Button("Remove email", role: .destructive) { Task { await removeEmail() } }
              .disabled(busy || emailPassword.isEmpty)
          }
        }
        Section("Password") {
          SecureField("Current password", text: $currentPassword)
          SecureField("New password", text: $newPassword)
          SecureField("Confirm new password", text: $confirmPassword)
          Button("Change password") { Task { await changePassword() } }
            .disabled(busy || currentPassword.isEmpty || newPassword.count < 10)
        }
        Section("Active sessions") {
          ForEach(sessions) { session in
            VStack(alignment: .leading, spacing: 3) {
              Text(session.current ? "This device" : "Signed-in session")
                .fontWeight(session.current ? .semibold : .regular)
              Text("Last active \(Date(timeIntervalSince1970: TimeInterval(session.lastSeen) / 1000).formatted())")
                .font(.caption).foregroundStyle(.secondary)
            }
          }
          Button("Sign out other sessions", role: .destructive) { confirmLogoutOthers = true }
            .disabled(busy || !sessions.contains(where: { !$0.current }))
        }
        Section("Account access") {
          Text("Disabling signs out all devices. You can reactivate by signing in. Deleting permanently removes your account and eligible account owned data.")
            .font(.caption).foregroundStyle(.secondary)
          SecureField("Current password", text: $accountPassword)
          TextField("Type DISABLE or DELETE", text: $accountConfirmation)
            .autocorrectionDisabled()
          Button("Disable account", role: .destructive) {
            accountAction = .disable
            showingAccountConfirmation = true
          }
            .disabled(busy || accountPassword.isEmpty || accountConfirmation != "DISABLE")
          Button("Delete account permanently", role: .destructive) {
            accountAction = .delete
            showingAccountConfirmation = true
          }
            .disabled(busy || accountPassword.isEmpty || accountConfirmation != "DELETE")
        }
      }
      .navigationTitle("Account")
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
    .frame(minWidth: 400, idealWidth: 520, minHeight: 530)
    .task {
      username = model.session?.user.username ?? ""
      email = model.session?.user.email ?? ""
      sessions = await model.accountSessions()
    }
    .confirmationDialog("Sign out other sessions?", isPresented: $confirmLogoutOthers) {
      Button("Sign out other sessions", role: .destructive) {
        Task {
          busy = true
          if await model.logoutOtherSessions() {
            sessions = await model.accountSessions()
            notice = "Other sessions signed out."
          }
          busy = false
        }
      }
    }
    .confirmationDialog(
      accountAction == .delete ? "Delete account permanently?" : "Disable account?",
      isPresented: $showingAccountConfirmation
    ) {
      Button(accountAction == .delete ? "Delete permanently" : "Disable account", role: .destructive) {
        Task {
          busy = true
          if await model.closeAccount(password: accountPassword, permanently: accountAction == .delete) {
            dismiss()
          }
          busy = false
        }
      }
    } message: {
      Text(accountAction == .delete ? "This cannot be undone." : "You can sign in again to reactivate your account.")
    }
  }

  private func changeUsername() async {
    busy = true
    if await model.changeUsername(current: usernamePassword, new: username) {
      usernamePassword = ""
      notice = "Username updated."
    }
    busy = false
  }

  private func saveEmail() async {
    busy = true
    if let message = await model.updateEmail(email, password: emailPassword) {
      emailPassword = ""
      notice = message
    }
    busy = false
  }

  private func removeEmail() async {
    busy = true
    if await model.removeEmail(password: emailPassword) {
      email = ""
      emailPassword = ""
      notice = "Email removed."
    }
    busy = false
  }

  private func resendEmail() async {
    busy = true
    if let message = await model.resendEmailVerification() { notice = message }
    busy = false
  }

  private func changePassword() async {
    guard newPassword == confirmPassword else {
      model.errorMessage = "The new passwords do not match."
      return
    }
    busy = true
    if await model.changePassword(current: currentPassword, new: newPassword) {
      currentPassword = ""
      newPassword = ""
      confirmPassword = ""
      sessions = await model.accountSessions()
      notice = "Password changed. Other sessions were signed out."
    }
    busy = false
  }
}
