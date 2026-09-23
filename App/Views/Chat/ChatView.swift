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
      VStack(spacing: 0) {
        if showsRoomHeader {
          ChatRoomHeader()
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
    }
    .navigationTitle(model.selectedRoom?.title ?? "Conversation")
    .modifier(CompactToolbarTitleModifier())
    .toolbar {
      if !showsRoomHeader {
        ToolbarItem(placement: .primaryAction) { ConnectionToolbarItem() }
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
    .fileImporter(
      isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true
    ) { result in
      guard case .success(let urls) = result, !urls.isEmpty else { return }
      let spoiler = attachAsSpoiler
      Task { await attach(urls, asSpoiler: spoiler) }
    }
    .sheet(item: $editingMessage) { message in editSheet(message) }
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
      ConnectionStatusView()
        .frame(maxWidth: 150)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(.bar)
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
