import SwiftUI
@preconcurrency import WebRTC

struct CallDockView: View {
  @Environment(AppModel.self) private var model
  private var call: CallController { model.calls }

  var body: some View {
    if call.hasCall || call.error != nil {
      VStack(spacing: 12) {
        if let invitation = call.incoming {
          HStack(spacing: 12) {
            Image(systemName: "phone.arrow.down.left.fill").foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 3) {
              Text(invitation.title).font(.headline).lineLimit(1)
              Text("Incoming call").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Decline", role: .destructive) { Task { await call.decline() } }.adaptiveGlassButton()
            Button("Answer") { call.answer() }.adaptiveGlassButton(prominent: true).tint(.green)
          }
        } else if call.room != nil {
          callHeader
          if call.expanded {
            if call.videoEnabled || !remoteVideos.isEmpty { videoStage }
            if !call.participants.isEmpty { participantStrip }
            callControls
          }
        }
        if let error = call.error {
          HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            Text(error).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
            if call.room != nil {
              Button("Reconnect") { call.reconnect() }.adaptiveGlassButton()
            }
            Button { call.error = nil } label: { Image(systemName: "xmark") }
              .buttonStyle(.plain).accessibilityLabel("Dismiss call error")
          }
        }
      }
      .padding(16)
      .frame(maxWidth: 960)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
      .overlay { RoundedRectangle(cornerRadius: 22).stroke(.primary.opacity(0.07), lineWidth: 0.5) }
      .padding(.horizontal, 12).padding(.vertical, 8)
      .frame(maxWidth: .infinity)
    }
  }

  private var callHeader: some View {
    HStack(spacing: 12) {
      Image(systemName: call.room?.kind == .voice ? "waveform" : "phone.fill")
        .font(.title3).foregroundStyle(call.mediaConnected ? .green : .accentColor)
        .frame(width: 36, height: 36)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
      VStack(alignment: .leading, spacing: 3) {
        Text(call.title).font(.headline).lineLimit(1)
        HStack(spacing: 8) {
          Text(call.joined && !call.peers.isEmpty && !call.mediaConnected ? "Connecting audio…" : call.status)
          if let start = call.startedAt { Text(start, style: .timer).monospacedDigit() }
        }.font(.caption).foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      if !call.expanded {
        control(call.muted ? "Unmute" : "Mute", symbol: call.muted ? "mic.slash.fill" : "mic.fill", active: call.muted) { call.toggleMute() }
          .disabled(call.deafened)
      }
      Button { call.expanded.toggle() } label: { Image(systemName: call.expanded ? "chevron.down" : "chevron.up") }
        .adaptiveGlassButton().accessibilityLabel(call.expanded ? "Minimize call" : "Expand call")
      control("End call", symbol: "phone.down.fill", active: true, tint: .red) { Task { await call.end() } }
    }
  }

  private var callControls: some View {
    AdaptiveGlassContainer {
      HStack(spacing: 12) {
        control(call.muted ? "Unmute" : "Mute", symbol: call.muted ? "mic.slash.fill" : "mic.fill", active: call.muted) { call.toggleMute() }
          .disabled(call.deafened)
        control(call.deafened ? "Undeafen" : "Deafen", symbol: call.deafened ? "headphones.slash" : "headphones", active: call.deafened) { call.toggleDeafen() }
        control(call.videoEnabled ? "Stop video" : "Start video", symbol: call.videoEnabled ? "video.fill" : "video", active: call.videoEnabled) { Task { await call.toggleVideo() } }
          .disabled(!call.joined)
        control("Reconnect call", symbol: "arrow.clockwise") { call.reconnect() }
          .disabled(!call.joined)
        if !call.joined { ProgressView().controlSize(.small) }
      }
      .frame(maxWidth: .infinity)
    }
  }

  private func control(_ title: String, symbol: String, active: Bool = false, tint: Color = .accentColor, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).frame(width: 28, height: 28)
    }
    .adaptiveGlassButton(prominent: active).tint(tint)
    .help(title).accessibilityLabel(title)
  }

  private var participantStrip: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        ForEach(call.participants) { participant in
          HStack(spacing: 5) {
            Image(systemName: participant.deafened ? "headphones.slash" : participant.muted ? "mic.slash" : "person.fill")
            Text(participant.id == call.userID ? "You" : participant.name)
            if participant.reconnecting { Image(systemName: "arrow.triangle.2.circlepath") }
          }
          .font(.caption).padding(.horizontal, 10).padding(.vertical, 7)
          .background(.primary.opacity(0.05), in: Capsule())
          .accessibilityElement(children: .combine)
        }
      }
    }.scrollIndicators(.hidden)
  }

  private var remoteVideos: [NativeCallPeer] {
    call.peers.values.filter { peer in
      peer.remoteVideo != nil && call.participants.contains(where: { $0.id == peer.userID && $0.sharingVideo })
    }
      .sorted { $0.userID < $1.userID }
  }
  private var videoStage: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 10) {
        if call.videoEnabled, let track = call.localVideo { videoTile(track: track, title: "You") }
        ForEach(remoteVideos, id: \.userID) { peer in
          if let track = peer.remoteVideo {
            videoTile(track: track, title: call.participants.first(where: { $0.id == peer.userID })?.name ?? "Participant")
          }
        }
      }
    }.scrollIndicators(.hidden)
  }
  private func videoTile(track: RTCVideoTrack, title: String) -> some View {
    NativeCallVideo(track: track)
      .frame(width: 280, height: 158)
      .background(.black)
      .overlay(alignment: .bottomLeading) {
        Text(title).font(.caption.weight(.medium)).foregroundStyle(.white)
          .padding(7).background(.black.opacity(0.5), in: Capsule()).padding(8)
      }
      .clipShape(RoundedRectangle(cornerRadius: 14))
      .accessibilityLabel("Video from \(title)")
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
