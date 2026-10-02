import SwiftUI

struct ConversationListView: View {
  @Environment(AppModel.self) private var model
  let compactNavigation: Bool
  @State private var search = ""
  @State private var filter: ConversationFilter = .all
  @State private var leaving: PWConversation?
  private enum ConversationFilter: String, CaseIterable { case all = "All", unread = "Unread", requests = "Requests" }

  var body: some View {
    List {
      Section {
        Picker("Show", selection: $filter) {
          ForEach(ConversationFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.segmented).listRowSeparator(.hidden)
      }
      if let warning = model.syncWarning {
        Section {
          HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(warning).font(.caption).foregroundStyle(.secondary)
          }
          .padding(.vertical, 4)
        }
      }

      Section {
        ForEach(filteredConversations) { conversation in
          conversationDestination(conversation)
            .contextMenu {
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
    }
    .modifier(ConversationListStyleModifier())
    .overlay {
      if filteredConversations.isEmpty {
        ContentUnavailableView(
          search.isEmpty ? "No messages yet" : "No matching conversations",
          systemImage: search.isEmpty ? "message" : "magnifyingglass",
          description: Text(
            search.isEmpty ? "Start a conversation from Friends." : "Try another name or message."))
      }
    }
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
    .confirmationDialog("Leave this conversation?", isPresented: Binding(
      get: { leaving != nil }, set: { if !$0 { leaving = nil } }
    ), titleVisibility: .visible) {
      if let conversation = leaving {
        Button("Leave", role: .destructive) { Task { _ = await model.conversationAction(conversation, action: .leave) }; leaving = nil }
      }
    }
    .refreshable { await model.refresh() }
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
      .listRowBackground(
        model.selectedRoom?.scope == "direct" && model.selectedRoom?.roomID == conversation.id
          ? Color.accentColor.opacity(0.10) : Color.clear)
    }
  }
}

private struct ConversationRow: View {
  @Environment(AppModel.self) private var model
  let conversation: PWConversation

  var body: some View {
    HStack(spacing: 12) {
      ZStack(alignment: .bottomTrailing) {
        RemoteAvatar(
          url: model.mediaURL(model.conversationDisplayAvatar(conversation)),
          fallback: String(model.conversationDisplayName(conversation).prefix(1)), size: 46)
        if conversation.unread > 0 {
          Circle()
            .fill(Color.accentColor)
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(.background, lineWidth: 2))
        }
      }

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          Text(model.conversationDisplayName(conversation))
            .font(.body.weight(conversation.unread > 0 ? .semibold : .medium))
            .lineLimit(1)
          Spacer(minLength: 6)
          if conversation.updatedAt > 0 {
            Text(conversationDate)
              .font(.caption2)
              .foregroundStyle(.tertiary)
          }
        }

        HStack(spacing: 7) {
          if model.calls.activeCalls[conversation.id] != nil {
            Image(systemName: "phone.fill").foregroundStyle(.green)
              .accessibilityLabel("Call in progress")
          }
          Text(conversation.lastBody.isEmpty ? "No messages yet" : conversation.lastBody)
            .font(.subheadline)
            .foregroundStyle(conversation.unread > 0 ? .primary : .secondary)
            .lineLimit(1)
          Spacer(minLength: 4)
          if model.drafts["direct:\(conversation.id)"]?.isEmpty == false {
            Text("Draft").font(.caption2.weight(.medium)).foregroundStyle(.orange)
          }
          if conversation.muted { Image(systemName: "bell.slash").font(.caption2).foregroundStyle(.secondary) }
          if conversation.unread > 0 {
            Text("\(conversation.unread)")
              .font(.caption2.bold())
              .foregroundStyle(.white)
              .monospacedDigit()
              .padding(.horizontal, 7)
              .padding(.vertical, 3)
              .background(Color.accentColor, in: Capsule())
          }
        }
      }
    }
    .padding(.vertical, 5)
    .contentShape(Rectangle())
  }

  private var conversationDate: String {
    let date = Date(timeIntervalSince1970: TimeInterval(conversation.updatedAt) / 1000)
    if Calendar.current.isDateInToday(date) {
      return date.formatted(date: .omitted, time: .shortened)
    }
    if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
    return date.formatted(date: .abbreviated, time: .omitted)
  }
}

private struct ConversationListStyleModifier: ViewModifier {
  @ViewBuilder func body(content: Content) -> some View {
    #if os(macOS)
      content.listStyle(.sidebar)
    #else
      content.listStyle(.insetGrouped)
    #endif
  }
}
