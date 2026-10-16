import SwiftUI

struct ConversationListView: View {
  @Environment(AppModel.self) private var model
  let compactNavigation: Bool
  @State private var search = ""
  @State private var filter: ConversationFilter = .all
  @State private var leaving: PWConversation?
  private enum ConversationFilter: String, CaseIterable { case all = "All", unread = "Unread", requests = "Requests" }

  var body: some View {
    VStack(spacing: 0) {
      browserHeader
      Divider()
      if let warning = model.syncWarning {
        HStack(alignment: .top, spacing: 9) {
          Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
          Text(warning).font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
      }
      List {
        ForEach(filteredConversations) { conversation in
          conversationDestination(conversation)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
            .contextMenu {
              Button(model.isConversationMuted(conversation) ? "Unmute on This Device" : "Mute on This Device",
                systemImage: model.isConversationMuted(conversation) ? "bell" : "bell.slash") {
                model.setConversationMuted(conversation, muted: !model.isConversationMuted(conversation))
              }
              Button("Mark Read", systemImage: "checkmark") {
                Task { await model.readConversation(conversation) }
              }
              Button("Close Conversation", systemImage: "archivebox") {
                Task { _ = await model.conversationAction(conversation, action: .close) }
              }
              if conversation.memberCount > 2 {
                Button("Leave Conversation", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { leaving = conversation }
              }
            }
        }
      }
      .modifier(ConversationListStyleModifier())
      .scrollContentBackground(.hidden)
      .frame(minHeight: 0, maxHeight: .infinity)
      .overlay {
        if filteredConversations.isEmpty {
          ContentUnavailableView(emptyTitle, systemImage: search.isEmpty ? "message" : "magnifyingglass",
            description: Text(search.isEmpty ? "New conversations will appear here." : "Try another name or message."))
        }
      }
      .clipped()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.canvas)
    .clipped()
    #if os(iOS)
    .navigationTitle("Messages")
    .searchable(text: $search, prompt: "Filter conversations")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button { model.showNewConversation = true } label: { Image(systemName: "square.and.pencil") }
          .help("New conversation").accessibilityLabel("New conversation")
      }
      ToolbarItem(placement: .primaryAction) {
        Button { model.showMessageSearch = true } label: { Image(systemName: "magnifyingglass") }
          .help("Search all messages").accessibilityLabel("Search all messages")
      }
    }
    #endif
    .confirmationDialog("Leave this conversation?", isPresented: Binding(
      get: { leaving != nil }, set: { if !$0 { leaving = nil } }
    ), titleVisibility: .visible) {
      if let conversation = leaving {
        Button("Leave", role: .destructive) { Task { _ = await model.conversationAction(conversation, action: .leave) }; leaving = nil }
      }
    }
    .refreshable { await model.refresh() }
  }

  private var browserHeader: some View {
    VStack(alignment: .leading, spacing: 14) {
      #if os(macOS)
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Conversations").font(.title3.weight(.semibold))
          Text("\(filteredConversations.count) \(filter == .requests ? "requests" : "conversations")")
            .font(.caption).foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        Button { model.showMessageSearch = true } label: { Image(systemName: "text.magnifyingglass").frame(width: 18, height: 18) }
          .adaptiveGlassButton().controlSize(.small).help("Search all messages").accessibilityLabel("Search all messages")
        Button { model.showNewConversation = true } label: { Image(systemName: "square.and.pencil").frame(width: 18, height: 18) }
          .adaptiveGlassButton(prominent: true).controlSize(.small).help("New conversation").accessibilityLabel("New conversation")
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("plainwire.conversationHeader")
      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        TextField("Filter conversations", text: $search).textFieldStyle(.plain)
          .accessibilityLabel("Filter conversations")
        if !search.isEmpty {
          Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
            .buttonStyle(.plain).accessibilityLabel("Clear conversation filter")
        }
      }
      .padding(10).background(Color.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.primary.opacity(0.09), lineWidth: 1) }
      #endif
      Picker("Show conversations", selection: $filter) {
        ForEach(ConversationFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }.pickerStyle(.segmented).labelsHidden()
    }
    .padding(14)
  }

  private var emptyTitle: String {
    if !search.isEmpty { return "No matching conversations" }
    switch filter {
    case .all: return "No conversations yet"
    case .unread: return "All caught up"
    case .requests: return "No message requests"
    }
  }

  private var filteredConversations: [PWConversation] {
    let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let source = model.conversations.filter {
      switch filter {
      case .all: $0.requestState != "pending"
      case .unread: $0.unread > 0 && $0.requestState != "pending"
      case .requests: $0.requestState == "pending"
      }
    }
    guard !query.isEmpty else { return source }
    return source.filter { conversation in
      model.conversationDisplayName(conversation).lowercased().contains(query)
        || conversation.peerUsername.lowercased().contains(query)
        || conversation.lastBody.lowercased().contains(query)
    }
  }

  @ViewBuilder private func conversationDestination(_ conversation: PWConversation) -> some View {
    if compactNavigation {
      NavigationLink {
        ChatView(initialConversation: conversation)
      } label: {
        ConversationRow(conversation: conversation)
      }
    } else {
      Button {
        Task { await model.openConversation(conversation) }
      } label: {
        ConversationRow(conversation: conversation)
      }
      .buttonStyle(.plain)
    }
  }
}

