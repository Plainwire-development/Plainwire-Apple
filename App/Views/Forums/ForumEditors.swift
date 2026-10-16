import SwiftUI
import UniformTypeIdentifiers

struct CreateForumSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var slug = ""
  @State private var description = ""
  @State private var customSlug = false
  @State private var saving = false

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Label("A place for your people", systemImage: "bubble.left.and.bubble.right.fill")
            .font(.title2.weight(.semibold)).foregroundStyle(.indigo)
          Text("Choose a name, give your community a home, and let the conversations grow.")
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        Section("Your community") {
          TextField("Name", text: $name)
          TextField("Description", text: $description, axis: .vertical).lineLimit(3...6)
          TextField("Address", text: Binding(get: { slug }, set: { slug = $0; customSlug = true }))
            .autocorrectionDisabled()
          Text("Use 2–40 letters, numbers, hyphens, or underscores for the address.")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        if name.utf8.count > PWForumLimits.name || description.utf8.count > PWForumLimits.description {
          Section { InlineNotice(text: "Try a shorter name or description. The name allows 80 bytes and the description allows 280 bytes.") }
        }
        if let error = model.forums.errors["create-forum"] {
          Section { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
        }
      }
      .formStyle(.grouped)
      .navigationTitle("Create Forum")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
        ToolbarItem(placement: .confirmationAction) {
          Button(saving ? "Creating…" : "Create") { create() }.disabled(!valid || saving)
        }
      }
      .onChange(of: name) { _, value in
        guard !customSlug else { return }
        let folded = value.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
        slug = String(folded.replacingOccurrences(of: "[^a-z0-9_-]+", with: "-", options: .regularExpression)
          .trimmingCharacters(in: CharacterSet(charactersIn: "-_")).prefix(PWForumLimits.slug))
      }
    }
    .adaptiveSheetSize(minWidth: 380, idealWidth: 520, minHeight: 440, idealHeight: 560)
    .interactiveDismissDisabled(saving)
  }

  private var valid: Bool {
    name.trimmingCharacters(in: .whitespacesAndNewlines).utf8.count >= 2 && name.utf8.count <= PWForumLimits.name
      && description.utf8.count <= PWForumLimits.description && (2...PWForumLimits.slug).contains(slug.utf8.count)
      && slug.unicodeScalars.allSatisfy { (97...122).contains($0.value) || (48...57).contains($0.value) || $0 == "-" || $0 == "_" }
  }

  private func create() {
    guard valid, !saving else { return }
    saving = true
    let store = model.forums
    Task {
      defer { saving = false }
      if let id = await store.createForum(name: name.trimmingCharacters(in: .whitespacesAndNewlines), slug: slug, description: description) {
        store.path = [.forum(id)]
        dismiss()
      }
    }
  }
}

