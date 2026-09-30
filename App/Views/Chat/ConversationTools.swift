import SwiftUI

struct NewConversationSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var conversationID: PlainwireID? = nil
  @State private var query = ""
  @State private var name = ""
  @State private var results: [PWUser] = []
  @State private var selected: [PWUser] = []
  @State private var searching = false
  @State private var saving = false
  @State private var searchError: String?

  private var existingIDs: Set<PlainwireID> {
    Set(conversationID.flatMap { model.conversationDetails[$0] }?.members.map(\.user.id) ?? [])
  }
  private var people: [PWUser] {
    let source = query.count >= 2 ? results : model.friends.filter { $0.status == "accepted" }.map(\.user)
    return source.filter { $0.id != model.session?.user.id && !existingIDs.contains($0.id) }
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        if conversationID == nil {
          TextField("Group name (optional)", text: $name)
            .textFieldStyle(.roundedBorder).padding(.horizontal).padding(.top)
        }
        TextField("Find a username", text: $query)
          .textFieldStyle(.roundedBorder).padding()
        if !selected.isEmpty {
          ScrollView(.horizontal) {
            HStack {
              ForEach(selected) { user in
                Button { selected.removeAll { $0.id == user.id } } label: {
                  Label(user.displayName, systemImage: "xmark.circle.fill")
                    .font(.caption).padding(8)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                }.buttonStyle(.plain)
              }
            }.padding(.horizontal)
          }.padding(.bottom, 8)
        }
        if searching { ProgressView().controlSize(.small).padding(8) }
        if let searchError { Text(searchError).font(.caption).foregroundStyle(.red).padding() }
        List(people) { user in
          Button {
            if selected.contains(where: { $0.id == user.id }) { selected.removeAll { $0.id == user.id } }
            else if selected.count < 49 { selected.append(user) }
          } label: {
            HStack(spacing: 10) {
              RemoteAvatar(url: model.mediaURL(user.avatarURL), fallback: String(user.displayName.prefix(1)), size: 36)
              VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName).foregroundStyle(.primary)
                Text("@\(user.username)").font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Image(systemName: selected.contains(where: { $0.id == user.id }) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(Color.accentColor)
            }.contentShape(Rectangle())
          }.buttonStyle(.plain)
        }
        .overlay {
          if people.isEmpty && !searching {
            ContentUnavailableView("Find someone to chat with", systemImage: "person.crop.circle.badge.plus",
              description: Text("Enter at least two characters to search Plainwire."))
          }
        }
      }
      .navigationTitle(conversationID == nil ? "New Conversation" : "Add Members")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button(saving ? "Saving…" : conversationID == nil ? "Create" : "Add") {
            saving = true
            Task {
              let success: Bool
              if let conversationID { success = await model.addMembers(id: conversationID, users: selected) }
              else { success = await model.createConversation(users: selected, name: name.trimmingCharacters(in: .whitespacesAndNewlines)) }
              saving = false
              if success { dismiss() }
            }
          }.disabled(selected.isEmpty || saving)
        }
      }
      .task(id: query) {
        results = []
        searchError = nil
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else { searching = false; return }
        searching = true
        do {
          try await Task.sleep(for: .milliseconds(350))
          let users = await model.searchUsers(query)
          guard !Task.isCancelled else { return }
          results = users
          searching = false
        } catch { if !Task.isCancelled { searching = false; searchError = error.localizedDescription } }
      }
    }
    .adaptiveSheetSize(minWidth: 360, idealWidth: 480, minHeight: 480)
    .sheetErrorNotice()
    .interactiveDismissDisabled(saving)
  }
}

struct MessageSearchView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var results: [PWMessage] = []
  @State private var loading = false
  @State private var error: String?
  @State private var complete = true
  @State private var hasMore = false
  @State private var opening = false

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        TextField("Search all your messages", text: $query)
          .textFieldStyle(.roundedBorder).padding()
        if !complete {
          Text("Older messages are still being indexed. Results may be incomplete.")
            .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
        }
        if let error {
          Text(error).font(.callout).foregroundStyle(.red).padding()
        }
        List {
          ForEach(results) { message in
            Button {
              guard !opening else { return }
              opening = true
              Task {
                await model.openMessage(message)
                opening = false
                if model.messageJumpID == message.id { dismiss() }
              }
            } label: { MessageResultRow(message: message) }
              .buttonStyle(.plain).disabled(opening)
          }
          if hasMore {
            Button("Load More") { Task { await search(before: results.last?.id) } }.disabled(loading)
          }
        }
        .overlay {
          if results.isEmpty && !loading && error == nil {
            ContentUnavailableView(query.count < 2 ? "Find a message" : "No results", systemImage: "magnifyingglass",
              description: Text(query.count < 2 ? "Search across direct messages and server channels." : "Try another word or phrase."))
          }
        }
        if loading || opening { ProgressView(opening ? "Opening message…" : "Searching…").padding() }
      }
      .navigationTitle("Search Messages")
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
      .task(id: query) {
        results = []
        error = nil
        hasMore = false
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else { loading = false; return }
        do {
          try await Task.sleep(for: .milliseconds(450))
          await search()
        } catch {}
      }
    }
    .adaptiveSheetSize(minWidth: 360, idealWidth: 600, minHeight: 500)
    .sheetErrorNotice()
  }

  private func search(before: PlainwireID? = nil) async {
    let requestedQuery = query
    loading = true
    do {
      let response = try await model.searchMessages(requestedQuery, before: before)
      guard !Task.isCancelled, query == requestedQuery else { return }
      if before == nil { results = response.messages }
      else {
        let seen = Set(results.map(\.id))
        results.append(contentsOf: response.messages.filter { !seen.contains($0.id) })
      }
      complete = response.indexingComplete
      hasMore = response.messages.count == 30
      error = nil
    } catch {
      if !Task.isCancelled, query == requestedQuery { self.error = error.localizedDescription }
    }
    if !Task.isCancelled, query == requestedQuery { loading = false }
  }
}

