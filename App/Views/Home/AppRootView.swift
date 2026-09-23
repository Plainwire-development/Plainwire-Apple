import SwiftUI

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
    case .friends, .settings:
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
    case .friends, .settings: EmptyView()
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
