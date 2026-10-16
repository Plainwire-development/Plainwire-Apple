import SwiftUI
import ImageIO

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// ImageIO access is serialized by the lock. Frames are decoded only on utility
/// tasks; immutable CGImages can then be displayed on the main thread.
final class RemoteImageAsset: @unchecked Sendable {
  let poster: CGImage
  let durations: [TimeInterval]
  let cost: Int
  var isAnimated: Bool { durations.count > 1 }
  private let source: CGImageSource
  private let pixelSize: Int
  private let lock = NSLock()
  private let frames = NSCache<NSNumber, ImageFrame>()

  init?(data: Data, pixelSize: Int) {
    guard let source = CGImageSourceCreateWithData(data as CFData,
      [kCGImageSourceShouldCache: false] as CFDictionary),
      let poster = Self.decode(source, index: 0, pixelSize: pixelSize)
    else { return nil }
    self.source = source
    self.pixelSize = pixelSize
    self.poster = poster
    let count = CGImageSourceGetCount(source)
    // Avoid walking unbounded metadata in a malicious image. Large animations
    // still have a usable first frame.
    let type = CGImageSourceGetType(source) as String?
    if count > 1, count <= 1000, type == "com.compuserve.gif" || type == "public.png" {
      durations = (0..<count).map { index in
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let png = properties?[kCGImagePropertyPNGDictionary] as? [CFString: Any]
        let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
          ?? (gif?[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue
          ?? (png?[kCGImagePropertyAPNGUnclampedDelayTime] as? NSNumber)?.doubleValue
          ?? (png?[kCGImagePropertyAPNGDelayTime] as? NSNumber)?.doubleValue ?? 0.1
        // Match browser behavior for zero/very short GIF delays.
        return delay.isFinite && delay >= 0.02 ? min(delay, 60) : 0.1
      }
    } else { durations = [0.1] }
    frames.totalCostLimit = 8 * 1024 * 1024
    frames.countLimit = 12
    cost = data.count + poster.bytesPerRow * poster.height + (durations.count > 1 ? 8 * 1024 * 1024 : 0)
  }

  func frame(at index: Int) -> CGImage? {
    guard durations.indices.contains(index) else { return nil }
    if index == 0 { return poster }
    return lock.withLock {
      let key = NSNumber(value: index)
      if let cached = frames.object(forKey: key) { return cached.image }
      guard let image = Self.decode(source, index: index, pixelSize: pixelSize) else { return nil }
      frames.setObject(ImageFrame(image), forKey: key, cost: image.bytesPerRow * image.height)
      return image
    }
  }

  private static func decode(_ source: CGImageSource, index: Int, pixelSize: Int) -> CGImage? {
    guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
      width.isFinite, height.isFinite, width > 0, height > 0,
      width <= 20_000, height <= 20_000, width * height <= 64_000_000
    else { return nil }
    return CGImageSourceCreateThumbnailAtIndex(source, index, [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: pixelSize,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
    ] as CFDictionary)
  }

  private final class ImageFrame: NSObject {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
  }
}

enum CachedImagePhase {
  case empty
  case success(RemoteImage)
  case failure
}

/// The poster supplies the same intrinsic size and layout as a SwiftUI Image.
/// Animated frames update a native layer without invalidating SwiftUI chat rows.
struct RemoteImage: View {
  let asset: RemoteImageAsset
  private var resizes = false
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @AppStorage(AppPreferenceKeys.reduceInterfaceMotion) private var reduceInterfaceMotion = false
  @AppStorage(AppPreferenceKeys.autoplayAnimatedMedia) private var autoplay = true
  @State private var visible = true

  func resizable() -> Self {
    var copy = self
    copy.resizes = true
    return copy
  }

  var body: some View {
    Group {
      if resizes { poster.resizable() } else { poster }
    }
    .overlay {
      if asset.isAnimated {
        AnimatedImageSurface(asset: asset,
          playing: visible && scenePhase == .active && autoplay && !reduceMotion && !reduceInterfaceMotion)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
    }
    .onScrollVisibilityChange(threshold: 0.01) { visible = $0 }
    .onAppear { visible = true }
    .onDisappear { visible = false }
  }

  private var poster: Image {
    Image(decorative: asset.poster, scale: 1)
  }
}

struct CachedRemoteImage<Content: View>: View {
  let url: URL?
  let pixelSize: Int
  let content: (CachedImagePhase) -> Content
  @State private var asset: RemoteImageAsset?
  @State private var loadedURL: URL?
  @State private var loadedGeneration = -1
  @State private var finished = false

  init(url: URL?, pixelSize: Int, @ViewBuilder content: @escaping (CachedImagePhase) -> Content) {
    self.url = url
    self.pixelSize = pixelSize
    self.content = content
  }

  var body: some View {
    let generation = RemoteImageStore.shared.generation
    content(phase(generation: generation))
      .task(id: "\(url?.absoluteString ?? "")#\(pixelSize)#\(generation)") {
        asset = nil
        finished = false
        loadedURL = url
        loadedGeneration = generation
        guard let url else { finished = true; return }
        let result = await RemoteImageStore.shared.image(for: url, pixelSize: pixelSize)
        guard !Task.isCancelled, generation == RemoteImageStore.shared.generation else { return }
        asset = result
        finished = true
      }
      .onDisappear { asset = nil; finished = false }
  }

  private func phase(generation: Int) -> CachedImagePhase {
    guard loadedURL == url, loadedGeneration == generation else { return .empty }
    if let asset { return .success(RemoteImage(asset: asset)) }
    return finished ? .failure : .empty
  }
}

@MainActor @Observable
final class RemoteImageStore {
  static let shared = RemoteImageStore()
  private(set) var generation = 0
  @ObservationIgnored private let cache = NSCache<NSString, RemoteImageAsset>()
  @ObservationIgnored private var session: URLSession
  @ObservationIgnored private var transferDelegate: PlainwireTransferDelegate
  @ObservationIgnored private var configuration = PlainwireConfiguration()
  @ObservationIgnored private var pending: [String: Task<RemoteImageAsset?, Never>] = [:]

  private init() {
    let delegate = PlainwireTransferDelegate(configuration: PlainwireConfiguration(), maximumBytes: 32 * 1024 * 1024)
    transferDelegate = delegate
    session = Self.makeSession(delegate: delegate)
    cache.countLimit = 240
    cache.totalCostLimit = 96 * 1024 * 1024
  }

  private static func makeSession(delegate: PlainwireTransferDelegate) -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = .shared
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 45
    configuration.httpMaximumConnectionsPerHost = 4
    configuration.urlCache = nil
    return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
  }

  func configure(_ configuration: PlainwireConfiguration) {
    guard self.configuration != configuration else { return }
    clear()
    session.invalidateAndCancel()
    self.configuration = configuration
    let delegate = PlainwireTransferDelegate(configuration: configuration, maximumBytes: 32 * 1024 * 1024)
    transferDelegate = delegate
    session = Self.makeSession(delegate: delegate)
  }

  func clear() {
    generation += 1
    pending.values.forEach { $0.cancel() }
    pending.removeAll()
    cache.removeAllObjects()
  }

  func image(for url: URL, pixelSize: Int) async -> RemoteImageAsset? {
    guard configuration.mediaURL(url.absoluteString) != nil else { return nil }
    let pixelSize = min(1600, max(64, pixelSize))
    let key = "\(url.absoluteString)#\(pixelSize)"
    if let cached = cache.object(forKey: key as NSString) { return cached }
    let requestGeneration = generation
    if let task = pending[key] {
      let result = await task.value
      return generation == requestGeneration ? result : nil
    }
    let delegate = transferDelegate
    let session = session
    let task = Task<RemoteImageAsset?, Never> {
      do {
        let (file, response) = try await delegate.download(URLRequest(url: url), using: session)
        defer { try? FileManager.default.removeItem(at: file) }
        let size = (try file.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
        guard !Task.isCancelled, size > 0, size <= 32 * 1024 * 1024,
          (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let decode = Task.detached(priority: .utility) { () -> RemoteImageAsset? in
          guard !Task.isCancelled, let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return nil }
          return RemoteImageAsset(data: data, pixelSize: pixelSize)
        }
        let result = await withTaskCancellationHandler { await decode.value } onCancel: { decode.cancel() }
        return Task.isCancelled ? nil : result
      } catch { return nil }
    }
    pending[key] = task
    let result = await task.value
    guard generation == requestGeneration else { return nil }
    pending[key] = nil
    if let result { cache.setObject(result, forKey: key as NSString, cost: result.cost) }
    return result
  }
}

// One native layer per visible image. No display timers or frame arrays remain
// active when an image leaves its window, stops being visible, or motion is off.
@MainActor final class AnimatedImageDriver {
  private var task: Task<Void, Never>?
  private weak var layer: CALayer?
  private var asset: RemoteImageAsset?
  private var playing = false

  func update(asset: RemoteImageAsset, layer: CALayer, playing: Bool) {
    guard self.asset !== asset || self.layer !== layer || self.playing != playing else { return }
    stop()
    self.asset = asset
    self.layer = layer
    self.playing = playing
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.contents = asset.poster
    CATransaction.commit()
    guard playing else { return }
    task = Task { [weak layer] in
      var index = 0
      while !Task.isCancelled {
        let started = ContinuousClock.now
        let next = (index + 1) % asset.durations.count
        let decode = Task.detached(priority: .utility) { asset.frame(at: next) }
        let frame = await withTaskCancellationHandler { await decode.value } onCancel: { decode.cancel() }
        let elapsed = started.duration(to: .now)
        do { try await Task.sleep(for: max(.zero, .seconds(asset.durations[index]) - elapsed)) }
        catch { return }
        guard !Task.isCancelled, let layer else { return }
        if let frame {
          CATransaction.begin()
          CATransaction.setDisableActions(true)
          layer.contents = frame
          CATransaction.commit()
        }
        index = next
      }
    }
  }

  func stop() {
    task?.cancel()
    task = nil
    asset = nil
    playing = false
  }

  deinit { task?.cancel() }
}

#if os(macOS)
private struct AnimatedImageSurface: NSViewRepresentable {
  let asset: RemoteImageAsset
  let playing: Bool
  func makeNSView(context: Context) -> AnimatedImageNativeView { AnimatedImageNativeView() }
  func updateNSView(_ view: AnimatedImageNativeView, context: Context) {
    view.asset = asset
    view.playing = playing
    view.updatePlayback()
  }
  static func dismantleNSView(_ view: AnimatedImageNativeView, coordinator: ()) { view.driver.stop() }
}

private final class AnimatedImageNativeView: NSView {
  let driver = AnimatedImageDriver()
  var asset: RemoteImageAsset?
  var playing = false
  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.contentsGravity = .resize
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updatePlayback() }
  func updatePlayback() {
    guard let asset, let layer else { driver.stop(); return }
    driver.update(asset: asset, layer: layer, playing: playing && window != nil)
  }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
#else
private struct AnimatedImageSurface: UIViewRepresentable {
  let asset: RemoteImageAsset
  let playing: Bool
  func makeUIView(context: Context) -> AnimatedImageNativeView { AnimatedImageNativeView() }
  func updateUIView(_ view: AnimatedImageNativeView, context: Context) {
    view.asset = asset
    view.playing = playing
    view.updatePlayback()
  }
  static func dismantleUIView(_ view: AnimatedImageNativeView, coordinator: ()) { view.driver.stop() }
}

private final class AnimatedImageNativeView: UIView {
  let driver = AnimatedImageDriver()
  var asset: RemoteImageAsset?
  var playing = false
  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    layer.contentsGravity = .resize
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func didMoveToWindow() { super.didMoveToWindow(); updatePlayback() }
  func updatePlayback() {
    guard let asset else { driver.stop(); return }
    driver.update(asset: asset, layer: layer, playing: playing && window != nil)
  }
}
#endif
