import SwiftUI

struct ForumsView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.scenePhase) private var scenePhase
  @State private var search = ""
  @State private var joinedOnly = false
  @State private var creating = false
  private var store: ForumStore { model.forums }

  var body: some View {
    @Bindable var store = model.forums
    NavigationStack(path: $store.path) {
      overview
        .navigationDestination(for: ForumRoute.self) { route in
          switch route {
          case .forum(let id): ForumBoardView(forumID: id)
          case .thread(let id): ForumThreadView(threadID: id)
          }
        }
    }
    .sheet(isPresented: $creating) { CreateForumSheet() }
    .task {
      await store.loadForums()
      await model.synchronizeForumSubscriptions()
    }
    .onChange(of: store.path) { _, _ in Task { await model.synchronizeForumSubscriptions() } }
    .onChange(of: store.forums) { _, _ in Task { await model.synchronizeForumSubscriptions() } }
    .task(id: scenePhase == .active) {
      guard scenePhase == .active else { return }
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(30)) } catch { return }
        guard model.selectedSection == .forums, model.sessionState == .ready else { return }
        await store.refreshVisible()
      }
    }
  }

  private var filtered: [PWForum] {
    store.forums.filter {
      (!joinedOnly || $0.joined) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
        || $0.description.localizedCaseInsensitiveContains(search))
    }
  }

  private var overview: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        PageHeader(title: "Make room for ideas.", subtitle: "Find your community. Ask a question. Start a conversation worth keeping.",
          symbol: "text.bubble.fill", accent: .indigo, eyebrow: "Plainwire Forums")
        ViewThatFits(in: .horizontal) {
          HStack {
            filter
            Spacer(minLength: 12)
            StatPill(title: "\(store.forums.count) forums", symbol: "square.grid.2x2", tint: .indigo)
            StatPill(title: "\(store.forums.reduce(0) { $0 + $1.threadCount }) discussions", symbol: "bubble.left.and.bubble.right", tint: .teal)
          }
          filter
        }
        if let error = store.errors["forums"] {
          InlineNotice(text: error)
          Button("Try Again") { Task { await store.loadForums() } }.adaptiveGlassButton()
        }
        if !store.hasLoaded && store.loading.contains("forums") {
          ProgressView("Finding your communities…").frame(maxWidth: .infinity).padding(40)
        } else if filtered.isEmpty && store.errors["forums"] == nil {
          ContentUnavailableView {
            Label(search.isEmpty ? joinedOnly ? "Find your people" : "Room for a new community" : "No matching forums",
              systemImage: "text.bubble")
          } description: {
            Text(search.isEmpty ? joinedOnly ? "Browse all forums and join a conversation that interests you." : "Create the first forum for this community." : "Try another name or topic.")
          } actions: {
            if joinedOnly { Button("Browse All Forums") { joinedOnly = false }.adaptiveGlassButton(prominent: true) }
            else if search.isEmpty { Button("Create a Forum") { creating = true }.adaptiveGlassButton(prominent: true) }
          }
          .padding(.vertical, 32)
        } else {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 18)], alignment: .leading, spacing: 18) {
            ForEach(filtered) { forum in
              NavigationLink(value: ForumRoute.forum(forum.id)) { ForumCard(forum: forum) }
                .buttonStyle(.plain)
            }
          }
        }
      }
      .frame(maxWidth: 1120).padding(24).frame(maxWidth: .infinity)
    }
    .background(AppBackdrop())
    .navigationTitle("Forums")
    .searchable(text: $search, prompt: "Find a forum")
    .refreshable { await store.refreshVisible() }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("Create Forum", systemImage: "plus") { creating = true }
          .help("Create a community forum")
      }
    }
  }

  private var filter: some View {
    Picker("Forums", selection: $joinedOnly) {
      Text("Explore").tag(false)
      Text("Joined").tag(true)
    }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 260)
  }
}

