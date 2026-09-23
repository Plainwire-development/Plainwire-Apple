import SwiftUI
import ImageIO

#if os(iOS)
  import UIKit
  typealias PlatformImage = UIImage
#elseif os(macOS)
  import AppKit
  typealias PlatformImage = NSImage
#endif

// Keep preference keys stable across releases.
enum AppPreferenceKeys {
  static let sendTypingIndicators = "plainwire.apple.sendTypingIndicators"
  static let notificationPreviews = "plainwire.apple.notificationPreviews"
  static let notificationSounds = "plainwire.apple.notificationSounds"
  static let reduceInterfaceMotion = "plainwire.apple.reduceInterfaceMotion"
  static let compactMessages = "plainwire.apple.compactMessages"
}

enum AppPreferences {
  static func registerDefaults() {
    UserDefaults.standard.register(defaults: [
      AppPreferenceKeys.sendTypingIndicators: true,
      AppPreferenceKeys.notificationPreviews: true,
      AppPreferenceKeys.notificationSounds: true,
      AppPreferenceKeys.reduceInterfaceMotion: false,
      AppPreferenceKeys.compactMessages: false,
    ])
  }
}

struct AppBackdrop: View {
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    ZStack {
      Color.windowBackground.ignoresSafeArea()
      RadialGradient(
        colors: [Color.accentColor.opacity(colorScheme == .dark ? 0.13 : 0.10), .clear],
        center: .topTrailing, startRadius: 30, endRadius: 650
      )
      .ignoresSafeArea()
      LinearGradient(
        colors: [
          Color.accentColor.opacity(colorScheme == .dark ? 0.045 : 0.025),
          .clear,
          Color.indigo.opacity(colorScheme == .dark ? 0.06 : 0.035),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .ignoresSafeArea()
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
  }
}

extension Color {
  fileprivate static var windowBackground: Color {
    #if os(macOS)
      Color(nsColor: .windowBackgroundColor)
    #else
      Color(uiColor: .systemBackground)
    #endif
  }
}

struct PlainwireMark: View {
  var size: CGFloat

  var body: some View {
    Image("PlainwireMark")
      .resizable()
      .renderingMode(.template)
      .scaledToFit()
      .foregroundStyle(.primary)
      .frame(width: size, height: size)
      .accessibilityLabel("Plainwire")
  }
}

struct RemoteAvatar: View {
  let url: URL?
  let fallback: String
  let size: CGFloat
  var cornerRadius: CGFloat? = nil

  var body: some View {
    CachedRemoteImage(url: url, pixelSize: Int(size * 2)) { phase in
      switch phase {
      case .success(let image):
        image.resizable().scaledToFill()
      default:
        ZStack {
          LinearGradient(
            colors: avatarColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing)
          Text(fallback.uppercased())
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
        }
      }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? size / 2, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: cornerRadius ?? size / 2, style: .continuous)
        .strokeBorder(.white.opacity(0.16), lineWidth: 1)
    }
    .contentShape(Rectangle())
    .accessibilityHidden(true)
  }

  private var avatarColors: [Color] {
    let palettes: [[Color]] = [
      [.indigo, .purple], [.teal, .blue], [.orange, .pink],
      [.mint, .cyan], [.pink, .purple], [.blue, .indigo],
    ]
    let index = fallback.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % palettes.count }
    return palettes[index]
  }
}

enum CachedImagePhase {
  case empty
  case success(Image)
  case failure
}

struct CachedRemoteImage<Content: View>: View {
  let url: URL?
  let pixelSize: Int
  let content: (CachedImagePhase) -> Content
  @State private var loadedImage: PlatformImage?
  @State private var finished = false

  init(url: URL?, pixelSize: Int, @ViewBuilder content: @escaping (CachedImagePhase) -> Content) {
    self.url = url
    self.pixelSize = pixelSize
    self.content = content
  }

  var body: some View {
    content(phase)
      .task(id: "\(url?.absoluteString ?? "")#\(pixelSize)") {
        loadedImage = nil
        finished = false
        guard let url else { finished = true; return }
        let result = await RemoteImageStore.shared.image(for: url, pixelSize: pixelSize)
        guard !Task.isCancelled else { return }
        loadedImage = result
        finished = true
      }
  }

  private var phase: CachedImagePhase {
    if let loadedImage {
      #if os(iOS)
        return .success(Image(uiImage: loadedImage))
      #else
        return .success(Image(nsImage: loadedImage))
      #endif
    }
    return finished ? .failure : .empty
  }
}

@MainActor
final class RemoteImageStore {
  static let shared = RemoteImageStore()

  private let cache = NSCache<NSString, PlatformImage>()
  private var pending: [String: Task<PlatformImage?, Never>] = [:]
  private var generation = 0

  private init() {
    cache.countLimit = 240
    cache.totalCostLimit = 96 * 1024 * 1024
  }

  func clear() {
    generation += 1
    pending.values.forEach { $0.cancel() }
    pending.removeAll()
    cache.removeAllObjects()
  }

