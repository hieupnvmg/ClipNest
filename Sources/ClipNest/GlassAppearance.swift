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
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  var body: some View {
    let rendering = GlassRendering.resolve(
      style: style, reduceTransparency: reduceTransparency,
      supportsLiquid: GlassRendering.supportsLiquid)
    Group {
      if rendering == .solid {
        RoundedRectangle(cornerRadius: 22).fill(Color(nsColor: .windowBackgroundColor))
      } else if #available(macOS 26, *), rendering == .liquid {
        RoundedRectangle(cornerRadius: 22).fill(.clear)
          .glassEffect(.regular, in: .rect(cornerRadius: 22))
          .opacity(opacity)
      } else {
        Glass(opacity: opacity)
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

// No per-card glass or custom shader: one window backdrop, with light control outlines.
// Keeping the toolbar on the same glass surface avoids nested blur/rendering passes.
struct GlassControlSurface: ViewModifier {
  let enabled: Bool
  func body(content: Content) -> some View {
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
