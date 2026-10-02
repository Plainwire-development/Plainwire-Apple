import SwiftUI
@preconcurrency import WebRTC

struct CallDockView: View {
  @Environment(AppModel.self) private var model
  @State private var preferredSize = CGSize(width: 480, height: 380)
  @State private var panelOrigin: CGPoint?
  @GestureState private var dragTranslation = CGSize.zero
  @GestureState private var resizeTranslation = CGSize.zero
  private var call: CallController { model.calls }
  private var expanded: Bool { call.room != nil && call.expanded }

  var body: some View {
    if call.hasCall || call.error != nil {
      GeometryReader { geometry in
        let restingSize = CGSize(width: preferredSize.width, height: expanded ? preferredSize.height : compactHeight)
        let anchor = PWCallPanelLayout(container: geometry.size, preferredSize: restingSize, origin: panelOrigin)
        let requestedSize = CGSize(
          width: preferredSize.width + resizeTranslation.width,
          height: expanded ? max(280, preferredSize.height + resizeTranslation.height) : compactHeight)
        let moved = CGPoint(x: anchor.origin.x + dragTranslation.width, y: anchor.origin.y + dragTranslation.height)
        let layout = PWCallPanelLayout(container: geometry.size, preferredSize: requestedSize, origin: moved)
        panel(layout: layout, container: geometry.size)
          .position(x: layout.origin.x + layout.size.width / 2, y: layout.origin.y + layout.size.height / 2)
      }
    }
  }

  private var compactHeight: CGFloat {
    if call.incoming != nil { return call.error == nil ? 188 : 252 }
    if call.room == nil { return 160 }
    return call.error == nil ? 124 : 212
  }

