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
    List(selection: Binding<AppModel.Section?>(
      get: { model.selectedSection },
      set: { if let section = $0 { model.selectedSection = section } })) {
      Section {
        HStack(spacing: 10) {
          PlainwireMark(size: 30)
          VStack(alignment: .leading, spacing: 1) {
            Text("Plainwire").font(.headline)
            Text(model.serverDisplayName).font(.caption2).foregroundStyle(.secondary)
              .lineLimit(1).truncationMode(.middle)
          }
        }
        .padding(.vertical, 5)
        .listRowSeparator(.hidden)
      }

      Section("Browse") {
        ForEach(navigationSections) { section in
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
          .tag(section)
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
    .listStyle(.sidebar)
    .scrollContentBackground(.hidden)
    .navigationTitle("Plainwire")
    .safeAreaInset(edge: .bottom) {
      VStack(spacing: 10) {
        if let user = model.session?.user {
          HStack(spacing: 10) {
            RemoteAvatar(
              url: model.mediaURL(user.avatarURL), fallback: String(user.displayName.prefix(1)),
              size: 34)
            VStack(alignment: .leading, spacing: 3) {
              Menu {
                ForEach(["online", "away", "busy", "invisible"], id: \.self) { status in
                  Button {
                    Task { await model.setStatus(status) }
                  } label: {
                    Label(status == "busy" ? "Do Not Disturb" : status.capitalized,
                      systemImage: user.status == status ? "checkmark.circle.fill" : "circle")
                  }
                }
                Divider()
                Button("Settings…", systemImage: "gearshape") {
                  #if os(macOS)
                    model.showSettings = true
                  #else
                    model.selectedSection = .settings
                  #endif
                }
                Button("Switch Server Host…", systemImage: "network") { model.showServerPicker = true }
              } label: {
                Text(user.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
              }
              .menuStyle(.borderlessButton)
              .menuIndicator(.visible)
              .frame(maxWidth: .infinity, alignment: .leading)
              .help("Profile and status")
              .accessibilityLabel("Account menu for \(user.displayName)")
              Text("@\(user.username)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
          }
          .padding(.top, 4)
        }
        HStack(spacing: 8) {
          ConnectionStatusView()
          Spacer(minLength: 0)
          Menu {
            Button("Forums", systemImage: "text.bubble") { model.openWorkspace(fragment: "forums") }
            Button("Source Hub", systemImage: "chevron.left.forwardslash.chevron.right") { model.openWorkspace(fragment: "source") }
            Button("Developer Apps", systemImage: "hammer") { model.openWorkspace(fragment: "settings") }
          } label: {
            Image(systemName: "ellipsis")
              .font(.body.weight(.semibold))
              .frame(width: 28, height: 24)
              .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          }
          .menuStyle(.borderlessButton)
          .menuIndicator(.hidden)
          .fixedSize()
          .help("More tools")
          .accessibilityLabel("More tools")
        }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .overlay(alignment: .top) { Divider().padding(.horizontal, 14) }
    }
    .background { SidebarSurface().ignoresSafeArea() }
  }
}
