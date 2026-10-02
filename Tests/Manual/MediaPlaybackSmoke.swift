import AppKit
import SwiftUI
import AVFoundation
import AVKit

// Compile with MediaPlayback.swift and APIError.swift; this does not need a
// signed-in account or a remote video. See QA.md for the command.
@main struct MediaPlaybackSmoke {
  @MainActor static func main() async throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("plainwire-smoke-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(at: url) }
    try await makeVideo(url)

    let playback = MediaPlayback()
    for _ in 0..<5 {
      playback.load(url)
      for _ in 0..<100 {
        if playback.player != nil, !playback.loading { break }
        try await Task.sleep(for: .milliseconds(20))
      }
      guard let player = playback.player, playback.error == nil else {
        throw SmokeError.failed("Video did not become playable")
      }
      let view = NSHostingView(rootView: NativeVideoPlayer(player: player))
      let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
        styleMask: [.borderless], backing: .buffered, defer: false)
      window.alphaValue = 0
      window.contentView = view
      window.orderBack(nil)
      view.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(250))
      guard containsPlayer(view) else { throw SmokeError.failed("Native AVPlayerView was not mounted") }
      if let playerView = findPlayer(view) {
        try await checkScrollRouting(playerView)
      } else {
        throw SmokeError.failed("Option-scroll player was not mounted")
      }
      playback.reset()
      window.orderOut(nil)
      guard playback.player == nil, !playback.loading, !playback.playing else {
        throw SmokeError.failed("Player was not released")
      }
    }
    playback.load(url)
    playback.reset()
    try await Task.sleep(for: .milliseconds(200))
    guard playback.player == nil else { throw SmokeError.failed("Cancelled loading resurrected a player") }
    playback.load(url.appendingPathExtension("missing"))
    for _ in 0..<100 {
      if !playback.loading { break }
      try await Task.sleep(for: .milliseconds(20))
    }
    guard playback.error != nil, playback.player == nil else { throw SmokeError.failed("Missing video did not show an error") }
    playback.reset()
    print("Media smoke passed: native mounting, scroll routing, playback, teardown, cancellation, and failure recovery.")
  }

  @MainActor private static func containsPlayer(_ view: NSView) -> Bool {
    view is AVPlayerView || view.subviews.contains(where: containsPlayer)
  }

  @MainActor private static func findPlayer(_ view: NSView) -> OptionScrollPlayerView? {
    if let player = view as? OptionScrollPlayerView { return player }
    return view.subviews.lazy.compactMap { findPlayer($0) }.first
  }

  @MainActor private static func checkScrollRouting(_ view: OptionScrollPlayerView) async throws {
    let receiver = ScrollReceiver()
    let previousResponder = view.nextResponder
    view.nextResponder = receiver
    defer { view.nextResponder = previousResponder }

    guard let player = view.player,
      let cgEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
      wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0) else {
      throw SmokeError.failed("Could not create scroll event")
    }
    player.pause()
    for (enabled, flags, shouldForward) in [
      (true, CGEventFlags(), true),
      (true, CGEventFlags.maskShift, true),
      (true, CGEventFlags.maskControl, true),
      (true, CGEventFlags.maskAlternate, false),
      (false, CGEventFlags.maskAlternate, true),
      (false, CGEventFlags(), true),
      (true, CGEventFlags.maskAlternate, false),
    ] {
      await player.seek(to: CMTime(seconds: 0.5, preferredTimescale: 600))
      let previousTime = player.currentTime().seconds
      view.optionScrollSeeking = enabled
      cgEvent.flags = flags
      guard let event = NSEvent(cgEvent: cgEvent) else {
        throw SmokeError.failed("Could not bridge scroll event")
      }
      let previousCount = receiver.scrollCount
      view.scrollWheel(with: event)
      guard receiver.scrollCount == previousCount + (shouldForward ? 1 : 0) else {
        throw SmokeError.failed("Scroll routing failed: enabled=\(enabled), flags=\(flags.rawValue), expectedForward=\(shouldForward), forwarded=\(receiver.scrollCount - previousCount)")
      }
      for _ in 0..<50 {
        if abs(player.currentTime().seconds - previousTime) > 0.001 { break }
        if shouldForward { break }
        try await Task.sleep(for: .milliseconds(10))
      }
      let didSeek = abs(player.currentTime().seconds - previousTime) > 0.001
      guard didSeek != shouldForward, player.rate == 0 else {
        throw SmokeError.failed("Scroll seeking did not respect the setting or preserve paused playback")
      }
      // Let the completion handler release the accumulated seek target.
      try await Task.sleep(for: .milliseconds(20))
    }
    view.optionScrollSeeking = true
  }

  @MainActor private final class ScrollReceiver: NSResponder {
    var scrollCount = 0
    override func scrollWheel(with event: NSEvent) { scrollCount += 1 }
  }

  @MainActor private static func makeVideo(_ url: URL) async throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64,
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
      sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64])
    writer.add(input)
    guard writer.startWriting() else { throw SmokeError.failed("Could not create sample video") }
    writer.startSession(atSourceTime: .zero)
    var buffer: CVPixelBuffer?
    guard CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32ARGB, nil, &buffer) == kCVReturnSuccess,
      let buffer else { throw SmokeError.failed("Could not create sample frame") }
    CVPixelBufferLockBaseAddress(buffer, [])
    if let address = CVPixelBufferGetBaseAddress(buffer) { memset(address, 127, CVPixelBufferGetDataSize(buffer)) }
    CVPixelBufferUnlockBaseAddress(buffer, [])
    for frame in 0..<60 {
      while !input.isReadyForMoreMediaData {
        if writer.status == .failed { throw SmokeError.failed("Sample encoder failed") }
        try await Task.sleep(for: .milliseconds(5))
      }
      guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else {
        throw SmokeError.failed("Sample frame failed")
      }
    }
    input.markAsFinished()
    await writer.finishWriting()
    guard writer.status == .completed else { throw SmokeError.failed("Sample encoding failed") }
  }

  private enum SmokeError: Error { case failed(String) }
}
