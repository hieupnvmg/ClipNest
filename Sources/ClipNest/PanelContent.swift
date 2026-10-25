import SwiftUI

final class PanelPresentation: ObservableObject {
  @Published var isVisible = false
}

// Only observe visibility here. The clipboard view subscribes to Store while the
// panel is open; background captures cannot rebuild its cards or glass when hidden.
struct PanelContent<Content: View>: View {
  @ObservedObject var presentation: PanelPresentation
  @ViewBuilder let content: () -> Content
  var body: some View {
    Group {
      if presentation.isVisible { content() } else { Color.clear }
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
