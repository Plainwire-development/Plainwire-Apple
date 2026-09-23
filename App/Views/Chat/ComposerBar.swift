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

  var body: some View {
    AdaptiveGlassContainer(spacing: 8) {
      VStack(spacing: 0) {
        if let replyingTo { replyStrip(replyingTo) }

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
            .onSubmit(onSend)

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
}
