import SwiftUI

struct ConversationListView: View {
  @Environment(AppModel.self) private var model
  let compactNavigation: Bool
  @State private var search = ""

  var body: some View {
    List {
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
    .searchable(text: $search, prompt: "Search messages")
    .refreshable { await model.refresh() }
  }

  private var filteredConversations: [PWConversation] {
    let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !query.isEmpty else { return model.conversations }
    return model.conversations.filter { conversation in
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
          Text(conversation.lastBody.isEmpty ? "No messages yet" : conversation.lastBody)
            .font(.subheadline)
            .foregroundStyle(conversation.unread > 0 ? .primary : .secondary)
            .lineLimit(1)
          Spacer(minLength: 4)
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
