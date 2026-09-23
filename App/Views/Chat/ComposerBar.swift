import SwiftUI

struct ComposerBar: View {
  @Environment(AppModel.self) private var model
  @AppStorage(AppPreferenceKeys.sendTypingIndicators) private var sendTypingIndicators = true
  @Binding var text: String
  let uploading: Bool
  let replyingTo: PWMessage?
  let onCancelReply: () -> Void
  let onAttach: () -> Void
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
          .disabled(uploading)
          .accessibilityLabel(uploading ? "Uploading attachments" : "Attach files")

          TextField("Message \(model.selectedRoom?.title ?? "")", text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1...7)
            .padding(.horizontal, 3)
            .padding(.vertical, 7)
            .onChange(of: text) { _, _ in
              if sendTypingIndicators { model.noteTyping() }
            }
            .onSubmit {
              if let first = mentionCandidates.first { insertMention(first.username) }
              else { onSend() }
            }

          Button(action: onSend) {
            Image(systemName: "arrow.up")
              .font(.system(size: 14, weight: .bold))
              .frame(width: 24, height: 24)
          }
          .adaptiveGlassButton(prominent: true)
          .controlSize(.small)
          .disabled(trimmedText.isEmpty || uploading)
          .accessibilityLabel("Send message")
          .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
      }
      .adaptiveGlass(cornerRadius: 21, interactive: true)
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

  private func insertMention(_ username: String) {
    guard activeMentionQuery != nil, let at = text.lastIndex(of: "@") else { return }
    text.replaceSubrange(at..<text.endIndex, with: "@\(username) ")
  }
}
