import SwiftUI

struct SidebarView: View {
  @Environment(AppModel.self) private var model

  private var navigationSections: [AppModel.Section] {
    #if os(macOS)
      [.messages, .servers, .friends, .activity]
    #else
      [.messages, .servers, .friends, .activity, .settings]
    #endif
  }

  var body: some View {
    List {
      Section {
        HStack(spacing: 10) {
          PlainwireMark(size: 30)
          VStack(alignment: .leading, spacing: 1) {
            Text("Plainwire").font(.headline)
            Text("Your conversations, together").font(.caption2).foregroundStyle(.secondary)
          }
        }
        .padding(.vertical, 5)
        .listRowSeparator(.hidden)
      }

      Section("Browse") {
        ForEach(navigationSections) { section in
          Button {
            model.selectedSection = section
          } label: {
            HStack {
              Label(section.title, systemImage: section.systemImage)
                .fontWeight(model.selectedSection == section ? .semibold : .regular)
              Spacer()
              let count = section == .messages ? model.unreadMessageCount : section == .activity ? model.unreadActivityCount : 0
              if count > 0 {
                Text(count > 99 ? "99+" : "\(count)").font(.caption2.bold()).monospacedDigit()
                  .padding(.horizontal, 6).padding(.vertical, 2)
                  .background(Color.accentColor.opacity(0.15), in: Capsule())
              }
            }.contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .listRowBackground(
            model.selectedSection == section ? Color.accentColor.opacity(0.13) : Color.clear)
        }
      }


      if !model.servers.isEmpty {
        Section("Servers") {
          ForEach(model.servers.prefix(10)) { server in
            Button {
              model.selectedSection = .servers
              Task { await model.openServer(server) }
            } label: {
              HStack(spacing: 10) {
                RemoteAvatar(
                  url: model.mediaURL(server.iconURL), fallback: String(server.name.prefix(1)),
                  size: 28, cornerRadius: 8)
                Text(server.name).lineLimit(1)
                Spacer(minLength: 0)
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
    .navigationTitle("Plainwire")
    .safeAreaInset(edge: .bottom) {
      VStack(spacing: 8) {
        if let user = model.session?.user {
          HStack(spacing: 9) {
            RemoteAvatar(
              url: model.mediaURL(user.avatarURL), fallback: String(user.displayName.prefix(1)),
              size: 30)
            VStack(alignment: .leading, spacing: 1) {
              Text(user.displayName).font(.caption.weight(.semibold)).lineLimit(1)
              Text("@\(user.username)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
          }
          .padding(.horizontal, 10)
        }
        HStack(spacing: 8) {
          ConnectionStatusView()
          Menu {
            Button("Forums", systemImage: "text.bubble") { model.openWorkspace(fragment: "forums") }
            Button("Source Hub", systemImage: "chevron.left.forwardslash.chevron.right") { model.openWorkspace(fragment: "source") }
            Button("Developer Apps", systemImage: "hammer") { model.openWorkspace(fragment: "settings") }
          } label: { Image(systemName: "ellipsis.circle") }
          .menuStyle(.borderlessButton)
          .help("More tools")
          .accessibilityLabel("More tools")
        }.padding(.horizontal, 10)
      }
      .padding(.vertical, 8)
      .background(.bar)
    }
  }
}
