import SwiftUI
import UniformTypeIdentifiers

struct ServerChannelBrowserView: View {
  @Environment(AppModel.self) private var model
  @State private var showingCreateServer = false
  @State private var showingJoinServer = false
  @State private var showingServerSettings = false

  var body: some View {
    VStack(spacing: 0) {
      serverHeader
      Divider().opacity(0.35)
      channelList
    }
    .navigationTitle("Servers")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Menu {
          Button("Create Server", systemImage: "plus") { showingCreateServer = true }
          Button("Join Server", systemImage: "link") { showingJoinServer = true }
        } label: { Image(systemName: "plus") }
      }
    }
    .sheet(isPresented: $showingCreateServer) { CreateServerSheet() }
    .sheet(isPresented: $showingJoinServer) { JoinServerSheet() }
    .sheet(isPresented: $showingServerSettings) {
      if let server = selectedServer { ServerManagementSheet(server: server) }
    }
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
        Button { showingServerSettings = true } label: {
          Image(systemName: "gearshape")
            .frame(width: 28, height: 28)
        }
        .adaptiveGlassButton()
        .controlSize(.small)
        .accessibilityLabel("Server settings")
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
        Button {
          model.workspaceStartFragment = "server/\(channel.serverId)"
          model.selectedSection = .workspace
        } label: {
          HStack(spacing: 9) {
            Image(systemName: "speaker.wave.2").foregroundStyle(.secondary).frame(width: 18)
            Text(channel.name)
            Spacer()
            Image(systemName: "arrow.up.right.square")
              .font(.caption2).foregroundStyle(.secondary)
          }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens this server in the full workspace for voice")
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
  @State private var showingCreateServer = false
  @State private var showingJoinServer = false

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
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Menu {
          Button("Create Server", systemImage: "plus") { showingCreateServer = true }
          Button("Join Server", systemImage: "link") { showingJoinServer = true }
        } label: { Image(systemName: "plus") }
      }
    }
    .sheet(isPresented: $showingCreateServer) { CreateServerSheet() }
    .sheet(isPresented: $showingJoinServer) { JoinServerSheet() }
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
  @State private var showingServerSettings = false
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
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("Server Settings", systemImage: "gearshape") { showingServerSettings = true }
      }
    }
    .sheet(isPresented: $showingServerSettings) { ServerManagementSheet(server: server) }
    .task { await model.openServer(server) }
  }

  @ViewBuilder private func channelLinks(_ channels: [PWChannel]) -> some View {
    ForEach(channels.sorted(by: { $0.position < $1.position })) { channel in
      if channel.kind == "voice" {
        Button {
          model.workspaceStartFragment = "server/\(channel.serverId)"
          model.selectedSection = .workspace
        } label: {
          Label(channel.name, systemImage: "speaker.wave.2")
        }
        .accessibilityHint("Opens this server in the full workspace for voice")
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

private struct CreateServerSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var description = ""
  @State private var busy = false

  var body: some View {
    NavigationStack {
      Form {
        Section("New server") {
          TextField("Server name", text: $name)
          TextField("Description", text: $description, axis: .vertical).lineLimit(2...5)
        }
      }
      .navigationTitle("Create Server")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Create") {
            Task {
              busy = true
              if await model.createServer(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                          description: description) { dismiss() }
              busy = false
            }
          }
          .disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
        }
      }
    }
    .frame(minWidth: 380, idealWidth: 480, minHeight: 270)
  }
}

