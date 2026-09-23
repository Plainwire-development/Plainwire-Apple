import SwiftUI

struct FriendsView: View {
  @Environment(AppModel.self) private var model
  @State private var search = ""
  @State private var results: [PWUser] = []
  @State private var searching = false

  private var pending: [PWFriend] { model.friends.filter { $0.status == "pending" } }
  private var accepted: [PWFriend] { model.friends.filter { $0.status == "accepted" } }
  private var hasQuery: Bool {
    !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    ZStack {
      AppBackdrop()
      List {
        if !pending.isEmpty {
          Section {
            ForEach(pending, id: \.user.id) { friend in
              FriendRow(friend: friend, requestActions: true)
            }
          } header: {
            Label("Requests", systemImage: "person.crop.circle.badge.plus")
          }
        }

        Section {
          if accepted.isEmpty {
            FriendsEmptyRow()
          } else {
            ForEach(accepted, id: \.user.id) { friend in
              FriendRow(friend: friend, requestActions: false)
            }
          }
        } header: {
          HStack {
            Label("Friends", systemImage: "person.2")
            Spacer()
            if !accepted.isEmpty {
              Text("\(accepted.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
            }
          }
        }

        if hasQuery {
          Section("People") {
            if searching {
              HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Searching Plainwire…").foregroundStyle(.secondary)
              }
              .padding(.vertical, 8)
            } else if results.isEmpty {
              Text("No matching people")
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
            } else {
              ForEach(results) { user in SearchUserRow(user: user, request: request) }
            }
          }
        }
      }
      .scrollContentBackground(.hidden)
      .modifier(FriendsListStyleModifier())
    }
    .navigationTitle("Friends")
    .searchable(text: $search, prompt: "Find people")
    .onSubmit(of: .search) { Task { await performSearch() } }
    .onChange(of: search) { _, newValue in
      if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { results = [] }
    }
    .refreshable { await model.refresh() }
  }

  private func performSearch() async {
    let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
    guard q.count >= 2 else {
      results = []
      return
    }
    searching = true
    defer { searching = false }
    let found = await model.searchUsers(q)
    results = found.filter { $0.id != model.session?.user.id }
  }

  private func request(_ user: PWUser) async {
    await model.sendFriendRequest(to: user)
    results.removeAll { $0.id == user.id }
  }
}

private struct SearchUserRow: View {
  @Environment(AppModel.self) private var model
  @State private var showingProfile = false
  let user: PWUser
  let request: (PWUser) async -> Void

  var body: some View {
    HStack(spacing: 12) {
      RemoteAvatar(
        url: model.mediaURL(user.avatarURL), fallback: String(user.displayName.prefix(1)), size: 42)
      VStack(alignment: .leading, spacing: 2) {
        Text(user.displayName).font(.headline).lineLimit(1)
        Text("@\(user.username)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }
      Spacer(minLength: 10)
      Button { showingProfile = true } label: {
        Image(systemName: "person.crop.circle")
      }
      .adaptiveGlassButton()
      .controlSize(.small)
      .accessibilityLabel("View profile")
      Button("Add") { Task { await request(user) } }
        .adaptiveGlassButton(prominent: true)
        .controlSize(.small)
    }
    .padding(.vertical, 4)
    .sheet(isPresented: $showingProfile) { PersonProfileSheet(userID: user.id) }
  }
}

private struct FriendsEmptyRow: View {
  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "person.2.slash")
        .font(.title3)
        .foregroundStyle(.tertiary)
        .frame(width: 36)
      VStack(alignment: .leading, spacing: 2) {
        Text("No friends yet").font(.subheadline.weight(.medium))
        Text("Search for a username above to add someone.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 8)
  }
}

private struct FriendRow: View {
  @Environment(AppModel.self) private var model
  @State private var showingProfile = false
  let friend: PWFriend
  let requestActions: Bool

  var body: some View {
    HStack(spacing: 12) {
      ZStack(alignment: .bottomTrailing) {
        RemoteAvatar(
          url: model.mediaURL(friend.user.avatarURL),
          fallback: String(friend.user.displayName.prefix(1)), size: 44)
        Circle()
          .fill(statusColor)
          .frame(width: 11, height: 11)
          .overlay(Circle().stroke(.background, lineWidth: 2))
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(friend.user.displayName).font(.headline).lineLimit(1)
        Text("@\(friend.user.username)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 10)
      Button { showingProfile = true } label: {
        Image(systemName: "person.crop.circle")
      }
      .adaptiveGlassButton()
      .controlSize(.small)
      .accessibilityLabel("View profile")
      if requestActions {
        if friend.incoming {
          Button("Accept") { Task { await model.acceptFriend(friend.user) } }
            .adaptiveGlassButton(prominent: true)
            .controlSize(.small)
        } else {
          Label("Pending", systemImage: "clock")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } else {
        Button {
          Task { await model.startConversation(with: friend.user) }
        } label: {
          Image(systemName: "message.fill")
            .frame(width: 20, height: 20)
        }
        .adaptiveGlassButton()
        .controlSize(.small)
        .help("Message")
        .accessibilityLabel("Message \(friend.user.displayName)")
      }
    }
    .padding(.vertical, 4)
    .sheet(isPresented: $showingProfile) { PersonProfileSheet(userID: friend.user.id) }
  }

  private var statusColor: Color {
    switch model.presenceStatus(for: friend.user) {
    case "online": .green
    case "busy": .red
    case "away": .orange
    default: .secondary.opacity(0.65)
    }
  }
}

struct PersonProfileSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let userID: PlainwireID
  @State private var profile: PWProfile?

  var body: some View {
    NavigationStack {
      ScrollView {
        if let user = profile?.user {
          VStack(alignment: .leading, spacing: 18) {
            if let banner = model.mediaURL(user.bannerURL) {
              AsyncImage(url: banner) { image in
                image.resizable().scaledToFill()
              } placeholder: { Color.secondary.opacity(0.12) }
              .frame(height: 135).clipped().cornerRadius(16)
            }
            HStack(spacing: 16) {
              RemoteAvatar(url: model.mediaURL(user.avatarURL),
                           fallback: String(user.displayName.prefix(1)), size: 72)
              VStack(alignment: .leading, spacing: 3) {
                Text(user.displayName).font(.title2.bold())
                Text("@\(user.username)").foregroundStyle(.secondary)
              }
            }
            if !user.status.isEmpty {
              Label(user.status, systemImage: "bubble.left")
                .font(.subheadline)
            }
            if !user.bio.isEmpty { Text(user.bio).textSelection(.enabled) }
            Text("Joined \(Date(timeIntervalSince1970: TimeInterval(user.createdAt) / 1000).formatted(date: .abbreviated, time: .omitted))")
              .font(.caption).foregroundStyle(.secondary)
            if user.id != model.session?.user.id {
              Button {
                Task { await model.startConversation(with: user); dismiss() }
              } label: { Label("Message", systemImage: "message") }
              .buttonStyle(.borderedProminent)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(24)
        } else {
          ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .navigationTitle("Profile")
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
    .frame(minWidth: 360, idealWidth: 480, minHeight: 400)
    .task(id: userID) { profile = await model.profile(id: userID) }
  }
}

private struct FriendsListStyleModifier: ViewModifier {
  @ViewBuilder func body(content: Content) -> some View {
    #if os(macOS)
      content.listStyle(.inset)
    #else
      content.listStyle(.insetGrouped)
    #endif
  }
}
