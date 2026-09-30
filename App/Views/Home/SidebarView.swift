import SwiftUI

struct SidebarView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    List {
      Section {
        HStack(spacing: 10) {
          PlainwireMark(size: 30)
          VStack(alignment: .leading, spacing: 1) {
            Text("Plainwire").font(.headline)
            Text("Messages and servers").font(.caption2).foregroundStyle(.secondary)
          }
        }
        .padding(.vertical, 5)
        .listRowSeparator(.hidden)
      }

      Section("Browse") {
        ForEach(AppModel.Section.allCases) { section in
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

      Section("Workspace") {
        Button { model.openWorkspace(fragment: "forums") } label: { Label("Forums", systemImage: "text.bubble") }
        Button { model.openWorkspace(fragment: "source") } label: { Label("Source Hub", systemImage: "chevron.left.forwardslash.chevron.right") }
      }.buttonStyle(.plain)

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
        ConnectionStatusView().padding(.horizontal, 10)
      }
      .padding(.vertical, 8)
      .background(.bar)
    }
  }
}
