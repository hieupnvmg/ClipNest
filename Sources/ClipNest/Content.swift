import AppKit
import ImageIO
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
struct SearchField: NSViewRepresentable {
  @Binding var text: String
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NSSearchField {
    let field = NSSearchField()
    field.placeholderString = "Search clipboard"
    field.delegate = context.coordinator
    field.sendsSearchStringImmediately = true
    field.focusRingType = .none
    field.font = .systemFont(ofSize: 13)
    field.bezelStyle = .roundedBezel
    field.identifier = NSUserInterfaceItemIdentifier("clipboard-search")
    DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
    return field
  }
  func updateNSView(_ field: NSSearchField, context: Context) {
    context.coordinator.parent = self
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
final class PreviewCache {
  static let shared = PreviewCache()
  let images = NSCache<NSString, NSImage>()
  let icons = NSCache<NSString, NSImage>()
  private init() {
    images.totalCostLimit = 32 * 1024 * 1024
    icons.countLimit = 100
  }
  func image(_ clip: Clip) -> NSImage? {
    let key = clip.id.uuidString as NSString
    if let i = images.object(forKey: key) { return i }
    guard let data = clip.data, let source = CGImageSourceCreateWithData(data as CFData, nil),
      let thumbnail = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: 600,
          kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary)
    else { return nil }
    let image = NSImage(
      cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
    images.setObject(image, forKey: key, cost: thumbnail.bytesPerRow * thumbnail.height)
    return image
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
}
private struct ClipboardDragModifier: ViewModifier {
  let allowed: Bool
  let item: Clip
  @ViewBuilder func body(content: Content) -> some View {
    if allowed {
      content.onDrag {
        if item.kind == "Image", let data = item.data {
          return NSItemProvider(item: data as NSData, typeIdentifier: "public.png")
        }
        return NSItemProvider(object: item.text as NSString)
      }
    } else {
      content
    }
  }
}
struct ClipCard: View {
  let clip: Clip
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
      Text(clip.text).font(.system(size: 13)).lineLimit(5).frame(
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
      if let img = PreviewCache.shared.image(clip) {
        GeometryReader { geo in
          Image(nsImage: img).resizable().scaledToFill().frame(
            width: geo.size.width, height: geo.size.height
          ).clipped()
        }
        .overlay(alignment: .bottom) {
          Text(clip.text).font(.system(size: 10)).padding(.horizontal, 7).padding(.vertical, 3)
            .background(.regularMaterial, in: Capsule()).padding(9)
        }
      } else {
        Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
      }
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
          Text(clip.text).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(
          Color(nsColor: .controlBackgroundColor))
      }
    case "Files":
      VStack(spacing: 12) {
        if let first = clip.text.split(separator: "\n").first, let url = URL(string: String(first))
        {
          Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit()
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
        Text(clip.text).font(.system(size: 13)).lineSpacing(3).lineLimit(8).frame(
          maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        Text("\(clip.text.count) characters").font(.system(size: 10)).foregroundStyle(.tertiary)
          .frame(maxWidth: .infinity)
      }.padding(13)
    }
  }
}
struct ClipboardContent: View {
  @ObservedObject var store: Store
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
                  clip: store.displayClip(item), selected: selectedID == item.id, number: index,
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
                .modifier(ClipboardDragModifier(allowed: !masked, item: item))
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
    .background(Glass(opacity: store.backgroundOpacity))
    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.3), lineWidth: 1))
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
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
  }
  var toolbar: some View {
    HStack(spacing: 10) {
      if store.searchVisible {
        SearchField(text: $store.query).frame(width: 220)
        Button {
          store.query = ""
          store.searchVisible = false
          (NSApp.delegate as? AppDelegate)?.focusCards()
        } label: {
          Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
        }.buttonStyle(.plain).help("Close search")
      } else {
        Button {
          store.searchVisible = true
        } label: {
          Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium)).frame(
            width: 28, height: 28)
        }.buttonStyle(.plain).help("Search · ⌘F").accessibilityLabel("Search clipboard")
      }
      Spacer(minLength: 0)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 7) {
          boardTab("Clipboard", value: nil, index: 0)
          ForEach(Array(store.boards.enumerated()), id: \.element) { index, name in
            boardTab(name, value: name, index: index)
              .contextMenu {
                Button("Rename Pinboard…") {
                  store.renamingBoard = name
                  store.newBoard = name
                  store.showRenameBoard = true
                }
                Button("Remove Pinboard") { store.deleteBoard(name) }
              }
          }
          Button {
            store.newBoard = ""
            store.adding = true
          } label: {
            Image(systemName: "plus").font(.system(size: 15)).frame(width: 28, height: 28)
          }.buttonStyle(.plain).foregroundStyle(.secondary).help("New pinboard")
        }
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
      }.menuStyle(.borderlessButton).fixedSize().help("Options and filters").accessibilityLabel(
        "Options")
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
      store.writeClipboard(item)
      store.toast = "Copied to clipboard"
    }
    Divider()
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
  var preferences: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        HStack {
          Image(nsImage: NSImage(named: "AppIcon") ?? NSImage()).resizable().frame(
            width: 32, height: 32)
          Text("ClipNest").font(.title2.bold())
          Spacer()
          Text("0.5.3").foregroundStyle(.secondary)
        }
        Divider()
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Appearance").font(.headline)
            Spacer()
            Text("\(Int(store.backgroundOpacity * 100))%").monospacedDigit().foregroundStyle(
              .secondary)
          }
          Slider(value: $store.backgroundOpacity, in: 0.35...1, step: 0.05) {
            Text("Background opacity")
          }.labelsHidden().accessibilityLabel("Background opacity")
          HStack {
            Text("More transparent")
            Spacer()
            Text("More opaque")
          }.font(.caption).foregroundStyle(.secondary)
          Text("Changes apply immediately. Cards and text stay readable.").font(.caption)
            .foregroundStyle(.secondary)
        }
        Divider()
        UpdateSettings()
        Divider()
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Open Clipboard").font(.headline)
            Spacer()
            Text(store.shortcut.label).font(.system(.body, design: .monospaced)).padding(
              .horizontal, 10
            ).padding(.vertical, 5).background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            Button(store.recordingShortcut ? "Cancel" : "Change…") {
              if let app = NSApp.delegate as? AppDelegate {
                if store.recordingShortcut {
                  app.cancelShortcutRecording()
                } else {
                  app.beginShortcutRecording()
                }
              }
            }
            Button("Reset") { (NSApp.delegate as? AppDelegate)?.applyShortcut(.default) }.disabled(
              store.shortcut == .default || store.recordingShortcut)
          }
          Text(
            store.recordingShortcut
              ? "Press your new shortcut now. Esc to cancel."
              : "Default: ⇧⌘V. Changes are saved automatically."
          ).font(.caption).foregroundStyle(.secondary)
          if let message = store.shortcutError {
            Text(message).font(.caption).foregroundStyle(.orange)
          }
        }
        Divider()
        HStack {
          VStack(alignment: .leading, spacing: 5) {
            Text("Clipboard Storage").font(.headline)
            Text("\(store.storageDescription) · \(store.clips.count) items").font(
              .system(.body, design: .monospaced)
            ).monospacedDigit()
            Text("SQLite database, journal and any migration backup on this Mac.").font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button("Clear…", role: .destructive) { store.clearConfirmation = true }
        }
        Divider()
        Text("Clipboard").font(.headline)
        Picker("Keep unpinned items", selection: $store.retention) {
          Text("Last 500").tag(500)
          Text("Last 1,000").tag(1000)
          Text("Last 5,000").tag(5000)
          Text("Unlimited").tag(0)
        }
        Text("Pinned items are always kept. Retention applies when you save these settings.").font(
          .caption
        ).foregroundStyle(.secondary)
        Divider()
        VStack(alignment: .leading, spacing: 8) {
          Toggle("Tự bảo vệ nội dung nhạy cảm", isOn: $store.sensitiveProtectionEnabled).font(
            .headline)
          Text(
            "Chỉ che khi hiển thị: mật khẩu, token, private key và thông tin cá nhân nhận diện được vẫn được lưu để dán nguyên bản."
          ).font(.caption).foregroundStyle(.secondary)
          Text(
            "Không tự bỏ qua nội dung theo pattern. Nút Hiện mở tạm 15 giây; nội dung gốc vẫn lưu trên máy, không phải mã hóa."
          ).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
          Text(
            "Chỉ nhận diện văn bản, có thể nhầm hoặc bỏ sót; chưa quét chữ trong ảnh. Nội dung cũ được che khi nhận diện, không tự xóa khỏi lịch sử."
          ).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        Divider()
        Text("Ignore applications").font(.headline)
        TextField("Bundle IDs separated by commas", text: $store.excluded).textFieldStyle(
          .roundedBorder)
        Text(
          "Example: com.apple.keychainaccess. Password and transient clipboard markers are also ignored."
        ).font(.caption).foregroundStyle(.secondary)
        Divider()
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("Direct paste").font(.headline)
            Text(
              store.accessibilityGranted
                ? "Accessibility permission enabled"
                : "Permission needed to paste directly into other apps."
            ).font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          Button(store.accessibilityGranted ? "Enabled" : "Open Settings…") {
            store.requestAccessibilityPermission(openSettings: true)
          }.disabled(store.accessibilityGranted)
        }
        Text(
          "Clipboard history stays on this Mac, without app-level encryption. Only update checks and downloads contact GitHub; clipboard contents are never uploaded."
        ).font(.caption).foregroundStyle(.secondary)
        if let error = store.error {
          Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
        }
        HStack {
          Text("Author: hieupn").font(.caption).foregroundStyle(.secondary)
          Spacer()
          Button("Done") {
            (NSApp.delegate as? AppDelegate)?.cancelShortcutRecording()
            store.trim()
            store.save()
            store.settings = false
          }.keyboardShortcut(.defaultAction)
        }
      }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
    }.frame(width: 560, height: 680)
      .onAppear {
        store.refreshStorageUsage()
        store.refreshAccessibilityStatus()
      }
      .onDisappear {
        if store.recordingShortcut { (NSApp.delegate as? AppDelegate)?.cancelShortcutRecording() }
      }
      .alert("Clear all clipboard history?", isPresented: $store.clearConfirmation) {
        Button("Cancel", role: .cancel) {}
        Button("Clear All", role: .destructive) { store.clearHistory() }
      } message: {
        Text(
          "All saved items, including pinned items, will be deleted. Migration backups will also be removed. Your pinboards and current system clipboard will be kept. This cannot be undone."
        )
      }
  }
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
