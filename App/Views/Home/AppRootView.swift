import SwiftUI
import QuickLook

struct AppRootView: View {
  @Environment(AppModel.self) private var model
  #if os(macOS)
    @Environment(\.openSettings) private var openSettings
  #endif
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @AppStorage(AppPreferenceKeys.reduceInterfaceMotion) private var reduceInterfaceMotion = false

  var body: some View {
    ZStack(alignment: .top) {
      Group {
        switch model.sessionState {
        case .booting: LaunchView()
        case .signedOut: SignInView()
        case .ready: authenticatedRoot
        case .unavailable: ConnectionRecoveryView()
        }
      }

      if model.downloadingAttachment {
        HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Downloading attachment…").font(.caption) }
          .padding(12).background(.regularMaterial, in: Capsule()).padding(.top, 10).zIndex(99)
      }
      if let message = model.errorMessage {
        AppNoticeBanner(message: friendlyError(message)) {
          withAnimation(reduceMotion || reduceInterfaceMotion ? nil : .snappy(duration: 0.2)) { model.errorMessage = nil }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .transition(.move(edge: .top).combined(with: .opacity))
        .zIndex(100)
      }
    }
    .animation(reduceMotion || reduceInterfaceMotion ? nil : .snappy(duration: 0.22), value: model.errorMessage != nil)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if model.sessionState == .ready { CallDockView() }
    }
    .quickLookPreview(Binding(get: { model.previewFileURL }, set: { model.previewFileURL = $0 }))
    .environment(\.openURL, OpenURLAction { url in
      if url.scheme == "plainwire" || (url.host == PlainwireConfiguration().baseURL.host && url.fragment != nil) {
        Task { await model.handleDeepLink(url) }
        return .handled
      }
      guard ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return .discarded }
      return .systemAction
    })
    .preferredColorScheme(preferredColorScheme)
    .sheet(isPresented: Binding(get: { model.showMessageSearch }, set: { model.showMessageSearch = $0 })) {
      MessageSearchView()
    }
    .sheet(isPresented: Binding(get: { model.showNewConversation }, set: { model.showNewConversation = $0 })) {
      NewConversationSheet()
    }
    .sheet(isPresented: Binding(get: { model.showWorkspace }, set: { model.showWorkspace = $0 })) {
      NavigationStack {
        WebWorkspaceView()
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button("Done") { model.showWorkspace = false }
            }
          }
      }.adaptiveSheetSize(minWidth: 800, minHeight: 620)
    }
    .onChange(of: model.showWorkspace) { _, shown in
      if !shown { Task { await model.refresh() } }
    }
    #if os(macOS)
      .onChange(of: model.showSettings) { _, shown in
        if shown { model.showSettings = false; openSettings() }
      }
    #endif
    .onChange(of: model.selectedSection) { _, section in
      Task { await model.sectionDidChange(section) }
    }
  }

  private var preferredColorScheme: ColorScheme? {
    switch model.session?.user.theme {
    case "light": .light
    case "dark": .dark
    default: nil
    }
  }

  @ViewBuilder private var authenticatedRoot: some View {
    #if os(iOS)
      if horizontalSizeClass == .compact { CompactRootView() } else { SplitRootView() }
    #else
      SplitRootView()
    #endif
  }

  private func friendlyError(_ raw: String) -> String {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return "Something went wrong. Please try again." }
    if value.count > 220 { return String(value.prefix(217)) + "…" }
    return value
  }
}

private struct AppNoticeBanner: View {
  let message: String
  let dismiss: () -> Void

  var body: some View {
    HStack(spacing: 11) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
        .symbolRenderingMode(.hierarchical)
      Text(message)
        .font(.subheadline)
        .lineLimit(3)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button(action: dismiss) {
        Image(systemName: "xmark")
          .font(.caption.weight(.bold))
          .frame(width: 24, height: 24)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .accessibilityLabel("Dismiss")
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 11)
    .frame(maxWidth: 640)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(.primary.opacity(0.08), lineWidth: 0.5)
    }
    .shadow(color: .black.opacity(0.10), radius: 18, y: 7)
  }
}

