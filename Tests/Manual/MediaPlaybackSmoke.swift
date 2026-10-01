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
    print("Media smoke passed: native mounting, playback, teardown, cancellation, and failure recovery.")
  }

  @MainActor private static func containsPlayer(_ view: NSView) -> Bool {
    view is AVPlayerView || view.subviews.contains(where: containsPlayer)
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