struct MessageResultRow: View {
  @Environment(AppModel.self) private var model
  let message: PWMessage
  var body: some View {
    HStack(alignment: .top, spacing: 11) {
      RemoteAvatar(url: model.mediaURL(message.avatarURL), fallback: String(message.displayName.prefix(1)), size: 34)
      VStack(alignment: .leading, spacing: 5) {
        HStack {
          Text(message.displayName).font(.subheadline.weight(.semibold))
          Spacer()
          Text(Date(timeIntervalSince1970: Double(message.createdAt) / 1000), format: .dateTime.month().day().hour().minute())
            .font(.caption2).foregroundStyle(.secondary)
        }
        Text(PWMessageText.redactingSpoilers(message.body))
          .font(.body).lineLimit(4).foregroundStyle(.primary)
        Text(roomTitle).font(.caption).foregroundStyle(.secondary)
      }
    }.padding(.vertical, 7).contentShape(Rectangle())
  }
  private var roomTitle: String {
    if message.scope == "direct", let room = model.conversations.first(where: { $0.id == message.scopeId }) {
      return model.conversationDisplayName(room)
    }
    if let channel = model.serverDetails.values.flatMap(\.channels).first(where: { $0.id == message.scopeId }) {
      return "# \(channel.name)"
    }
    return message.scope == "direct" ? "Direct message" : "Server channel"
  }
}

struct PinnedMessagesSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let channelID: PlainwireID
  @State private var messages: [PWMessage] = []
  @State private var loading = true
  @State private var error: String?
  var body: some View {
    NavigationStack {
      List(messages) { message in
        Button {
          Task { await model.openMessage(message); if model.messageJumpID == message.id { dismiss() } }
        } label: { MessageResultRow(message: message) }.buttonStyle(.plain)
      }
      .overlay {
        if loading { ProgressView() }
        else if let error {
          ContentUnavailableView { Label("Unable to load pins", systemImage: "pin.slash") }
          description: { Text(error) } actions: { Button("Try Again") { Task { await load() } } }
        } else if messages.isEmpty {
          ContentUnavailableView("No pinned messages", systemImage: "pin", description: Text("Pin useful messages from their context menu."))
        }
      }
      .navigationTitle("Pinned Messages")
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
      .task { await load() }
    }.adaptiveSheetSize(minWidth: 360, idealWidth: 560, minHeight: 440)
    .sheetErrorNotice()
  }
  private func load() async {
    loading = true
    error = nil
    do { messages = try await model.pinnedMessages(channelID: channelID) }
    catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    loading = false
  }
}

struct ForwardMessageSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let message: PWMessage
  @State private var search = ""
  @State private var sending = false
  private var rooms: [AppModel.Room] {
    let direct = model.conversations.filter { $0.requestState == "accepted" }.map {
      AppModel.Room(scope: "direct", roomID: $0.id, title: model.conversationDisplayName($0), avatarURL: model.conversationDisplayAvatar($0))
    }
    let channels = model.serverDetails.values.flatMap { detail in
      detail.channels.filter { $0.kind == "text" }.map {
        AppModel.Room(scope: "channel", roomID: $0.id, title: "# \($0.name)", subtitle: detail.server.name)
      }
    }
    return (direct + channels).filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.subtitle.localizedCaseInsensitiveContains(search) }
  }
  var body: some View {
    NavigationStack {
      List(rooms) { room in
        Button {
          sending = true
          Task { if await model.forward(message, to: room) { dismiss() }; sending = false }
        } label: {
          HStack {
            Image(systemName: room.scope == "direct" ? "bubble.left" : "number").foregroundStyle(.tint)
            VStack(alignment: .leading) {
              Text(room.title).foregroundStyle(.primary)
              if !room.subtitle.isEmpty { Text(room.subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Image(systemName: "arrowshape.turn.up.right").foregroundStyle(.secondary)
          }.padding(.vertical, 5)
        }.buttonStyle(.plain).disabled(sending)
      }
      .searchable(text: $search, prompt: "Choose a conversation or channel")
      .navigationTitle(sending ? "Forwarding…" : "Forward Message")
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(sending) } }
    }.adaptiveSheetSize(minWidth: 360, idealWidth: 460, minHeight: 420)
    .sheetErrorNotice()
    .interactiveDismissDisabled(sending)
    .task {
      for server in model.servers {
        guard !Task.isCancelled else { return }
        await model.ensureServerDetails(server.id)
      }
    }
  }
}

