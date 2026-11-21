import AppKit
import Sparkle
import SwiftUI

/// What the update window shows. Sparkle still downloads, verifies the EdDSA signature
/// and installs; this only replaces its stock alerts with ClipNest's own window.
final class UpdateFlow: ObservableObject {
  enum Phase: Equatable {
    case idle, permission, checking, available, upToDate, downloading, extracting, ready
    case installing, failed(String)
  }
  @Published var phase: Phase = .idle
  @Published var version = ""
  @Published var date: Date?
  @Published var size: UInt64 = 0
  @Published var notes: [ReleaseNotes.Block] = []
  @Published var notesUnavailable = false
  @Published var stage: SPUUserUpdateStage = .notDownloaded
  @Published var informationOnly = false
  @Published var critical = false
  @Published var received: UInt64 = 0
  @Published var expected: UInt64 = 0
  @Published var extraction = 0.0
  @Published var applicationTerminated = true
  let currentVersion =
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

  // Sparkle hands out one-shot replies; each is cleared as soon as it is used.
  var cancellation: (() -> Void)?
  var choiceReply: ((SPUUserUpdateChoice) -> Void)?
  var acknowledgement: (() -> Void)?
  var permissionReply: ((SUUpdatePermissionResponse) -> Void)?
  var retryTermination: (() -> Void)?
  var close: () -> Void = {}

  var downloadFraction: Double? {
    expected > 0 ? min(Double(received) / Double(expected), 1) : nil
  }
  func choose(_ choice: SPUUserUpdateChoice) {
    let reply = choiceReply
    choiceReply = nil
    // Installing continues in the same window (download, then install progress).
    if choice != .install { close() }
    reply?(choice)
  }
  func cancel() {
    let reply = cancellation
    cancellation = nil
    close()
    reply?()
  }
  func acknowledge() {
    let reply = acknowledgement
    acknowledgement = nil
    close()
    reply?()
  }
  func answerPermission(automaticChecks: Bool) {
    let reply = permissionReply
    permissionReply = nil
    close()
    reply?(SUUpdatePermissionResponse(automaticUpdateChecks: automaticChecks, sendSystemProfile: false))
  }
  func retryTerminating() { retryTermination?() }
  /// Closing the window is the same as the safest button for the current step.
  func windowClosed() {
    if permissionReply != nil { answerPermission(automaticChecks: false) }
    if choiceReply != nil { choose(.dismiss) }
    if cancellation != nil { cancel() }
    if acknowledgement != nil { acknowledge() }
  }
  func reset() {
    cancellation = nil
    choiceReply = nil
    acknowledgement = nil
    permissionReply = nil
    retryTermination = nil
    phase = .idle
  }
}

/// Release notes in the appcast are short Markdown: headings, paragraphs and bullets.
enum ReleaseNotes {
  struct Block: Identifiable, Equatable {
    enum Kind: Equatable { case heading, paragraph, bullet }
    let id: Int
    let kind: Kind
    let text: AttributedString
  }
  static func blocks(markdown: String) -> [Block] {
    var blocks: [Block] = []
    var paragraph: [String] = []
    func inline(_ text: String) -> AttributedString {
      (try? AttributedString(
        markdown: text,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(text)
    }
    func add(_ kind: Block.Kind, _ text: String) {
      let trimmed = text.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { return }
      blocks.append(Block(id: blocks.count, kind: kind, text: inline(trimmed)))
    }
    func flush() {
      add(.paragraph, paragraph.joined(separator: " "))
      paragraph.removeAll()
    }
    for raw in markdown.components(separatedBy: .newlines) {
      let line = raw.trimmingCharacters(in: .whitespaces)
      if line.isEmpty {
        flush()
      } else if line.hasPrefix("#") {
        flush()
        add(.heading, String(line.drop { $0 == "#" }))
      } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
        flush()
        add(.bullet, String(line.dropFirst(2)))
      } else {
        paragraph.append(line)
      }
    }
    flush()
    return blocks
  }
  static func blocks(html: Data) -> [Block] {
    guard
      let text = try? NSAttributedString(
        data: html, options: [.documentType: NSAttributedString.DocumentType.html],
        documentAttributes: nil
      ).string
    else { return [] }
    return blocks(markdown: text)
  }
}

final class ClipNestUpdateDriver: NSObject, SPUUserDriver, NSWindowDelegate {
  let flow = UpdateFlow()
  private var window: NSWindow?