  func image(for url: URL, pixelSize: Int) async -> PlatformImage? {
    let key = "\(url.absoluteString)#\(pixelSize)"
    if let cached = cache.object(forKey: key as NSString) { return cached }
    if let current = pending[key] {
      let requestGeneration = generation
      let result = await current.value
      return generation == requestGeneration ? result : nil
    }
    let requestGeneration = generation

    let task = Task<PlatformImage?, Never> {
      do {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard !Task.isCancelled, data.count <= 32 * 1024 * 1024,
          (response as? HTTPURLResponse)?.statusCode == 200,
          let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        let options: [CFString: Any] = [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceThumbnailMaxPixelSize: max(64, pixelSize),
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        #if os(iOS)
          return UIImage(cgImage: thumbnail)
        #else
          return NSImage(
            cgImage: thumbnail,
            size: NSSize(width: thumbnail.width, height: thumbnail.height))
        #endif
      } catch {
        return nil
      }
    }
    pending[key] = task
    let result = await task.value
    guard generation == requestGeneration else { return nil }
    pending[key] = nil
    if let result {
      cache.setObject(result, forKey: key as NSString, cost: pixelSize * pixelSize * 4)
    }
    return result
  }
}

// Keep glass effects on controls so long message lists stay light.
struct AdaptiveGlassModifier: ViewModifier {
  let cornerRadius: CGFloat
  let interactive: Bool

  @ViewBuilder func body(content: Content) -> some View {
    if #available(iOS 26.0, macOS 26.0, *) {
      content.glassEffect(
        interactive ? .regular.interactive() : .regular,
        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    } else {
      content
        .background(
          .ultraThinMaterial,
          in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(.primary.opacity(0.08), lineWidth: 0.5)
        }
    }
  }
}

struct AdaptiveGlassContainer<Content: View>: View {
  let spacing: CGFloat
  @ViewBuilder let content: () -> Content

  init(spacing: CGFloat = 10, @ViewBuilder content: @escaping () -> Content) {
    self.spacing = spacing
    self.content = content
  }

  @ViewBuilder var body: some View {
    if #available(iOS 26.0, macOS 26.0, *) {
      GlassEffectContainer(spacing: spacing) { content() }
    } else {
      content()
    }
  }
}

struct AdaptiveGlassButtonModifier: ViewModifier {
  let prominent: Bool

  @ViewBuilder func body(content: Content) -> some View {
    if #available(iOS 26.0, macOS 26.0, *) {
      if prominent {
        content.buttonStyle(.glassProminent)
      } else {
        content.buttonStyle(.glass)
      }
    } else if prominent {
      content.buttonStyle(.borderedProminent)
    } else {
      content.buttonStyle(.bordered)
    }
  }
}

@available(iOS 26.0, macOS 26.0, *)
private struct LiquidGlassSwitchToggleStyle: ToggleStyle {
  func makeBody(configuration: Configuration) -> some View {
    Button {
      withAnimation(.snappy(duration: 0.2)) { configuration.isOn.toggle() }
    } label: {
      HStack(spacing: 12) {
        configuration.label
        Spacer(minLength: 16)
        ZStack {
          Capsule(style: .continuous)
            .fill(
              configuration.isOn ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.045))
          Circle()
            .fill(.primary.opacity(configuration.isOn ? 0.96 : 0.72))
            .padding(3.5)
            .frame(width: 27, height: 27)
            .offset(x: configuration.isOn ? 9 : -9)
        }
        .frame(width: 48, height: 30)
        .glassEffect(
          .regular
            .tint(configuration.isOn ? Color.accentColor.opacity(0.52) : nil)
            .interactive(),
          in: Capsule(style: .continuous)
        )
        .accessibilityHidden(true)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityValue(configuration.isOn ? "On" : "Off")
  }
}

private struct AdaptiveGlassToggleModifier: ViewModifier {
  @ViewBuilder func body(content: Content) -> some View {
    if #available(iOS 26.0, macOS 26.0, *) {
      content.toggleStyle(LiquidGlassSwitchToggleStyle())
    } else {
      content.toggleStyle(.switch)
    }
  }
}

extension View {
  func adaptiveGlass(cornerRadius: CGFloat = 22, interactive: Bool = false) -> some View {
    modifier(AdaptiveGlassModifier(cornerRadius: cornerRadius, interactive: interactive))
  }

  func adaptiveGlassButton(prominent: Bool = false) -> some View {
    modifier(AdaptiveGlassButtonModifier(prominent: prominent))
  }

  func adaptiveGlassToggle() -> some View {
    modifier(AdaptiveGlassToggleModifier())
  }
}

struct ConnectionStatusView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    HStack(spacing: 7) {
      Circle().fill(color).frame(width: 7, height: 7)
      Text(label).font(.caption).foregroundStyle(.secondary)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .adaptiveGlass(cornerRadius: 14)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Realtime status: \(label)")
  }

  private var color: Color {
    switch model.realtimeState {
    case .connected: .green
    case .connecting, .reconnecting: .orange
    case .failed: .red
    case .stopped: .secondary
    }
  }

  private var label: String {
    switch model.realtimeState {
    case .connected: "Connected"
    case .connecting: "Connecting"
    case .reconnecting: "Reconnecting"
    case .failed: "Offline"
    case .stopped: "Idle"
    }
  }
}
