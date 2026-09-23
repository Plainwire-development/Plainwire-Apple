import Foundation
import SwiftUI

@main
struct PlainwireApp: App {
  @State private var model = AppModel()
  @Environment(\.scenePhase) private var scenePhase

  init() {
    AppPreferences.registerDefaults()
    URLCache.shared.memoryCapacity = 64 * 1024 * 1024
    URLCache.shared.diskCapacity = 512 * 1024 * 1024
  }

  var body: some Scene {
    #if os(macOS)
      WindowGroup {
        rootView
          .frame(minWidth: 920, minHeight: 620)
      }
      .defaultSize(width: 1180, height: 760)
      .windowResizability(.contentMinSize)
      .commands {
        CommandGroup(after: .appInfo) {
          Button("Refresh Plainwire") { Task { await model.refresh() } }
            .keyboardShortcut("r", modifiers: .command)
        }
        CommandMenu("Plainwire") {
          Button("Messages") { model.selectedSection = .messages }
            .keyboardShortcut("1", modifiers: .command)
          Button("Servers") { model.selectedSection = .servers }
            .keyboardShortcut("2", modifiers: .command)
          Button("Friends") { model.selectedSection = .friends }
            .keyboardShortcut("3", modifiers: .command)
        }
      }
      Settings {
        SettingsView(showNavigationTitle: false, detailPresentation: true).environment(model).frame(
          minWidth: 760, minHeight: 620)
      }
    #else
      WindowGroup { rootView }
    #endif
  }

  private var rootView: some View {
    AppRootView()
      .environment(model)
      .task {
        NotificationCoordinator.shared.configure { url in
          Task { await model.handleDeepLink(url) }
        }
        await model.start()
      }
      .onOpenURL { url in Task { await model.handleDeepLink(url) } }
      .onChange(of: scenePhase) { _, phase in
        guard model.sessionState == .ready else { return }
        #if os(iOS)
          switch phase {
          case .active:
            Task { await model.resumeFromForeground() }
          case .background:
            Task { await model.prepareForBackground() }
          case .inactive:
            break
          @unknown default:
            break
          }
        #else
          if phase == .active { Task { await model.refresh() } }
        #endif
      }
  }
}
