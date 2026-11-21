import AppKit
import SwiftUI

enum InterfaceStyle: String, CaseIterable, Identifiable {
  case standard, liquidGlass
  var id: String { rawValue }
  var label: String { self == .liquidGlass ? "Liquid Glass" : "Standard" }
  static func load(from defaults: UserDefaults) -> Self {
    defaults.string(forKey: "interfaceStyle").flatMap(Self.init(rawValue:)) ?? .liquidGlass
  }
}

/// Liquid Glass variants, as on iOS: Regular adapts for legibility, Clear shows more of
/// what is behind the panel. Glass is never faded with opacity, which removes its
/// refraction and highlights.
enum GlassVariant: String, CaseIterable, Identifiable {
  case regular, clear
  var id: String { rawValue }
  var label: String { self == .clear ? "Clear" : "Regular" }
  static func load(from defaults: UserDefaults) -> Self {
    defaults.string(forKey: "glassVariant").flatMap(Self.init(rawValue:)) ?? .regular
  }
}

enum PanelShape {
  static let cornerRadius: CGFloat = 26
}

enum GlassRendering: Equatable {
  case solid, material, liquid
  static func resolve(style: InterfaceStyle, reduceTransparency: Bool, supportsLiquid: Bool) -> Self {
    if reduceTransparency { return .solid }
    return style == .liquidGlass && supportsLiquid ? .liquid : .material
  }
  static var supportsLiquid: Bool {
    if #available(macOS 26, *) { return true }
    return false
  }
}

struct ClipboardBackdrop: View {
  let style: InterfaceStyle
  let opacity: Double
  var variant: GlassVariant = .regular
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  var body: some View {
    let rendering = GlassRendering.resolve(
      style: style, reduceTransparency: reduceTransparency,
      supportsLiquid: GlassRendering.supportsLiquid)
    Group {
      if rendering == .solid {
        RoundedRectangle(cornerRadius: PanelShape.cornerRadius)
          .fill(Color(nsColor: .windowBackgroundColor))
      } else if #available(macOS 26, *), rendering == .liquid {
        // The system window glass draws its own rim, highlights and refraction.
        NativeGlass(variant: variant, cornerRadius: PanelShape.cornerRadius)
      } else {
        Glass(opacity: opacity)
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

@available(macOS 26, *)
struct NativeGlass: NSViewRepresentable {
  let variant: GlassVariant
  let cornerRadius: CGFloat
  func makeNSView(context: Context) -> NSGlassEffectView {
    let view = NSGlassEffectView()
    updateNSView(view, context: context)
    return view
  }
  func updateNSView(_ view: NSGlassEffectView, context: Context) {
    let style: NSGlassEffectView.Style = variant == .clear ? .clear : .regular
    if view.style != style { view.style = style }
    if view.cornerRadius != cornerRadius { view.cornerRadius = cornerRadius }
  }
}

// Cards stay opaque, like content on iOS; only floating controls are glass.
// On macOS 26+ each control is real Liquid Glass; older systems keep a light outline.
struct GlassControlSurface: ViewModifier {
  let enabled: Bool
  var interactive = true
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @ViewBuilder func body(content: Content) -> some View {
    if #available(macOS 26, *), enabled, !reduceTransparency {
      content.glassEffect(interactive ? .regular.interactive() : .regular, in: .capsule)
    } else {
      content
        .background {
          if enabled {
            Capsule().fill(Color.primary.opacity(0.035))
              .overlay(Capsule().strokeBorder(.primary.opacity(0.10), lineWidth: 0.5))
              .allowsHitTesting(false)
          }
        }
    }
  }
}

/// Groups neighbouring glass controls so they render and blend together, as on iOS.
struct GlassGroup<Content: View>: View {
  let enabled: Bool
  var spacing: CGFloat = 10
  @ViewBuilder let content: () -> Content
  var body: some View {
    if #available(macOS 26, *), enabled {
      GlassEffectContainer(spacing: spacing) { content() }
    } else {
      content()
    }
  }
}