  private func panel(layout: PWCallPanelLayout, container: CGSize) -> some View {
    VStack(spacing: 12) {
      HStack(spacing: 8) {
        HStack(spacing: 8) {
          Image(systemName: "hand.draw").font(.caption)
          Text(call.incoming != nil ? "INCOMING CALL" : "PLAINWIRE CALL")
            .font(.caption2.weight(.semibold)).tracking(1)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .gesture(dragGesture(layout: layout, container: container))
        .help("Drag to move the call panel")
        .accessibilityLabel("Move call panel")
        Menu {
          Button("Reset position and size") { panelOrigin = nil; preferredSize = CGSize(width: 480, height: 380) }
          Button("Small panel") { preferredSize = CGSize(width: 380, height: 320) }
          Button("Large panel") { preferredSize = CGSize(width: 720, height: 520) }
        } label: { Image(systemName: "ellipsis").frame(width: 24, height: 20) }
        .menuStyle(.borderlessButton).fixedSize()
        .accessibilityLabel("Call panel options")
      }
      if let invitation = call.incoming {
        ScrollView {
          HStack(spacing: 12) {
            callIcon("phone.arrow.down.left.fill", color: .green)
            VStack(alignment: .leading, spacing: 3) {
              Text(invitation.title).font(.headline).lineLimit(2)
              Text("Incoming call").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
          }
          errorNotice
        }
        HStack(spacing: 12) {
          Button("Decline", role: .destructive) { Task { await call.decline() } }.adaptiveGlassButton()
          Button("Answer") { call.answer() }.adaptiveGlassButton(prominent: true).tint(.green)
        }.frame(maxWidth: .infinity)
      } else if call.room != nil {
        callHeader
        if expanded {
          ScrollView {
            VStack(spacing: 14) {
              if call.videoEnabled || !remoteVideos.isEmpty { videoStage(width: layout.size.width - 32) }
              else { audioStage }
              if !call.participants.isEmpty { participantStrip }
              errorNotice
            }.frame(maxWidth: .infinity)
          }.scrollIndicators(.hidden)
          Divider()
          callControls
        } else if call.error != nil {
          ScrollView { errorNotice }
        }
      } else {
        ScrollView { errorNotice }
      }
    }
    .padding(16)
    .padding(.bottom, expanded ? 10 : 0)
    .frame(width: layout.size.width, height: layout.size.height, alignment: .top)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    .overlay { RoundedRectangle(cornerRadius: 24).stroke(.primary.opacity(0.10), lineWidth: 0.5) }
    .overlay(alignment: .bottomTrailing) {
      if expanded {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
          .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
          .frame(width: 30, height: 30).contentShape(Rectangle())
          .gesture(resizeGesture(container: container))
          .help("Drag to resize the call panel")
          .accessibilityLabel("Call panel size")
          .accessibilityAdjustableAction { direction in
            let delta: CGFloat = direction == .increment ? 40 : -40
            preferredSize = CGSize(width: max(320, preferredSize.width + delta), height: max(280, preferredSize.height + delta))
          }
      }
    }
    .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
    .onChange(of: container) { _, size in
      let fitted = PWCallPanelLayout(container: size, preferredSize: layout.size, origin: panelOrigin)
      if panelOrigin != nil { panelOrigin = fitted.origin }
    }
  }

  private func dragGesture(layout: PWCallPanelLayout, container: CGSize) -> some Gesture {
    // Remove the live translation to keep the anchor stable throughout the drag.
    let anchor = PWCallPanelLayout(container: container, preferredSize: layout.size, origin: panelOrigin).origin
    return DragGesture(minimumDistance: 3)
      .updating($dragTranslation) { value, state, _ in state = value.translation }
      .onEnded { value in
        panelOrigin = PWCallPanelLayout(container: container, preferredSize: layout.size,
          origin: CGPoint(x: anchor.x + value.translation.width, y: anchor.y + value.translation.height)).origin
      }
  }

  private func resizeGesture(container: CGSize) -> some Gesture {
    let anchor = PWCallPanelLayout(container: container, preferredSize: preferredSize, origin: panelOrigin)
    return DragGesture(minimumDistance: 2)
      .updating($resizeTranslation) { value, state, _ in state = value.translation }
      .onEnded { value in
        let requested = CGSize(width: preferredSize.width + value.translation.width,
          height: max(280, preferredSize.height + value.translation.height))
        let resized = PWCallPanelLayout(container: container, preferredSize: requested, origin: anchor.origin)
        preferredSize = resized.size
        panelOrigin = resized.origin
      }
  }

  private var callHeader: some View {
    HStack(spacing: 10) {
      callIcon(call.room?.kind == .voice ? "waveform" : "phone.fill", color: call.mediaConnected ? .green : .accentColor)
      VStack(alignment: .leading, spacing: 3) {
        Text(call.title).font(.headline).lineLimit(1)
        HStack(spacing: 6) {
          Text(call.joined && !call.peers.isEmpty && !call.mediaConnected ? "Connecting audio…" : call.status).lineLimit(1)
          if let start = call.startedAt { Text(start, style: .timer).monospacedDigit() }
        }.font(.caption).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      if !expanded {
        control(call.muted ? "Unmute" : "Mute", symbol: call.muted ? "mic.slash.fill" : "mic.fill", active: call.muted) { call.toggleMute() }
          .disabled(call.deafened)
      }
      Button { call.expanded.toggle() } label: { Image(systemName: expanded ? "chevron.down" : "chevron.up") }
        .adaptiveGlassButton().accessibilityLabel(expanded ? "Minimize call" : "Expand call")
      control("End call", symbol: "phone.down.fill", active: true, tint: .red) { Task { await call.end() } }
    }
  }

  private func callIcon(_ symbol: String, color: Color) -> some View {
    Image(systemName: symbol).font(.title3).foregroundStyle(color)
      .frame(width: 38, height: 38)
      .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
  }

  @ViewBuilder private var errorNotice: some View {
    if let error = call.error {
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
          Text(error).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
          Button { call.error = nil } label: { Image(systemName: "xmark") }
            .buttonStyle(.plain).accessibilityLabel("Dismiss call error")
        }
        if call.room != nil { Button("Reconnect") { call.reconnect() }.adaptiveGlassButton() }
      }.padding(10).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
  }

  private var audioStage: some View {
    VStack(spacing: 10) {
      Image(systemName: call.mediaConnected ? "waveform" : "person.2.fill")
        .font(.system(size: 30, weight: .medium)).foregroundStyle(Color.accentColor)
        .frame(width: 72, height: 72)
        .background(Color.accentColor.opacity(0.10), in: Circle())
      Text(call.participants.count > 1 ? "\(call.participants.count) people in this call" : "Waiting for others to join")
        .font(.subheadline).foregroundStyle(.secondary)
    }.frame(maxWidth: .infinity).padding(.vertical, 12)
  }

  private var callControls: some View {
    AdaptiveGlassContainer {
      HStack(spacing: 12) {
        control(call.muted ? "Unmute" : "Mute", symbol: call.muted ? "mic.slash.fill" : "mic.fill", active: call.muted) { call.toggleMute() }
          .disabled(call.deafened)
        control(call.deafened ? "Undeafen" : "Deafen", symbol: call.deafened ? "headphones.slash" : "headphones", active: call.deafened) { call.toggleDeafen() }
        control(call.videoEnabled ? "Stop video" : "Start video", symbol: call.videoEnabled ? "video.fill" : "video", active: call.videoEnabled) { Task { await call.toggleVideo() } }
          .disabled(!call.joined)
        control("Reconnect call", symbol: "arrow.clockwise") { call.reconnect() }.disabled(!call.joined)
        if !call.joined { ProgressView().controlSize(.small) }
      }.frame(maxWidth: .infinity)
    }
  }

  private func control(_ title: String, symbol: String, active: Bool = false, tint: Color = .accentColor, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).frame(width: 24, height: 24)
    }.adaptiveGlassButton(prominent: active).tint(tint).help(title).accessibilityLabel(title)
  }

