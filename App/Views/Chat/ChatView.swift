import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

struct ChatView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
  #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  #endif
  @AppStorage(AppPreferenceKeys.reduceInterfaceMotion) private var reduceInterfaceMotion = false

  let initialConversation: PWConversation?
  let initialChannel: PWChannel?
  let initialServer: PWServer?

  @State private var sending = false
  @State private var voiceNoteRoom: AppModel.Room?
  @State private var importerRoom: AppModel.Room?
  @State private var forwardingMessage: PWMessage?
  @State private var showingPins = false
  @State private var showingConversationSettings = false
  @State private var deletingMessage: PWMessage?
  @State private var savingEdit = false

  private var draft: String {
    get { model.selectedRoom.flatMap { model.drafts[$0.identifier] } ?? "" }
    nonmutating set { if let room = model.selectedRoom { model.drafts[room.identifier] = newValue } }
  }
  private var draftBinding: Binding<String> {
    let key = model.selectedRoom?.identifier ?? ""
    return Binding(get: { model.drafts[key] ?? "" }, set: { model.drafts[key] = $0 })
  }
  @State private var showImporter = false
  @State private var attachAsSpoiler = false
  @State private var uploading = false
  @State private var editingMessage: PWMessage?
  @State private var editText = ""
  @State private var replyingTo: PWMessage?
  @State private var nearBottom = true
  @State private var unreadWhileScrolled = 0
  @State private var showsMembers = true
  @State private var showsMemberSheet = false
  @State private var availableWidth: CGFloat = 0
  @FocusState private var composerFocused: Bool

  private let quickReactions = ["👍", "❤️", "😂", "🔥", "🎉", "😮", "😢", "👏"]

  init(
    initialConversation: PWConversation? = nil, initialChannel: PWChannel? = nil,
    initialServer: PWServer? = nil
  ) {
    self.initialConversation = initialConversation
    self.initialChannel = initialChannel
    self.initialServer = initialServer
  }

  var body: some View {
    ZStack {
      AppBackdrop()
      HStack(spacing: 0) {
        chatColumn
        if showsInlineMembers {
          Divider()
          roomMembers
            .frame(width: 246)
            .transition(shouldAnimate ? .move(edge: .trailing).combined(with: .opacity) : .opacity)
        }
      }
    }
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _, width in
      availableWidth = width
    }
    .navigationTitle(model.selectedRoom?.title ?? "Conversation")
    .modifier(CompactToolbarTitleModifier())
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Menu {
          Button("Search Messages", systemImage: "magnifyingglass") { model.showMessageSearch = true }
          if model.selectedRoom?.scope == "channel" {
            Button("Pinned Messages", systemImage: "pin") { showingPins = true }
          }
          if groupConversationID != nil {
            Button("Conversation Settings", systemImage: "gearshape") { showingConversationSettings = true }
          }
          if let room = model.selectedRoom {
            Button("Calling Controls", systemImage: "phone") {
              model.openWorkspace(fragment: "\(room.scope == "direct" ? "dm" : "channel")/\(room.roomID)")
            }
          }
        } label: { Image(systemName: "ellipsis.circle") }
      }
      if !showsRoomHeader {
        ToolbarItem(placement: .primaryAction) { ConnectionToolbarItem() }
        if hasRoomMembers {
          ToolbarItem(placement: .primaryAction) {
            Button { showsMemberSheet = true } label: {
              Label("Members", systemImage: "person.2")
            }
          }
        }
      }
    }
    .task(id: taskIdentity) {
      if let initialConversation {
        await model.openConversation(initialConversation)
      } else if let initialChannel {
        await model.openChannel(initialChannel, server: initialServer)
      } else {
        await model.loadSelectedRoom()
      }
    }
    .task(id: directConversationID) {
      if let directConversationID {
        await model.loadConversationDetails(directConversationID)
      }
    }
    .fileImporter(
      isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true
    ) { result in
      guard case .success(let urls) = result, !urls.isEmpty else { return }
      let spoiler = attachAsSpoiler
      guard let room = importerRoom else { return }
      Task { await attach(urls, asSpoiler: spoiler, room: room) }
    }
    .onAppear { if nearBottom { model.readingRoomID = model.selectedRoom?.identifier } }
    .onDisappear { model.readingRoomID = nil }
    .onChange(of: model.replyTarget?.id) { _, _ in
      if let message = model.replyTarget, message.scope == model.selectedRoom?.scope, message.scopeId == model.selectedRoom?.roomID {
        replyingTo = message
        composerFocused = true
      }
      model.replyTarget = nil
    }
    .onChange(of: model.selectedRoom?.identifier) { _, _ in
      replyingTo = nil
      unreadWhileScrolled = 0
      model.readingRoomID = model.selectedRoom?.identifier
    }
    .dropDestination(for: URL.self) { urls, _ in
      guard !uploading, let room = model.selectedRoom else { return false }
      Task { await attach(urls, asSpoiler: false, room: room) }
      return true
    }
    .sheet(item: $voiceNoteRoom) { VoiceNoteSheet(room: $0) }
    .sheet(item: $forwardingMessage) { ForwardMessageSheet(message: $0) }
    .sheet(isPresented: $showingPins) {
      if let room = model.selectedRoom, room.scope == "channel" { PinnedMessagesSheet(channelID: room.roomID) }
    }
    .sheet(isPresented: $showingConversationSettings) {
      if let room = model.selectedRoom, let conversation = model.conversations.first(where: { $0.id == room.roomID }) {
        ConversationSettingsSheet(conversation: conversation)
      }
    }
    .confirmationDialog("Delete this message?", isPresented: Binding(
      get: { deletingMessage != nil }, set: { if !$0 { deletingMessage = nil } }
    ), titleVisibility: .visible) {
      if let message = deletingMessage {
        Button("Delete", role: .destructive) { Task { await model.deleteMessage(message) }; deletingMessage = nil }
      }
    }
    .sheet(item: $editingMessage) { message in editSheet(message) }
    .sheet(isPresented: $showsMemberSheet) {
      NavigationStack {
        roomMembers
          .navigationTitle("Members")
          .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { showsMemberSheet = false } }
          }
      }
    }
  }

  private var chatColumn: some View {
    VStack(spacing: 0) {
        if showsRoomHeader {
          ChatRoomHeader(
            showsMemberButton: hasRoomMembers,
            membersVisible: showsInlineMembers,
            onToggleMembers: {
              if canShowInlineMembers { withAnimation(shouldAnimate ? .smooth(duration: 0.22) : nil) { showsMembers.toggle() } }
              else { showsMemberSheet = true }
            })
          Divider().opacity(0.32)
        }

        if let room = model.selectedRoom, model.contextRooms.contains(room.identifier) {
          HStack {
            Label("Viewing message history", systemImage: "clock.arrow.circlepath").font(.caption)
            Spacer()
            Button("Back to Latest") { Task { await model.returnToLive() } }.font(.caption.weight(.semibold))
          }.padding(12).background(.bar)
        }
        if let room = model.selectedRoom, room.scope == "direct",
          let conversation = model.conversations.first(where: { $0.id == room.roomID }),
          conversation.requestState == "pending" {
          HStack(spacing: 12) {
            Text("Message request").font(.subheadline.weight(.medium))
            Spacer()
            Button("Accept") { Task { _ = await model.conversationAction(conversation, action: .accept) } }
              .buttonStyle(.borderedProminent)
            Button("Decline", role: .destructive) { Task { _ = await model.conversationAction(conversation, action: .deny) } }
          }.padding(12).background(.bar)
        }
        messages

        if let typing = model.typingLabelForSelectedRoom() {
          HStack(spacing: 7) {
            TypingDots()
            Text(typing).font(.caption).foregroundStyle(.secondary)
            Spacer()
          }
          .padding(.horizontal, 20)
          .padding(.top, 4)
          .transition(.opacity)
        }

        ComposerBar(
          text: draftBinding, uploading: uploading, sending: sending, replyingTo: replyingTo,
          onCancelReply: { replyingTo = nil },
          onAttach: { importerRoom = model.selectedRoom; attachAsSpoiler = false; showImporter = true },
          onRecordVoiceNote: { voiceNoteRoom = model.selectedRoom },
          onAttachSpoiler: { importerRoom = model.selectedRoom; attachAsSpoiler = true; showImporter = true }, onSend: send
        )
        .focused($composerFocused)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var hasRoomMembers: Bool {
    groupConversationID != nil || (model.selectedRoom?.scope == "channel" && model.selectedServerID != nil)
  }
  @ViewBuilder private var roomMembers: some View {
    if let id = groupConversationID { ConversationMembersSidebar(conversationID: id) }
    else if let serverID = model.selectedServerID, model.selectedRoom?.scope == "channel" {
      ServerMembersSidebar(serverID: serverID)
    }
  }

  private var groupConversationID: PlainwireID? {
    guard let room = model.selectedRoom, let id = directConversationID else { return nil }
    let conversation = model.conversations.first(where: { $0.id == room.roomID })
      ?? initialConversation
    return (conversation?.memberCount ?? 0) > 2 ? id : nil
  }

  private var directConversationID: PlainwireID? {
    guard let room = model.selectedRoom, room.scope == "direct" else { return nil }
    return room.roomID
  }

  private var showsInlineMembers: Bool {
    showsMembers && canShowInlineMembers
  }

  private var canShowInlineMembers: Bool {
    guard hasRoomMembers, availableWidth >= 660 else { return false }
    #if os(iOS)
      return horizontalSizeClass != .compact
    #else
      return true
    #endif
  }

  private var showsRoomHeader: Bool {
    #if os(iOS)
      horizontalSizeClass != .compact
    #else
      true
    #endif
  }

  private var shouldAnimate: Bool {
    !accessibilityReduceMotion && !reduceInterfaceMotion
  }

  private var taskIdentity: String {
    initialConversation.map { "d:\($0.id)" } ?? initialChannel.map { "c:\($0.id)" }
      ?? model.selectedRoom?.identifier ?? "none"
  }

  private var messages: some View {
    ScrollViewReader { proxy in
      ZStack(alignment: .bottomTrailing) {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            let rows = model.messagePresentationsForSelectedRoom()
            if let room = model.selectedRoom, model.canLoadOlder(room) {
              Button {
                let anchor = rows.first?.id
                Task {
                  await model.loadOlderMessages()
                  guard model.selectedRoom?.identifier == room.identifier else { return }
                  await Task.yield()
                  if let anchor { proxy.scrollTo(anchor, anchor: .top) }
                }
              } label: {
                HStack { Spacer(); Label("Load Earlier Messages", systemImage: "arrow.up"); Spacer() }
                  .font(.caption).padding(.vertical, 12)
              }.buttonStyle(.plain).disabled(model.isLoadingOlder(room))
            }
            ForEach(rows) { presentation in
              MessageRow(presentation: presentation)
                .id(presentation.id)
                .contextMenu { messageMenu(presentation.message) }
            }
          }
          .scrollTargetLayout()
          .padding(.horizontal, 12)
          .padding(.top, 12)
          .padding(.bottom, 18)
          .frame(maxWidth: 980, alignment: .leading)
          .frame(maxWidth: .infinity)
        }
        .overlay {
          if let room = model.selectedRoom, rowsAreEmpty {
            if model.isLoadingRoom(room) { ProgressView("Loading messages…") }
            else if !model.hasLoadedRoom(room) {
              ContentUnavailableView { Label("Unable to load messages", systemImage: "wifi.exclamationmark") }
              description: { Text("Try reconnecting to this conversation.") }
              actions: { Button("Try Again") { Task { await model.loadSelectedRoom() } } }
            } else {
              ContentUnavailableView("Start the conversation", systemImage: "bubble.left.and.bubble.right",
                description: Text("Send a message or drop a file here."))
            }
          }
        }
        .defaultScrollAnchor(.bottom)
        .modifier(ChatScrollKeyboardModifier())
        .onScrollGeometryChange(for: Bool.self) { geometry in
          let scrollableHeight =
            geometry.contentSize.height
            + geometry.contentInsets.top + geometry.contentInsets.bottom
          let viewportBottom = geometry.contentOffset.y + geometry.containerSize.height
          return scrollableHeight - viewportBottom < 150
        } action: { _, value in
          nearBottom = value
          model.readingRoomID = value ? model.selectedRoom?.identifier : nil
          if value {
            unreadWhileScrolled = 0
            if let room = model.selectedRoom, !model.contextRooms.contains(room.identifier) { model.messageJumpID = nil }
            Task { await model.markRead(room: model.selectedRoom) }
          }
        }
        .task(id: model.messageJumpID) {
          let target = model.messageJumpID
          await Task.yield()
          guard !Task.isCancelled, target == model.messageJumpID else { return }
          if let target {
            model.readingRoomID = nil
            withAnimation(shouldAnimate ? .smooth(duration: 0.25) : nil) { proxy.scrollTo(target, anchor: .center) }
          }
        }
        .onChange(of: model.selectedRoom?.identifier) { _, _ in
          nearBottom = true
          unreadWhileScrolled = 0
          Task { @MainActor in
            await Task.yield()
            if let target = model.messageJumpID {
              proxy.scrollTo(target, anchor: .center)
            } else if let id = model.messagePresentationsForSelectedRoom().last?.id {
              proxy.scrollTo(id, anchor: .bottom)
            }
          }
        }
        .onChange(of: model.messagePresentationsForSelectedRoom().last?.id) { old, new in
          guard new != old, let new,
            let last = model.messagePresentationsForSelectedRoom().last?.message
          else { return }

          if model.messageJumpID != nil { return }
          if last.userId == model.session?.user.id || nearBottom {
            unreadWhileScrolled = 0
            Task { await model.markRead(room: model.selectedRoom) }
            withAnimation(shouldAnimate ? .snappy(duration: 0.18) : nil) {
              proxy.scrollTo(new, anchor: .bottom)
            }
          } else {
            unreadWhileScrolled += 1
          }
        }

        if unreadWhileScrolled > 0 {
          Button {
            if let id = model.messagePresentationsForSelectedRoom().last?.id {
              withAnimation(shouldAnimate ? .snappy(duration: 0.2) : nil) {
                proxy.scrollTo(id, anchor: .bottom)
              }
            }
            unreadWhileScrolled = 0
          } label: {
            Label(
              unreadWhileScrolled == 1 ? "1 new message" : "\(unreadWhileScrolled) new messages",
              systemImage: "arrow.down.circle.fill"
            )
            .font(.caption.weight(.semibold))
          }
          .adaptiveGlassButton()
          .controlSize(.small)
          .padding(.trailing, 16)
          .padding(.bottom, 12)
          .transition(shouldAnimate ? .move(edge: .bottom).combined(with: .opacity) : .opacity)
        }
      }
    }
  }

  @ViewBuilder private func messageMenu(_ message: PWMessage) -> some View {
    Button {
      copyMessage(message.body)
    } label: {
      Label("Copy message", systemImage: "doc.on.doc")
    }

    Button {
      replyingTo = message
      composerFocused = true
    } label: {
      Label("Reply", systemImage: "arrowshape.turn.up.left")
    }

    Menu {
      ForEach(quickReactions, id: \.self) { emoji in
        Button(emoji) { Task { await model.toggleReaction(emoji, on: message) } }
      }
    } label: {
      Label("React", systemImage: "face.smiling")
    }

    Button { forwardingMessage = message } label: { Label("Forward", systemImage: "arrowshape.turn.up.right") }
    Button { copyMessage("https://plainwi.re/#\(message.scope == "direct" ? "dm" : "channel")/\(message.scopeId)") }
      label: { Label("Copy Conversation Link", systemImage: "link") }
    if message.scope == "channel", model.canPinMessages {
      Button { Task { _ = await model.togglePin(message) } }
        label: { Label(message.pinned ? "Unpin" : "Pin", systemImage: message.pinned ? "pin.slash" : "pin") }
    }

    if message.userId == model.session?.user.id || (message.scope == "channel" && model.canPinMessages) {
      Divider()
      if message.userId == model.session?.user.id && message.forwardedFrom == nil && message.kind == "text" {
        Button { editText = message.body; editingMessage = message } label: { Label("Edit", systemImage: "pencil") }
      }
      Button(role: .destructive) {
        deletingMessage = message
      } label: {
        Label("Delete", systemImage: "trash")
      }
    }
  }

  private func copyMessage(_ text: String) {
    #if os(iOS)
      UIPasteboard.general.string = text
    #else
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
    #endif
  }

  private func editSheet(_ message: PWMessage) -> some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 14) {
        Text("Edit message")
          .font(.headline)
        TextField("Message", text: $editText, axis: .vertical)
          .textFieldStyle(.plain)
          .lineLimit(3...12)
          .padding(12)
          .background(
            .primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        Spacer(minLength: 0)
      }
      .padding(18)
      .navigationTitle("Edit Message")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { editingMessage = nil }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            Task {
              savingEdit = true
              if await model.editMessage(message, body: editText) { editingMessage = nil }
              savingEdit = false
            }
          }
          .disabled(savingEdit || editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
    .adaptiveSheetSize(minWidth: 390, minHeight: 250)
    .sheetErrorNotice()
  }

  private var rowsAreEmpty: Bool { model.messagePresentationsForSelectedRoom().isEmpty }

  private func send() {
    guard !sending, !uploading, let room = model.selectedRoom else { return }
    let outgoing = model.drafts[room.identifier] ?? ""
    guard !outgoing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    let reply = replyingTo
    let accountID = model.session?.user.id
    let csrf = model.session?.csrf
    model.drafts[room.identifier] = ""
    replyingTo = nil
    sending = true
    Task {
      let success = await model.sendMessage(outgoing, in: room, replyTo: reply?.id)
      if !success, model.sessionState == .ready, model.session?.user.id == accountID, model.session?.csrf == csrf {
        let newer = model.drafts[room.identifier] ?? ""
        model.drafts[room.identifier] = newer.isEmpty ? outgoing : outgoing + "\n" + newer
        if model.selectedRoom?.identifier == room.identifier { replyingTo = reply }
      }
      sending = false
    }
  }

  private func attach(_ urls: [URL], asSpoiler: Bool, room: AppModel.Room) async {
    guard !uploading else { return }
    uploading = true
    defer { uploading = false }
    for url in urls {
      if let upload = await model.upload(url), model.sessionState == .ready {
        var text = model.drafts[room.identifier] ?? ""
        if !text.isEmpty, !text.hasSuffix(" ") { text += " " }
        let markdown = model.attachmentMarkdown(for: upload)
        text += asSpoiler ? "||\(markdown)||" : markdown
        model.drafts[room.identifier] = text
      }
    }
  }

}