private struct JoinServerSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var input = ""
  @State private var preview: JSONValue?
  @State private var busy = false

  private var code: String {
    let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if let url = URL(string: value), let fragment = url.fragment,
      fragment.hasPrefix("wire/") { return String(fragment.dropFirst(5)) }
    if value.hasPrefix("#wire/") { return String(value.dropFirst(6)) }
    return value
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Invite") {
          TextField("Paste an invite code or link", text: $input)
            .autocorrectionDisabled()
            .onSubmit { Task { await loadPreview() } }
          Button("Preview invite") { Task { await loadPreview() } }
            .disabled(busy || code.isEmpty)
        }
        if let data = preview?.objectValue, let server = data["server"]?.objectValue {
          Section("Server") {
            Text(server["name"]?.stringValue ?? "Server").font(.headline)
            if let description = server["description"]?.stringValue, !description.isEmpty {
              Text(description).foregroundStyle(.secondary)
            }
            if let count = server["member_count"]?.intValue {
              Label("\(count) members", systemImage: "person.2")
            }
            if data["valid"]?.boolValue == true {
              Button("Join Server") { Task { await join() } }
                .buttonStyle(.borderedProminent)
                .disabled(busy)
            } else {
              Label("This invite has expired or been revoked.", systemImage: "link.badge.plus")
                .foregroundStyle(.secondary)
            }
          }
        }
      }
      .navigationTitle("Join Server")
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
    }
    .frame(minWidth: 380, idealWidth: 480, minHeight: 290)
    .onChange(of: input) { _, _ in preview = nil }
  }

  private func loadPreview() async {
    guard !code.isEmpty else { return }
    busy = true
    preview = await model.invitePreview(code: code)
    busy = false
  }

  private func join() async {
    busy = true
    if await model.joinInvite(code: code) { dismiss() }
    busy = false
  }
}

private struct ServerManagementSheet: View {
  private enum Page: String, CaseIterable, Identifiable {
    case overview, channels, invites, members, profile
    var id: Self { self }
    var title: String { rawValue.capitalized }
    var symbol: String {
      switch self {
      case .overview: "paintbrush.pointed"
      case .channels: "number"
      case .invites: "link"
      case .members: "person.2"
      case .profile: "person.crop.circle"
      }
    }
  }

  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let server: PWServer
  @State private var name: String
  @State private var description: String
  @State private var iconURL: String
  @State private var bannerURL: String
  @State private var accentColor: String
  @State private var welcomeMessage: String
  @State private var nickname = ""
  @State private var memberBio = ""
  @State private var memberAvatarURL = ""
  @State private var categoryName = ""
  @State private var channelName = ""
  @State private var channelKind = "text"
  @State private var categoryID: PlainwireID?
  @State private var invites: [PWInvite] = []
  @State private var editingChannel: PWChannel?
  @State private var pickingImage = false
  @State private var imageField = "icon"
  @State private var busy = false
  @State private var notice = ""
  @State private var page: Page = .overview

  init(server: PWServer) {
    self.server = server
    _name = State(initialValue: server.name)
    _description = State(initialValue: server.description)
    _iconURL = State(initialValue: server.iconURL)
    _bannerURL = State(initialValue: server.bannerURL)
    _accentColor = State(initialValue: server.accentColor)
    _welcomeMessage = State(initialValue: server.welcomeMessage)
  }

  private var detail: PWServerDetail? { model.serverDetails[server.id] }
  private func hasPermission(_ bit: Int64) -> Bool {
    server.ownerId == model.session?.user.id
      || (server.permissions & (1 << 30)) != 0
      || (server.permissions & bit) != 0
  }
  private var canManageServer: Bool { hasPermission(1 << 4) }
  private var canManageChannels: Bool { hasPermission(1 << 3) }
  private var canCreateInvites: Bool { hasPermission(1 << 8) }
  private var canManageInvites: Bool { hasPermission(1 << 11) }
  private var previewColor: Color {
    let value = accentColor.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard value.count == 6, let rgb = UInt64(value, radix: 16) else { return .accentColor }
    return Color(red: Double((rgb >> 16) & 255) / 255,
                 green: Double((rgb >> 8) & 255) / 255,
                 blue: Double(rgb & 255) / 255)
  }
  private var availablePages: [Page] {
    Page.allCases.filter { page in
      switch page {
      case .channels: canManageChannels
      case .invites: canCreateInvites || canManageInvites
      default: true
      }
    }
  }

