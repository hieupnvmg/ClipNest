import AppKit
import SwiftUI

enum PreferencesPane: String, CaseIterable, Identifiable {
  case general, appearance, clipboard, developer, sync, privacy, updates
  var id: String { rawValue }
  var title: String {
    switch self {
    case .general: return "General"
    case .appearance: return "Appearance"
    case .clipboard: return "Clipboard"
    case .sync: return "iCloud Sync"
    case .developer: return "Developer"
    case .privacy: return "Privacy"
    case .updates: return "Updates"
    }
  }
  var symbol: String {
    switch self {
    case .general: return "gearshape.fill"
    case .appearance: return "paintbrush.fill"
    case .clipboard: return "doc.on.clipboard.fill"
    case .sync: return "icloud.fill"
    case .developer: return "terminal.fill"
    case .privacy: return "hand.raised.fill"
    case .updates: return "arrow.down.circle.fill"
    }
  }
  var tint: Color {
    switch self {
    case .general: return .gray
    case .appearance: return .indigo
    case .clipboard: return .orange
    case .sync: return .cyan
    case .developer: return Color(white: 0.25)
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
    case .sync: SyncSettings(store: store)
    case .developer: developer
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
      Toggle("Recognize text in images", isOn: $store.imageTextRecognition)
      if store.imageTextRecognition {
        LabeledContent("Text model") { imageTextModelStatus }
        LabeledContent("Languages") {
          Text(ImageTextRecognizer.languageNames.isEmpty
            ? "Unavailable" : ImageTextRecognizer.languageNames.joined(separator: ", "))
            .foregroundStyle(.secondary)
        }
        LabeledContent("Images with text") {
          HStack(spacing: 8) {
            if store.imageTextPending > 0 {
              ProgressView().controlSize(.small)
              Text("\(store.imageTextPending) in progress ·").foregroundStyle(.secondary)
            }
            Text("\(store.imageText.values.filter { !$0.text.isEmpty }.count) of \(store.clips.filter { $0.kind == "Image" }.count)")
              .monospacedDigit().foregroundStyle(.secondary)
          }
        }
        if let error = store.imageTextModelError {
          Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.caption).foregroundStyle(.orange)
        }
      }
    } header: {
      Text("Images")
    } footer: {
      SettingsFootnote(
        "Uses Apple’s Vision on this Mac; nothing is uploaded and nothing is downloaded. The model is part of macOS: the first recognition after installing or updating macOS prepares it, which can take about a minute. Search then finds screenshots by their words, and images that show passwords or tokens are masked.")
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
    DatabasePerformanceSection(store: store)
  }

  @ViewBuilder private var imageTextModelStatus: some View {
    let preparing = store.imageTextModelChecking || (!store.imageTextModelReady && store.imageTextPending > 0)
    if ImageTextRecognizer.languageNames.isEmpty {
      Label("Unavailable on this Mac", systemImage: "xmark.circle.fill").foregroundStyle(.red)
    } else if preparing {
      HStack(spacing: 8) {
        ProgressView().controlSize(.small)
        Text(store.imageTextModelReady ? "Checking…" : "Preparing… about a minute the first time")
          .foregroundStyle(.secondary)
      }
    } else if store.imageTextModelReady {
      HStack(spacing: 10) {
        Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        Button("Check Again") { store.prepareImageTextModel() }
      }
    } else {
      HStack(spacing: 10) {
        Label("Not prepared on this macOS yet", systemImage: "clock.arrow.circlepath")
          .foregroundStyle(.orange)
        Button("Prepare Now") { store.prepareImageTextModel() }
      }
    }
  }