private struct ConversationRow: View {
  @Environment(AppModel.self) private var model
  let conversation: PWConversation
  @State private var hovering = false

  var body: some View {
    HStack(alignment: .top, spacing: 11) {
      RemoteAvatar(
          url: model.mediaURL(model.conversationDisplayAvatar(conversation)),
          fallback: String(model.conversationDisplayName(conversation).prefix(1)), size: 40)

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          Text(model.conversationDisplayName(conversation))
            .font(.body.weight(conversation.unread > 0 ? .semibold : .medium))
            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1)
          if conversation.unread > 0 {
            Text(conversation.unread > 99 ? "99+" : "\(conversation.unread)")
              .font(.caption2.bold()).foregroundStyle(.white).monospacedDigit()
              .padding(.horizontal, 6).padding(.vertical, 2).background(Color.accentColor, in: Capsule())
              .fixedSize()
          }
        }

        Text(preview).font(.callout).foregroundStyle(.secondary).lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)
        HStack(spacing: 6) {
          if model.calls.activeCalls[conversation.id] != nil {
            Image(systemName: "phone.fill").foregroundStyle(.green)
              .accessibilityLabel("Call in progress")
          }
          if model.drafts["direct:\(conversation.id)"]?.isEmpty == false {
            Text("Draft").foregroundStyle(.orange)
            Text("·").foregroundStyle(.tertiary)
          }
          if conversation.updatedAt > 0 { Text(conversationDate).lineLimit(1) }
          Spacer(minLength: 0)
          if model.isConversationMuted(conversation) { Image(systemName: "bell.slash").accessibilityLabel("Muted on this device") }
        }.font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 12).padding(.vertical, 11).frame(maxWidth: .infinity, alignment: .leading)
    .background(selected ? Color.accentColor.opacity(0.13) : Color.primary.opacity(hovering ? 0.04 : 0),
      in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(selected ? Color.accentColor.opacity(0.22) : .clear, lineWidth: 1)
    }
    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .onHover { hovering = $0 }
  }

  private var selected: Bool { model.selectedRoom?.scope == "direct" && model.selectedRoom?.roomID == conversation.id }

  private var preview: AttributedString {
    let parsed = PWMessageText.parseBody(String(conversation.lastBody.prefix(400)))
    let text = PWMessageText.redactingSpoilers(parsed.text)
    if !text.isEmpty {
      return (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
    if let attachment = parsed.attachments.first {
      if attachment.isSpoiler { return AttributedString("Spoiler attachment") }
      switch attachment.kind {
      case .image: return AttributedString("Photo or GIF")
      case .video: return AttributedString("Video")
      case .voice: return AttributedString("Voice message")
      case .file: return AttributedString(attachment.name)
      }
    }
    return AttributedString(conversation.lastBody.isEmpty ? "No messages yet" : "Attachment")
  }

  private var conversationDate: String {
    let date = Date(timeIntervalSince1970: TimeInterval(conversation.updatedAt) / 1000)
    if Calendar.current.isDateInToday(date) {
      return date.formatted(date: .omitted, time: .shortened)
    }
    if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
    if Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year) {
      return date.formatted(.dateTime.month(.abbreviated).day())
    }
    return date.formatted(date: .abbreviated, time: .omitted)
  }
}

private struct ConversationListStyleModifier: ViewModifier {
  @ViewBuilder func body(content: Content) -> some View {
    #if os(macOS)
      content.listStyle(.plain)
    #else
      content.listStyle(.insetGrouped)
    #endif
  }
}