  var body: some View {
    NavigationStack {
      Group {
#if os(macOS)
      HStack(spacing: 0) {
        pageSidebar
        Divider()
        settingsForm
      }
#else
      VStack(spacing: 0) {
        Picker("Settings section", selection: $page) {
          ForEach(availablePages) { item in
            Label(item.title, systemImage: item.symbol).tag(item)
          }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        Divider()
        settingsForm
      }
#endif
      }
      .navigationTitle("Server Settings")
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
    .modifier(ServerManagementFrameModifier())
    .task {
      if detail == nil { await model.reloadServer(server.id) }
      if let me = detail?.members.first(where: { $0.user.id == model.session?.user.id }) {
        nickname = me.nickname ?? ""
        memberBio = me.serverBio ?? ""
        memberAvatarURL = me.serverAvatarURL ?? ""
      }
      if canManageInvites { invites = await model.invites(serverID: server.id) }
    }
    .sheet(item: $editingChannel) { channel in ChannelEditorSheet(channel: channel) }
    .fileImporter(isPresented: $pickingImage, allowedContentTypes: [.image]) { result in
      guard case .success(let url) = result else { return }
      let field = imageField
      Task {
        if let upload = await model.upload(url) {
          switch field {
          case "icon": iconURL = upload.url
          case "banner": bannerURL = upload.url
          default: memberAvatarURL = upload.url
          }
        }
      }
    }
  }

#if os(macOS)
  private var pageSidebar: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("SERVER SETTINGS")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.top, 18)
        .padding(.bottom, 8)
      ForEach(availablePages) { item in
        Button { page = item; notice = "" } label: {
          Label(item.title, systemImage: item.symbol)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(page == item ? Color.accentColor.opacity(0.14) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 9))
        .fontWeight(page == item ? .semibold : .regular)
      }
      Spacer(minLength: 0)
      Text(server.name).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        .padding(12)
    }
    .padding(.horizontal, 10)
    .frame(width: 190)
    .background(.bar)
  }
