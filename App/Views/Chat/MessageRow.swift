import SwiftUI

struct MessageRow: View {
  @Environment(AppModel.self) private var model
  @AppStorage(AppPreferenceKeys.compactMessages) private var compactMessages = false
  @State private var showingProfile = false
  @State private var hovering = false
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

        if let reply = message.replyTo {
          Button {
            Task { await model.jumpToMessage(id: reply.id) }
          } label: { replyPreview(reply) }.buttonStyle(.plain)
        }
        if let forwarded = message.forwardedFrom {
          Label("Forwarded from \(forwarded.displayName)", systemImage: "arrowshape.turn.up.right.fill")
            .font(.caption).foregroundStyle(.secondary)
        }

        if message.deletedAt != nil {
          Label("Message deleted", systemImage: "trash")
            .font(.subheadline.italic())
            .foregroundStyle(.tertiary)
        } else {
          if !presentation.displayBody.isEmpty {
            MessageBodyView(presentation: presentation, compact: compactMessages)
          }

          if !presentation.attachments.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
              ForEach(Array(presentation.attachments.enumerated()), id: \.offset) { item in
                MessageAttachmentView(attachment: item.element)
              }
            }
            .padding(.top, presentation.displayBody.isEmpty ? 0 : 4)
          }
        }

        if message.deletedAt == nil {
          if !message.reactions.isEmpty {
            ReactionBar(message: message).padding(.top, 3)
          }
        }
      }
      .frame(maxWidth: 720, alignment: .leading)

      Spacer(minLength: 0)
      }
      .padding(.horizontal, 6)
      .padding(.vertical, presentation.startsGroup ? (compactMessages ? 5 : 8) : 2)
      .background((isMentioned || model.messageJumpID == message.id) ? Color.accentColor.opacity(0.09) : Color.clear,
                  in: RoundedRectangle(cornerRadius: 10))
      .contentShape(Rectangle())
      .modifier(MessageHoverSurfaceModifier())
      .onHover { hovering = $0 }
      .overlay(alignment: .topTrailing) {
        #if os(macOS)
        if hovering && message.deletedAt == nil {
          HStack(spacing: 8) {
            Button { Task { await model.toggleReaction("👍", on: message) } } label: { Image(systemName: "hand.thumbsup") }
              .help("React with thumbs up")
            Button { model.replyTarget = message } label: { Image(systemName: "arrowshape.turn.up.left") }
              .help("Reply")
            if message.scope == "channel", model.canPinMessages {
              Button { Task { _ = await model.togglePin(message) } } label: { Image(systemName: message.pinned ? "pin.slash" : "pin") }
                .help(message.pinned ? "Unpin" : "Pin")
            }
          }
          .font(.caption).buttonStyle(.plain).padding(8)
          .background(.regularMaterial, in: Capsule())
          .overlay(Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
          .padding(.trailing, 6)
        }
        #endif
      }
    }
    .sheet(isPresented: $showingProfile) { PersonProfileSheet(userID: message.userId) }
  }

  private var isMentioned: Bool {
    guard message.userId != model.session?.user.id,
      let username = model.session?.user.username, !username.isEmpty
    else { return false }
    let body = message.body.replacingOccurrences(
      of: #"(?s)```.*?```"#, with: "", options: .regularExpression)
    let token = NSRegularExpression.escapedPattern(for: username)
    let pattern = "(?:^|[^A-Za-z0-9_.-])@\(token)(?![A-Za-z0-9_-])"
    return body.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
  }

  private var messageHeader: some View {
    HStack(alignment: .firstTextBaseline, spacing: 7) {
      Button(message.displayName) { showingProfile = true }
        .buttonStyle(.plain)
        .font(compactMessages ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
        .lineLimit(1)
        .foregroundStyle(Color(plainwireHex: message.roleColor) ?? .primary)
        .accessibilityHint("View profile")
      if message.isBot {
        Text("APP").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.accentColor)
          .padding(.horizontal, 4).padding(.vertical, 2)
          .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
      }
      if message.pinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary) }
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
        Text(PWMessageText.redactingSpoilers(reply.body))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Reply to \(reply.displayName): \(PWMessageText.redactingSpoilers(reply.body))")
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
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @AppStorage(AppPreferenceKeys.reduceInterfaceMotion) private var reduceInterfaceMotion = false
  let attachment: AppModel.MessageAttachment
  @State private var revealed = false

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      if attachment.isSpoiler && !revealed {
        Button {
          withAnimation(reduceMotion || reduceInterfaceMotion ? nil : .easeInOut(duration: 0.2)) { revealed = true }
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
    .onChange(of: attachment) { _, _ in revealed = false }
  }

  @ViewBuilder private var attachmentContent: some View {
    switch attachment.kind {
    case .image:
      AttachmentImage(name: attachment.name, url: model.mediaURL(attachment.url))
    case .video:
      VideoAttachment(name: attachment.name, url: model.mediaURL(attachment.url))
    case .voice:
      AudioAttachment(name: attachment.name, url: model.mediaURL(attachment.url))
    case .file:
      AttachmentLinkCard(
        name: attachment.name, url: model.mediaURL(attachment.url), symbol: "doc.fill",
        subtitle: "Attachment")
    }
  }
}

private struct AttachmentImage: View {
  @Environment(AppModel.self) private var model
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
              .onTapGesture { Task { await model.previewAttachment(url: url, name: name) } }
              .accessibilityAddTraits(.isButton)
              .accessibilityAction { Task { await model.previewAttachment(url: url, name: name) } }
              .accessibilityHint("Preview full image")
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
  @Environment(\.scenePhase) private var scenePhase
  @State private var playback = MediaPlayback()

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ZStack {
        if let player = playback.player {
          NativeVideoPlayer(player: player)
            .overlay {
              if playback.loading { ProgressView().tint(.white).allowsHitTesting(false) }
            }
        } else {
          Button {
            if let url { playback.load(url) }
          } label: {
            ZStack {
              RoundedRectangle(cornerRadius: 16).fill(Color.accentColor.opacity(0.09))
              VStack(spacing: 8) {
                if playback.loading { ProgressView() }
                else {
                  Image(systemName: playback.error == nil ? "play.circle.fill" : "arrow.clockwise.circle.fill")
                    .font(.system(size: 44)).foregroundStyle(Color.accentColor)
                }
                Text(playback.loading ? "Loading video…" : url == nil ? "Video unavailable" : playback.error == nil ? "Play video" : "Retry video")
                  .font(.caption.weight(.medium)).foregroundStyle(.secondary)
              }
            }
          }
          .buttonStyle(.plain)
          .disabled(url == nil || playback.loading)
          .accessibilityLabel("Play video: \(name)")
        }
      }
      .aspectRatio(16.0 / 9.0, contentMode: .fit)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
      .accessibilityLabel(name.isEmpty ? "Video attachment" : name)
      if let error = playback.error { Text(error).font(.caption).foregroundStyle(.secondary) }
      HStack(spacing: 8) {
        Image(systemName: "film").foregroundStyle(Color.accentColor)
        Text(name.isEmpty ? "Video" : name).lineLimit(1)
        Spacer(minLength: 8)
        if let url {
          Link(destination: url) { Image(systemName: "arrow.up.right.square") }
            .accessibilityLabel("Open video in browser")
        }
      }
      .font(.caption.weight(.medium)).foregroundStyle(.secondary)
    }
    .frame(maxWidth: 520, alignment: .leading)
    .onDisappear { playback.reset() }
    .onChange(of: url) { _, _ in playback.reset() }
    .onChange(of: scenePhase) { _, phase in if phase != .active { playback.pause() } }
  }
}

