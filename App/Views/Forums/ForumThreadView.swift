import SwiftUI
import UniformTypeIdentifiers

struct ForumThreadView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @AppStorage(AppPreferenceKeys.reduceInterfaceMotion) private var reduceInterfaceMotion = false
  let threadID: PlainwireID
  @State private var editing = false
  @State private var editingReply: PWForumReply?
  @State private var deletingReply: PWForumReply?
  @State private var confirmDelete = false
  @State private var pickingFile = false
  @State private var uploading = false
  @State private var postedReplyID: PlainwireID?
  @State private var deletionErrorKey: String?
  private var store: ForumStore { model.forums }
  private var detail: PWForumThreadDetail? { store.details[threadID] }
  private var draftKey: String { "forum-reply:\(threadID)" }
  private var draft: Binding<String> {
    Binding(get: { model.drafts[draftKey] ?? "" }, set: { model.drafts[draftKey] = $0 })
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 20) {
          if let detail {
            threadHeader(detail.thread)
            ForumPostCard(userID: detail.thread.userId, name: detail.thread.displayName,
              username: detail.thread.username, avatarURL: detail.thread.avatarURL,
              bodyText: detail.thread.body, createdAt: detail.thread.createdAt,
              edited: false, originalPoster: true,
              canEdit: detail.thread.canEdit, canDelete: detail.thread.canDelete,
              onEdit: { editing = true }, onDelete: { confirmDelete = true })
            voting(detail.thread)
            HStack {
              Text("Replies").font(.title3.weight(.semibold))
              Text("\(detail.thread.replyCount)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
              Spacer()
              if store.loading.contains("thread:\(threadID)") { ProgressView().controlSize(.small) }
            }.padding(.top, 8)
            if detail.replies.isEmpty {
              ContentUnavailableView("Keep the conversation going", systemImage: "bubble.left.and.bubble.right",
                description: Text(detail.thread.locked ? "This discussion is closed to new replies." : "Share a thought, a useful link, or a different perspective."))
                .padding(.vertical, 20)
            }
            ForEach(detail.replies) { reply in
              ForumPostCard(userID: reply.userId, name: reply.displayName, username: reply.username,
                avatarURL: reply.avatarURL, bodyText: reply.body, createdAt: reply.createdAt,
                edited: reply.updatedAt != reply.createdAt, originalPoster: reply.userId == detail.thread.userId,
                canEdit: reply.canEdit, canDelete: reply.canDelete,
                onEdit: { editingReply = reply }, onDelete: { deletingReply = reply })
                .id(reply.id)
            }
            if detail.replies.count < detail.thread.replyCount {
              Text("Showing \(detail.replies.count) of \(detail.thread.replyCount) replies.")
                .font(.caption).foregroundStyle(.secondary)
            }
            if detail.thread.locked {
              InlineNotice(text: "This discussion is closed to new replies.", symbol: "lock", tint: .secondary)
            } else if !detail.thread.viewerJoined,
              let forum = store.forums.first(where: { $0.id == detail.thread.forumId }) {
              ForumJoinCard(forum: forum)
            }
            if let error = actionError { InlineNotice(text: error) }
          } else if store.loading.contains("thread:\(threadID)") {
            ProgressView("Opening discussion…").frame(maxWidth: .infinity).padding(50)
          } else {
            ContentUnavailableView("Discussion unavailable", systemImage: "text.bubble",
              description: Text(store.errors["thread:\(threadID)"] ?? "This discussion may have been removed."))
            Button("Try Again") { Task { await store.loadThread(threadID) } }.adaptiveGlassButton()
          }
        }
        .frame(maxWidth: 850).padding(24).frame(maxWidth: .infinity)
      }
      .onChange(of: postedReplyID) { _, id in
        if let id {
          withAnimation(reduceMotion || reduceInterfaceMotion ? nil : .smooth(duration: 0.2)) {
            proxy.scrollTo(id, anchor: .bottom)
          }
        }
      }
    }
    .background(AppBackdrop())
    .navigationTitle(detail?.thread.title ?? "Discussion")
    .safeAreaInset(edge: .bottom) {
      if let thread = detail?.thread, thread.viewerJoined, !thread.locked { replyComposer }
    }
    .task(id: threadID) { await store.loadThread(threadID); await model.synchronizeForumSubscriptions() }
    .refreshable { await store.loadThread(threadID) }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        ShareLink(item: model.appURL(fragment: "t/\(threadID)")) { Label("Share discussion", systemImage: "square.and.arrow.up") }
      }
      ToolbarItem(placement: .primaryAction) {
        if let thread = detail?.thread, thread.canEdit || thread.canDelete || thread.canModerate {
          Menu {
            if thread.canEdit { Button("Edit Discussion", systemImage: "pencil") { editing = true } }
            if thread.canModerate {
              Button(thread.pinned ? "Unpin Discussion" : "Pin Discussion", systemImage: "pin") {
                Task { _ = await store.moderate(thread, action: "pin", value: !thread.pinned) }
              }
              Button(thread.locked ? "Reopen Discussion" : "Close Discussion", systemImage: thread.locked ? "lock.open" : "lock") {
                Task { _ = await store.moderate(thread, action: "lock", value: !thread.locked) }
              }
            }
            if thread.canDelete { Button("Delete Discussion…", systemImage: "trash", role: .destructive) { confirmDelete = true } }
          } label: { Label("Discussion options", systemImage: "ellipsis.circle") }
          .disabled(store.busy.contains("moderate:\(threadID)") || store.busy.contains("delete-thread:\(threadID)"))
        }
      }
    }
    .sheet(isPresented: $editing) {
      if let thread = detail?.thread { ForumThreadEditor(thread: thread) }
    }
    .sheet(item: $editingReply) { ForumReplyEditor(reply: $0) }
    .confirmationDialog("Delete this discussion and its replies?", isPresented: $confirmDelete, titleVisibility: .visible) {
      Button("Delete Discussion", role: .destructive) { if let thread = detail?.thread { Task { _ = await store.deleteThread(thread) } } }
    }
    .confirmationDialog("Delete this reply?", isPresented: Binding(get: { deletingReply != nil },
      set: { if !$0 { deletingReply = nil } }), titleVisibility: .visible) {
      if let reply = deletingReply {
        Button("Delete Reply", role: .destructive) {
          deletingReply = nil
          deletionErrorKey = "delete-reply:\(reply.id)"
          Task { _ = await store.deleteReply(reply) }
        }
      }
    }
    .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.data]) { result in
      guard case .success(let url) = result else { return }
      uploading = true
      Task {
        defer { uploading = false }
        if let upload = await model.upload(url) {
          let current = model.drafts[draftKey] ?? ""
          model.drafts[draftKey] = current + (current.isEmpty ? "" : "\n") + model.attachmentMarkdown(for: upload)
        }
      }
    }
  }

  private func threadHeader(_ thread: PWForumThread) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Button { store.path = [.forum(thread.forumId)] } label: {
        Label(thread.forumName, systemImage: "bubble.left.and.bubble.right")
          .font(.callout.weight(.semibold)).foregroundStyle(forumAccent(thread.forumId))
      }.buttonStyle(.plain)
      Text(thread.title).font(.system(.largeTitle, design: .rounded, weight: .bold))
        .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
      HStack(spacing: 10) {
        if thread.pinned { StatPill(title: "Pinned", symbol: "pin.fill", tint: .indigo) }
        if thread.locked { StatPill(title: "Closed", symbol: "lock.fill", tint: .secondary) }
        StatPill(title: "\(thread.views) views", symbol: "eye", tint: .secondary)
      }
    }
    .padding(.bottom, 4)
  }

  private func voting(_ thread: PWForumThread) -> some View {
    HStack(spacing: 12) {
      Button {
        Task { _ = await store.vote(thread, value: thread.userVote == 1 ? 0 : 1) }
      } label: { Image(systemName: "arrow.up").frame(width: 22, height: 22) }
        .adaptiveGlassButton(prominent: thread.userVote == 1)
        .accessibilityLabel(thread.userVote == 1 ? "Remove upvote" : "Upvote discussion")
        .accessibilityAddTraits(thread.userVote == 1 ? .isSelected : [])
      Text("\(thread.score)").font(.callout.weight(.semibold)).monospacedDigit()
        .accessibilityLabel("Score: \(thread.score)")
      Button {
        Task { _ = await store.vote(thread, value: thread.userVote == -1 ? 0 : -1) }
      } label: { Image(systemName: "arrow.down").frame(width: 22, height: 22) }
        .adaptiveGlassButton(prominent: thread.userVote == -1)
        .accessibilityLabel(thread.userVote == -1 ? "Remove downvote" : "Downvote discussion")
        .accessibilityAddTraits(thread.userVote == -1 ? .isSelected : [])
      Spacer()
      if !thread.viewerJoined { Text("Join to vote").font(.caption).foregroundStyle(.secondary) }
    }
    .disabled(!thread.viewerJoined || store.busy.contains("vote:\(threadID)"))
  }

  private var replyComposer: some View {
    VStack(alignment: .leading, spacing: 10) {
      TextField("Add to the conversation…", text: draft, axis: .vertical)
        .textFieldStyle(.plain).lineLimit(2...6).font(.body)
        .accessibilityLabel("Reply to discussion")
      HStack(spacing: 12) {
        Button { pickingFile = true } label: { Image(systemName: "paperclip").frame(width: 22, height: 22) }
          .adaptiveGlassButton().accessibilityLabel("Attach a file to your reply")
          .disabled(uploading || store.busy.contains("reply:\(threadID)"))
        if uploading { ProgressView("Uploading…").controlSize(.small) }
        Spacer(minLength: 0)
        Text("\(ByteCountFormatter.string(fromByteCount: Int64((model.drafts[draftKey] ?? "").utf8.count), countStyle: .file)) / 12 KB")
          .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
          .help("Replies can contain up to 12,000 UTF-8 bytes, including emoji.")
        Button(store.busy.contains("reply:\(threadID)") ? "Posting…" : "Post Reply", systemImage: "arrow.up") { postReply() }
          .adaptiveGlassButton(prominent: true)
          .keyboardShortcut(.return, modifiers: .command)
          .disabled(!validReply || uploading || store.busy.contains("reply:\(threadID)"))
      }
      if let error = store.errors["reply:\(threadID)"] { Text(error).font(.caption).foregroundStyle(.red) }
    }
    .padding(16).frame(maxWidth: 802).cardSurface(cornerRadius: 18)
    .padding(.horizontal, 24).padding(.vertical, 12).frame(maxWidth: .infinity)
    .background(.bar)
  }

  private var validReply: Bool {
    let text = model.drafts[draftKey] ?? ""
    return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf8.count <= PWForumLimits.body
  }

  private func postReply() {
    guard validReply, !uploading else { return }
    let text = model.drafts[draftKey] ?? ""
    let currentStore = store
    Task {
      if await currentStore.reply(threadID: threadID, body: text) {
        if model.drafts[draftKey] == text { model.drafts[draftKey] = "" }
        postedReplyID = currentStore.details[threadID]?.replies.last?.id
      }
    }
  }

  private var actionError: String? {
    ["thread:\(threadID)", "vote:\(threadID)", "moderate:\(threadID)", "delete-thread:\(threadID)", deletionErrorKey ?? ""]
      .compactMap { store.errors[$0] }.first
  }
}

