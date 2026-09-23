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

  @State private var draft = ""
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
        if showsInlineMembers, let conversationID = groupConversationID {
          Divider()
          ConversationMembersSidebar(conversationID: conversationID)
            .frame(width: 246)
        }
      }
    }
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _, width in
      availableWidth = width
    }
    .navigationTitle(model.selectedRoom?.title ?? "Conversation")
    .modifier(CompactToolbarTitleModifier())
    .toolbar {
      if !showsRoomHeader {
        ToolbarItem(placement: .primaryAction) { ConnectionToolbarItem() }
        if groupConversationID != nil {
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
      Task { await attach(urls, asSpoiler: spoiler) }
    }
    .sheet(item: $editingMessage) { message in editSheet(message) }
    .sheet(isPresented: $showsMemberSheet) {
      if let conversationID = groupConversationID {
        NavigationStack {
          ConversationMembersSidebar(conversationID: conversationID)
            .navigationTitle("Members")
            .toolbar {
              ToolbarItem(placement: .confirmationAction) {
                Button("Done") { showsMemberSheet = false }
              }
            }
        }
      }
    }
  }

  private var chatColumn: some View {
    VStack(spacing: 0) {
        if showsRoomHeader {
          ChatRoomHeader(
            showsMemberButton: groupConversationID != nil,
            membersVisible: showsInlineMembers,
            onToggleMembers: {
              if canShowInlineMembers { showsMembers.toggle() }
              else { showsMemberSheet = true }
            })
          Divider().opacity(0.32)
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
          text: $draft, uploading: uploading, replyingTo: replyingTo,
          onCancelReply: { replyingTo = nil },
          onAttach: { attachAsSpoiler = false; showImporter = true },
          onAttachSpoiler: { attachAsSpoiler = true; showImporter = true }, onSend: send
        )
        .focused($composerFocused)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    guard groupConversationID != nil, availableWidth >= 660 else { return false }
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
            ForEach(rows) { presentation in
              MessageRow(presentation: presentation)
                .id(presentation.id)
                .onAppear {
                  guard presentation.id == rows.first?.id else { return }
                  let anchorID = presentation.id
                  let previousCount = rows.count
                  Task { @MainActor in
                    await model.loadOlderMessages()
                    guard model.messagePresentationsForSelectedRoom().count > previousCount else {
                      return
                    }
                    await Task.yield()
                    proxy.scrollTo(anchorID, anchor: .top)
                  }
                }
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
          if value { unreadWhileScrolled = 0 }
        }
        .onChange(of: model.selectedRoom?.identifier) { _, _ in
          nearBottom = true
          unreadWhileScrolled = 0
          Task { @MainActor in
            await Task.yield()
            if let id = model.messagePresentationsForSelectedRoom().last?.id {
              proxy.scrollTo(id, anchor: .bottom)
            }
          }
        }
        .onChange(of: model.messagePresentationsForSelectedRoom().last?.id) { old, new in
          guard new != old, let new,
            let last = model.messagePresentationsForSelectedRoom().last?.message
          else { return }

          if last.userId == model.session?.user.id || nearBottom {
            unreadWhileScrolled = 0
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

    if message.userId == model.session?.user.id {
      Divider()
      Button {
        editText = message.body
        editingMessage = message
      } label: {
        Label("Edit", systemImage: "pencil")
      }
      Button(role: .destructive) {
        Task { await model.deleteMessage(message) }
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
              await model.editMessage(message, body: editText)
              editingMessage = nil
            }
          }
          .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
    .frame(minWidth: 390, minHeight: 250)
  }

  private func send() {
    let outgoing = draft
    guard !outgoing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    draft = ""
    let replyID = replyingTo?.id
    replyingTo = nil
    Task {
      if !(await model.sendMessage(outgoing, replyTo: replyID)) {
        draft = outgoing
      }
    }
  }

  private func attach(_ urls: [URL], asSpoiler: Bool) async {
    uploading = true
    defer { uploading = false }
    for url in urls {
      if let upload = await model.upload(url) {
        if !draft.isEmpty, !draft.hasSuffix(" ") { draft += " " }
        let markdown = model.attachmentMarkdown(for: upload)
        draft += asSpoiler ? "||\(markdown)||" : markdown
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
        ProgressView("Loading members…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
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
