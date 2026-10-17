import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension Color {
  static var canvas: Color {
    #if os(macOS)
      Color(nsColor: .underPageBackgroundColor)
    #else
      Color(uiColor: .systemGroupedBackground)
    #endif
  }

  static var panel: Color {
    #if os(macOS)
      Color(nsColor: .controlBackgroundColor)
    #else
      Color(uiColor: .secondarySystemGroupedBackground)
    #endif
  }
}

private struct CardSurface: ViewModifier {
  @Environment(\.colorSchemeContrast) private var contrast
  let radius: CGFloat
  func body(content: Content) -> some View {
    content
      .background(Color.panel, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .strokeBorder(.primary.opacity(contrast == .increased ? 0.28 : 0.07), lineWidth: 1)
      }
  }
}

extension View {
  func cardSurface(cornerRadius: CGFloat = 20) -> some View {
    modifier(CardSurface(radius: cornerRadius))
  }

  func pageSearch(text: Binding<String>, prompt: LocalizedStringKey) -> some View {
    modifier(PageSearchModifier(text: text, prompt: prompt))
  }
}

private struct PageSearchModifier: ViewModifier {
  @Binding var text: String
  let prompt: LocalizedStringKey
  #if os(macOS)
    @FocusState private var focused: Bool
    @Environment(\.colorSchemeContrast) private var contrast
  #endif

  func body(content: Content) -> some View {
    #if os(macOS)
      // SwiftUI gives every .searchable field the same NSToolbar identifier.
      // Replacing pages or dismissing a sheet can insert it twice and raise an
      // AppKit exception. Keep Mac search in the page's reserved header area.
      VStack(spacing: 0) {
        HStack(spacing: 8) {
          Image(systemName: "magnifyingglass")
            .foregroundStyle(.secondary).accessibilityHidden(true)
          TextField(prompt, text: $text)
            .textFieldStyle(.plain)
            .focused($focused)
            .accessibilityIdentifier("plainwire.pageSearch")
            .onExitCommand {
              if text.isEmpty { focused = false }
              else { text = "" }
            }
          if !text.isEmpty {
            Button { text = "" } label: {
              Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain).accessibilityLabel("Clear search")
          }
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(focused ? Color.accentColor : .primary.opacity(contrast == .increased ? 0.3 : 0.12),
              lineWidth: focused ? 2 : 1)
        }
        .frame(maxWidth: 1120)
        .padding(.horizontal, 20).padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color.canvas, ignoresSafeAreaEdges: [])
        .overlay(alignment: .bottom) { Divider() }
        .background {
          Button("Find") { focused = true }
            .keyboardShortcut("f", modifiers: .command)
            .hidden().accessibilityHidden(true)
        }
        .zIndex(1)
        GeometryReader { geometry in
          content.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        .clipped()
      }
    #else
      content.searchable(text: $text, prompt: prompt)
    #endif
  }
}

struct PageHeader: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  let title: String
  let subtitle: String
  let symbol: String
  var accent: Color = .accentColor
  var eyebrow: String? = nil

  var body: some View {
    let layout = typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
      : AnyLayout(HStackLayout(alignment: .top, spacing: 18))
    layout {
      Image(systemName: symbol)
        .font(.system(size: 27, weight: .medium))
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(.white)
        .frame(width: 60, height: 60)
        .background(LinearGradient(colors: [accent, accent.opacity(0.72)], startPoint: .topLeading,
          endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 6) {
        if let eyebrow {
          Text(eyebrow.uppercased()).font(.caption2.weight(.bold)).tracking(1.5)
            .foregroundStyle(.secondary)
        }
        Text(title).font(.system(.largeTitle, design: .rounded, weight: .bold))
          .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
        Text(subtitle).font(.callout).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(24)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(alignment: .topTrailing) {
      LinearGradient(colors: [accent.opacity(0.075), .clear], startPoint: .topTrailing, endPoint: .bottomLeading)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
    .cardSurface(cornerRadius: 22)
  }
}

struct StatPill: View {
  let title: String
  let symbol: String
  var tint: Color = .accentColor
  var body: some View {
    Label { Text(title).foregroundStyle(Color.primary) }
      icon: { Image(systemName: symbol).foregroundStyle(tint) }
      .font(.caption.weight(.medium))
      .padding(.horizontal, 10).padding(.vertical, 6)
      .background(tint.opacity(0.09), in: Capsule())
      .accessibilityElement(children: .combine)
  }
}

struct InlineNotice: View {
  let text: String
  var symbol = "exclamationmark.circle"
  var tint: Color = .orange
  var body: some View {
    Label {
      Text(text).foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true)
    } icon: { Image(systemName: symbol).foregroundStyle(tint) }
      .font(.callout)
      .padding(14).frame(maxWidth: .infinity, alignment: .leading)
      .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .accessibilityElement(children: .combine)
  }
}

extension AppModel.Section {
  var accent: Color {
    switch self {
    case .messages: .blue
    case .servers: .purple
    case .forums: .indigo
    case .friends: .teal
    case .activity: .orange
    case .settings: .secondary
    }
  }
}
