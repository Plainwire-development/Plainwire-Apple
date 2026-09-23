import SwiftUI
import WebKit

struct AppRootView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  var body: some View {
    ZStack(alignment: .top) {
      Group {
        switch model.sessionState {
        case .booting: LaunchView()
        case .signedOut: SignInView()
        case .ready: authenticatedRoot
        }
      }

      if let message = model.errorMessage {
        AppNoticeBanner(message: friendlyError(message)) {
          withAnimation(.snappy(duration: 0.2)) { model.errorMessage = nil }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .transition(.move(edge: .top).combined(with: .opacity))
        .zIndex(100)
      }
    }
    .animation(.snappy(duration: 0.22), value: model.errorMessage != nil)
    .preferredColorScheme(preferredColorScheme)
    .onChange(of: model.selectedSection) { oldSection, newSection in
      if oldSection == .workspace && newSection != .workspace {
        Task {
          if let serverID = model.selectedServerID {
            await model.reloadServer(serverID)
          } else {
            await model.refresh()
          }
          model.workspaceStartFragment = nil
        }
      }
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
      NavigationStack { ConversationListView(compactNavigation: true) }
        .tabItem { Label("Messages", systemImage: "message.fill") }.tag(AppModel.Section.messages)
      NavigationStack { MobileServersView() }
        .tabItem { Label("Servers", systemImage: "rectangle.3.group.fill") }.tag(
          AppModel.Section.servers)
      NavigationStack { FriendsView() }
        .tabItem { Label("Friends", systemImage: "person.2.fill") }.tag(AppModel.Section.friends)
      NavigationStack { WebWorkspaceView() }
        .tabItem { Label("Workspace", systemImage: "square.grid.2x2.fill") }.tag(AppModel.Section.workspace)
      NavigationStack { SettingsView() }
        .tabItem { Label("You", systemImage: "person.crop.circle.fill") }.tag(
          AppModel.Section.settings)
    }
  }
}

private struct SplitRootView: View {
  @Environment(AppModel.self) private var model
  @State private var visibility: NavigationSplitViewVisibility = .all

  var body: some View {
    switch model.selectedSection {
    case .messages, .servers:
      threeColumnRoot
    case .friends, .workspace, .settings:
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
      if model.selectedRoom != nil {
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
      case .settings:
        SettingsView(showNavigationTitle: true, detailPresentation: true)
      case .workspace:
        WebWorkspaceView()
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
    case .friends, .workspace, .settings: EmptyView()
    }
  }
}

private struct WebWorkspaceView: View {
  @Environment(AppModel.self) private var model
  @State private var reloadToken = UUID()

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Image(systemName: "square.grid.2x2.fill")
          .foregroundStyle(.tint)
        VStack(alignment: .leading, spacing: 2) {
          Text("Full Workspace").font(.headline)
          Text("Development, live calls, and every web workspace tool")
            .font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Button { reloadToken = UUID() } label: { Label("Reload", systemImage: "arrow.clockwise") }
          .adaptiveGlassButton()
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      Divider()
      PlainwireWorkspaceWebView(
        reloadToken: reloadToken, initialFragment: model.workspaceStartFragment)
    }
    .navigationTitle("Workspace")
  }
}

#if os(iOS)
private struct PlainwireWorkspaceWebView: UIViewRepresentable {
  @Environment(AppModel.self) private var model
  let reloadToken: UUID
  let initialFragment: String?

  func makeUIView(context: Context) -> WKWebView { makeWebView(coordinator: context.coordinator) }
  func updateUIView(_ view: WKWebView, context: Context) {
    if context.coordinator.lastReload != reloadToken {
      context.coordinator.lastReload = reloadToken
      view.reload()
    }
  }
  func makeCoordinator() -> Coordinator {
    Coordinator(reloadToken: reloadToken, onSessionEnded: { Task { await model.logout() } })
  }
}
#else
private struct PlainwireWorkspaceWebView: NSViewRepresentable {
  @Environment(AppModel.self) private var model
  let reloadToken: UUID
  let initialFragment: String?

  func makeNSView(context: Context) -> WKWebView { makeWebView(coordinator: context.coordinator) }
  func updateNSView(_ view: WKWebView, context: Context) {
    if context.coordinator.lastReload != reloadToken {
      context.coordinator.lastReload = reloadToken
      view.reload()
    }
  }
  func makeCoordinator() -> Coordinator {
    Coordinator(reloadToken: reloadToken, onSessionEnded: { Task { await model.logout() } })
  }
}
#endif

private extension PlainwireWorkspaceWebView {
  final class Coordinator: NSObject, WKHTTPCookieStoreObserver {
    var lastReload: UUID
    var hasLoadedSession = false
    let onSessionEnded: @MainActor () -> Void

    init(reloadToken: UUID, onSessionEnded: @escaping @MainActor () -> Void) {
      lastReload = reloadToken
      self.onSessionEnded = onSessionEnded
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
      guard hasLoadedSession else { return }
      cookieStore.getAllCookies { [weak self] cookies in
        guard let self, !cookies.contains(where: { $0.name == "pw_session" }) else { return }
        Task { @MainActor in self.onSessionEnded() }
      }
    }
  }

  func makeWebView(coordinator: Coordinator) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    #if os(iOS)
      configuration.allowsInlineMediaPlayback = true
    #endif
    let view = WKWebView(frame: .zero, configuration: configuration)
    var baseURL = PlainwireConfiguration().baseURL
    if let initialFragment, var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) {
      parts.fragment = initialFragment
      baseURL = parts.url ?? baseURL
    }
    let cookies = HTTPCookieStorage.shared.cookies(for: baseURL) ?? []
    let cookieStore = configuration.websiteDataStore.httpCookieStore
    cookieStore.add(coordinator)
    Task { @MainActor in
      for cookie in cookies {
        await withCheckedContinuation { continuation in
          cookieStore.setCookie(cookie) { continuation.resume() }
        }
      }
      coordinator.hasLoadedSession = true
      view.load(URLRequest(url: baseURL))
    }
    return view
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