struct ConversationSettingsSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let conversation: PWConversation
  @State private var name = ""
  @State private var saving = false
  @State private var adding = false
  @State private var confirmLeave = false
  @State private var removingMember: PWUser?
  var body: some View {
    NavigationStack {
      Form {
        if conversation.ownerId == model.session?.user.id {
          Section("Group Name") {
            TextField("Name", text: $name)
            Button("Save Name") {
              saving = true
              Task { if await model.updateConversation(id: conversation.id, name: name) { dismiss() }; saving = false }
            }.disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }
        Section("Members") {
          ForEach(model.conversationDetails[conversation.id]?.members ?? [], id: \.user.id) { member in
            HStack {
              Text(member.nickname.isEmpty ? member.user.displayName : member.nickname)
              Spacer()
              Text(member.groupRole.capitalized).font(.caption).foregroundStyle(.secondary)
              if conversation.ownerId == model.session?.user.id, member.user.id != conversation.ownerId {
                Menu {
                  Button(member.groupRole == "moderator" ? "Remove Moderator Role" : "Make Moderator") {
                    Task { _ = await model.setMemberRole(conversationID: conversation.id, userID: member.user.id, moderator: member.groupRole != "moderator") }
                  }
                  Button("Remove Member", role: .destructive) { removingMember = member.user }
                } label: { Image(systemName: "ellipsis.circle") }
              }
            }
          }
          Button("Add Members", systemImage: "person.badge.plus") { adding = true }
        }
        Section {
          Button("Leave Conversation", role: .destructive) { confirmLeave = true }
        }
      }
      .navigationTitle("Conversation Settings")
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
      .task { name = conversation.name; await model.loadConversationDetails(conversation.id) }
      .confirmationDialog("Remove this member?", isPresented: Binding(
        get: { removingMember != nil }, set: { if !$0 { removingMember = nil } }
      ), titleVisibility: .visible) {
        if let member = removingMember {
          Button("Remove \(member.displayName)", role: .destructive) {
            Task { _ = await model.removeMember(conversationID: conversation.id, userID: member.id) }
            removingMember = nil
          }
        }
      }
      .sheet(isPresented: $adding) { NewConversationSheet(conversationID: conversation.id) }
      .confirmationDialog("Leave this conversation?", isPresented: $confirmLeave, titleVisibility: .visible) {
        Button("Leave", role: .destructive) {
          Task { if await model.conversationAction(conversation, action: .leave) { dismiss() } }
        }
      }
    }.adaptiveSheetSize(minWidth: 360, idealWidth: 480, minHeight: 420)
    .sheetErrorNotice()
  }
}

struct ServerMembersSidebar: View {
  @Environment(AppModel.self) private var model
  let serverID: PlainwireID
  @State private var selectedUser: PWUser?
  private var members: [PWServerMember] {
    (model.serverDetails[serverID]?.members ?? []).sorted {
      let leftOnline = model.livePresenceStatus(for: $0.user) == "online"
      let rightOnline = model.livePresenceStatus(for: $1.user) == "online"
      if leftOnline != rightOnline { return leftOnline }
      return name($0).localizedCaseInsensitiveCompare(name($1)) == .orderedAscending
    }
  }
  var body: some View {
    VStack(spacing: 0) {
      HStack { Text("Members").font(.headline); Spacer(); Text("\(members.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
        .padding(16)
      Divider()
      ScrollView {
        LazyVStack(spacing: 2) {
          ForEach(members, id: \.user.id) { member in
            Button { selectedUser = member.user } label: {
              HStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                  RemoteAvatar(url: model.mediaURL(member.serverAvatarURL.flatMap { $0.isEmpty ? nil : $0 } ?? member.user.avatarURL),
                    fallback: String(name(member).prefix(1)), size: 34)
                  Circle().fill(presenceColor(member.user)).frame(width: 10, height: 10)
                    .overlay(Circle().stroke(.background, lineWidth: 2)).offset(x: 2, y: 2)
                }
                VStack(alignment: .leading, spacing: 2) {
                  Text(name(member)).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                  Text(member.roleNames.flatMap { $0.isEmpty ? nil : $0 } ?? member.role.capitalized)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
              }.padding(.horizontal, 12).padding(.vertical, 7).contentShape(Rectangle())
            }.buttonStyle(.plain)
          }
        }.padding(6)
      }
    }.background(.bar)
    .sheet(item: $selectedUser) { PersonProfileSheet(userID: $0.id) }
  }
  private func name(_ member: PWServerMember) -> String {
    member.nickname.flatMap { $0.isEmpty ? nil : $0 } ?? member.user.displayName
  }
  private func presenceColor(_ user: PWUser) -> Color {
    switch model.livePresenceStatus(for: user) {
    case "online": .green
    case "busy": .red
    case "away": .orange
    default: .secondary.opacity(0.5)
    }
  }
}