  override init() {
    super.init()
    flow.close = { [weak self] in self?.closeWindow() }
  }
  private func present() {
    if window == nil {
      let controller = NSHostingController(rootView: UpdateView(flow: flow))
      controller.sizingOptions = .preferredContentSize
      let window = NSWindow(contentViewController: controller)
      window.styleMask = [.titled, .closable, .fullSizeContentView]
      window.titlebarAppearsTransparent = true
      window.titleVisibility = .hidden
      window.title = "ClipNest Update"
      window.isMovableByWindowBackground = true
      window.isReleasedWhenClosed = false
      window.delegate = self
      window.center()
      self.window = window
    }
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }
  private func closeWindow() {
    guard let window else { return }
    window.delegate = nil
    window.close()
    self.window = nil
  }
  func windowWillClose(_ notification: Notification) {
    window = nil
    flow.windowClosed()
  }

  func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
    flow.reset()
    flow.permissionReply = reply
    flow.phase = .permission
    present()
  }
  func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
    flow.reset()
    flow.cancellation = cancellation
    flow.phase = .checking
    present()
  }
  func showUpdateFound(
    with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
    reply: @escaping (SPUUserUpdateChoice) -> Void
  ) {
    flow.reset()
    flow.version = appcastItem.displayVersionString
    flow.date = appcastItem.date
    flow.size = appcastItem.contentLength
    flow.stage = state.stage
    flow.informationOnly = appcastItem.isInformationOnlyUpdate
    flow.critical = appcastItem.isCriticalUpdate
    flow.notesUnavailable = false
    if let description = appcastItem.itemDescription {
      flow.notes =
        appcastItem.itemDescriptionFormat == "html"
        ? ReleaseNotes.blocks(html: Data(description.utf8))
        : ReleaseNotes.blocks(markdown: description)
    } else {
      flow.notes = []
    }
    flow.choiceReply = reply
    flow.phase = .available
    present()
  }
  func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
    let isHTML = downloadData.mimeType?.contains("html") ?? true
    flow.notes =
      isHTML
      ? ReleaseNotes.blocks(html: downloadData.data)
      : ReleaseNotes.blocks(markdown: String(decoding: downloadData.data, as: UTF8.self))
  }
  func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
    flow.notesUnavailable = true
  }
  func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
    flow.reset()
    flow.acknowledgement = acknowledgement
    flow.phase = .upToDate
    present()
  }
  func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
    flow.reset()
    flow.acknowledgement = acknowledgement
    flow.phase = .failed(error.localizedDescription)
    present()
  }
  func showDownloadInitiated(cancellation: @escaping () -> Void) {
    flow.cancellation = cancellation
    flow.received = 0
    flow.expected = 0
    flow.phase = .downloading
    present()
  }
  func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
    flow.expected = expectedContentLength
  }
  func showDownloadDidReceiveData(ofLength length: UInt64) {
    flow.received += length
  }
  func showDownloadDidStartExtractingUpdate() {
    flow.cancellation = nil
    flow.extraction = 0
    flow.phase = .extracting
  }
  func showExtractionReceivedProgress(_ progress: Double) {
    flow.extraction = progress
  }
  func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
    flow.choiceReply = reply
    flow.phase = .ready
    present()
  }
  func showInstallingUpdate(
    withApplicationTerminated applicationTerminated: Bool,
    retryTerminatingApplication: @escaping () -> Void
  ) {
    flow.applicationTerminated = applicationTerminated
    flow.retryTermination = retryTerminatingApplication
    flow.phase = .installing
  }
  func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
    flow.reset()
    closeWindow()
    acknowledgement()
  }
  func showUpdateInFocus() { if window != nil { present() } }
  func dismissUpdateInstallation() {
    flow.reset()
    closeWindow()
  }
}