struct ForumThreadEditor: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let forumID: PlainwireID
  let forumName: String
  let thread: PWForumThread?
  @State private var title: String
  @State private var bodyText: String
  @State private var saving = false
  @State private var preview = false
  @State private var pickingFile = false
  @State private var uploading = false

  init(forum: PWForum) {
    forumID = forum.id
    forumName = forum.name
    thread = nil
    _title = State(initialValue: "")
    _bodyText = State(initialValue: "")
  }

  init(thread: PWForumThread) {
    forumID = thread.forumId
    forumName = thread.forumName
    self.thread = thread
    _title = State(initialValue: thread.title)
    _bodyText = State(initialValue: thread.rawBody)
  }

  private var key: String { thread.map { "edit-thread:\($0.id)" } ?? "create-thread:\(forumID)" }
  private var draftKey: String { "forum-thread:\(forumID)" }
  private var valid: Bool {
    title.trimmingCharacters(in: .whitespacesAndNewlines).utf8.count >= 3 && title.utf8.count <= PWForumLimits.title
      && !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && bodyText.utf8.count <= PWForumLimits.body
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Label(forumName, systemImage: "bubble.left.and.bubble.right").font(.callout.weight(.medium)).foregroundStyle(.indigo)
          TextField("Give your discussion a title", text: $title, axis: .vertical)
            .font(.title2.weight(.semibold)).textFieldStyle(.plain).lineLimit(1...3)
            .accessibilityLabel("Discussion title")
          Divider()
          HStack {
            Picker("Editor", selection: $preview) { Text("Write").tag(false); Text("Preview").tag(true) }
              .pickerStyle(.segmented).frame(maxWidth: 220)
            Spacer()
            Button("Attach", systemImage: "paperclip") { pickingFile = true }
              .adaptiveGlassButton().disabled(uploading || saving)
          }
          if preview {
            if bodyText.isEmpty { Text("Your discussion preview will appear here.").foregroundStyle(.secondary).padding(.vertical, 30) }
            else { ForumBody(text: bodyText).equatable() }
          } else {
            TextField("What would you like to share?", text: $bodyText, axis: .vertical)
              .textFieldStyle(.plain).lineLimit(12...).font(.body).lineSpacing(3)
              .accessibilityLabel("Discussion body")
          }
          Divider()
          ForumWritingFooter(text: bodyText)
          if title.utf8.count > PWForumLimits.title {
            InlineNotice(text: "Try a shorter title. Titles can use up to 160 bytes, including emoji.")
          }
          if uploading { ProgressView("Uploading attachment…").controlSize(.small) }
          if let error = model.forums.errors[key] { InlineNotice(text: error) }
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
      }
      .navigationTitle(thread == nil ? "New Discussion" : "Edit Discussion")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
        ToolbarItem(placement: .confirmationAction) {
          Button(saving ? "Saving…" : thread == nil ? "Publish" : "Save") { save() }
            .disabled(!valid || saving || uploading).keyboardShortcut(.return, modifiers: .command)
        }
      }
    }
    .adaptiveSheetSize(minWidth: 390, idealWidth: 680, minHeight: 440, idealHeight: 620)
    .interactiveDismissDisabled(saving || uploading)
    .onAppear {
      if thread == nil {
        title = model.drafts[draftKey + ":title"] ?? ""
        bodyText = model.drafts[draftKey] ?? ""
      }
    }
    .onChange(of: title) { _, value in if thread == nil { model.drafts[draftKey + ":title"] = value } }
    .onChange(of: bodyText) { _, value in if thread == nil { model.drafts[draftKey] = value } }
    .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.data]) { result in
      guard case .success(let url) = result else { return }
      uploading = true
      Task {
        defer { uploading = false }
        if let upload = await model.upload(url) {
          bodyText += (bodyText.isEmpty ? "" : "\n") + model.attachmentMarkdown(for: upload)
        }
      }
    }
  }

  private func save() {
    guard valid, !saving, !uploading else { return }
    saving = true
    let store = model.forums
    Task {
      defer { saving = false }
      if let thread {
        if await store.editThread(thread, title: title, body: bodyText) { dismiss() }
      } else if let id = await store.createThread(forumID: forumID, title: title, body: bodyText) {
        model.drafts[draftKey] = ""
        model.drafts[draftKey + ":title"] = ""
        store.path = [.forum(forumID), .thread(id)]
        dismiss()
      }
    }
  }
}

struct ForumReplyEditor: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let reply: PWForumReply
  @State private var text: String
  @State private var saving = false
  init(reply: PWForumReply) { self.reply = reply; _text = State(initialValue: reply.rawBody) }
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          TextField("Reply", text: $text, axis: .vertical).textFieldStyle(.plain).lineLimit(8...).font(.body)
          Divider()
          ForumWritingFooter(text: text)
          if let error = model.forums.errors["edit-reply:\(reply.id)"] { InlineNotice(text: error) }
        }.padding(24)
      }
      .navigationTitle("Edit Reply")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
        ToolbarItem(placement: .confirmationAction) {
          Button(saving ? "Saving…" : "Save") {
            saving = true
            Task { if await model.forums.editReply(reply, body: text) { dismiss() }; saving = false }
          }.disabled(saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.utf8.count > PWForumLimits.body)
        }
      }
    }
    .adaptiveSheetSize(minWidth: 380, idealWidth: 600, minHeight: 340, idealHeight: 480)
    .interactiveDismissDisabled(saving)
  }
}

struct ForumWritingFooter: View {
  let text: String
  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Label("Markdown supported", systemImage: "textformat").foregroundStyle(.secondary)
      Spacer(minLength: 0)
      Text("\(ByteCountFormatter.string(fromByteCount: Int64(text.utf8.count), countStyle: .file)) / 12 KB")
        .monospacedDigit().foregroundStyle(text.utf8.count > PWForumLimits.body ? .red : .secondary)
        .help("Posts can contain up to 12,000 UTF-8 bytes. Emoji and some letters use more than one byte.")
    }
    .font(.caption)
  }
}
