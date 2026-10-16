import SwiftUI

#if os(iOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

// Keep preference keys stable across releases.
enum AppPreferenceKeys {
  static let serverAddress = "plainwire.apple.serverAddress"
  static let recentServers = "plainwire.apple.recentServers"
  static let autoplayAnimatedMedia = "plainwire.apple.autoplayAnimatedMedia"
  static let enterSendsMessage = "plainwire.apple.enterSendsMessage"
  static let sendTypingIndicators = "plainwire.apple.sendTypingIndicators"
  static let notificationPreviews = "plainwire.apple.notificationPreviews"
  static let notificationSounds = "plainwire.apple.notificationSounds"
  static let reduceInterfaceMotion = "plainwire.apple.reduceInterfaceMotion"
  static let compactMessages = "plainwire.apple.compactMessages"
  static let optionScrollVideoSeeking = "plainwire.apple.optionScrollVideoSeeking"
}

enum AppPreferences {
  static func registerDefaults() {
    UserDefaults.standard.register(defaults: [
      AppPreferenceKeys.autoplayAnimatedMedia: true,
      AppPreferenceKeys.enterSendsMessage: true,
      AppPreferenceKeys.sendTypingIndicators: true,
      AppPreferenceKeys.notificationPreviews: true,
      AppPreferenceKeys.notificationSounds: true,
      AppPreferenceKeys.reduceInterfaceMotion: false,
      AppPreferenceKeys.compactMessages: false,
      AppPreferenceKeys.optionScrollVideoSeeking: true,
    ])
  }
}

struct AppBackdrop: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var body: some View {
    ZStack {
      Color.canvas.ignoresSafeArea()
      #if !os(macOS)
      if !reduceTransparency {
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
      #endif
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
  @Environment(\.displayScale) private var displayScale
  let url: URL?
  let fallback: String
  let size: CGFloat
  var cornerRadius: CGFloat? = nil

  var body: some View {
    CachedRemoteImage(url: url, pixelSize: Int(ceil(size * displayScale))) { phase in
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
    .fixedSize()
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? size / 2, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: cornerRadius ?? size / 2, style: .continuous)
        .strokeBorder(.white.opacity(0.16), lineWidth: 1)
    }
    .contentShape(RoundedRectangle(cornerRadius: cornerRadius ?? size / 2, style: .continuous))
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

// Keep glass effects on controls so long message lists stay light.
struct AdaptiveGlassModifier: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  let cornerRadius: CGFloat
  let interactive: Bool

  @ViewBuilder func body(content: Content) -> some View {
    if reduceTransparency {
      content.background(Color.windowBackground, in: RoundedRectangle(cornerRadius: cornerRadius))
        .overlay { RoundedRectangle(cornerRadius: cornerRadius).stroke(.primary.opacity(0.15), lineWidth: 1) }
    } else if #available(iOS 26.0, macOS 26.0, *) {
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

  func body(content: Content) -> some View {
    styled(content)
      .buttonBorderShape(.roundedRectangle(radius: 10))
  }

  @ViewBuilder private func styled(_ content: Content) -> some View {
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

// System switches adopt Liquid Glass on iOS/macOS 26 and retain native
// keyboard, accessibility, dragging, and Reduce Motion behavior on every OS.
private struct AdaptiveGlassToggleModifier: ViewModifier {
  func body(content: Content) -> some View {
    content.toggleStyle(.switch).tint(.accentColor)
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
      Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
        .lineLimit(1)
    }
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

private struct SheetErrorNoticeModifier: ViewModifier {
  @Environment(AppModel.self) private var model
  func body(content: Content) -> some View {
    content.safeAreaInset(edge: .bottom) {
      if let error = model.errorMessage {
        HStack(alignment: .top, spacing: 10) {
          Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
          Text(error).font(.caption).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
          Button { model.errorMessage = nil } label: { Image(systemName: "xmark") }
            .buttonStyle(.plain).accessibilityLabel("Dismiss error")
        }.padding(12).background(.regularMaterial)
      }
    }
  }
}

extension View {
  func sheetErrorNotice() -> some View { modifier(SheetErrorNoticeModifier()) }
}

extension View {
  @ViewBuilder func adaptiveSheetSize(
    minWidth: CGFloat, idealWidth: CGFloat? = nil, minHeight: CGFloat, idealHeight: CGFloat? = nil
  ) -> some View {
    #if os(macOS)
      frame(
        minWidth: minWidth, idealWidth: idealWidth ?? max(minWidth, 480), maxWidth: .infinity,
        minHeight: minHeight, idealHeight: idealHeight ?? max(minHeight, 520), maxHeight: .infinity
      )
      .presentationSizing(.fitted)
      .buttonBorderShape(.roundedRectangle(radius: 10))
    #else
      frame(maxWidth: .infinity, maxHeight: .infinity)
    #endif
  }
}

// Paint the entire sidebar once, including its bottom inset. Mixing a List's
// default vibrancy with a separate bar material gives the footer a hard seam.
struct SidebarSurface: View {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var body: some View {
    if reduceTransparency {
      Color.windowBackground
    } else {
      Rectangle().fill(.regularMaterial)
    }
  }
}

extension Color {
  init?(plainwireHex: String) {
    let hex = plainwireHex.hasPrefix("#") ? String(plainwireHex.dropFirst()) : plainwireHex
    guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
    self.init(red: Double((value >> 16) & 255) / 255,
              green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
  }
}