  @ViewBuilder private var developer: some View {
    Section {
      Toggle("Review pastes into terminals", isOn: $store.safeTerminalPaste)
    } header: {
      Text("Terminal")
    } footer: {
      SettingsFootnote(
        "When you paste into Terminal, iTerm2, Ghostty, Warp, kitty, Alacritty, WezTerm or Hyper, ClipNest pastes plain text without the trailing newline, so nothing runs on its own. It asks first when the text has several lines or an Ansible command looks risky.")
    }
    Section {
      Toggle("Collect Ansible commands", isOn: $store.collectAnsibleCommands)
      LabeledContent("Production names") {
        TextField("Production names", text: $store.productionNames, prompt: Text("prod, production, prd"))
          .labelsHidden().multilineTextAlignment(.trailing).frame(width: 220)
      }
    } header: {
      Text("Ansible")
    } footer: {
      SettingsFootnote(
        "Copied ansible and ansible-playbook commands gather on the Ansible board, showing their inventory, limit and tags. ClipNest warns when an inventory, limit or host pattern contains one of these words and the command has no --limit or --check, or passes a secret with -e. Copied PLAY RECAP output offers a retry command for failed hosts, and FAILED! output can be turned into a readable error. Ansible Vault blocks are masked.")
    }
    Section {
      Text("Right-click a text item and choose Transform to format, minify or convert JSON to YAML, decode a JWT, Base64 or URL, convert a Unix timestamp, remove terminal colors, join lines, quote for the shell or hash with SHA-256. The result is copied and added to history; nothing leaves your Mac.")
        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    } header: {
      Text("Transforms")
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

/// Typed passphrases live here, not in Store, and are cleared once used.
final class SyncSetupForm: ObservableObject {
  @Published var passphrase = ""
  @Published var confirmation = ""
  @Published var error: String?
}

struct SyncSettings: View {
  @ObservedObject var store: Store
  @StateObject private var form = SyncSetupForm()
  private var status: SyncStatus { store.syncStatus }

  var body: some View {
    if !status.cloudAvailable {
      Section {
        Label("iCloud Drive is off on this Mac", systemImage: "exclamationmark.icloud")
          .foregroundStyle(.orange)
      } footer: {
        SettingsFootnote("Turn on iCloud Drive in System Settings → Apple Account → iCloud, then come back here.")
      }
    } else if status.configured {
      configured
    } else {
      setup
    }
  }

  @ViewBuilder private var configured: some View {
    Section {
      LabeledContent("Status") {
        HStack(spacing: 8) {
          if status.busy { ProgressView().controlSize(.small) }
          if let error = status.error {
            Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
              .lineLimit(2)
          } else if let last = status.lastSync {
            Label("Synced \(last.formatted(.relative(presentation: .named)))",
              systemImage: "checkmark.icloud.fill").foregroundStyle(.green)
          } else {
            Text("Waiting for first sync…").foregroundStyle(.secondary)
          }
        }
      }
      LabeledContent("Pinned items in sync") {
        Text("\(status.synced)").monospacedDigit().foregroundStyle(.secondary)
      }
      Toggle("Include sensitive items", isOn: $store.syncIncludeSensitive)
      HStack {
        Button("Stop Syncing on This Mac", role: .destructive) { store.leaveSync() }
        Spacer()
        Button("Sync Now") { store.syncNow() }.disabled(status.busy)
      }
    } header: {
      Text("Pinboards")
    } footer: {
      SettingsFootnote(
        "Items on your own pinboards sync through the “ClipNest Sync” folder in iCloud Drive, encrypted with your sync passphrase before they leave this Mac. Useful Links and IP Addresses fill themselves from every copy and stay on each Mac. Sensitive items stay local unless you include them. Changes from other Macs arrive within about a minute.")
    }
  }

  @ViewBuilder private var setup: some View {
    let joining = status.vaultExists
    Section {
      SecureField("Sync passphrase", text: $form.passphrase)
      if !joining {
        SecureField("Confirm passphrase", text: $form.confirmation)
      }
      if let error = form.error {
        Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
      }
      HStack {
        Spacer()
        if status.busy { ProgressView().controlSize(.small) }
        Button(joining ? "Join Sync" : "Start Syncing") { submit(joining: joining) }
          .buttonStyle(.borderedProminent)
          .disabled(status.busy || form.passphrase.isEmpty)
      }
    } header: {
      Text(joining ? "Join from this Mac" : "Sync pinboards with iCloud Drive")
    } footer: {
      SettingsFootnote(
        joining
          ? "Another Mac already syncs ClipNest. Enter the same sync passphrase you chose there."
          : "Choose a passphrase you will also enter on your other Macs. It encrypts everything ClipNest puts in iCloud Drive, so Apple cannot read it. It cannot be recovered: if you forget it, delete the “ClipNest Sync” folder in iCloud Drive and start again.")
    }
  }

  private func submit(joining: Bool) {
    form.error = nil
    if !joining && form.passphrase != form.confirmation {
      form.error = "The passphrases do not match."
      return
    }
    store.setUpSync(passphrase: form.passphrase, join: joining) { error in
      if let error {
        form.error = error.localizedDescription
      } else {
        form.passphrase = ""
        form.confirmation = ""
      }
    }
  }
}

/// Settings › Clipboard: times the history database on a copy and shows each operation as a bar
/// against one frame (16.7 ms), the point where a delay starts to be visible.
struct DatabasePerformanceSection: View {
  @ObservedObject var store: Store

  var body: some View {
    Section {
      if let result = store.databaseBenchmark {
        summary(result)
        ForEach(DatabaseBenchmark.Moment.allCases, id: \.self) { moment in
          let steps = result.steps.filter { $0.moment == moment }
          if !steps.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
              Text(moment.rawValue).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
              ForEach(steps) { step in row(step, scale: scale(result)) }
            }
            .padding(.vertical, 2)
          }
        }
      }
      LabeledContent {
        HStack(spacing: 8) {
          if store.databaseBenchmarkRunning {
            ProgressView().controlSize(.small)
            Text("Measuring…").foregroundStyle(.secondary)
          } else if let result = store.databaseBenchmark {
            Text(result.date, style: .time).foregroundStyle(.secondary)
          }
          Button(store.databaseBenchmark == nil ? "Run Benchmark" : "Run Again") { store.runDatabaseBenchmark() }
            .disabled(store.databaseBenchmarkRunning)
        }
      } label: {
        Text(store.databaseBenchmark == nil ? "Check database speed" : "Last measured")
      }
      if let error = store.databaseBenchmarkError {
        Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
      }
    } header: {
      Text("Database performance")
    } footer: {
      SettingsFootnote(
        "Runs on a temporary copy of your history, which is deleted afterwards; your data is never changed. Saves happen in the background. The dashed line is one frame (16.7 ms): anything shorter cannot be noticed.")
    }
  }

  private func summary(_ result: DatabaseBenchmark) -> some View {
    let slowest = result.slowestInteractive?.milliseconds ?? 0
    let smooth = slowest < DatabaseBenchmark.frameBudget
    return HStack(alignment: .top, spacing: 12) {
      Image(systemName: smooth ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
        .font(.system(size: 26)).foregroundStyle(smooth ? Color.green : Color.orange)
      VStack(alignment: .leading, spacing: 3) {
        Text(smooth ? "Fast — every save is shorter than one frame" : "Some saves take longer than one frame")
          .font(.system(size: 13, weight: .semibold))
        Text(String(format: "Slowest while in use: %@ · launch: %@", Self.format(slowest), Self.format(result.launchMilliseconds)))
          .font(.caption).foregroundStyle(.secondary)
        Text("\(result.clips.formatted()) items · \(result.images.formatted()) images · "
          + ByteCountFormatter.string(fromByteCount: result.databaseBytes, countStyle: .file))
          .font(.caption).foregroundStyle(.secondary).monospacedDigit()
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 4)
  }

  /// The bar scale: the slowest step, but never less than a frame so the frame line always fits.
  private func scale(_ result: DatabaseBenchmark) -> Double {
    max(DatabaseBenchmark.frameBudget * 1.25, result.steps.map(\.milliseconds).max() ?? 0)
  }

  private func row(_ step: DatabaseBenchmark.Step, scale: Double) -> some View {
    let barWidth: CGFloat = 170
    let fraction = min(1, step.milliseconds / scale)
    let frameX = barWidth * DatabaseBenchmark.frameBudget / scale
    return HStack(spacing: 10) {
      Text(step.title).font(.system(size: 12)).lineLimit(1)
      Spacer(minLength: 8)
      ZStack(alignment: .leading) {
        Capsule().fill(Color.primary.opacity(0.07))
        Capsule().fill(color(step).gradient)
          .frame(width: max(4, barWidth * fraction))
        Path { path in
          path.move(to: CGPoint(x: frameX, y: -3))
          path.addLine(to: CGPoint(x: frameX, y: 9))
        }
        .stroke(Color.secondary.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
      }
      .frame(width: barWidth, height: 6)
      Text(Self.format(step.milliseconds))
        .font(.system(size: 12, design: .rounded)).monospacedDigit()
        .foregroundStyle(.secondary).frame(width: 62, alignment: .trailing)
    }
    .accessibilityElement(children: .combine)
  }

  private func color(_ step: DatabaseBenchmark.Step) -> Color {
    if step.moment == .launch { return .blue }
    if step.milliseconds < DatabaseBenchmark.frameBudget / 2 { return .green }
    return step.milliseconds < DatabaseBenchmark.frameBudget ? .yellow : .orange
  }

  static func format(_ milliseconds: Double) -> String {
    milliseconds < 10 ? String(format: "%.1f ms", milliseconds) : String(format: "%.0f ms", milliseconds)
  }
}