struct UpdateView: View {
  @ObservedObject var flow: UpdateFlow
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      header
      content
      buttons
    }
    .padding(.horizontal, 26).padding(.top, 34).padding(.bottom, 22)
    .frame(width: 460, alignment: .leading)
    .fixedSize(horizontal: false, vertical: true)
  }

  private var header: some View {
    HStack(spacing: 14) {
      Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
        .resizable().frame(width: 60, height: 60)
        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.system(size: 17, weight: .semibold))
        Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
  }

  private var title: String {
    switch flow.phase {
    case .idle, .checking: return "Checking for updates…"
    case .permission: return "Keep ClipNest up to date?"
    case .available:
      return flow.informationOnly ? "ClipNest \(flow.version) is available" : "A new version of ClipNest is ready"
    case .upToDate: return "You’re up to date"
    case .downloading: return "Downloading ClipNest \(flow.version)…"
    case .extracting: return "Preparing the update…"
    case .ready: return "Ready to install"
    case .installing: return "Installing ClipNest \(flow.version)…"
    case .failed: return "Update failed"
    }
  }
  private var subtitle: String {
    switch flow.phase {
    case .permission:
      return "ClipNest can check GitHub for new versions in the background. Checks never include clipboard contents."
    case .available:
      var parts = ["Version \(flow.version) · you have \(flow.currentVersion)"]
      if let date = flow.date { parts.append(date.formatted(date: .abbreviated, time: .omitted)) }
      if flow.size > 0 {
        parts.append(ByteCountFormatter.string(fromByteCount: Int64(flow.size), countStyle: .file))
      }
      return parts.joined(separator: " · ")
    case .upToDate: return "ClipNest \(flow.currentVersion) is the newest version available."
    case .downloading, .extracting:
      return "Downloads are verified with ClipNest’s signing key before installation."
    case .ready: return "ClipNest will quit, install \(flow.version) and open again."
    case .installing:
      return flow.applicationTerminated
        ? "This only takes a moment." : "Waiting for ClipNest to quit…"
    case .failed(let message): return message
    case .idle, .checking: return "Contacting GitHub."
    }
  }

  @ViewBuilder private var content: some View {
    switch flow.phase {
    case .available where !flow.notes.isEmpty || flow.notesUnavailable:
      notesCard
    case .checking, .idle:
      ProgressView().progressViewStyle(.linear)
    case .downloading:
      VStack(alignment: .leading, spacing: 6) {
        if let fraction = flow.downloadFraction {
          ProgressView(value: fraction)
        } else {
          ProgressView().progressViewStyle(.linear)
        }
        Text(downloadDetail).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
      }
    case .extracting:
      ProgressView(value: flow.extraction)
    case .installing:
      ProgressView().progressViewStyle(.linear)
    default:
      EmptyView()
    }
  }

  private var downloadDetail: String {
    let received = ByteCountFormatter.string(fromByteCount: Int64(flow.received), countStyle: .file)
    guard flow.expected > 0 else { return received }
    let total = ByteCountFormatter.string(fromByteCount: Int64(flow.expected), countStyle: .file)
    return "\(received) of \(total)"
  }

  private var notesCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("WHAT’S NEW").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
        .tracking(0.6)
      ScrollView {
        VStack(alignment: .leading, spacing: 8) {
          if flow.notes.isEmpty {
            Text("Release notes could not be loaded.").foregroundStyle(.secondary)
          }
          ForEach(flow.notes) { block in
            switch block.kind {
            case .heading:
              Text(block.text).font(.system(size: 13, weight: .semibold))
                .padding(.top, block.id == 0 ? 0 : 4)
            case .paragraph:
              Text(block.text).font(.system(size: 12.5)).foregroundStyle(.primary.opacity(0.85))
            case .bullet:
              HStack(alignment: .firstTextBaseline, spacing: 7) {
                Circle().fill(Color.accentColor).frame(width: 5, height: 5).offset(y: -2)
                Text(block.text).font(.system(size: 12.5)).foregroundStyle(.primary.opacity(0.85))
              }
            }
          }
        }
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
      }
      .frame(maxHeight: 220)
      .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
  }

  @ViewBuilder private var buttons: some View {
    HStack(spacing: 10) {
      switch flow.phase {
      case .permission:
        Spacer()
        Button("Don’t Check") { flow.answerPermission(automaticChecks: false) }
        Button("Check Automatically") { flow.answerPermission(automaticChecks: true) }
          .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
      case .available:
        if !flow.critical && flow.stage == .notDownloaded {
          Button("Skip This Version") { flow.choose(.skip) }.buttonStyle(.link)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button(flow.informationOnly ? "Close" : "Later") { flow.choose(.dismiss) }
          .keyboardShortcut(.cancelAction)
        if !flow.informationOnly {
          Button(flow.stage == .notDownloaded ? "Update Now" : "Install and Relaunch") {
            flow.choose(.install)
          }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
        }
      case .checking, .idle, .downloading:
        Spacer()
        Button("Cancel") { flow.cancel() }.keyboardShortcut(.cancelAction)
      case .ready:
        Spacer()
        Button("Later") { flow.choose(.dismiss) }.keyboardShortcut(.cancelAction)
        Button("Install and Relaunch") { flow.choose(.install) }.keyboardShortcut(.defaultAction)
          .buttonStyle(.borderedProminent)
      case .installing:
        Spacer()
        if !flow.applicationTerminated {
          Button("Try Again") { flow.retryTerminating() }
        }
      case .upToDate, .failed:
        Spacer()
        Button("OK") { flow.acknowledge() }.keyboardShortcut(.defaultAction)
          .buttonStyle(.borderedProminent)
      case .extracting:
        Spacer()
      }
    }
    .controlSize(.large)
  }
}
