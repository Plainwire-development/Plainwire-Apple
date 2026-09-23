import SwiftUI

struct ServerChannelBrowserView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    VStack(spacing: 0) {
      serverHeader
      Divider().opacity(0.35)
      channelList
    }
    .navigationTitle("Servers")
    .task {
      if model.selectedServerID == nil, let first = model.servers.first {
        await model.openServer(first)
      }
    }
  }

  @ViewBuilder private var serverHeader: some View {
    if let server = selectedServer {
      HStack(spacing: 11) {
        RemoteAvatar(
          url: model.mediaURL(server.iconURL), fallback: String(server.name.prefix(1)), size: 38,
          cornerRadius: 11)
        VStack(alignment: .leading, spacing: 2) {
          Text(server.name).font(.headline).lineLimit(1)
          Text("\(server.memberCount) members")
            .font(.caption).foregroundStyle(.secondary)
        }
        Spacer(minLength: 8)
        Menu {
          ForEach(model.servers) { candidate in
            Button {
              Task { await model.openServer(candidate) }
            } label: {
              if candidate.id == server.id {
                Label(candidate.name, systemImage: "checkmark")
              } else {
                Text(candidate.name)
              }
            }
          }
        } label: {
          Image(systemName: "chevron.up.chevron.down")
            .font(.caption.weight(.semibold))
            .frame(width: 28, height: 28)
        }
        .adaptiveGlassButton()
        .controlSize(.small)
        .accessibilityLabel("Choose server")
      }
      .padding(.horizontal, 13)
      .padding(.vertical, 10)
    }
  }

  @ViewBuilder private var channelList: some View {
    if let serverID = model.selectedServerID, let detail = model.serverDetails[serverID] {
      List {
        ForEach(detail.categories.sorted(by: { $0.position < $1.position })) { category in
          Section(category.name) { channels(detail, category: category.id) }
        }
        let uncategorized = detail.channels.filter { $0.categoryId == nil }
        if !uncategorized.isEmpty { Section("Channels") { channels(detail, category: nil) } }
      }
      .modifier(ServerListStyleModifier())
    } else if model.servers.isEmpty {
      ContentUnavailableView(
        "No servers", systemImage: "rectangle.3.group",
        description: Text("Servers you join will appear here."))
    } else {
      ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  @ViewBuilder private func channels(_ detail: PWServerDetail, category: PlainwireID?) -> some View
  {
    ForEach(
      detail.channels.filter { $0.categoryId == category }.sorted(by: {
        $0.position == $1.position ? $0.id < $1.id : $0.position < $1.position
      })
    ) { channel in
      if channel.kind == "voice" {
        HStack(spacing: 9) {
          Image(systemName: "speaker.wave.2").foregroundStyle(.secondary).frame(width: 18)
          Text(channel.name)
          Spacer()
          Text("Voice").font(.caption2).foregroundStyle(.secondary)
        }
        .foregroundStyle(.secondary)
        .accessibilityHint("Voice channels require native calling support")
      } else {
        Button {
          Task {
            await model.openChannel(
              channel, server: model.servers.first(where: { $0.id == detail.server.id }))
          }
        } label: {
          HStack(spacing: 9) {
            Image(systemName: "number").foregroundStyle(.secondary).frame(width: 18)
            Text(channel.name).lineLimit(1)
            Spacer(minLength: 0)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
          model.selectedChannelID == channel.id ? Color.accentColor.opacity(0.10) : Color.clear)
      }
    }
  }

  private var selectedServer: PWServer? {
    guard let id = model.selectedServerID else { return model.servers.first }
    return model.servers.first(where: { $0.id == id })
  }
}

struct MobileServersView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    List(model.servers) { server in
      NavigationLink {
        MobileServerChannelsView(server: server)
      } label: {
        HStack(spacing: 12) {
          RemoteAvatar(
            url: model.mediaURL(server.iconURL), fallback: String(server.name.prefix(1)), size: 44,
            cornerRadius: 12)
          VStack(alignment: .leading, spacing: 3) {
            Text(server.name).font(.headline).lineLimit(1)
            Text("\(server.memberCount) members").font(.caption).foregroundStyle(.secondary)
          }
        }
        .padding(.vertical, 4)
      }
    }
    .modifier(MobileServerListStyleModifier())
    .navigationTitle("Servers")
    .overlay {
      if model.servers.isEmpty {
        ContentUnavailableView("No servers", systemImage: "rectangle.3.group")
      }
    }
    .refreshable { await model.refresh() }
  }
}

private struct MobileServerChannelsView: View {
  @Environment(AppModel.self) private var model
  let server: PWServer

  var body: some View {
    Group {
      if let detail = model.serverDetails[server.id] {
        List {
          ForEach(detail.categories.sorted(by: { $0.position < $1.position })) { category in
            Section(category.name) {
              channelLinks(detail.channels.filter { $0.categoryId == category.id })
            }
          }
          let rest = detail.channels.filter { $0.categoryId == nil }
          if !rest.isEmpty { Section("Channels") { channelLinks(rest) } }
        }
        .modifier(MobileServerListStyleModifier())
      } else {
        ProgressView()
      }
    }
    .navigationTitle(server.name)
    .task { await model.openServer(server) }
  }

  @ViewBuilder private func channelLinks(_ channels: [PWChannel]) -> some View {
    ForEach(channels.sorted(by: { $0.position < $1.position })) { channel in
      if channel.kind == "voice" {
        Label(channel.name, systemImage: "speaker.wave.2")
          .foregroundStyle(.secondary)
          .accessibilityHint("Voice channels require native calling support")
      } else {
        NavigationLink {
          ChatView(initialChannel: channel, initialServer: server)
        } label: {
          Label(channel.name, systemImage: "number")
        }
      }
    }
  }
}

private struct ServerListStyleModifier: ViewModifier {
  @ViewBuilder func body(content: Content) -> some View {
    #if os(macOS)
      content.listStyle(.sidebar)
    #else
      content.listStyle(.insetGrouped)
    #endif
  }
}

private struct MobileServerListStyleModifier: ViewModifier {
  @ViewBuilder func body(content: Content) -> some View {
    #if os(macOS)
      content.listStyle(.inset)
    #else
      content.listStyle(.insetGrouped)
    #endif
  }
}
