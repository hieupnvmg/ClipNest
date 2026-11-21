import AppKit
import SwiftUI

enum PreferencesPane: String, CaseIterable, Identifiable {
  case general, appearance, clipboard, privacy, updates
  var id: String { rawValue }
  var title: String {
    switch self {
    case .general: return "General"
    case .appearance: return "Appearance"
    case .clipboard: return "Clipboard"
    case .privacy: return "Privacy"
    case .updates: return "Updates"
    }
  }
  var symbol: String {
    switch self {
    case .general: return "gearshape.fill"
    case .appearance: return "paintbrush.fill"
    case .clipboard: return "doc.on.clipboard.fill"
    case .privacy: return "hand.raised.fill"
    case .updates: return "arrow.down.circle.fill"
    }
  }
  var tint: Color {
    switch self {
    case .general: return .gray
    case .appearance: return .indigo
    case .clipboard: return .orange
    case .privacy: return .blue
    case .updates: return .green
    }
  }
}

/// Small explanatory text under a settings group, like System Settings.
struct SettingsFootnote: View {
  let text: String
  init(_ text: String) { self.text = text }
  var body: some View {
    Text(text).font(.caption).foregroundStyle(.secondary)
      .multilineTextAlignment(.leading)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct PaneIcon: View {
  let pane: PreferencesPane
  var size: CGFloat = 22
  var body: some View {
    Image(systemName: pane.symbol)
      .font(.system(size: size * 0.55, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .background(pane.tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
  }
}

struct PreferencesView: View {
  @ObservedObject var store: Store
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  private var nativeGlass: Bool {
    GlassRendering.resolve(
      style: store.interfaceStyle, reduceTransparency: reduceTransparency,
      supportsLiquid: GlassRendering.supportsLiquid) == .liquid
  }
  private var appDelegate: AppDelegate? { NSApp.delegate as? AppDelegate }
  // This toolchain has no SwiftUI macro plugin for @State, so the selection lives in Store.
  private var pane: PreferencesPane { store.preferencesPane }

  var body: some View {
    HStack(spacing: 0) {
      sidebar
      Divider()
      VStack(spacing: 0) {
        HStack(spacing: 10) {
          PaneIcon(pane: pane, size: 28)
          Text(pane.title).font(.system(size: 20, weight: .semibold))
          Spacer()
        }
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 4)
        Form { detail }
          .formStyle(.grouped)
          .scrollContentBackground(.hidden)
        Divider()
        footer
      }
      .frame(maxWidth: .infinity)
    }
    .frame(width: 720, height: 540)
    .onAppear {
      store.refreshStorageUsage()
      store.refreshAccessibilityStatus()
    }
    .onDisappear {
      if store.recordingShortcut { appDelegate?.cancelShortcutRecording() }
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

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 10) {
        Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
          .resizable().frame(width: 36, height: 36)
        VStack(alignment: .leading, spacing: 1) {
          Text("ClipNest").font(.system(size: 14, weight: .semibold))
          Text(
            "Version "
              + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? "–")
          ).font(.system(size: 11)).foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 10).padding(.top, 22).padding(.bottom, 16)
      ForEach(PreferencesPane.allCases) { item in
        Button {
          store.preferencesPane = item
        } label: {
          HStack(spacing: 9) {
            PaneIcon(pane: item)
            Text(item.title).font(.system(size: 13))
            Spacer(minLength: 0)
          }
          .padding(.horizontal, 8).padding(.vertical, 6)
          .background(
            pane == item ? Color.accentColor.opacity(0.18) : .clear,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(pane == item ? .isSelected : [])
      }
      Spacer()
      Text("Made by hieupn").font(.system(size: 11)).foregroundStyle(.tertiary)
        .padding(.horizontal, 10).padding(.bottom, 16)
    }
    .padding(.horizontal, 10)
    .frame(width: 200)
    .background(Color.primary.opacity(0.035))
  }

  private var footer: some View {
    HStack(spacing: 10) {
      if let error = store.error {
        Label(error, systemImage: "exclamationmark.triangle.fill")
          .font(.caption).foregroundStyle(.red).lineLimit(2).help(error)
          .textSelection(.enabled)
      }
      Spacer()
      Button("Done") {
        appDelegate?.cancelShortcutRecording()
        store.trim()
        store.save()
        store.settings = false
      }
      .keyboardShortcut(.defaultAction)
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
    }
    .padding(.horizontal, 20).padding(.vertical, 12)
  }

  @ViewBuilder private var detail: some View {
    switch pane {
    case .general: general
    case .appearance: appearance
    case .clipboard: clipboard
    case .privacy: privacy
    case .updates: UpdateSettings()
    }
  }

  @ViewBuilder private var general: some View {
    Section {
      LabeledContent("Open ClipNest") {
        HStack(spacing: 8) {
          Text(store.recordingShortcut ? "Type shortcut…" : store.shortcut.label)
            .font(.system(.body, design: .rounded).weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(
              store.recordingShortcut ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.07),
              in: RoundedRectangle(cornerRadius: 6, style: .continuous))
          Button(store.recordingShortcut ? "Cancel" : "Change…") {
            if store.recordingShortcut {
              appDelegate?.cancelShortcutRecording()
            } else {
              appDelegate?.beginShortcutRecording()
            }
          }
          Button("Reset") { appDelegate?.applyShortcut(.default) }
            .disabled(store.shortcut == .default || store.recordingShortcut)
        }
      }
      if let message = store.shortcutError {
        Label(message, systemImage: "exclamationmark.triangle.fill")
          .font(.caption).foregroundStyle(.orange)
      }
    } header: {
      Text("Keyboard")
    } footer: {
      SettingsFootnote(
        store.recordingShortcut
          ? "Press your new shortcut now. Esc to cancel."
          : "Default: ⇧⌘V. Changes are saved automatically.")
    }
    StartupSettings()
    Section {
      LabeledContent {
        if store.accessibilityGranted {
          Label("Enabled", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
          Button("Open Settings…") { store.requestAccessibilityPermission(openSettings: true) }
        }
      } label: {
        Text("Paste directly into other apps")
      }
    } header: {
      Text("Direct paste")
    } footer: {
      SettingsFootnote(
        store.accessibilityGranted
          ? "Choosing an item pastes it into the app you were using."
          : "Needs Accessibility permission. Without it, items are copied and you press ⌘V yourself.")
    }
  }

  @ViewBuilder private var appearance: some View {
    Section {
      Picker("Style", selection: $store.interfaceStyle) {
        ForEach(InterfaceStyle.allCases) { style in Text(style.label).tag(style) }
      }
      .pickerStyle(.segmented)
      if nativeGlass {
        Picker("Glass", selection: $store.glassVariant) {
          ForEach(GlassVariant.allCases) { variant in Text(variant.label).tag(variant) }
        }
        .pickerStyle(.segmented)
      } else {
        LabeledContent("Background opacity") {
          HStack(spacing: 10) {
            Slider(value: $store.backgroundOpacity, in: 0.35...1, step: 0.05)
              .frame(width: 180)
              .accessibilityLabel("Background opacity")
            Text("\(Int(store.backgroundOpacity * 100))%").monospacedDigit()
              .foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
          }
        }
      }
    } footer: {
      SettingsFootnote(appearanceNote)
    }
  }
  private var appearanceNote: String {
    if nativeGlass {
      return "Liquid Glass uses Apple’s native glass. Regular adapts for legibility; Clear shows more of what is behind the panel, like iPhone over a bright wallpaper. Cards always stay readable."
    }
    if store.interfaceStyle == .liquidGlass && !GlassRendering.supportsLiquid {
      return "Liquid Glass uses a frosted background on this Mac. Native Liquid Glass requires macOS 26."
    }
    return "Changes apply immediately. Cards and text stay readable."
  }

  @ViewBuilder private var clipboard: some View {
    Section {
      Picker("Keep unpinned items", selection: $store.retention) {
        Text("Last 500").tag(500)
        Text("Last 1,000").tag(1000)
        Text("Last 5,000").tag(5000)
        Text("Unlimited").tag(0)
      }
      LabeledContent("Storage") {
        HStack(spacing: 10) {
          Text("\(store.storageDescription) · \(store.clips.count) items")
            .monospacedDigit().foregroundStyle(.secondary)
          Button("Clear…", role: .destructive) { store.clearConfirmation = true }
        }
      }
    } header: {
      Text("History")
    } footer: {
      SettingsFootnote(
        "Pinned items are always kept; the limit applies when you click Done. History is stored in a SQLite database on this Mac.")
    }
    Section {
      TextField("Bundle IDs", text: $store.excluded, prompt: Text("com.example.app, …"), axis: .vertical)
        .lineLimit(1...4)
        .labelsHidden()
    } header: {
      Text("Ignore applications")
    } footer: {
      SettingsFootnote(
        "Bundle IDs separated by commas, e.g. com.apple.keychainaccess. Password and transient clipboard markers are always ignored.")
    }
  }

  @ViewBuilder private var privacy: some View {
    Section {
      Toggle("Tự bảo vệ nội dung nhạy cảm", isOn: $store.sensitiveProtectionEnabled)
    } footer: {
      VStack(alignment: .leading, spacing: 6) {
        SettingsFootnote(
          "Chỉ che khi hiển thị: mật khẩu, token, private key và thông tin cá nhân nhận diện được vẫn được lưu để dán nguyên bản.")
        SettingsFootnote(
          "Không tự bỏ qua nội dung theo pattern. Nút Hiện mở tạm 15 giây; nội dung gốc vẫn lưu trên máy, không phải mã hóa.")
        SettingsFootnote(
          "Chỉ nhận diện văn bản, có thể nhầm hoặc bỏ sót; chưa quét chữ trong ảnh. Nội dung cũ được che khi nhận diện, không tự xóa khỏi lịch sử.")
      }
    }
    Section {
      Label("History stays on this Mac, without app-level encryption.", systemImage: "internaldrive")
      Label("Update checks contact GitHub and never include clipboard contents.", systemImage: "arrow.down.circle")
      Label("Text is sent to pikab.in only when you choose Push to pikab.in.", systemImage: "paperplane")
    } header: {
      Text("Your data")
    }
  }
}