  private var participantStrip: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        ForEach(call.participants) { participant in
          HStack(spacing: 5) {
            Image(systemName: participant.deafened ? "headphones.slash" : participant.muted ? "mic.slash" : "person.fill")
            Text(participant.id == call.userID ? "You" : participant.name)
            if participant.reconnecting { Image(systemName: "arrow.triangle.2.circlepath") }
          }.font(.caption).padding(.horizontal, 10).padding(.vertical, 7)
            .background(.primary.opacity(0.05), in: Capsule()).accessibilityElement(children: .combine)
        }
      }
    }.scrollIndicators(.hidden)
  }

  private var remoteVideos: [NativeCallPeer] {
    call.peers.values.filter { peer in
      peer.remoteVideo != nil && call.participants.contains(where: { $0.id == peer.userID && $0.sharingVideo })
    }.sorted { $0.userID < $1.userID }
  }

  private func videoStage(width: CGFloat) -> some View {
    let tracks = (call.videoEnabled ? 1 : 0) + remoteVideos.count
    let tileWidth = tracks > 1 ? max(180, width * 0.72) : width
    return ScrollView(.horizontal) {
      HStack(spacing: 10) {
        if call.videoEnabled, let track = call.localVideo { videoTile(track: track, title: "You", width: tileWidth) }
        ForEach(remoteVideos, id: \.userID) { peer in
          if let track = peer.remoteVideo {
            videoTile(track: track, title: call.participants.first(where: { $0.id == peer.userID })?.name ?? "Participant", width: tileWidth)
          }
        }
      }
    }.scrollIndicators(.hidden)
  }

  private func videoTile(track: RTCVideoTrack, title: String, width: CGFloat) -> some View {
    NativeCallVideo(track: track).frame(width: width, height: width * 9 / 16).background(.black)
      .overlay(alignment: .bottomLeading) {
        Text(title).font(.caption.weight(.medium)).foregroundStyle(.white)
          .padding(7).background(.black.opacity(0.5), in: Capsule()).padding(8)
      }.clipShape(RoundedRectangle(cornerRadius: 14)).accessibilityLabel("Video from \(title)")
  }
}

private struct NativeCallVideo: View {
  let track: RTCVideoTrack
  var body: some View { NativeVideoRenderer(track: track) }
}

#if os(macOS)
private struct NativeVideoRenderer: NSViewRepresentable {
  let track: RTCVideoTrack
  func makeCoordinator() -> VideoRendererCoordinator { VideoRendererCoordinator() }
  func makeNSView(context: Context) -> RTCMTLNSVideoView {
    let view = RTCMTLNSVideoView(frame: .zero)
    context.coordinator.attach(track, to: view)
    return view
  }
  func updateNSView(_ view: RTCMTLNSVideoView, context: Context) { context.coordinator.attach(track, to: view) }
  static func dismantleNSView(_ view: RTCMTLNSVideoView, coordinator: VideoRendererCoordinator) { coordinator.detach() }
}
#else
private struct NativeVideoRenderer: UIViewRepresentable {
  let track: RTCVideoTrack
  func makeCoordinator() -> VideoRendererCoordinator { VideoRendererCoordinator() }
  func makeUIView(context: Context) -> RTCMTLVideoView {
    let view = RTCMTLVideoView(frame: .zero)
    view.videoContentMode = .scaleAspectFit
    context.coordinator.attach(track, to: view)
    return view
  }
  func updateUIView(_ view: RTCMTLVideoView, context: Context) { context.coordinator.attach(track, to: view) }
  static func dismantleUIView(_ view: RTCMTLVideoView, coordinator: VideoRendererCoordinator) { coordinator.detach() }
}
#endif

@MainActor private final class VideoRendererCoordinator {
  private var track: RTCVideoTrack?
  private var renderer: (any RTCVideoRenderer)?
  func attach(_ track: RTCVideoTrack, to renderer: any RTCVideoRenderer) {
    guard self.track !== track else { return }
    detach()
    self.track = track
    self.renderer = renderer
    track.add(renderer)
  }
  func detach() {
    if let track, let renderer { track.remove(renderer) }
    track = nil; renderer = nil
  }
}
