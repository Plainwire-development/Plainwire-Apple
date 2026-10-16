import SwiftUI

struct ComposerBar: View {
  @Environment(AppModel.self) private var model
  @AppStorage(AppPreferenceKeys.sendTypingIndicators) private var sendTypingIndicators = true
  @AppStorage(AppPreferenceKeys.enterSendsMessage) private var enterSendsMessage = true
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @AppStorage(AppPreferenceKeys.reduceInterfaceMotion) private var reduceInterfaceMotion = false
  @Binding var text: String
  @State private var selection: TextSelection?
  let uploading: Bool
  let sending: Bool
  let replyingTo: PWMessage?
  let onCancelReply: () -> Void
  let onAttach: () -> Void
  let onRecordVoiceNote: () -> Void
  let onChooseGIF: () -> Void
  let onAttachSpoiler: () -> Void
  let onSend: () -> Void

  private var mentionCandidates: [PWUser] {
    guard let query = activeMentionQuery, let room = model.selectedRoom else { return [] }
    let users: [PWUser]
    if room.scope == "direct" {
      users = model.conversationDetails[room.roomID]?.members.map(\.user) ?? []
    } else if let serverID = model.selectedServerID {
      users = model.serverDetails[serverID]?.members.map(\.user) ?? []
    } else {
      users = []
    }
    return users.filter { user in
      query.isEmpty || user.username.lowercased().hasPrefix(query.lowercased())
        || user.displayName.localizedCaseInsensitiveContains(query)
    }
    .sorted(by: { lhs, rhs in
      let lhsPrefix = lhs.username.lowercased().hasPrefix(query.lowercased())
      let rhsPrefix = rhs.username.lowercased().hasPrefix(query.lowercased())
      if lhsPrefix != rhsPrefix { return lhsPrefix }
      return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    })
    .prefix(8)
    .map { $0 }
  }

  private var activeMentionQuery: String? {
    guard let at = text.lastIndex(of: "@") else { return nil }
    if at != text.startIndex {
      let before = text[text.index(before: at)]
      guard before.isWhitespace else { return nil }
    }
    let query = String(text[text.index(after: at)...])
    guard query.count <= 40,
      query.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") })
    else { return nil }
    return query
  }