private struct ForumPostCard: View {
  @Environment(AppModel.self) private var model
  let userID: PlainwireID
  let name: String
  let username: String
  let avatarURL: String
  let bodyText: String
  let createdAt: Int64
  let edited: Bool
  let originalPoster: Bool
  let canEdit: Bool
  let canDelete: Bool
  let onEdit: () -> Void
  let onDelete: () -> Void
  @State private var showingProfile = false

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(alignment: .top, spacing: 12) {
        RemoteAvatar(url: model.mediaURL(avatarURL), fallback: String(name.prefix(1)), size: 40)
        VStack(alignment: .leading, spacing: 4) {
          Button(name) { showingProfile = true }.buttonStyle(.plain).font(.headline)
            .foregroundStyle(.primary).lineLimit(2).accessibilityHint("View profile")
          Text(Date(timeIntervalSince1970: Double(createdAt) / 1000), format: .dateTime.month().day().year().hour().minute())
            .font(.caption).foregroundStyle(.secondary)
          if originalPoster { Text("Original poster").font(.caption2.weight(.medium)).foregroundStyle(.indigo) }
        }
        Spacer(minLength: 8)
        if canEdit || canDelete {
          Menu {
            if canEdit { Button("Edit", systemImage: "pencil", action: onEdit) }
            if canDelete { Button("Delete…", systemImage: "trash", role: .destructive, action: onDelete) }
          } label: { Label("Post options", systemImage: "ellipsis") }.labelStyle(.iconOnly)
        }
      }
      ForumBody(text: bodyText).equatable()
      if edited { Text("Edited").font(.caption2).foregroundStyle(.tertiary) }
    }
    .padding(22).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
    .sheet(isPresented: $showingProfile) { PersonProfileSheet(userID: userID) }
  }
}