private struct LaunchView: View {
  var body: some View {
    VStack(spacing: 18) {
      PlainwireMark(size: 72)
      ProgressView().controlSize(.large)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(AppBackdrop())
  }
}

private struct CompactRootView: View {
  @Environment(AppModel.self) private var model
  var body: some View {
    @Bindable var model = model
    TabView(selection: $model.selectedSection) {
      NavigationStack {
        ConversationListView(compactNavigation: true)
          .navigationDestination(item: navigationRoom(scope: "direct")) { _ in ChatView() }
      }
        .tabItem { Label("Messages", systemImage: "message.fill") }.tag(AppModel.Section.messages)
      NavigationStack {
        MobileServersView()
          .navigationDestination(item: navigationRoom(scope: "channel")) { _ in ChatView() }
      }
        .tabItem { Label("Servers", systemImage: "rectangle.3.group.fill") }.tag(
          AppModel.Section.servers)
      NavigationStack { FriendsView() }
        .tabItem { Label("Friends", systemImage: "person.2.fill") }.tag(AppModel.Section.friends)
      NavigationStack { ActivityView() }
        .tabItem { Label("Activity", systemImage: "bell.fill") }.tag(AppModel.Section.activity)
        .badge(model.unreadActivityCount)
      NavigationStack { SettingsView() }
        .tabItem { Label("You", systemImage: "person.crop.circle.fill") }.tag(
          AppModel.Section.settings)
    }
  }

  private func navigationRoom(scope: String) -> Binding<AppModel.Room?> {
    Binding(
      get: { model.navigationRoom?.scope == scope ? model.navigationRoom : nil },
      set: { room in
        if let room { model.navigationRoom = room }
        else if model.navigationRoom?.scope == scope { model.navigationRoom = nil }
      })
  }
}

private struct SplitRootView: View {
  @Environment(AppModel.self) private var model
  @State private var visibility: NavigationSplitViewVisibility = .all

  var body: some View {
    switch model.selectedSection {
    case .messages, .servers:
      threeColumnRoot
    case .friends, .activity, .settings:
      twoColumnRoot
    }
  }

  private var threeColumnRoot: some View {
    NavigationSplitView(columnVisibility: $visibility) {
      SidebarView()
        .navigationSplitViewColumnWidth(min: 190, ideal: 228, max: 300)
    } content: {
      browserColumn
        .navigationSplitViewColumnWidth(min: 270, ideal: 330, max: 440)
    } detail: {
      if let room = model.selectedRoom,
        (model.selectedSection == .messages && room.scope == "direct") || (model.selectedSection == .servers && room.scope == "channel") {
        ChatView()
      } else {
        EmptyDetailView(
          title: "Choose a conversation",
          symbol: "bubble.left.and.bubble.right",
          description: "Messages and channels stay synced with Plainwire.")
      }
    }
    .navigationSplitViewStyle(.balanced)
  }

  private var twoColumnRoot: some View {
    NavigationSplitView {
      SidebarView()
        .navigationSplitViewColumnWidth(min: 190, ideal: 228, max: 300)
    } detail: {
      switch model.selectedSection {
      case .friends:
        FriendsView()
      case .activity:
        ActivityView()
      case .settings:
        SettingsView(showNavigationTitle: true, detailPresentation: true)
      case .messages, .servers:
        EmptyView()
      }
    }
    .navigationSplitViewStyle(.balanced)
  }

  @ViewBuilder private var browserColumn: some View {
    switch model.selectedSection {
    case .messages: ConversationListView(compactNavigation: false)
    case .servers: ServerChannelBrowserView()
    case .friends, .activity, .settings: EmptyView()
    }
  }
}

private struct EmptyDetailView: View {
  let title: String
  let symbol: String
  let description: String

  var body: some View {
    ZStack {
      AppBackdrop()
      ContentUnavailableView(title, systemImage: symbol, description: Text(description))
        .padding(32)
    }
  }
}

private struct ConnectionRecoveryView: View {
  @Environment(AppModel.self) private var model
  var body: some View {
    ContentUnavailableView {
      Label("Unable to connect", systemImage: "wifi.exclamationmark")
    } description: {
      Text("Your saved session is still here. Check your connection and try again.")
    } actions: {
      Button("Try Again") { Task { await model.retryStart() } }
        .buttonStyle(.borderedProminent)
      Button("Sign Out", role: .destructive) { Task { await model.logout() } }
        .buttonStyle(.bordered)
    }
    .background(AppBackdrop())
  }
}