private struct AttachmentLinkCard: View {
  @Environment(AppModel.self) private var model
  let name: String
  let url: URL?
  let symbol: String
  let subtitle: String

  var body: some View {
    Group {
      if let url {
        Button { Task { await model.previewAttachment(url: url, name: name) } } label: { cardContent }
          .disabled(model.downloadingAttachment)
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

private struct MessageBodyView: View {
  let presentation: AppModel.MessagePresentation
  let compact: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @AppStorage(AppPreferenceKeys.reduceInterfaceMotion) private var reduceInterfaceMotion = false
  @State private var revealed = false
  private var hasSpoilers: Bool { presentation.displayBody.contains("||") }
  private var blocks: [AppModel.MessageTextBlock] {
    hasSpoilers && !revealed ? presentation.redactedTextBlocks : presentation.textBlocks
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(blocks) { value in
        switch value.block.kind {
        case .markdown:
          Text(value.markdown).textSelection(.enabled).font(.body)
            .lineSpacing(compact ? 0.5 : 1.6).fixedSize(horizontal: false, vertical: true)
        case .code(let language):
          VStack(alignment: .leading, spacing: 0) {
            HStack {
              Text(language.isEmpty ? "Code" : language).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
              Spacer()
              Button {
                #if os(macOS)
                  NSPasteboard.general.clearContents()
                  NSPasteboard.general.setString(value.block.text, forType: .string)
                #else
                  UIPasteboard.general.string = value.block.text
                #endif
              } label: { Image(systemName: "doc.on.doc").font(.caption2) }
                .buttonStyle(.plain).help("Copy code").accessibilityLabel("Copy code")
            }.padding(.horizontal, 12).padding(.vertical, 8)
            Divider().opacity(0.4)
            ScrollView(.horizontal) {
              Text(value.block.text).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false).padding(12)
            }
          }.background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
        }
      }
      if hasSpoilers {
        Button {
          withAnimation(reduceMotion || reduceInterfaceMotion ? nil : .easeInOut(duration: 0.15)) { revealed.toggle() }
        } label: { Label(revealed ? "Hide spoilers" : "Reveal spoilers", systemImage: revealed ? "eye.slash" : "eye") }
          .font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
      }
    }
    .onChange(of: presentation.message.body) { _, _ in revealed = false }
  }
}

private struct AudioAttachment: View {
  let name: String
  let url: URL?
  @Environment(\.scenePhase) private var scenePhase
  @State private var playback = MediaPlayback()
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        Button {
          if playback.player != nil { playback.togglePlayback() }
          else if let url { playback.load(url, audio: true) }
        } label: {
          Group {
            if playback.loading { ProgressView().controlSize(.small) }
            else { Image(systemName: playback.playing ? "pause.fill" : "play.fill").font(.headline) }
          }
          .frame(width: 36, height: 36)
          .foregroundStyle(Color.accentColor)
          .background(Color.accentColor.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain).disabled(url == nil || playback.loading)
        .accessibilityLabel(playback.playing ? "Pause voice note" : "Play voice note")
        VStack(alignment: .leading, spacing: 6) {
          Text(name.isEmpty ? "Voice note" : name).font(.subheadline.weight(.medium)).lineLimit(1)
          ProgressView(value: playback.progress).tint(.accentColor)
          Text(playback.loading ? "Loading…" : "\(timestamp(playback.elapsed)) / \(timestamp(playback.duration))")
            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
      }
      if let error = playback.error {
        Text(error).font(.caption).foregroundStyle(.secondary)
        if let url { Link("Open voice note in browser", destination: url).font(.caption) }
      }
    }
    .padding(12).frame(maxWidth: 420)
    .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
    .onDisappear { playback.reset() }
    .onChange(of: url) { _, _ in playback.reset() }
    .onChange(of: scenePhase) { _, phase in if phase != .active { playback.pause() } }
  }
  private func timestamp(_ value: Double) -> String {
    guard value.isFinite, value >= 0 else { return "0:00" }
    let seconds = Int(min(value, 86400))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
  }
}