  var body: some View {
    AdaptiveGlassContainer(spacing: 8) {
      VStack(spacing: 0) {
        if let replyingTo { replyStrip(replyingTo) }

        if !mentionCandidates.isEmpty {
          ScrollView {
            LazyVStack(spacing: 2) {
              ForEach(mentionCandidates) { user in
                Button { insertMention(user.username) } label: {
                  HStack(spacing: 9) {
                    RemoteAvatar(url: model.mediaURL(user.avatarURL),
                                 fallback: String(user.displayName.prefix(1)), size: 28)
                    Text(user.displayName).lineLimit(1)
                    Spacer(minLength: 4)
                    Text("@\(user.username)").font(.caption).foregroundStyle(.secondary)
                      .lineLimit(1)
                  }
                  .padding(.horizontal, 9)
                  .padding(.vertical, 5)
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
              }
            }
            .padding(5)
          }
          .frame(maxHeight: 192)
          Divider().opacity(0.3)
        }

        HStack(alignment: .bottom, spacing: 9) {
          Menu {
            Button("Attach files", systemImage: "paperclip", action: onAttach)
            Button("Attach as spoiler", systemImage: "eye.slash", action: onAttachSpoiler)
            Button("Record Voice Note", systemImage: "mic", action: onRecordVoiceNote)
            Divider()
            Menu("Formatting", systemImage: "textformat") {
              Button("Bold") { insertFormat(prefix: "**", suffix: "**", placeholder: "bold text") }
              Button("Italic") { insertFormat(prefix: "*", suffix: "*", placeholder: "italic text") }
              Button("Inline Code") { insertFormat(prefix: "`", suffix: "`", placeholder: "code") }
              Button("Code Block") { insertFormat(prefix: "\n```\n", suffix: "\n```\n", placeholder: "code") }
              Button("Quote") { insertFormat(prefix: "\n> ", suffix: "\n", placeholder: "quote") }
              Button("Spoiler") { insertFormat(prefix: "||", suffix: "||", placeholder: "spoiler") }
            }
          } label: {
            Group {
              if uploading {
                ProgressView().controlSize(.small)
              } else {
                Image(systemName: "plus")
                  .font(.system(size: 15, weight: .semibold))
              }
            }
            .frame(width: 24, height: 24)
          }
          .adaptiveGlassButton()
          .controlSize(.small)
          .disabled(uploading || !model.canSendInSelectedRoom)
          .accessibilityLabel(uploading ? "Uploading attachments" : "Attach files")

          Button(action: onChooseGIF) {
            Text("GIF").font(.system(size: 10, weight: .bold, design: .rounded))
              .frame(width: 24, height: 24)
          }
          .adaptiveGlassButton().controlSize(.small)
          .disabled(uploading || !model.canSendInSelectedRoom)
          .keyboardShortcut("g", modifiers: .command)
          .help("Search GIFs").accessibilityLabel("Search GIFs")

          TextField("Message \(model.selectedRoom?.title ?? "")", text: $text, selection: $selection, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1...7)
            .padding(.horizontal, 3)
            .padding(.vertical, 7)
            .onChange(of: text) { _, _ in
              if sendTypingIndicators && model.canSendInSelectedRoom { model.noteTyping() }
            }
            .disabled(!model.canSendInSelectedRoom)
            .submitLabel(enterSendsMessage ? .send : .return)
            .onKeyPress(.return, phases: .down) { press in
              if press.modifiers.contains(.command) {
                submitMessage()
                return .handled
              }
              if press.modifiers.contains(.shift) || !enterSendsMessage {
                replaceSelection(with: "\n")
                return .handled
              }
              if let first = mentionCandidates.first { insertMention(first.username) }
              else { submitMessage() }
              return .handled
            }
            .onSubmit {
              if enterSendsMessage { submitMessage() }
              else { replaceSelection(with: "\n") }
            }

          Button(action: onSend) {
            Image(systemName: sending ? "ellipsis" : "arrow.up")
              .font(.system(size: 14, weight: .bold))
              .frame(width: 24, height: 24)
          }
          .adaptiveGlassButton(prominent: true)
          .controlSize(.small)
          .disabled(trimmedText.isEmpty || text.utf16.count > 5000 || uploading || sending || !model.canSendInSelectedRoom)
          .accessibilityLabel("Send message")
          .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
      }
      .adaptiveGlass(cornerRadius: 21, interactive: true)
    }
    .animation(reduceMotion || reduceInterfaceMotion ? nil : .snappy(duration: 0.2), value: replyingTo?.id)
    .animation(reduceMotion || reduceInterfaceMotion ? nil : .snappy(duration: 0.2), value: mentionCandidates.isEmpty)
    .onChange(of: model.selectedRoom?.identifier) { _, _ in selection = nil }
    .overlay(alignment: .bottomTrailing) {
      if text.utf16.count > 4500 {
        Text("\(text.utf16.count)/5000").font(.caption2.monospacedDigit())
          .foregroundStyle(text.utf16.count > 5000 ? Color.red : Color.secondary)
          .padding(.trailing, 16).offset(y: 14)
      }
    }
    .frame(maxWidth: 900)
    .frame(maxWidth: .infinity)
  }

  private func replyStrip(_ message: PWMessage) -> some View {
    HStack(spacing: 9) {
      Image(systemName: "arrowshape.turn.up.left.fill")
        .font(.caption)
        .foregroundStyle(Color.accentColor)
      VStack(alignment: .leading, spacing: 1) {
        Text("Replying to \(message.displayName)")
          .font(.caption.weight(.semibold))
        Text(message.body.isEmpty ? "Message" : message.body)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 8)
      Button(action: onCancelReply) {
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Cancel reply")
    }
    .padding(.horizontal, 12)
    .padding(.top, 9)
    .padding(.bottom, 6)
    .overlay(alignment: .bottom) { Divider().opacity(0.22) }
  }

  private var trimmedText: String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func submitMessage() {
    guard !trimmedText.isEmpty, !sending, !uploading, model.canSendInSelectedRoom,
      text.utf16.count <= 5000 else { return }
    onSend()
  }

  private var selectedRange: Range<String.Index> {
    if case .selection(let range) = selection?.indices,
      range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex,
      (range.lowerBound == text.endIndex || text.indices.contains(range.lowerBound)),
      (range.upperBound == text.endIndex || text.indices.contains(range.upperBound)) { return range }
    return text.endIndex..<text.endIndex
  }

  private func replaceSelection(with insertion: String) {
    let range = selectedRange
    let offset = range.lowerBound.utf16Offset(in: text)
    text.replaceSubrange(range, with: insertion)
    let cursor = String.Index(utf16Offset: offset + insertion.utf16.count, in: text)
    selection = TextSelection(range: cursor..<cursor)
  }

  private func insertFormat(prefix: String, suffix: String, placeholder: String) {
    let selected = String(text[selectedRange])
    replaceSelection(with: prefix + (selected.isEmpty ? placeholder : selected) + suffix)
  }

  private func insertMention(_ username: String) {
    guard activeMentionQuery != nil, let at = text.lastIndex(of: "@") else { return }
    text.replaceSubrange(at..<text.endIndex, with: "@\(username) ")
  }
}
