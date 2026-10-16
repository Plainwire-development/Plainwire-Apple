import SwiftUI

struct ActivityView: View {
  @Environment(AppModel.self) private var model
  @State private var loading = false
  @State private var error: String?
  @State private var confirmClear = false
  @State private var unreadOnly = false
  private var visible: [PWNotification] { model.notifications.filter { !unreadOnly || !$0.seen } }
  var body: some View {
    List {
      Section {
        PageHeader(title: "Your activity", subtitle: "Mentions, replies, and the moments you might have missed.",
          symbol: "bell.badge.fill", accent: .orange, eyebrow: "Stay in the loop")
          .listRowSeparator(.hidden).listRowBackground(Color.clear)
      }
      Section {
        HStack {
          Picker("Activity", selection: $unreadOnly) {
            Text("All activity").tag(false)
            Text("Unread").tag(true)
          }.pickerStyle(.segmented).frame(maxWidth: 280)
          Spacer()
          if model.unreadActivityCount > 0 {
            Text("\(model.unreadActivityCount) new").font(.caption.weight(.medium)).foregroundStyle(.orange)
          }
        }.listRowSeparator(.hidden).listRowBackground(Color.clear)
      }
      if visible.isEmpty {
        Section {
          Group {
            if loading { ProgressView("Loading activity…").frame(maxWidth: .infinity).padding(40) }
            else if let error {
              ContentUnavailableView { Label("Activity unavailable", systemImage: "wifi.exclamationmark") }
              description: { Text(error) } actions: { Button("Try Again") { Task { await load() } } }
            } else {
              ContentUnavailableView("You’re all caught up", systemImage: "checkmark.circle",
                description: Text(unreadOnly ? "You have no unread activity." : "New mentions, replies, and friend requests will appear here."))
            }
          }
          .padding(.vertical, 24).listRowSeparator(.hidden).listRowBackground(Color.clear)
        }
      }
      ForEach(visible) { notification in
      Button {
        guard let url = URL(string: notification.url, relativeTo: model.appURL()) else { return }
        Task { await model.handleDeepLink(url.absoluteURL) }
      } label: {
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: symbol(notification.kind))
            .foregroundStyle(accent(notification.kind))
            .frame(width: 40, height: 40)
            .background(accent(notification.kind).opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
          VStack(alignment: .leading, spacing: 5) {
            Text(notification.body).font(.body).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            Text(Date(timeIntervalSince1970: Double(notification.createdAt) / 1000), style: .relative)
              .font(.caption).foregroundStyle(.secondary)
          }
          Spacer(minLength: 0)
          if !notification.seen {
            Circle().fill(Color.accentColor).frame(width: 7, height: 7).padding(.top, 8)
              .accessibilityLabel("Unread")
          }
        }.padding(16).cardSurface(cornerRadius: 16)
          .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      }.buttonStyle(.plain).listRowBackground(Color.clear).listRowSeparator(.hidden)
      }
    }
    .listStyle(.inset)
    .scrollContentBackground(.hidden)
    .background(AppBackdrop())
    .frame(maxWidth: 1000).frame(maxWidth: .infinity).background(AppBackdrop())
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

  private func accent(_ kind: String) -> Color {
    switch kind {
    case "mention": .indigo
    case "friend_request", "friend_accepted": .teal
    case "reaction": .pink
    case "missed_call": .red
    default: .blue
    }
  }
}
