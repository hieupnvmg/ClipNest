import AppKit
import SwiftUI

struct Glass: NSViewRepresentable {
  var opacity: Double = AppearancePreferences.defaultOpacity
  func makeNSView(context: Context) -> NSVisualEffectView {
    let v = NSVisualEffectView()
    v.material = .hudWindow
    v.blendingMode = .behindWindow
    v.state = .active
    v.alphaValue = opacity
    return v
  }
  func updateNSView(_ nsView: NSVisualEffectView, context: Context) { nsView.alphaValue = opacity }
}
final class ClipboardSearchField: NSSearchField {
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard window != nil else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      (NSApp.delegate as? AppDelegate)?.searchFieldAttached(self)
    }
  }
}

struct SearchField: NSViewRepresentable {
  @Binding var text: String
  /// Inside a Liquid Glass capsule the field draws no bezel of its own.
  var plain = false
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NSSearchField {
    let field = ClipboardSearchField()
    field.stringValue = text
    field.placeholderString = "Search clipboard"
    field.delegate = context.coordinator
    field.sendsSearchStringImmediately = true
    field.focusRingType = .none
    field.font = .systemFont(ofSize: 13)
    field.bezelStyle = .roundedBezel
    field.identifier = NSUserInterfaceItemIdentifier("clipboard-search")
    applyChrome(field)
    return field
  }
  private func applyChrome(_ field: NSSearchField) {
    if field.isBezeled == plain { field.isBezeled = !plain }
    if field.drawsBackground == plain { field.drawsBackground = !plain }
  }
  func updateNSView(_ field: NSSearchField, context: Context) {
    context.coordinator.parent = self
    applyChrome(field)
    if field.stringValue != text && (field.currentEditor() as? NSTextView)?.hasMarkedText() != true
    {
      field.stringValue = text
    }
  }
  class Coordinator: NSObject, NSSearchFieldDelegate {
    var parent: SearchField
    init(_ parent: SearchField) { self.parent = parent }
    func controlTextDidChange(_ obj: Notification) {
      if let field = obj.object as? NSSearchField { parent.text = field.stringValue }
    }
  }
}
extension Clip {
  static let previewCharacterLimit = 2_000
  /// Enough text to fill a card. Laying out megabytes of text made each card slow to render.
  var previewText: String {
    text.utf8.count <= Self.previewCharacterLimit
      ? text : String(text.prefix(Self.previewCharacterLimit))
  }
}
final class PreviewCache {
  static let shared = PreviewCache()
  let images = NSCache<NSString, NSImage>()
  let icons = NSCache<NSString, NSImage>()
  private final class CharacterCount {
    let bytes: Int
    let value: Int
    init(bytes: Int, value: Int) { self.bytes = bytes; self.value = value }
  }
  private let characterCounts = NSCache<NSString, CharacterCount>()
  /// Counting characters walks the whole string, so large texts are counted once.
  func characterCount(_ clip: Clip) -> Int {
    let bytes = clip.text.utf8.count
    guard bytes > 16 * 1024 else { return clip.text.count }
    let key = clip.id.uuidString as NSString
    if let cached = characterCounts.object(forKey: key), cached.bytes == bytes { return cached.value }
    let value = clip.text.count
    characterCounts.setObject(CharacterCount(bytes: bytes, value: value), forKey: key)
    return value
  }
  private init() {
    images.totalCostLimit = 32 * 1024 * 1024
    icons.countLimit = 200
  }
  func icon(_ clip: Clip) -> NSImage? {
    guard let bid = clip.bundleID else { return nil }
    if let i = icons.object(forKey: bid as NSString) { return i }
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) else {
      return nil
    }
    let icon = NSWorkspace.shared.icon(forFile: url.path)
    icons.setObject(icon, forKey: bid as NSString)
    return icon
  }
  /// Finder icons can hit the disk (or a network volume); look each path up once.
  func fileIcon(_ path: String) -> NSImage {
    let key = "file:\(path)" as NSString
    if let cached = icons.object(forKey: key) { return cached }
    let icon = NSWorkspace.shared.icon(forFile: path)
    icons.setObject(icon, forKey: key)
    return icon
  }
}
private struct ClipboardDragModifier: ViewModifier {
  let allowed: Bool
  let item: Clip
  let store: Store
  @ViewBuilder func body(content: Content) -> some View {
    if allowed {
      content.onDrag {
        if item.kind == "Image" { return store.imageProvider(item) }
        return NSItemProvider(object: item.text as NSString)
      }
    } else {
      content
    }
  }
}
struct ClipCard: View {
  let clip: Clip
  let store: Store
  let selected: Bool
  let number: Int
  var masked = false
  var revealed = false
  var protectionLabel = ""
  var onPrivacyAction: (() -> Void)? = nil
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        VStack(alignment: .leading, spacing: 2) {
          Text(clip.kind).font(.system(size: 14, weight: .semibold))
          Text(clip.date, style: .relative).font(.system(size: 10)).opacity(0.8).lineLimit(1)
        }
        Spacer(minLength: 0)
        if clip.board != nil { Image(systemName: "pin.fill").font(.system(size: 10)).opacity(0.8) }
        if let icon = PreviewCache.shared.icon(clip) {
          Image(nsImage: icon).resizable().interpolation(.high).frame(width: 36, height: 36).help(
            clip.source)
        } else {
          Image(systemName: clip.symbol).font(.system(size: 22, weight: .light)).frame(
            width: 32, height: 32
          ).help(clip.source)
        }
      }.foregroundColor(.white).padding(.horizontal, 13).frame(height: 52).background(
        clip.color.gradient)
      Group {
        if masked { maskedPreview } else { preview }
      }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
    }
    .frame(width: 242, height: 248)
    .background(Color(nsColor: .controlBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14).strokeBorder(
        selected ? Color.accentColor : Color.black.opacity(0.06), lineWidth: selected ? 3 : 0.7)
    )
    .overlay(alignment: .bottomTrailing) {
      if selected && number < 9 {
        Text("⌘\(number + 1)").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
          .padding(.horizontal, 5).padding(.vertical, 3).background(
            .regularMaterial, in: RoundedRectangle(cornerRadius: 4)
          ).padding(7)
      }
    }
    .overlay(alignment: .bottomLeading) {
      if revealed {
        Button {
          onPrivacyAction?()
        } label: {
          Label("Che lại", systemImage: "eye.slash").font(.system(size: 10))
        }
        .buttonStyle(.plain).padding(5).background(.regularMaterial, in: Capsule()).padding(7)
      }
    }
    .shadow(color: .black.opacity(0.10), radius: 7, x: 0, y: 3)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(clip.kind), \(clip.displayTitle.prefix(100)), from \(clip.source)")
  }
  var maskedPreview: some View {
    VStack(alignment: .leading, spacing: 9) {
      Label("Đã che", systemImage: "lock.shield").font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
      if !clip.title.isEmpty {
        Text(clip.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
      }
      Text(clip.previewText).font(.system(size: 13)).lineLimit(5).frame(
        maxWidth: .infinity, alignment: .leading)
      Spacer(minLength: 0)
      Text(protectionLabel).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
      Button {
        onPrivacyAction?()
      } label: {
        Label("Hiện 15 giây", systemImage: "eye").font(.system(size: 11))
      }
      .buttonStyle(.borderless)
    }.padding(13)
  }
  @ViewBuilder var preview: some View {
    switch clip.kind {
    case "Image":
      DeferredImagePreview(clip: clip, store: store)
    case "Link":
      VStack(spacing: 0) {
        ZStack {
          LinearGradient(
            colors: [clip.color.opacity(0.13), clip.color.opacity(0.04)], startPoint: .topLeading,
            endPoint: .bottomTrailing)
          Image(systemName: "globe.europe.africa.fill").font(.system(size: 65, weight: .ultraLight))
            .foregroundStyle(clip.color.opacity(0.65))
          Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .medium))
            .foregroundStyle(clip.color).frame(
              maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing
            ).padding(12)
        }
        VStack(alignment: .leading, spacing: 4) {
          Text(clip.displayTitle).font(.system(size: 12, weight: .semibold)).lineLimit(1)
          Text(clip.previewText).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(
          Color(nsColor: .controlBackgroundColor))
      }
    case "Files":
      VStack(spacing: 12) {
        if let first = clip.text.split(separator: "\n").first, let url = URL(string: String(first))
        {
          Image(nsImage: PreviewCache.shared.fileIcon(url.path)).resizable().scaledToFit()
            .frame(width: 76, height: 76)
        }
        Text(clip.displayTitle).font(.system(size: 12, weight: .medium)).lineLimit(2)
          .multilineTextAlignment(.center)
        Text("\(clip.text.split(separator: "\n").count) file(s)").font(.system(size: 10))
          .foregroundStyle(.secondary)
      }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity)
    case "Color":
      ZStack {
        (Color(hex: clip.text) ?? clip.color)
        Text(clip.text.uppercased()).font(.system(size: 26, weight: .medium, design: .monospaced))
          .foregroundColor(.white).shadow(color: .black.opacity(0.25), radius: 3)
      }
    default:
      VStack(alignment: .leading, spacing: 8) {
        if !clip.title.isEmpty {
          Text(clip.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
        }
        Text(clip.previewText).font(.system(size: 13)).lineSpacing(3).lineLimit(8).frame(
          maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        Text("\(PreviewCache.shared.characterCount(clip)) characters").font(.system(size: 10)).foregroundStyle(.tertiary)
          .frame(maxWidth: .infinity)
      }.padding(13)
    }
  }
}
struct ClipboardContent: View {
  @ObservedObject var store: Store
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  /// True when the panel uses the system Liquid Glass (macOS 26+).
  var nativeGlass: Bool {
    GlassRendering.resolve(
      style: store.interfaceStyle, reduceTransparency: reduceTransparency,
      supportsLiquid: GlassRendering.supportsLiquid) == .liquid
  }
  let boardColors: [Color] = [.red, .orange, .green, .blue, .purple, .pink]
  var body: some View {
    let items = store.filtered
    let selectedID = store.selectedClip?.id
    return VStack(spacing: 0) {
      toolbar.padding(.horizontal, 20).frame(height: 56)
      if items.isEmpty {
        emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollViewReader { proxy in
          ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 18) {
              ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let masked = store.isMasked(item)
                ClipCard(
                  clip: store.displayClip(item), store: store, selected: selectedID == item.id, number: index,
                  masked: masked, revealed: store.revealedSensitiveIDs.contains(item.id),
                  protectionLabel: store.sensitiveProtectionEnabled
                    ? store.protection(for: item).label : "",
                  onPrivacyAction: {
                    if masked {
                      store.revealSensitiveItem(item)
                    } else {
                      store.hideRevealedSensitiveItem(item.id)
                    }
                  }
                )
                .id(item.id)
                .onTapGesture(count: 2) { store.copy(item) }
                .onTapGesture {
                  store.selected = item.id
                  (NSApp.delegate as? AppDelegate)?.focusCards()
                }
                .contextMenu { cardMenu(item) }
                .modifier(ClipboardDragModifier(allowed: !masked, item: item, store: store))
              }
            }.padding(.horizontal, 20).padding(.vertical, 8)
          }
          .onChange(of: store.selected) { value in
            if let id = value { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) } }
          }
          .onChange(of: store.board) { _ in
            if let first = store.filtered.first { proxy.scrollTo(first.id, anchor: .leading) }
          }
        }
      }
      footer.padding(.horizontal, 22).frame(height: 26)
    }
    .frame(minWidth: 780, minHeight: 346)
    .background(
      ClipboardBackdrop(
        style: store.interfaceStyle, opacity: store.backgroundOpacity, variant: store.glassVariant))
    .overlay {
      // System glass draws its own rim; the hand-drawn outline is only for older styles.
      if !nativeGlass {
        RoundedRectangle(cornerRadius: PanelShape.cornerRadius)
          .strokeBorder(.white.opacity(0.3), lineWidth: 1)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: PanelShape.cornerRadius, style: .continuous))
    .alert("New Pinboard", isPresented: $store.adding) {
      TextField("Name", text: $store.newBoard)
      Button("Create") { store.createBoard() }
      Button("Cancel", role: .cancel) { store.newBoard = "" }
    }
    .alert("Rename Pinboard", isPresented: $store.showRenameBoard) {
      TextField("Name", text: $store.newBoard)
      Button("Save") { store.renameBoard() }
      Button("Cancel", role: .cancel) {}
    }
    .onChange(of: store.query) { _ in store.selected = store.filtered.first?.id }
    .onChange(of: store.kind) { _ in store.selected = store.filtered.first?.id }
    .onChange(of: store.settings) { value in if value { store.hideRevealedSensitiveItems() } }
    .sheet(isPresented: $store.settings) { preferences }
    .sheet(item: $store.editing) { item in editor(item) }
    .modifier(PikabinPresentation(sharing: store.pikabin))
    .modifier(PasswordGeneratorPresentation(model: store.passwordGenerator, store: store))
  }
  var toolbar: some View {
    GlassGroup(enabled: nativeGlass) { toolbarControls }
  }
  var toolbarControls: some View {
    HStack(spacing: 10) {
      if store.searchVisible {
        SearchField(text: $store.query, plain: nativeGlass).frame(width: 220)
          .padding(.horizontal, store.interfaceStyle == .liquidGlass ? 8 : 0)
          .padding(.vertical, store.interfaceStyle == .liquidGlass ? 5 : 0)
          .modifier(GlassControlSurface(enabled: store.interfaceStyle == .liquidGlass))
        Button {
          store.query = ""
          store.searchVisible = false
          (NSApp.delegate as? AppDelegate)?.focusCards()
        } label: {
          Image(systemName: nativeGlass ? "xmark" : "xmark.circle.fill")
            .foregroundStyle(.secondary)
            .frame(width: nativeGlass ? 28 : nil, height: nativeGlass ? 28 : nil)
            .contentShape(Circle())
        }.buttonStyle(.plain).modifier(GlassControlSurface(enabled: nativeGlass))
          .help("Close search")
      } else {
        Button {
          store.searchVisible = true
        } label: {
          Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium)).frame(
            width: 28, height: 28).contentShape(Circle())
        }.buttonStyle(.plain).modifier(GlassControlSurface(enabled: nativeGlass))
          .help("Search · ⌘F").accessibilityLabel("Search clipboard")
      }
      Spacer(minLength: 0)
      Button { store.passwordGenerator.open() } label: {
        Label("Password", systemImage: "key.fill")
          .font(.system(size: 12, weight: .medium)).padding(.horizontal, 10).frame(height: 28)
      }.buttonStyle(.plain)
        .modifier(GlassControlSurface(enabled: store.interfaceStyle == .liquidGlass))
        .help("Generate a secure password").accessibilityLabel("Generate password")
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 7) {
          boardTab("Clipboard", value: nil, index: 0)
          ForEach(Array(store.boards.enumerated()), id: \.element) { index, name in
            boardTab(name, value: name, index: index)
              .contextMenu {
                if !Store.automaticBoards.contains(name) {
                  Button("Rename Pinboard…") {
                    store.renamingBoard = name
                    store.newBoard = name
                    store.showRenameBoard = true
                  }
                  Button("Remove Pinboard") { store.deleteBoard(name) }
                }
              }
          }
          Button {
            store.newBoard = ""
            store.adding = true
          } label: {
            Image(systemName: "plus").font(.system(size: 15)).frame(width: 28, height: 28)
          }.buttonStyle(.plain).foregroundStyle(.secondary).help("New pinboard")
        }
        .padding(.horizontal, store.interfaceStyle == .liquidGlass ? 5 : 0)
        .padding(.vertical, store.interfaceStyle == .liquidGlass ? 3 : 0)
        .modifier(GlassControlSurface(enabled: store.interfaceStyle == .liquidGlass, interactive: false))
      }.fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
      Menu {
        Picker("Content type", selection: $store.kind) {
          ForEach(["All types", "Text", "Link", "Image", "Files", "Color"], id: \.self) { Text($0) }
        }
        Divider()
        Button(store.paused ? "Resume Capture" : "Pause Capture") { store.paused.toggle() }
        Button("Preferences…") { store.settings = true }
        Divider()
        Button("Quit ClipNest") { NSApp.terminate(nil) }
      } label: {
        Image(systemName: store.paused ? "pause.circle" : "ellipsis").font(.system(size: 18)).frame(
          width: 26)
      }.menuStyle(.borderlessButton).fixedSize()
        .padding(nativeGlass ? 5 : 0)
        .modifier(GlassControlSurface(enabled: nativeGlass))
        .help("Options and filters").accessibilityLabel("Options")
    }
  }
  func boardTab(_ name: String, value: String?, index: Int) -> some View {
    Button {
      store.selectBoard(value)
      (NSApp.delegate as? AppDelegate)?.focusCards()
    } label: {
      HStack(spacing: 6) {
        if value == nil {
          Image(systemName: "clock.arrow.circlepath").font(.system(size: 12))
        } else {
          Circle().fill(boardColors[index % boardColors.count]).frame(width: 9, height: 9)
        }
        Text(name).font(.system(size: 12, weight: store.board == value ? .semibold : .medium))
          .lineLimit(1)
      }.padding(.horizontal, 11).frame(height: 28).background(
        store.board == value ? Color.primary.opacity(0.10) : .clear, in: Capsule())
    }.buttonStyle(.plain)
  }
  var emptyState: some View {
    VStack(spacing: 10) {
      Image(
        systemName: store.query.isEmpty
          ? (store.board == nil ? "doc.on.clipboard" : "pin") : "magnifyingglass"
      ).font(.system(size: 30, weight: .ultraLight)).foregroundStyle(.secondary)
      Text(
        store.query.isEmpty
          ? (store.board == nil ? "A place for everything you copy" : "Keep your favorites here")
          : "No matching items"
      ).font(.system(size: 17, weight: .medium))
      Text(
        store.board == nil
          ? "Copy text, links, images or files. They'll appear here."
          : "Right-click a clipboard item and move it to this pinboard."
      ).font(.system(size: 12)).foregroundStyle(.secondary)
    }
  }
  var footer: some View {
    HStack(spacing: 6) {
      if store.error != nil {
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        Text("History storage needs attention — open Preferences")
      } else if let toast = store.toast {
        Text(toast)
      } else {
        Circle().fill(store.paused ? .orange : .green).frame(width: 5, height: 5)
        Text(store.paused ? "Paused" : "\(store.filtered.count) items")
        if store.kind != "All types" { Text("· \(store.kind)") }
      }
      Spacer()
      Text("← ↑ ↓ → to choose    ↵ to paste    ⌘1–9 quick paste    esc to close")
    }.font(.system(size: 10)).foregroundStyle(.secondary)
  }
  @ViewBuilder func cardMenu(_ item: Clip) -> some View {
    Button("Paste") { store.copy(item) }
    Button("Paste as Plain Text") { store.copy(item, plain: true) }.disabled(
      item.kind == "Image" || item.kind == "Files")
    Button("Copy Only") {
      store.copyOnly(item)
    }
    if PikabinSharing.supports(item) {
      Button("Push to pikab.in (1 week)…") { store.pushToPikabin(item) }
        .disabled(store.isMasked(item))
        .help(store.isMasked(item) ? "Hiện tạm nội dung trước khi gửi." : "Gửi text gốc lên pikab.in, lưu 1 tuần.")
    }
    Divider()
    if item.kind == "Link", item.board != Store.linksBoard {
      Button("Save to Useful Links") { store.saveLink(item) }
    }
    Menu("Move to Pinboard") {
      ForEach(store.boards, id: \.self) { name in Button(name) { store.pin(item, to: name) } }
      Divider()
      Button("Remove from Pinboard") { store.pin(item, to: nil) }
    }
    if store.sensitiveProtectionEnabled && store.protection(for: item).isSensitive {
      Button(store.isMasked(item) ? "Hiện tạm 15 giây" : "Che lại") {
        if store.isMasked(item) {
          store.revealSensitiveItem(item)
        } else {
          store.hideRevealedSensitiveItem(item.id)
        }
      }
    }
    Button("Edit / Rename…") { store.edit(item) }.disabled(store.isMasked(item))
    Divider()
    Button("Delete Item", role: .destructive) { store.remove(item) }
  }
  var preferences: some View { PreferencesView(store: store) }
  func editor(_ item: Clip) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Edit Item").font(.title2.bold())
      TextField("Label", text: $store.editedTitle).textFieldStyle(.roundedBorder)
      if ["Text", "Link", "Color"].contains(item.kind) {
        TextEditor(text: $store.editedText).font(.system(size: 14)).frame(height: 200).border(
          .secondary.opacity(0.2))
      }
      HStack {
        Button("Cancel") {
          store.editing = nil
          store.editedText = ""
          store.editedTitle = ""
        }.keyboardShortcut(.cancelAction)
        Spacer()
        Button("Save") { store.saveEdit() }.keyboardShortcut(.defaultAction)
      }
    }.padding(24).frame(width: 500)
  }
}