struct ForumBody: View, Equatable {
  let text: String
  @State private var revealed = false
  nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.text == rhs.text }

  var body: some View {
    let parsed = PWMessageText.parseBody(text)
    let visibleText = revealed ? parsed.text : PWMessageText.redactingSpoilers(parsed.text)
    VStack(alignment: .leading, spacing: 14) {
      ForEach(Array(PWMessageText.blocks(visibleText).enumerated()), id: \.offset) { _, block in
        switch block.kind {
        case .code(let language):
          VStack(alignment: .leading, spacing: 0) {
            Text(language.isEmpty ? "Code" : language).font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(12)
            Divider()
            ScrollView(.horizontal) {
              Text(block.text).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false).padding(14)
            }
          }
          .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .markdown:
          VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(block.text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
              ForumParagraph(line: line)
            }
          }
        }
      }
      ForEach(parsed.attachments) { MessageAttachmentView(attachment: $0) }
      if parsed.text.contains("||") {
        Button(revealed ? "Hide spoilers" : "Reveal spoilers", systemImage: revealed ? "eye.slash" : "eye") { revealed.toggle() }
          .font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .onChange(of: text) { _, _ in revealed = false }
  }
}

private struct ForumParagraph: View {
  let line: String
  private var heading: Int {
    for level in 1...3 where line.hasPrefix(String(repeating: "#", count: level) + " ") { return level }
    return 0
  }
  private var quote: Bool { line.hasPrefix("> ") }
  private var bullet: Bool { line.hasPrefix("- ") || line.hasPrefix("* ") }
  private var content: String {
    heading > 0 ? String(line.dropFirst(heading + 1)) : quote || bullet ? String(line.dropFirst(2)) : line
  }
  private var font: Font { heading == 1 ? .title2.weight(.semibold) : heading > 1 ? .title3.weight(.semibold) : .body }

  var body: some View {
    if line.isEmpty { Color.clear.frame(height: 6) }
    else {
      HStack(alignment: .top, spacing: 10) {
        if quote { RoundedRectangle(cornerRadius: 2).fill(.indigo.opacity(0.35)).frame(width: 3) }
        if bullet { Text("•").foregroundStyle(.secondary) }
        Text((try? AttributedString(markdown: content,
          options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(content))
          .font(font).lineSpacing(3).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.vertical, heading > 0 ? 5 : 0)
    }
  }
}