private struct ChatRoomHeader: View {
  @Environment(AppModel.self) private var model
  let showsMemberButton: Bool
  let membersVisible: Bool
  let onToggleMembers: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      if let room = model.selectedRoom {
        if !room.avatarURL.isEmpty {
          RemoteAvatar(
            url: model.mediaURL(room.avatarURL), fallback: String(room.title.prefix(1)), size: 38)
        } else {
          Image(systemName: room.scope == "channel" ? "number" : "bubble.left.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 38, height: 38)
            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(room.title).font(.headline).lineLimit(1)
          if !room.subtitle.isEmpty {
            Text(room.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
          }
        }
      }
      Spacer(minLength: 12)
      // Advanced room tools are also available from the compact toolbar.
      Button { model.showMessageSearch = true } label: { Image(systemName: "magnifyingglass") }
        .buttonStyle(.plain).help("Search messages").accessibilityLabel("Search messages")
      if let room = model.selectedRoom {
        Button { model.openWorkspace(fragment: "\(room.scope == "direct" ? "dm" : "channel")/\(room.roomID)") }
          label: { Image(systemName: "phone") }
          .buttonStyle(.plain).help("Open calling controls").accessibilityLabel("Open calling controls")
      }
      if showsMemberButton {
        Button(action: onToggleMembers) {
          Image(systemName: "person.2")
            .frame(width: 28, height: 28)
        }
        .adaptiveGlassButton()
        .help(membersVisible ? "Hide members" : "Show members")
        .accessibilityLabel(membersVisible ? "Hide members" : "Show members")
      }
      ConnectionStatusView()
        .frame(maxWidth: 150)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(.bar)
  }
}

private struct ConversationMembersSidebar: View {
  @Environment(AppModel.self) private var model
  let conversationID: PlainwireID
  @State private var selectedUser: PWUser?

