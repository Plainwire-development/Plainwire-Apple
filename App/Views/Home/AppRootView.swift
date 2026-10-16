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
    .overlay {
      if model.sessionState == .ready { CallDockView() }
    }
    .quickLookPreview(Binding(get: { model.previewFileURL }, set: { model.previewFileURL = $0 }))
    .environment(\.openURL, OpenURLAction { url in
      if url.scheme == "plainwire" || (model.isServerURL(url) && url.fragment != nil) {
        Task { await model.handleDeepLink(url) }
        return .handled
      }
      guard ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return .discarded }
      return .systemAction
    })
    .preferredColorScheme(preferredColorScheme)
    .sheet(isPresented: Binding(get: { model.showServerPicker }, set: { model.showServerPicker = $0 })) {
      ServerHostSheet()
    }
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
      }.adaptiveSheetSize(minWidth: 680, idealWidth: 1000, minHeight: 480, idealHeight: 700)
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
  @Environment(AppModel.self) private var model
  var body: some View {
    VStack(spacing: 18) {
      PlainwireMark(size: 72)
      ProgressView().controlSize(.large)
      Text(model.serverDisplayName).font(.callout).foregroundStyle(.secondary)
      Button("Switch Server Host…") { model.showServerPicker = true }
        .buttonStyle(.borderless).disabled(model.isBusy || model.isSwitchingHost)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(AppBackdrop())
  }
}

private struct CompactRootView: View {
  @Environment(AppModel.self) private var model
  var body: some View {
    TabView(selection: Binding(get: {
      model.selectedSection == .activity ? .friends : model.selectedSection
    }, set: { model.selectedSection = $0 })) {
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
      ForumsView()
        .tabItem { Label("Forums", systemImage: "text.bubble.fill") }.tag(AppModel.Section.forums)
      NavigationStack {
        VStack(spacing: 0) {
          Picker("People", selection: Binding(get: {
            model.selectedSection == .activity ? AppModel.Section.activity : .friends
          }, set: { model.selectedSection = $0 })) {
            Text("Friends").tag(AppModel.Section.friends)
            Text(model.unreadActivityCount > 0 ? "Activity (\(model.unreadActivityCount))" : "Activity")
              .tag(AppModel.Section.activity)
          }
          .pickerStyle(.segmented).frame(maxWidth: 360).padding(.horizontal, 20).padding(.vertical, 10)
          Group {
            if model.selectedSection == .activity { ActivityView() }
            else { FriendsView() }
          }
        }
        .background(AppBackdrop())
      }
        .tabItem { Label("People", systemImage: "person.2.fill") }.tag(AppModel.Section.friends)
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
    case .forums, .friends, .activity, .settings:
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
          title: model.selectedSection == .servers ? "Find your place." : "Good conversations start here.",
          symbol: model.selectedSection == .servers ? "rectangle.3.group.fill" : "bubble.left.and.bubble.right.fill",
          description: model.selectedSection == .servers ? "Choose a channel to catch up with your community." : "Pick a conversation, say hello, or discover a community in Forums.")
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
      case .forums:
        ForumsView()
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
    case .forums, .friends, .activity, .settings: EmptyView()
    }
  }
}

private struct EmptyDetailView: View {
  @Environment(AppModel.self) private var model
  let title: String
  let symbol: String
  let description: String

  var body: some View {
    ZStack {
      AppBackdrop()
      VStack(spacing: 22) {
        Image(systemName: symbol).font(.system(size: 48, weight: .medium)).symbolRenderingMode(.hierarchical)
          .foregroundStyle(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
          .frame(width: 120, height: 120)
          .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 36, style: .continuous))
        VStack(spacing: 10) {
          Text(title).font(.system(.title, design: .rounded, weight: .bold))
          Text(description).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.multilineTextAlignment(.center)
        HStack(spacing: 12) {
          if model.selectedSection == .messages {
            Button("New Conversation", systemImage: "square.and.pencil") { model.showNewConversation = true }
              .adaptiveGlassButton(prominent: true)
          }
          Button("Explore Forums", systemImage: "text.bubble") { model.openForums() }.adaptiveGlassButton()
        }
      }.padding(32).frame(maxWidth: 500)
    }
  }
}

private struct ConnectionRecoveryView: View {
  @Environment(AppModel.self) private var model
  var body: some View {
    ContentUnavailableView {
      Label("Unable to connect", systemImage: "wifi.exclamationmark")
    } description: {
      Text("Couldn’t reach \(model.serverDisplayName). Check your connection or choose another server host.")
    } actions: {
      Button("Try Again") { Task { await model.retryStart() } }
        .buttonStyle(.borderedProminent)
      Button("Sign Out", role: .destructive) { Task { await model.logout() } }
        .buttonStyle(.bordered)
      Button("Switch Server Host") { model.showServerPicker = true }
        .buttonStyle(.bordered).disabled(model.isBusy)
    }
    .background(AppBackdrop())
  }
}