private struct ForumCard: View {
  let forum: PWForum
  @State private var hovering = false
  private var accent: Color { forumAccent(forum.id) }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Image(systemName: "bubble.left.and.bubble.right.fill")
          .font(.title2).symbolRenderingMode(.hierarchical).foregroundStyle(accent)
          .frame(width: 48, height: 48)
          .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        Spacer()
        if forum.joined { StatPill(title: "Joined", symbol: "checkmark", tint: .teal) }
      }
      VStack(alignment: .leading, spacing: 7) {
        Text(forum.name).font(.title3.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
        Text(forum.description.isEmpty ? "A space to share ideas and meet your community." : forum.description)
          .font(.callout).foregroundStyle(.secondary).lineLimit(3)
          .frame(minHeight: 50, alignment: .topLeading)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Divider().opacity(0.6)
      HStack(spacing: 14) {
        Label("\(forum.threadCount)", systemImage: "text.bubble")
        Label("\(forum.memberCount)", systemImage: "person.2")
        Spacer(minLength: 0)
        Image(systemName: "arrow.up.right").foregroundStyle(accent)
      }
      .font(.caption.weight(.medium)).foregroundStyle(.secondary)
    }
    .padding(20).frame(maxWidth: .infinity, minHeight: 235, alignment: .topLeading)
    .cardSurface()
    .overlay {
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .strokeBorder(accent.opacity(hovering ? 0.45 : 0), lineWidth: 1)
    }
    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .onHover { hovering = $0 }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(forum.name), \(forum.threadCount) discussions, \(forum.memberCount) members\(forum.joined ? ", joined" : "")")
  }
}

struct ForumBoardView: View {
  @Environment(AppModel.self) private var model
  let forumID: PlainwireID
  @State private var query = ""
  @State private var sort: DiscussionSort = .active
  @State private var composing = false
  @State private var confirmDelete = false
  @State private var confirmLeave = false
  private var store: ForumStore { model.forums }
  private var forum: PWForum? { store.forums.first { $0.id == forumID } }
  private var key: String { "forum:\(forumID)" }

  private enum DiscussionSort: String, CaseIterable {
    case active = "Recent activity", newest = "Newest first", top = "Top discussions"
  }

  private var discussions: [PWForumThread] {
    (store.threads[forumID] ?? []).sorted {
      if $0.pinned != $1.pinned { return $0.pinned }
      switch sort {
      case .active: return $0.updatedAt == $1.updatedAt ? $0.id > $1.id : $0.updatedAt > $1.updatedAt
      case .newest: return $0.createdAt == $1.createdAt ? $0.id > $1.id : $0.createdAt > $1.createdAt
      case .top: return $0.score == $1.score ? $0.id > $1.id : $0.score > $1.score
      }
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        if let forum {
          PageHeader(title: forum.name, subtitle: forum.description.isEmpty ? "Good conversations start here." : forum.description,
            symbol: "bubble.left.and.bubble.right.fill", accent: forumAccent(forumID), eyebrow: "Community forum")
          HStack(spacing: 10) {
            StatPill(title: "\(forum.threadCount) discussions", symbol: "text.bubble", tint: forumAccent(forumID))
            StatPill(title: "\(forum.memberCount) members", symbol: "person.2", tint: .teal)
          }
          if !forum.joined { ForumJoinCard(forum: forum) }
          HStack {
            Text(query.isEmpty ? "Discussions" : "Search results").font(.title3.weight(.semibold))
            Spacer()
            Picker("Sort discussions", selection: $sort) {
              ForEach(DiscussionSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.menu).labelsHidden().fixedSize()
          }
          if let error = store.errors[key] {
            InlineNotice(text: error)
            Button("Try Again") { Task { await store.loadThreads(forumID: forumID, query: query) } }.adaptiveGlassButton()
          }
          if store.loading.contains(key) { ProgressView().controlSize(.small).frame(maxWidth: .infinity) }
          if discussions.isEmpty && !store.loading.contains(key) && store.errors[key] == nil {
            ContentUnavailableView(query.isEmpty ? "Start something good" : "No matching discussions",
              systemImage: "square.and.pencil", description: Text(query.isEmpty ? "Be the first to share an idea or ask a question." : "Try a different word or phrase."))
              .padding(.vertical, 30)
          }
          LazyVStack(spacing: 12) {
            ForEach(discussions) { thread in
              NavigationLink(value: ForumRoute.thread(thread.id)) { ForumDiscussionCard(thread: thread) }
                .buttonStyle(.plain)
            }
          }
          if query.isEmpty, forum.threadCount > discussions.count, !discussions.isEmpty {
            Text("Search this forum to find more discussions.").font(.caption).foregroundStyle(.secondary)
          }
          if let error = store.errors["membership:\(forumID)"] ?? store.errors["delete-forum:\(forumID)"] {
            InlineNotice(text: error)
          }
        } else if store.loading.contains("forums") {
          ProgressView("Loading forum…").frame(maxWidth: .infinity).padding(40)
        } else {
          ContentUnavailableView("Forum unavailable", systemImage: "text.bubble",
            description: Text(store.errors["forums"] ?? "This forum may have been removed."))
          Button("Try Again") { Task { await store.loadForums() } }.adaptiveGlassButton()
        }
      }
      .frame(maxWidth: 980).padding(24).frame(maxWidth: .infinity)
    }
    .background(AppBackdrop())
    .navigationTitle(forum?.name ?? "Forum")
    .searchable(text: $query, prompt: "Search discussions")
    .task(id: forumID) {
      if forum == nil { await store.loadForums() }
      await store.loadThreads(forumID: forumID, query: query)
    }
    .task(id: query) {
      do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
      guard !Task.isCancelled else { return }
      let normalized = PWForumLimits.prefix(query.trimmingCharacters(in: .whitespacesAndNewlines), maximumBytes: PWForumLimits.search)
      guard normalized != store.queries[forumID] else { return }
      await store.loadThreads(forumID: forumID, query: query)
    }
    .refreshable { await store.refreshVisible() }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("New Discussion", systemImage: "square.and.pencil") { composing = true }
          .disabled(forum?.joined != true)
      }
      ToolbarItem(placement: .primaryAction) {
        Menu {
          ShareLink(item: model.appURL(fragment: "f/\(forumID)"))
          if let forum, forum.joined, forum.ownerId != model.session?.user.id {
            Button("Leave Forum", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { confirmLeave = true }
          }
          if forum?.ownerId == model.session?.user.id {
            Button("Delete Forum…", systemImage: "trash", role: .destructive) { confirmDelete = true }
          }
        } label: { Label("Forum options", systemImage: "ellipsis.circle") }
      }
    }
    .sheet(isPresented: $composing) { if let forum { ForumThreadEditor(forum: forum) } }
    .confirmationDialog("Delete this forum and all its discussions?", isPresented: $confirmDelete, titleVisibility: .visible) {
      Button("Delete Forum", role: .destructive) { if let forum { Task { _ = await store.deleteForum(forum) } } }
    }
    .confirmationDialog("Leave this forum?", isPresented: $confirmLeave, titleVisibility: .visible) {
      Button("Leave Forum", role: .destructive) { if let forum { Task { _ = await store.setMembership(forum, joined: false) } } }
    }
  }
}

