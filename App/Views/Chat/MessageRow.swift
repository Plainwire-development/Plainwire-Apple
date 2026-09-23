import SwiftUI
import AVKit

struct MessageRow: View {
  @Environment(AppModel.self) private var model
  @AppStorage(AppPreferenceKeys.compactMessages) private var compactMessages = false
  @State private var showingProfile = false
  let presentation: AppModel.MessagePresentation

  private var message: PWMessage { presentation.message }

  var body: some View {
    VStack(spacing: 0) {
      if let dateHeader = presentation.dateHeader {
        HStack(spacing: 12) {
          Rectangle().fill(.primary.opacity(0.09)).frame(height: 1)
          Text(dateHeader)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .fixedSize()
          Rectangle().fill(.primary.opacity(0.09)).frame(height: 1)
        }
        .padding(.horizontal, 6)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .accessibilityAddTraits(.isHeader)
      }

      HStack(alignment: .top, spacing: compactMessages ? 8 : 11) {
      if presentation.startsGroup {
        RemoteAvatar(
          url: model.mediaURL(message.avatarURL),
          fallback: String(message.displayName.prefix(1)),
          size: compactMessages ? 34 : 40)
      } else {
        Color.clear.frame(width: compactMessages ? 34 : 40, height: 4)
      }

      VStack(alignment: .leading, spacing: compactMessages ? 3 : 5) {
        if presentation.startsGroup { messageHeader }

        if let reply = message.replyTo { replyPreview(reply) }

        if message.deletedAt != nil {
          Label("Message deleted", systemImage: "trash")
            .font(.subheadline.italic())
            .foregroundStyle(.tertiary)
        } else {
          if !presentation.displayBody.isEmpty {
            Text(presentation.displayMarkdown)
              .textSelection(.enabled)
              .font(.body)
              .lineSpacing(compactMessages ? 0.5 : 1.6)
              .fixedSize(horizontal: false, vertical: true)
          }

          if !presentation.attachments.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
              ForEach(presentation.attachments) { attachment in
                MessageAttachmentView(attachment: attachment)
              }
            }
            .padding(.top, presentation.displayBody.isEmpty ? 0 : 4)
          }
        }

        if message.deletedAt == nil {
          ReactionBar(message: message)
            .padding(.top, message.reactions.isEmpty ? 1 : 3)
        }
      }
      .frame(maxWidth: 720, alignment: .leading)

      Spacer(minLength: 0)
      }
      .padding(.horizontal, 6)
      .padding(.vertical, presentation.startsGroup ? (compactMessages ? 5 : 8) : 2)
      .contentShape(Rectangle())
      .modifier(MessageHoverSurfaceModifier())
    }
    .sheet(isPresented: $showingProfile) { PersonProfileSheet(userID: message.userId) }
  }

  private var messageHeader: some View {
    HStack(alignment: .firstTextBaseline, spacing: 7) {
      Button(message.displayName) { showingProfile = true }
        .buttonStyle(.plain)
        .font(compactMessages ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
        .lineLimit(1)
        .accessibilityHint("View profile")
      Text(presentation.timestampText)
        .font(.caption2)
        .foregroundStyle(.tertiary)
      if message.editedAt != nil {
        Text("edited")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
    }
  }

  private func replyPreview(_ reply: PWReplyPreview) -> some View {
    HStack(spacing: 7) {
      Capsule().fill(Color.accentColor.opacity(0.5)).frame(width: 2.5, height: 28)
      VStack(alignment: .leading, spacing: 1) {
        Text(reply.displayName)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        Text(reply.body)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Reply to \(reply.displayName): \(reply.body)")
  }
}

private struct ReactionBar: View {
  @Environment(AppModel.self) private var model
  let message: PWMessage

  private let quickReactions = ["👍", "❤️", "😂", "🔥", "🎉", "😮", "😢", "👏"]

  var body: some View {
    ReactionFlowLayout(spacing: 5) {
      ForEach(message.reactions, id: \.emoji) { reaction in
        Button {
          Task { await model.toggleReaction(reaction.emoji, on: message) }
        } label: {
          HStack(spacing: 4) {
            Text(reaction.emoji)
              .font(.system(size: 14))
            Text("\(reaction.count)")
              .font(.caption2.weight(.semibold))
              .monospacedDigit()
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(
            reaction.me ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05),
            in: Capsule(style: .continuous)
          )
          .overlay {
            Capsule(style: .continuous)
              .stroke(
                reaction.me ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.08),
                lineWidth: 0.65)
          }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(reaction.emoji), \(reaction.count) reactions")
        .accessibilityValue(reaction.me ? "You reacted" : "Not reacted")
      }

      Menu {
        ForEach(quickReactions, id: \.self) { emoji in
          Button(emoji) { Task { await model.toggleReaction(emoji, on: message) } }
        }
      } label: {
        Image(systemName: message.reactions.isEmpty ? "face.smiling" : "plus")
          .font(.caption.weight(.semibold))
          .frame(width: 25, height: 22)
          .background(.primary.opacity(0.045), in: Capsule(style: .continuous))
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Add reaction")
    }
  }
}

private struct MessageAttachmentView: View {
  @Environment(AppModel.self) private var model
  let attachment: AppModel.MessageAttachment
  @State private var revealed = false

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      if attachment.isSpoiler && !revealed {
        Button {
          withAnimation(.easeInOut(duration: 0.2)) { revealed = true }
        } label: {
          HStack(spacing: 12) {
            Image(systemName: "eye.slash.fill")
              .font(.title3)
              .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
              Text("Spoiler attachment").font(.subheadline.weight(.semibold))
              Text("Tap to reveal \(attachment.name)")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "eye").foregroundStyle(.secondary)
          }
          .padding(16)
          .frame(maxWidth: 520, minHeight: 84)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
          .overlay {
            RoundedRectangle(cornerRadius: 16)
              .strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 1)
          }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reveal spoiler attachment: \(attachment.name)")
      } else {
        attachmentContent
        if attachment.isSpoiler {
          Button("Hide spoiler", systemImage: "eye.slash") { revealed = false }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  @ViewBuilder private var attachmentContent: some View {
    switch attachment.kind {
    case .image:
      AttachmentImage(name: attachment.name, url: model.mediaURL(attachment.url))
    case .video:
      VideoAttachment(name: attachment.name, url: model.mediaURL(attachment.url))
    case .voice:
      AttachmentLinkCard(
        name: attachment.name, url: model.mediaURL(attachment.url), symbol: "waveform",
        subtitle: "Voice note")
    case .file:
      AttachmentLinkCard(
        name: attachment.name, url: model.mediaURL(attachment.url), symbol: "doc.fill",
        subtitle: "Attachment")
    }
  }
}

private struct AttachmentImage: View {
  let name: String
  let url: URL?

  var body: some View {
    Group {
      if let url {
        CachedRemoteImage(url: url, pixelSize: 1200) { phase in
          switch phase {
          case .empty:
            attachmentPlaceholder(progress: true)
          case .success(let image):
            image
              .resizable()
              .scaledToFit()
              .frame(maxWidth: 520, maxHeight: 440, alignment: .leading)
              .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
              .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                  .stroke(.primary.opacity(0.07), lineWidth: 0.5)
              }
              .accessibilityLabel(name.isEmpty ? "Image attachment" : name)
          case .failure:
            attachmentPlaceholder(progress: false)
          @unknown default:
            attachmentPlaceholder(progress: false)
          }
        }
      } else {
        attachmentPlaceholder(progress: false)
      }
    }
    .frame(maxWidth: 520, alignment: .leading)
  }

  private func attachmentPlaceholder(progress: Bool) -> some View {
    HStack(spacing: 10) {
      if progress {
        ProgressView().controlSize(.small)
      } else {
        Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(progress ? "Loading image…" : "Image unavailable")
          .font(.subheadline.weight(.medium))
        if !name.isEmpty { Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
      }
      Spacer(minLength: 0)
    }
    .padding(12)
    .frame(maxWidth: 420, minHeight: 62)
    .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}

private struct VideoAttachment: View {
  let name: String
  let url: URL?
  @State private var player: AVPlayer?

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      if let player {
        VideoPlayer(player: player)
          .frame(maxWidth: 520)
          .frame(height: 292)
          .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
          .accessibilityLabel(name.isEmpty ? "Video attachment" : name)
      } else {
        Button {
          guard let url else { return }
          let next = AVPlayer(url: url)
          next.automaticallyWaitsToMinimizeStalling = false
          player = next
          next.play()
        } label: {
          ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
              .fill(Color.accentColor.opacity(0.09))
            Image(systemName: "play.circle.fill")
              .font(.system(size: 48))
              .foregroundStyle(Color.accentColor)
          }
          .frame(maxWidth: 520)
          .frame(height: 190)
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
        .accessibilityLabel("Play video: \(name)")
      }
      HStack(spacing: 8) {
        Image(systemName: "film").foregroundStyle(Color.accentColor)
        Text(name.isEmpty ? "Video" : name).lineLimit(1)
        Spacer(minLength: 8)
        if let url {
          Link(destination: url) {
            Image(systemName: "arrow.up.right.square")
          }
          .accessibilityLabel("Open video in browser")
        }
      }
      .font(.caption.weight(.medium))
      .foregroundStyle(.secondary)
    }
    .frame(maxWidth: 520, alignment: .leading)
    .onDisappear { player?.pause() }
  }
}

private struct AttachmentLinkCard: View {
  let name: String
  let url: URL?
  let symbol: String
  let subtitle: String

  var body: some View {
    Group {
      if let url {
        Link(destination: url) { cardContent }
          .buttonStyle(.plain)
      } else {
        cardContent.opacity(0.7)
      }
    }
    .frame(maxWidth: 420, alignment: .leading)
  }

  private var cardContent: some View {
    HStack(spacing: 11) {
      Image(systemName: symbol)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(Color.accentColor)
        .frame(width: 36, height: 36)
        .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
      VStack(alignment: .leading, spacing: 2) {
        Text(name.isEmpty ? subtitle : name)
          .font(.subheadline.weight(.medium))
          .lineLimit(1)
        Text(subtitle).font(.caption).foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(
        .tertiary)
    }
    .padding(11)
    .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(.primary.opacity(0.07), lineWidth: 0.5)
    }
  }
}

private struct MessageHoverSurfaceModifier: ViewModifier {
  @State private var hovering = false

  @ViewBuilder func body(content: Content) -> some View {
    #if os(macOS)
      content
        .background(
          hovering ? Color.primary.opacity(0.035) : Color.clear,
          in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .onHover { hovering = $0 }
    #else
      content
    #endif
  }
}

private struct ReactionFlowLayout: Layout {
  let spacing: CGFloat

  func sizeThatFits(
    proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) -> CGSize {
    let maxWidth = proposal.width ?? .greatestFiniteMagnitude
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0
    var usedWidth: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x > 0, x + size.width > maxWidth {
        x = 0
        y += rowHeight + spacing
        rowHeight = 0
      }
      usedWidth = max(usedWidth, x + size.width)
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }
    return CGSize(width: min(usedWidth, maxWidth), height: y + rowHeight)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    var x = bounds.minX
    var y = bounds.minY
    var rowHeight: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x > bounds.minX, x + size.width > bounds.maxX {
        x = bounds.minX
        y += rowHeight + spacing
        rowHeight = 0
      }
      subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }
  }
}