#endif

  private var settingsForm: some View {
    Form {
      if !notice.isEmpty {
        Section { Label(notice, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
      }
      switch page {
      case .overview:
        overviewSections
      case .channels:
        channelSections
      case .invites:
        inviteSections
      case .members:
        memberSections
      case .profile:
        profileSections
      }
    }
    .formStyle(.grouped)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ViewBuilder private var overviewSections: some View {
    Section {
      ZStack(alignment: .bottomLeading) {
        LinearGradient(colors: [previewColor, previewColor.opacity(0.55), .black.opacity(0.75)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
        CachedRemoteImage(url: model.mediaURL(bannerURL), pixelSize: 1200) { phase in
          if case .success(let image) = phase {
            image.resizable().scaledToFill()
          } else {
            Color.clear
          }
        }
        .frame(height: 144)
        .clipped()
        LinearGradient(colors: [.clear, .black.opacity(0.55)],
                       startPoint: .center, endPoint: .bottom)
        HStack(spacing: 14) {
          RemoteAvatar(url: model.mediaURL(iconURL), fallback: String(name.prefix(1)),
                       size: 58, cornerRadius: 15)
          VStack(alignment: .leading, spacing: 5) {
            Text(name).font(.title3.weight(.semibold)).lineLimit(2)
            Label("\(server.memberCount) members", systemImage: "person.2")
              .font(.caption)
          }
          Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(16)
      }
      .frame(height: 144)
      .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
      if !description.isEmpty { Text(description).foregroundStyle(.secondary) }
      if !welcomeMessage.isEmpty { Text(welcomeMessage).font(.callout) }
    }
    if canManageServer {
      Section("Appearance") {
        TextField("Server name", text: $name)
        TextField("Description", text: $description, axis: .vertical).lineLimit(2...4)
        TextField("Welcome message", text: $welcomeMessage, axis: .vertical).lineLimit(2...5)
        HStack {
          Text("Accent color")
          Spacer(minLength: 12)
          Circle().fill(previewColor).frame(width: 18, height: 18)
            .overlay(Circle().stroke(.primary.opacity(0.14), lineWidth: 1))
          TextField("#5865f2", text: $accentColor)
            .multilineTextAlignment(.trailing).frame(width: 110)
        }
        Button { imageField = "icon"; pickingImage = true } label: {
          Label("Choose icon", systemImage: "photo.circle")
        }
        Button { imageField = "banner"; pickingImage = true } label: {
          Label("Choose banner", systemImage: "photo.on.rectangle")
        }
      }
      Section {
        Button("Save server changes") { Task { await saveServer() } }
          .buttonStyle(.borderedProminent)
          .disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    Section("More tools") {
      Button {
        model.workspaceStartFragment = "server/\(server.id)"
        model.selectedSection = .workspace
        dismiss()
      } label: {
        Label("Open server in full workspace", systemImage: "square.grid.2x2")
      }
    }
  }

  @ViewBuilder private var channelSections: some View {
    Section("Channels") {
      if let detail, !detail.channels.isEmpty {
        ForEach(detail.channels.sorted(by: { $0.position < $1.position })) { channel in
          Button { editingChannel = channel } label: {
            HStack {
              Label(channel.name, systemImage: channel.kind == "voice" ? "speaker.wave.2" : "number")
              Spacer()
              Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
          }
          .buttonStyle(.plain)
        }
      } else {
        Text("No channels yet.").foregroundStyle(.secondary)
      }
    }
    Section("Create category") {
      TextField("Category name", text: $categoryName)
      Button("Create category") { Task { await createCategory() } }
        .disabled(busy || categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    Section("Create channel") {
      TextField("Channel name", text: $channelName)
      Picker("Type", selection: $channelKind) {
        Text("Text").tag("text")
        Text("Voice").tag("voice")
      }
      Picker("Category", selection: $categoryID) {
        Text("No category").tag(nil as PlainwireID?)
        ForEach(detail?.categories ?? []) { category in
          Text(category.name).tag(Optional(category.id))
        }
      }
      Button("Create channel") { Task { await createChannel() } }
        .buttonStyle(.borderedProminent)
        .disabled(busy || channelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
  }

  @ViewBuilder private var inviteSections: some View {
    Section("Invite links") {
      if invites.allSatisfy({ $0.revoked == true }) {
        Text("No active invites.").foregroundStyle(.secondary)
      }
      ForEach(invites.filter { $0.revoked != true }) { invite in
        HStack(spacing: 12) {
          VStack(alignment: .leading, spacing: 3) {
            Text(invite.code).font(.body.monospaced()).textSelection(.enabled).lineLimit(1)
            if let uses = invite.uses {
              Text("\(uses) uses").font(.caption).foregroundStyle(.secondary)
            }
          }
          Spacer(minLength: 4)
          if let url = URL(string: "https://plainwi.re/#wire/\(invite.code)") {
            ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
              .accessibilityLabel("Share invite")
          }
          if canManageInvites {
            Button(role: .destructive) { Task { await revoke(invite) } } label: {
              Image(systemName: "trash")
            }
            .accessibilityLabel("Revoke invite")
          }
        }
      }
    }
    if canCreateInvites {
      Section {
        Button("Create invite link") { Task { await createInvite() } }
          .buttonStyle(.borderedProminent)
          .disabled(busy)
      }
    }
  }

  @ViewBuilder private var memberSections: some View {
    Section("Members") {
      if let detail {
        ForEach(detail.members, id: \.user.id) { member in
          HStack(spacing: 12) {
            RemoteAvatar(url: model.mediaURL(member.serverAvatarURL ?? member.user.avatarURL),
                         fallback: String(member.user.displayName.prefix(1)), size: 36)
            VStack(alignment: .leading, spacing: 2) {
              Text((member.nickname?.isEmpty == false ? member.nickname : nil)
                   ?? member.user.displayName)
              Text("@\(member.user.username)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(member.role.capitalized).font(.caption).foregroundStyle(.secondary)
          }
          .padding(.vertical, 3)
        }
      } else {
        ProgressView("Loading members…")
      }
    }
  }

  @ViewBuilder private var profileSections: some View {
    Section("My server profile") {
      Text("Your nickname, bio, and avatar here can differ from your account profile.")
        .font(.callout).foregroundStyle(.secondary)
      TextField("Nickname", text: $nickname)
      TextField("Bio", text: $memberBio, axis: .vertical).lineLimit(2...4)
      Button { imageField = "member"; pickingImage = true } label: {
        Label("Choose server avatar", systemImage: "person.crop.circle.badge.plus")
      }
    }
    Section {
      Button("Save my server profile") { Task { await saveMemberProfile() } }
        .buttonStyle(.borderedProminent)
        .disabled(busy)
    }
  }

  private func saveServer() async {
    busy = true
    let saved = await model.saveServer(id: server.id, fields: [
      "name": name, "description": description, "icon_url": iconURL,
      "banner_url": bannerURL, "accent_color": accentColor,
      "welcome_message": welcomeMessage,
    ])
    if saved { notice = "Server updated." }
    busy = false
  }

  private func saveMemberProfile() async {
    busy = true
    if await model.saveMemberProfile(serverID: server.id, nickname: nickname,
                                     bio: memberBio, avatarURL: memberAvatarURL) {
      notice = "Server profile updated."
    }
    busy = false
  }

  private func createCategory() async {
    busy = true
    if await model.createCategory(serverID: server.id,
                                  name: categoryName.trimmingCharacters(in: .whitespacesAndNewlines)) {
      categoryName = ""
      notice = "Category created."
    }
    busy = false
  }

  private func createChannel() async {
    busy = true
    if await model.createChannel(serverID: server.id,
                                 name: channelName.trimmingCharacters(in: .whitespacesAndNewlines),
                                 kind: channelKind, categoryID: categoryID) {
      channelName = ""
      notice = "Channel created."
    }
    busy = false
  }

  private func createInvite() async {
    busy = true
    if let invite = await model.createInvite(serverID: server.id, channelID: nil) {
      invites.insert(invite, at: 0)
      notice = "Invite link ready to share."
    }
    busy = false
  }

  private func revoke(_ invite: PWInvite) async {
    if await model.revokeInvite(serverID: server.id, code: invite.code) {
      invites.removeAll { $0.code == invite.code }
      notice = "Invite revoked."
    }
  }
}

private struct ServerManagementFrameModifier: ViewModifier {
  @ViewBuilder func body(content: Content) -> some View {
    #if os(macOS)
      content.frame(minWidth: 740, idealWidth: 820, minHeight: 610, idealHeight: 700)
    #else
      content
    #endif
  }
}

private struct ChannelEditorSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let channel: PWChannel
  @State private var name: String
  @State private var topic: String
  @State private var busy = false

  init(channel: PWChannel) {
    self.channel = channel
    _name = State(initialValue: channel.name)
    _topic = State(initialValue: channel.topic)
  }

  var body: some View {
    NavigationStack {
      Form {
        TextField("Channel name", text: $name)
        TextField("Topic", text: $topic, axis: .vertical).lineLimit(2...5)
      }
      .navigationTitle("Channel Settings")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            Task {
              busy = true
              if await model.saveChannel(channel, name: name, topic: topic) { dismiss() }
              busy = false
            }
          }
          .disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
    .frame(minWidth: 380, idealWidth: 480, minHeight: 270)
  }
}
