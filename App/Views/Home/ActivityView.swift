import SwiftUI

struct ActivityView: View {
  @Environment(AppModel.self) private var model
  @State private var loading = false
  @State private var error: String?
  @State private var confirmClear = false
  var body: some View {
    List(model.notifications) { notification in
      Button {
        guard let url = URL(string: notification.url, relativeTo: PlainwireConfiguration().baseURL) else { return }
        Task { await model.handleDeepLink(url.absoluteURL) }
      } label: {
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: symbol(notification.kind))
            .foregroundStyle(Color.accentColor)
            .frame(width: 34, height: 34)
            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
          VStack(alignment: .leading, spacing: 5) {
            Text(notification.body).font(.body).foregroundStyle(.primary)
            Text(Date(timeIntervalSince1970: Double(notification.createdAt) / 1000), style: .relative)
              .font(.caption).foregroundStyle(.secondary)
          }
          Spacer(minLength: 0)
          if !notification.seen {
            Circle().fill(Color.accentColor).frame(width: 7, height: 7).padding(.top, 8)
              .accessibilityLabel("Unread")
          }
        }.padding(.vertical, 8).contentShape(Rectangle())
      }.buttonStyle(.plain)
    }
    .scrollContentBackground(.hidden)
    .background(AppBackdrop())
    .overlay {
      if model.notifications.isEmpty {
        if loading { ProgressView() }
        else if let error {
          ContentUnavailableView { Label("Activity unavailable", systemImage: "wifi.exclamationmark") }
          description: { Text(error) } actions: { Button("Try Again") { Task { await load() } } }
        } else {
          ContentUnavailableView("You're all caught up", systemImage: "bell.badge", description: Text("Mentions, friend requests, and message activity appear here."))
        }
      }
    }
    .navigationTitle("Activity")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Menu {
          Button("Mark All Read", systemImage: "checkmark") { Task { await model.markActivitySeen() } }
          Button("Clear Activity", systemImage: "trash", role: .destructive) { confirmClear = true }
        } label: { Image(systemName: "ellipsis.circle") }.disabled(model.notifications.isEmpty)
      }
    }
    .confirmationDialog("Clear all activity?", isPresented: $confirmClear, titleVisibility: .visible) {
      Button("Clear Activity", role: .destructive) { Task { await model.clearActivity() } }
    }
    .task { await load() }
    .refreshable { await load() }
  }
  private func load() async {
    loading = true
    error = nil
    do { try await model.refreshActivity() }
    catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    loading = false
  }
  private func symbol(_ kind: String) -> String {
    switch kind {
    case "mention": "at"
    case "friend_request", "friend_accepted": "person.badge.plus"
    case "reaction": "face.smiling"
    case "missed_call": "phone.down"
    default: "bubble.left"
    }
  }
}