struct ForumJoinCard: View {
  @Environment(AppModel.self) private var model
  let forum: PWForum
  var body: some View {
    HStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Pull up a chair.").font(.headline)
        Text("Join this forum to start discussions, reply, and vote.").font(.callout).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Button("Join Forum", systemImage: "plus") { Task { _ = await model.forums.setMembership(forum, joined: true) } }
        .adaptiveGlassButton(prominent: true).disabled(model.forums.busy.contains("membership:\(forum.id)"))
    }
    .padding(18).cardSurface(cornerRadius: 16)
  }
}

private struct ForumDiscussionCard: View {
  @Environment(AppModel.self) private var model
  let thread: PWForumThread
  @State private var hovering = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 14) {
        VStack(alignment: .leading, spacing: 7) {
          if thread.pinned { Label("Pinned discussion", systemImage: "pin.fill").font(.caption.weight(.medium)).foregroundStyle(.indigo) }
          Text(thread.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
          Text(preview)
            .font(.callout).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary).padding(.top, 5)
      }
      HStack(spacing: 8) {
        RemoteAvatar(url: model.mediaURL(thread.avatarURL), fallback: String(thread.displayName.prefix(1)), size: 24)
        Text(thread.displayName).lineLimit(1)
        Text("·").foregroundStyle(.tertiary)
        Text(Date(timeIntervalSince1970: Double(thread.updatedAt) / 1000), style: .relative).lineLimit(1)
        Spacer(minLength: 6)
        Label("\(thread.replyCount)", systemImage: "bubble.right").fixedSize()
        Label("\(thread.score)", systemImage: "arrow.up").fixedSize()
      }
      .font(.caption).foregroundStyle(.secondary)
    }
    .padding(18).frame(maxWidth: .infinity, alignment: .leading).cardSurface(cornerRadius: 17)
    .overlay {
      RoundedRectangle(cornerRadius: 17, style: .continuous)
        .strokeBorder(Color.accentColor.opacity(hovering ? 0.35 : 0), lineWidth: 1)
    }
    .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous)).onHover { hovering = $0 }
  }

  private var preview: AttributedString {
    let parsed = PWMessageText.parseBody(String(thread.body.prefix(400)))
    let text = PWMessageText.redactingSpoilers(parsed.text).components(separatedBy: "\n")
      .map { $0.replacingOccurrences(of: "^(?:#{1,6}|>|[-*])\\s+", with: "", options: .regularExpression) }
      .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: " ")
    return (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
      ?? AttributedString(text)
  }
}

func forumAccent(_ id: PlainwireID) -> Color {
  let colors: [Color] = [.indigo, .teal, .blue, .purple, .orange, .pink]
  return colors[Int(id.magnitude % UInt64(colors.count))]
}
