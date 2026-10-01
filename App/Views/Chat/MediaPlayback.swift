import SwiftUI
import Observation
@preconcurrency import AVFoundation
import AVKit

/// Owns loading and observers so leaving a row also releases its media resources.
@MainActor @Observable
final class MediaPlayback {
  private(set) var player: AVPlayer?
  private(set) var loading = false
  private(set) var playing = false
  private(set) var elapsed: Double = 0
  private(set) var duration: Double = 0
  private(set) var error: String?
  @ObservationIgnored private var preparation: Task<Void, Never>?
  @ObservationIgnored private var asset: AVURLAsset?
  @ObservationIgnored private var statusObservation: NSKeyValueObservation?
  @ObservationIgnored private var playbackObservation: NSKeyValueObservation?
  @ObservationIgnored private var timeObserver: Any?
  @ObservationIgnored private var generation = 0

  var progress: Double { duration > 0 ? min(1, max(0, elapsed / duration)) : 0 }

  func load(_ url: URL, audio: Bool = false) {
    guard !loading else { return }
    reset()
    loading = true
    let requestGeneration = generation
    let asset = AVURLAsset(url: url, options: [
      AVURLAssetHTTPCookiesKey: HTTPCookieStorage.shared.cookies(for: url) ?? []
    ])
    self.asset = asset
    preparation = Task { [weak self] in
      do {
        guard try await asset.load(.isPlayable) else { throw PlainwireAPIError.invalidFile }
        let length = audio ? try await asset.load(.duration).seconds : 0
        try Task.checkCancellation()
        guard let self, self.generation == requestGeneration else { return }
        let item = AVPlayerItem(asset: asset)
        // Bound the forward buffer for long attachments and slow connections.
        item.preferredForwardBufferDuration = 10
        let player = AVPlayer(playerItem: item)
        self.duration = length.isFinite && length > 0 ? length : 0
        self.player = player
        self.statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
          let failed = item.status == .failed
          let ready = item.status == .readyToPlay
          Task { @MainActor [weak self, weak item] in
            guard let self, let item, self.player?.currentItem === item else { return }
            if ready { self.loading = false }
            if failed { self.fail() }
          }
        }
        self.playbackObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
          Task { @MainActor [weak self, weak player] in
            guard let self, let player, self.player === player else { return }
            self.playing = player.timeControlStatus == .playing
            self.updateTimeObservation(audio: audio)
          }
        }
        player.play()
      } catch {
        guard !Task.isCancelled, let self, self.generation == requestGeneration else { return }
        self.fail()
      }
    }
  }

  func togglePlayback() {
    guard let player else { return }
    if player.timeControlStatus != .paused { player.pause() }
    else {
      if duration > 0, elapsed >= duration - 0.1 {
        player.seek(to: .zero)
        elapsed = 0
      }
      player.play()
    }
  }

  func pause() { player?.pause() }

  func reset() {
    generation += 1
    preparation?.cancel()
    preparation = nil
    asset?.cancelLoading()
    asset = nil
    statusObservation?.invalidate()
    playbackObservation?.invalidate()
    statusObservation = nil
    playbackObservation = nil
    removeTimeObservation()
    player?.pause()
    player?.replaceCurrentItem(with: nil)
    player = nil
    loading = false
    playing = false
    elapsed = 0
    duration = 0
    error = nil
  }

  private func fail() {
    reset()
    error = "Unable to play this attachment. Try again or open it in your browser."
  }

  private func updateTimeObservation(audio: Bool) {
    guard audio, playing, let player else { removeTimeObservation(); return }
    guard timeObserver == nil else { return }
    timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self, weak player] time in
      Task { @MainActor [weak self, weak player] in
        guard let self, let player, self.player === player else { return }
        let seconds = time.seconds
        if seconds.isFinite { self.elapsed = max(0, seconds) }
      }
    }
  }

  private func removeTimeObservation() {
    if let timeObserver { player?.removeTimeObserver(timeObserver) }
    timeObserver = nil
  }

  isolated deinit {
    preparation?.cancel()
    asset?.cancelLoading()
    if let timeObserver { player?.removeTimeObserver(timeObserver) }
    player?.pause()
  }
}

// The SwiftUI VideoPlayer overlay crashes in _AVKit_SwiftUI on affected Mac
// runtimes. Embed AVKit's platform controls directly on both platforms.
#if os(macOS)
struct NativeVideoPlayer: NSViewRepresentable {
  let player: AVPlayer
  func makeNSView(context: Context) -> AVPlayerView {
    let view = AVPlayerView()
    view.controlsStyle = .inline
    view.videoGravity = .resizeAspect
    view.showsFullScreenToggleButton = true
    view.player = player
    return view
  }
  func updateNSView(_ view: AVPlayerView, context: Context) {
    if view.player !== player { view.player = player }
  }
  static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
    view.player?.pause()
    view.player = nil
  }
}
#else
struct NativeVideoPlayer: UIViewControllerRepresentable {
  let player: AVPlayer
  func makeUIViewController(context: Context) -> AVPlayerViewController {
    let controller = AVPlayerViewController()
    controller.videoGravity = .resizeAspect
    controller.player = player
    return controller
  }
  func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
    if controller.player !== player { controller.player = player }
  }
  static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
    controller.player?.pause()
    controller.player = nil
  }
}
#endif