  private var members: [PWConversationMember] {
    (model.conversationDetails[conversationID]?.members ?? []).sorted {
      let lhsOwner = $0.role == "owner" || $0.groupRole == "owner"
      let rhsOwner = $1.role == "owner" || $1.groupRole == "owner"
      if lhsOwner != rhsOwner { return lhsOwner }
      return $0.user.displayName.localizedCaseInsensitiveCompare($1.user.displayName) == .orderedAscending
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Members").font(.headline)
        Spacer()
        if !members.isEmpty {
          Text("\(members.count)").font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 16)
      Divider()
      if members.isEmpty {
        if model.loadingConversationDetails.contains(conversationID) {
          ProgressView("Loading members…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          ContentUnavailableView {
            Label("Members unavailable", systemImage: "person.2.slash")
          } actions: {
            Button("Try Again") { Task { await model.loadConversationDetails(conversationID) } }
          }
        }
      } else {
        ScrollView {
          LazyVStack(spacing: 2) {
            ForEach(members, id: \.user.id) { member in
              Button { selectedUser = member.user } label: {
                HStack(spacing: 10) {
                  ZStack(alignment: .bottomTrailing) {
                    RemoteAvatar(url: model.mediaURL(member.user.avatarURL),
                                 fallback: String(member.user.displayName.prefix(1)), size: 34)
                    presenceBadge(for: member.user)
                      .offset(x: 2, y: 2)
                  }
                  VStack(alignment: .leading, spacing: 2) {
                    Text(member.nickname.isEmpty ? member.user.displayName : member.nickname)
                      .font(.subheadline.weight(.medium)).lineLimit(1)
                    Text(member.groupRole == "owner" || member.role == "owner"
                         ? "Owner" : "@\(member.user.username)")
                      .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                  }
                  Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .accessibilityLabel("\(member.user.displayName), \(presenceLabel(for: member.user))")
            }
          }
          .padding(6)
        }
      }
    }
    .background(.bar)
    .sheet(item: $selectedUser) { user in PersonProfileSheet(userID: user.id) }
  }

  private func statusColor(for user: PWUser) -> Color {
    switch model.livePresenceStatus(for: user) {
    case "online": .green
    case "busy": .red
    case "away": .orange
    default: .secondary.opacity(0.65)
    }
  }

  @ViewBuilder private func presenceBadge(for user: PWUser) -> some View {
    if model.isUsingMacApp(user) {
      Image(systemName: "apple.logo")
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 18, height: 18)
        .background(.green, in: Circle())
        .overlay(Circle().stroke(.background, lineWidth: 2))
        .accessibilityHidden(true)
    } else {
      Circle().fill(statusColor(for: user))
        .frame(width: 11, height: 11)
        .overlay(Circle().stroke(.background, lineWidth: 2))
        .accessibilityHidden(true)
    }
  }

  private func presenceLabel(for user: PWUser) -> String {
    guard let status = model.livePresenceStatus(for: user) else { return "presence unavailable" }
    if model.isUsingMacApp(user) { return "online in the Mac app" }
    return status
  }
}

private struct ChatScrollKeyboardModifier: ViewModifier {
  @ViewBuilder func body(content: Content) -> some View {
    #if os(iOS)
      content.scrollDismissesKeyboard(.interactively)
    #else
      content
    #endif
  }
}

private struct ConnectionToolbarItem: View {
  @Environment(AppModel.self) private var model
  var body: some View {
    Image(systemName: symbol).foregroundStyle(color).help(label)
  }
  private var symbol: String {
    model.realtimeState == .connected ? "bolt.horizontal.circle.fill" : "bolt.slash.circle"
  }
  private var color: Color { model.realtimeState == .connected ? .green : .secondary }
  private var label: String {
    model.realtimeState == .connected ? "Realtime connected" : "Realtime reconnecting"
  }
}

private struct CompactToolbarTitleModifier: ViewModifier {
  @ViewBuilder func body(content: Content) -> some View {
    #if os(iOS)
      content.toolbarTitleDisplayMode(.inline)
    #else
      content
    #endif
  }
}

private struct TypingDots: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @AppStorage(AppPreferenceKeys.reduceInterfaceMotion) private var reduceInterfaceMotion = false
  @State private var phase = false

  var body: some View {
    HStack(spacing: 3) {
      ForEach(0..<3, id: \.self) { index in
        Circle().fill(.secondary).frame(width: 4, height: 4)
          .offset(y: phase ? CGFloat(index % 2) * -2 : 0)
      }
    }
    .task {
      guard !reduceMotion, !reduceInterfaceMotion else { return }
      withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { phase = true }
    }
  }
}
