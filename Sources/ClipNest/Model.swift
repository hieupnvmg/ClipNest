import AppKit
import Darwin
import ImageIO
import CryptoKit
import SwiftUI

struct ImageReference: Codable, Equatable, Hashable {
  let digest: String
  let byteCount: Int
  init(data: Data) {
    digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    byteCount = data.count
  }
  init(digest: String, byteCount: Int) { self.digest = digest; self.byteCount = byteCount }
}
struct HistoryWrite {
  let bytes: Int64
  let images: [UUID: ImageReference]
}

struct Clip: Codable, Identifiable, Equatable {
  var id = UUID()
  var date = Date()
  var source: String
  var kind: String
  var text: String
  var data: Data?
  var board: String?
  var title: String = ""
  var bundleID: String?
  var html: Data?
  var imageReference: ImageReference?
  var hasDeferredImage: Bool { kind == "Image" && data == nil && imageReference != nil }
  func imageMetadata() -> Clip {
    guard kind == "Image", let data else { return self }
    var compact = self
    compact.imageReference = ImageReference(data: data)
    compact.data = nil
    return compact
  }
  var displayTitle: String {
    if !title.isEmpty { return title }
    if kind == "Link", let url = URL(string: text) {
      return url.host?.replacingOccurrences(of: "www.", with: "") ?? text
    }
    if kind == "Files" {
      return text.split(separator: "\n").compactMap { URL(string: String($0))?.lastPathComponent }
        .joined(separator: ", ")
    }
    return text
  }
  static func textKind(_ text: String) -> String {
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if clean.hasPrefix("#"), Color(hex: clean) != nil { return "Color" }
    if let url = URL(string: clean), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
      url.host != nil, !clean.contains(where: \.isWhitespace)
    {
      return "Link"
    }
    return "Text"
  }
  var isIPAddress: Bool {
    guard kind == "Text" else { return false }
    let parts = text.trimmingCharacters(in: .whitespacesAndNewlines)
      .split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
    guard let address = parts.first, address.utf8.count < Int(INET6_ADDRSTRLEN),
      !address.utf8.contains(0)
    else { return false }

    var prefixLength = 0
    if parts.count == 2 {
      let suffix = parts[1]
      guard suffix.utf8.allSatisfy({ (48...57).contains($0) }),
        let length = Int(suffix), length <= 128
      else { return false }
      prefixLength = length
    }

    var ipv4 = in_addr()
    var ipv6 = in6_addr()
    return String(address).withCString {
      (prefixLength <= 32 && inet_pton(AF_INET, $0, &ipv4) == 1)
        || inet_pton(AF_INET6, $0, &ipv6) == 1
    }
  }
  var symbol: String {
    switch kind {
    case "Image": return "photo"
    case "Files": return "folder.fill"
    case "Link": return "safari"
    case "Color": return "paintpalette.fill"
    default: return "doc.text"
    }
  }
  var color: Color {
    if kind == "Color" { return Color(hex: text) ?? .pink }
    switch kind {
    case "Image": return Color(hex: "#F45263")!
    case "Files": return Color(hex: "#FEA128")!
    case "Link": return Color(hex: "#0797FA")!
    default: return Color(hex: "#EAB711")!
    }
  }
}
extension Color {
  init?(hex: String) {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let n = UInt(s, radix: 16) else { return nil }
    self.init(
      red: Double((n >> 16) & 255) / 255, green: Double((n >> 8) & 255) / 255,
      blue: Double(n & 255) / 255)
  }
}
final class Store: ObservableObject {
  @MainActor lazy var passwordGenerator = PasswordGeneratorModel()
  @MainActor lazy var pikabin = PikabinSharing(
    clipboardCount: { [weak self] in self?.pasteboard.changeCount ?? -1 },
    copyLink: { [weak self] url in
      self?.writeClipboard(Clip(source: "PikaBin", kind: "Link", text: url.absoluteString)) ?? false
    })
  @Published var interfaceStyle: InterfaceStyle {
    didSet { defaults.set(interfaceStyle.rawValue, forKey: "interfaceStyle") }
  }
  /// Text recognized in image clips (on-device Vision). Searchable and checked for secrets.
  @Published private(set) var imageText: [UUID: RecognizedText] = [:] {
    didSet { invalidateSearch() }
  }
  @Published var imageTextRecognition: Bool {
    didSet {
      defaults.set(imageTextRecognition, forKey: "imageTextRecognition")
      if imageTextRecognition { recognizeImageText() }
    }
  }
  // MARK: iCloud Drive sync
  let syncEngine: SyncEngine
  private let syncQueue = DispatchQueue(label: "local.clipnest.sync", qos: .utility)
  private var syncTimer: Timer?
  private var pendingSync: DispatchWorkItem?
  private var syncRunning = false
  private var syncAgain = false
  @Published private(set) var syncStatus = SyncStatus()
  @Published var syncIncludeSensitive: Bool {
    didSet {
      defaults.set(syncIncludeSensitive, forKey: "syncIncludeSensitive")
      scheduleSync()
    }
  }
  private var recognizingImages: Set<UUID> = [] {
    didSet { if imageTextPending != recognizingImages.count { imageTextPending = recognizingImages.count } }
  }
  /// Images waiting for or undergoing recognition.
  @Published private(set) var imageTextPending = 0
  /// True once recognition has succeeded on this macOS build and model revision.
  @Published private(set) var imageTextModelReady = false
  @Published private(set) var imageTextModelChecking = false
  @Published private(set) var imageTextModelError: String?
  @Published var glassVariant: GlassVariant {
    didSet { defaults.set(glassVariant.rawValue, forKey: "glassVariant") }
  }
  @Published var backgroundOpacity: Double {
    didSet {
      let value = AppearancePreferences.normalize(backgroundOpacity)
      if value != backgroundOpacity { backgroundOpacity = value }
      defaults.set(value, forKey: "backgroundOpacity")
    }
  }
  @Published var sensitiveProtectionEnabled: Bool {
    didSet {
      defaults.set(sensitiveProtectionEnabled, forKey: "sensitiveProtectionEnabled")
      hideRevealedSensitiveItems()
      prewarmSensitiveAssessments()
    }
  }
  @Published private(set) var revealedSensitiveIDs: Set<UUID> = []
  private var revealTasks: [UUID: DispatchWorkItem] = [:]
  // Assessments are small (masked text only) and pruned with their clips. An evicting
  // cache made search re-run the detectors on the main thread for older rich-text items.
  private var protectedPresentations: [UUID: ProtectedPresentation] = [:]
  private var backgroundAssessments: Set<UUID> = []
  private var urgentAssessments: Set<UUID> = []
  private let assessmentQueue = DispatchQueue(label: "local.clipnest.sensitive", qos: .utility)
  /// Bumped when an item that was shown as pending finishes its background assessment.
  @Published private(set) var assessmentRevision = 0
  /// Larger items (rich-text HTML is often 100 KB–1 MB) are inspected off the main thread.
  static let synchronousAssessmentLimit = 16 * 1024
  @Published var accessibilityGranted = AXIsProcessTrusted()
  @Published var shortcut: KeyboardShortcut
  @Published var recordingShortcut = false
  @Published var shortcutError: String?
  @Published var newBoard = ""
  @Published var adding = false
  @Published var settings = false
  @Published var preferencesPane: PreferencesPane = .general
  @Published var editing: Clip?
  @Published var editedText = ""
  @Published var editedTitle = ""
  @Published var selected: UUID?
  @Published var clips: [Clip] = [] { didSet { invalidateSearch() } }
  @Published var boards: [String]
  @Published var query = "" { didSet { cachedFiltered = nil } }
  @Published var board: String? { didSet { invalidateSearch() } }
  @Published var kind = "All types" { didSet { invalidateSearch() } }
  @Published var paused = false
  @Published var excluded: String
  @Published var error: String?
  @Published var renamingBoard: String?
  @Published var showRenameBoard = false
  @Published var retention: Int
  @Published var searchVisible = false
  @Published var toast: String?
  @Published var clearConfirmation = false
  @Published var storageBytes: Int64 = 0
  let folder: URL
  let defaults: UserDefaults
  let pasteboard: NSPasteboard
  var count: Int
  var timer: Timer?
  private var database: HistoryDatabase?
  private var cachedFiltered: [Clip]?
  /// Matches for the last query. Typing more characters only narrows this set.
  private var searchBase: (query: String, ids: Set<UUID>)?
  private let writerQueue = DispatchQueue(label: "local.clipnest.history", qos: .utility)
  private var pendingSave: DispatchWorkItem?
  private var pendingSnapshot: [Clip]?
  private var clipboardActionRevision = 0
  private var saveRevision = 0
  private var archiveUnreadable = false
  private let asynchronousSaves: Bool
  var url: URL { folder.appendingPathComponent("history.sqlite3") }
  init(
    folder: URL? = nil, defaults: UserDefaults = .standard, pasteboard: NSPasteboard = .general,
    monitoring: Bool = true, asynchronousSaves: Bool? = nil, syncFolder: URL? = nil
  ) {
    self.folder =
      folder
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("ClipNest")
    self.asynchronousSaves = asynchronousSaves ?? monitoring
    sensitiveProtectionEnabled =
      defaults.object(forKey: "sensitiveProtectionEnabled") as? Bool ?? true
    interfaceStyle = InterfaceStyle.load(from: defaults)
    backgroundOpacity = AppearancePreferences.load(from: defaults)
    glassVariant = GlassVariant.load(from: defaults)
    imageTextRecognition = defaults.object(forKey: "imageTextRecognition") as? Bool ?? true
    imageTextModelReady =
      defaults.string(forKey: "imageTextModelIdentity") == ImageTextRecognizer.modelIdentity
    shortcut = KeyboardShortcut.load(from: defaults)
    self.defaults = defaults
    self.pasteboard = pasteboard
    count = pasteboard.changeCount
    let savedBoards = defaults.stringArray(forKey: "boards") ?? ["Important Notes", "Work"]
    boards = Self.automaticBoards + savedBoards.filter { !Self.automaticBoards.contains($0) }
    excluded =
      defaults.string(forKey: "excluded")
      ?? "com.1password.1password,com.agilebits.onepassword7,com.apple.keychainaccess"
    retention = defaults.object(forKey: "retention") as? Int ?? 1000
    syncIncludeSensitive = defaults.bool(forKey: "syncIncludeSensitive")
    syncEngine = SyncEngine(
      cloud: syncFolder ?? SyncEngine.iCloudDriveFolder.appendingPathComponent("ClipNest Sync"),
      local: self.folder)
    do {
      let database = try HistoryDatabase(url: url)
      self.database = database
      clips = try database.loadAndMigrate()
      imageText = (try? database.imageTexts()) ?? [:]
    } catch {
      archiveUnreadable = true
      self.error =
        "Could not open clipboard history. Existing files have been kept. \(error.localizedDescription)"
    }
    selected = clips.first?.id
    refreshStorageUsage()
    refreshSyncStatus()
    if monitoring {
      timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
        self?.capture()
        if self?.settings == true { self?.refreshAccessibilityStatus() }
      }
      timer?.tolerance = 0.1
      prewarmSensitiveAssessments()
      // Pick up changes from other Macs regularly; local changes sync shortly after saving.
      syncTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
        self?.syncNow()
      }
      syncTimer?.tolerance = 10
      DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.syncNow() }
      recognizeImageText()
    }
  }
  deinit { timer?.invalidate() }
  private func invalidateSearch() {
    cachedFiltered = nil
    searchBase = nil
  }
  var filtered: [Clip] {
    if let result = cachedFiltered { return result }
    let candidates = clips.lazy.filter { [self] item in
      let matchesBoard: Bool
      switch board {
      case Self.linksBoard: matchesBoard = item.kind == "Link"
      case Self.ipBoard: matchesBoard = item.isIPAddress
      default:
        matchesBoard = (board == nil || item.board == board) && (kind == "All types" || item.kind == kind)
      }
      return matchesBoard
    }
    guard !query.isEmpty else {
      let result = Array(candidates)
      cachedFiltered = result
      return result
    }

    var exactPrefixes: [Clip] = []
    var foldedPrefixes: [Clip] = []
    var contentMatches: [Clip] = []
    var sourceMatches: [Clip] = []
    // A longer query can only match items the shorter one matched.
    let narrowed = searchBase.flatMap { query.hasPrefix($0.query) ? $0.ids : nil }
    for item in candidates {
      if let narrowed, !narrowed.contains(item.id) { continue }
      if item.text.hasPrefix(query) || item.title.hasPrefix(query) {
        exactPrefixes.append(item)
        continue
      }
      let textMatch = item.text.range(of: query, options: .caseInsensitive, locale: .current)
      let titleMatch = item.title.range(of: query, options: .caseInsensitive, locale: .current)
      if textMatch?.lowerBound == item.text.startIndex
        || titleMatch?.lowerBound == item.title.startIndex {
        foldedPrefixes.append(item)
      } else if textMatch != nil || titleMatch != nil
        || (item.kind == "Image"
          && recognizedText(for: item).range(of: query, options: .caseInsensitive, locale: .current) != nil)
      {
        contentMatches.append(item)
      } else if item.source.localizedCaseInsensitiveContains(query) {
        sourceMatches.append(item)
      }
    }
    let result = exactPrefixes + foldedPrefixes + contentMatches + sourceMatches
    cachedFiltered = result
    searchBase = (query, Set(result.lazy.map(\.id)))
    return result
  }
  var selectedClip: Clip? {
    let items = filtered
    return items.first { $0.id == selected } ?? items.first
  }
  var storageDescription: String {
    storageBytes == 0
      ? "0 KB" : ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file)
  }
  func refreshStorageUsage() {
    let bytes = writerQueue.sync { database?.storageBytes ?? 0 }
    if storageBytes != bytes { storageBytes = bytes }
  }
  private static func persist(_ snapshot: [Clip], in database: HistoryDatabase?) -> Result<
    HistoryWrite, Error
  > {
    Result {
      guard let database else { throw DatabaseError(message: "Clipboard database is unavailable.") }
      try database.save(snapshot)
      return HistoryWrite(bytes: database.storageBytes, images: database.imageReferences)
    }
  }
  private func didWrite(_ result: Result<HistoryWrite, Error>, revision: Int) {
    guard revision == saveRevision else { return }
    switch result {
    case .success(let saved):
      if storageBytes != saved.bytes { storageBytes = saved.bytes }
      if error != nil { error = nil }
      pendingSnapshot = nil
      pendingSave = nil
      var compact = clips
      var changed = false
      for i in compact.indices where compact[i].kind == "Image" && compact[i].data != nil {
        if let reference = saved.images[compact[i].id] {
          compact[i].imageReference = reference
          compact[i].data = nil
          protectedPresentations.removeValue(forKey: compact[i].id)
          changed = true
        }
      }
      if changed { clips = compact }
    case .failure(let failure):
      error = "History could not be saved: \(failure.localizedDescription)"
    }
  }
  func clearHistory() {
    // Serialize clearing after any write already in progress. Cancel queued saves
    // so an older snapshot can never restore items after Clear.
    saveRevision += 1
    pendingSave?.cancel()
    pendingSave = nil
    let result: Result<Int64, Error> = writerQueue.sync {
      Result {
        guard let database else {
          throw DatabaseError(message: "Clipboard database is unavailable.")
        }
        try database.clear()
        return database.storageBytes
      }
    }
    switch result {
    case .success(let bytes):
      pendingSnapshot = nil
      hideRevealedSensitiveItems()
      protectedPresentations.removeAll()
      ImageTextRecognizer.shared.cancelAll()
      recognizingImages.removeAll()
      imageText = [:]
      clips = []
      selected = nil
      query = ""
      error = nil
      archiveUnreadable = false
      storageBytes = bytes
      PreviewCache.shared.images.removeAllObjects()
      toast = "Clipboard history cleared"
    case .failure(let failure):
      error = "History could not be cleared: \(failure.localizedDescription)"
    }
  }
  func save() {
    guard !archiveUnreadable else { return }
    defaults.set(boards, forKey: "boards")
    defaults.set(excluded, forKey: "excluded")
    defaults.set(retention, forKey: "retention")
    saveRevision += 1
    let revision = saveRevision
    let snapshot = clips
    let database = self.database
    pendingSnapshot = snapshot
    pendingSave?.cancel()
    guard asynchronousSaves else {
      didWrite(
        writerQueue.sync { Self.persist(snapshot, in: database) }, revision: revision)
      return
    }
    // Coalesce quick changes; transactionally write only changed records off the UI.
    let work = DispatchWorkItem { [weak self] in
      let result = Self.persist(snapshot, in: database)
      DispatchQueue.main.async { [weak self] in self?.didWrite(result, revision: revision) }
    }
    pendingSave = work
    writerQueue.asyncAfter(deadline: .now() + 0.15, execute: work)
    scheduleSync()
  }
  func flushPendingSave() {
    guard !archiveUnreadable else { return }
    pendingSave?.cancel()
    pendingSave = nil
    let snapshot = pendingSnapshot
    let result: Result<HistoryWrite, Error> = writerQueue.sync {
      Result {
        guard let database else {
          throw DatabaseError(message: "Clipboard database is unavailable.")
        }
        if let snapshot { try database.save(snapshot) }
        try database.checkpoint()
        return HistoryWrite(bytes: database.storageBytes, images: database.imageReferences)
      }
    }
    didWrite(result, revision: saveRevision)
  }
  func refreshAccessibilityStatus() {
    let granted = AXIsProcessTrusted()
    if accessibilityGranted != granted { accessibilityGranted = granted }
  }
  func requestAccessibilityPermission(openSettings: Bool = false, automatically: Bool = false) {
    if automatically {
      let trusted = AXIsProcessTrusted()
      guard AccessibilityOnboarding.consumeAutomaticRequest(trusted: trusted, defaults: defaults) else {
        refreshAccessibilityStatus()
        return
      }
    }
    guard !AXIsProcessTrusted() else {
      refreshAccessibilityStatus()
      return
    }
    let options =
      [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    accessibilityGranted = AXIsProcessTrustedWithOptions(options)
    if openSettings,
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    {
      NSWorkspace.shared.open(url)
    }
  }
  func protection(for item: Clip) -> ProtectedPresentation {
    let recognized = recognizedText(for: item)
    if let cached = protectedPresentations[item.id], cached.original == item,
      cached.recognizedText == recognized
    {
      return cached
    }
    guard ProtectedPresentation.inspectedBytes(item) + recognized.utf8.count
      > Self.synchronousAssessmentLimit
    else {
      let result = ProtectedPresentation(item, recognizedText: recognized)
      protectedPresentations[item.id] = result
      return result
    }
    // Never block rendering on the detectors; keep the item masked until it is checked.
    scheduleAssessment(item, urgent: true)
    return ProtectedPresentation(pending: item)
  }
  private func scheduleAssessment(_ item: Clip, urgent: Bool) {
    let recognized = recognizedText(for: item)
    if urgent {
      guard urgentAssessments.insert(item.id).inserted else { return }
    } else {
      guard !urgentAssessments.contains(item.id),
        backgroundAssessments.insert(item.id).inserted else { return }
    }
    let work = { [weak self] in
      let result = ProtectedPresentation(item, recognizedText: recognized)
      DispatchQueue.main.async { self?.finishAssessment(result, urgent: urgent) }
    }
    if urgent {
      DispatchQueue.global(qos: .userInitiated).async(execute: work)
    } else {
      assessmentQueue.async(execute: work)
    }
  }
  private func finishAssessment(_ result: ProtectedPresentation, urgent: Bool) {
    let id = result.original.id
    if urgent { urgentAssessments.remove(id) } else { backgroundAssessments.remove(id) }
    // Removed items have no card waiting; don't trigger renders that would ask again.
    guard let current = clips.first(where: { $0.id == id }) else { return }
    // Keep only results for the current version. An edit made while this ran is
    // re-requested by the card on the next render, so still re-render below.
    if current == result.original, result.recognizedText == recognizedText(for: current),
      protectedPresentations[id]?.original != current
        || protectedPresentations[id]?.recognizedText != result.recognizedText
    {
      protectedPresentations[id] = result
    }
    if urgent { assessmentRevision &+= 1 }
  }
  /// Inspects large items in the background so search results render without waiting.
  func prewarmSensitiveAssessments() {
    guard sensitiveProtectionEnabled else { return }
    for item in clips where ProtectedPresentation.inspectedBytes(item) > Self.synchronousAssessmentLimit {
      if protectedPresentations[item.id]?.original == item { continue }
      scheduleAssessment(item, urgent: false)
    }
  }
  func isMasked(_ item: Clip) -> Bool {
    sensitiveProtectionEnabled && !revealedSensitiveIDs.contains(item.id)
      && protection(for: item).isSensitive
  }
  func displayClip(_ item: Clip) -> Clip { isMasked(item) ? protection(for: item).clip : item }
  func revealSensitiveItem(_ item: Clip, duration: TimeInterval = 15) {
    guard sensitiveProtectionEnabled, protection(for: item).isSensitive else { return }
    revealTasks[item.id]?.cancel()
    revealedSensitiveIDs.insert(item.id)
    let id = item.id
    let task = DispatchWorkItem { [weak self] in self?.hideRevealedSensitiveItem(id) }
    revealTasks[id] = task
    DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: task)
  }
  func hideRevealedSensitiveItem(_ id: UUID) {
    revealTasks.removeValue(forKey: id)?.cancel()
    guard revealedSensitiveIDs.contains(id) else { return }
    if editing?.id == id {
      editing = nil
      editedText = ""
      editedTitle = ""
    }
    revealedSensitiveIDs.remove(id)
  }
  func hideRevealedSensitiveItems() {
    let ids = revealedSensitiveIDs
    for id in ids { hideRevealedSensitiveItem(id) }
  }
  private func forgetCachedItem(_ id: UUID) {
    hideRevealedSensitiveItem(id)
    protectedPresentations.removeValue(forKey: id)
    PreviewCache.shared.images.removeObject(forKey: id.uuidString as NSString)
    if imageText[id] != nil { imageText.removeValue(forKey: id) }
  }
  /// Recognized text for an image clip, only while it belongs to the same image bytes.
  func recognizedText(for item: Clip) -> String {
    guard item.kind == "Image", let digest = item.imageReference?.digest,
      let recognized = imageText[item.id], recognized.digest == digest
    else { return "" }
    return recognized.text
  }
  /// Queues text recognition for every image that has none yet (oldest work first is
  /// fine: it runs one image at a time at utility priority).
  func recognizeImageText() {
    guard imageTextRecognition, !archiveUnreadable else { return }
    for item in clips where item.kind == "Image" { scheduleRecognition(item) }
  }
  private func scheduleRecognition(_ item: Clip) {
    guard imageTextRecognition, let digest = item.imageReference?.digest,
      imageText[item.id]?.digest != digest, recognizingImages.insert(item.id).inserted
    else { return }
    let id = item.id
    ImageTextRecognizer.shared.recognize(read: imageReader(item)) { [weak self] text in
      guard let self else { return }
      self.recognizingImages.remove(id)
      if text != nil { self.markImageTextModelReady() }
      // Drop results for images that were removed, replaced or cleared meanwhile.
      guard let text, self.imageTextRecognition,
        self.clips.contains(where: { $0.id == id && $0.imageReference?.digest == digest })
      else { return }
      let recognized = RecognizedText(digest: digest, text: text)
      self.imageText[id] = recognized
      let database = self.database
      self.writerQueue.async { try? database?.saveImageText(recognized, for: id) }
    }
  }
  /// Pinned clips that belong in sync. Automatic boards (Useful Links, IP Addresses) fill
  /// themselves from every copy, so only boards the user made are synced.
  func isSyncable(_ item: Clip) -> Bool {
    guard let board = item.board, !Self.automaticBoards.contains(board) else { return false }
    // Unchecked large items report as sensitive until inspected, so they wait a pass.
    return syncIncludeSensitive || protection(for: item).isSensitive == false
  }
  func refreshSyncStatus() {
    syncStatus.configured = syncEngine.isConfigured
    syncStatus.vaultExists = syncEngine.vaultExists
    syncStatus.cloudAvailable = syncEngine.cloudAvailable
  }
  private func scheduleSync() {
    guard syncEngine.isConfigured else { return }
    pendingSync?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.syncNow() }
    pendingSync = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
  }
  /// One sync pass: imports other Macs' changes, then uploads this Mac's.
  func syncNow(completion: (() -> Void)? = nil) {
    guard syncEngine.isConfigured, !archiveUnreadable else { refreshSyncStatus(); completion?(); return }
    guard !syncRunning else { syncAgain = true; completion?(); return }
    syncRunning = true
    syncStatus.busy = true
    let candidates = clips.filter(isSyncable).map { item -> SyncCandidate in
      SyncCandidate(
        id: item.id,
        clip: SyncClip(
          date: item.date, source: item.source, kind: item.kind, text: item.text,
          title: item.title, board: item.board ?? "", bundleID: item.bundleID,
          rtf: item.kind == "Image" || item.kind == "Files" ? nil : item.data, html: item.html),
        imageDigest: item.imageReference?.digest,
        loadImage: item.kind == "Image" ? imageReader(item) : nil)
    }
    let boards = self.boards.filter { !Self.automaticBoards.contains($0) }
    let engine = syncEngine
    syncQueue.async { [weak self] in
      let result = Result { try engine.sync(local: candidates, boards: boards) }
      DispatchQueue.main.async {
        guard let self else { return }
        self.syncRunning = false
        self.syncStatus.busy = false
        switch result {
        case .success(let outcome):
          self.applySync(outcome)
          self.syncStatus.lastSync = Date()
          self.syncStatus.synced = outcome.syncedCount
          self.syncStatus.error = nil
        case .failure(let failure):
          self.syncStatus.error = failure.localizedDescription
        }
        self.refreshSyncStatus()
        completion?()
        if self.syncAgain {
          self.syncAgain = false
          self.scheduleSync()
        }
      }
    }
  }
  private func applySync(_ outcome: SyncOutcome) {
    var changed = false
    for name in outcome.boards where !boards.contains(name) {
      boards.append(name)
      changed = true
    }
    guard !outcome.changes.isEmpty else {
      if changed { save() }
      return
    }
    var next = clips
    for change in outcome.changes {
      switch change {
      case .unpin(let id):
        if let index = next.firstIndex(where: { $0.id == id }) { next[index].board = nil }
      case .upsert(let id, let synced):
        var clip = Clip(
          id: id, date: synced.date, source: synced.source, kind: synced.kind, text: synced.text,
          data: synced.kind == "Image" ? synced.image : synced.rtf, board: synced.board,
          title: synced.title, bundleID: synced.bundleID, html: synced.html)
        if let image = synced.image { clip.imageReference = ImageReference(data: image) }
        if !boards.contains(synced.board) { boards.append(synced.board) }
        if let index = next.firstIndex(where: { $0.id == id }) {
          forgetCachedItem(id)
          next.remove(at: index)
        }
        next.insert(clip, at: next.firstIndex { $0.date < clip.date } ?? next.endIndex)
        if clip.kind == "Image" { scheduleRecognition(clip) }
      }
    }
    clips = next
    save()
  }
  func setUpSync(passphrase: String, join: Bool, completion: @escaping (Error?) -> Void) {
    let engine = syncEngine
    syncStatus.busy = true
    syncQueue.async {
      let result = Result { join ? try engine.join(passphrase: passphrase) : try engine.create(passphrase: passphrase) }
      DispatchQueue.main.async { [weak self] in
        self?.syncStatus.busy = false
        self?.refreshSyncStatus()
        switch result {
        case .success:
          completion(nil)
          self?.syncNow()
        case .failure(let error): completion(error)
        }
      }
    }
  }
  func leaveSync() {
    pendingSync?.cancel()
    let engine = syncEngine
    syncQueue.sync { engine.leave() }
    syncStatus = SyncStatus()
    refreshSyncStatus()
  }
  private func markImageTextModelReady() {
    imageTextModelError = nil
    guard !imageTextModelReady else { return }
    imageTextModelReady = true
    defaults.set(ImageTextRecognizer.modelIdentity, forKey: "imageTextModelIdentity")
  }
  /// Runs one small recognition so macOS prepares the model now instead of on the next
  /// screenshot, and confirms that recognition works on this Mac.
  func prepareImageTextModel() {
    guard !imageTextModelChecking else { return }
    imageTextModelChecking = true
    imageTextModelError = nil
    let sample = ImageTextRecognizer.sampleImage()
    ImageTextRecognizer.shared.recognize(read: { sample }) { [weak self] text in
      guard let self else { return }
      self.imageTextModelChecking = false
      if text?.localizedCaseInsensitiveContains("ClipNest") == true {
        self.markImageTextModelReady()
      } else {
        self.imageTextModelError = "Text recognition did not respond as expected. Try again later."
      }
    }
  }
  private func retaining(_ snapshot: [Clip]) -> [Clip] {
    guard retention > 0 else { return snapshot }
    var unpinned = 0
    // Scan without allocating a new array if no item exceeds the limit.
    let exceedsLimit = snapshot.contains { item in
      if item.board == nil { unpinned += 1 }
      return unpinned > retention
    }
    guard exceedsLimit else { return snapshot }
    unpinned = 0
    return snapshot.filter { item in
      if item.board != nil { return true }
      unpinned += 1
      if unpinned <= retention { return true }
      forgetCachedItem(item.id)
      return false
    }
  }
  func trim() {
    let kept = retaining(clips)
    guard kept.count != clips.count else { return }
    clips = kept
    if let selected, !clips.contains(where: { $0.id == selected }) {
      self.selected = filtered.first?.id
    }
  }
  func capture(source: String? = nil, bundleID: String? = nil) {
    let p = pasteboard
    guard p.changeCount != count else { return }
    count = p.changeCount
    guard !paused, !archiveUnreadable else { return }
    let app = NSWorkspace.shared.frontmostApplication
    let bid = bundleID ?? app?.bundleIdentifier ?? ""
    guard
      !excluded.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        .contains(bid)
    else { return }
    let privateTypes = [
      "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
      "org.nspasteboard.AutoGeneratedType", "com.agilebits.onepassword",
    ]
    guard
      !privateTypes.contains(where: { p.types?.contains(NSPasteboard.PasteboardType($0)) == true })
    else { return }
    let source = source ?? app?.localizedName ?? "Unknown"
    var clip: Clip?
    if let urls = p.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
      as? [URL], !urls.isEmpty
    {
      clip = Clip(
        source: source, kind: "Files", text: urls.map(\.absoluteString).joined(separator: "\n"))
    } else if let image = imageContent(from: p) {
      clip = Clip(source: source, kind: "Image", text: image.dimensions, data: image.data)
    } else if let str = p.string(forType: .string), !str.isEmpty, str.utf8.count < 5_000_000 {
      let rtf = p.data(forType: .rtf).flatMap { $0.count <= 5_000_000 ? $0 : nil }
      let html = p.data(forType: .html).flatMap { $0.count <= 5_000_000 ? $0 : nil }
      clip = Clip(source: source, kind: Clip.textKind(str), text: str, data: rtf, html: html)
    }
    guard var item = clip else { return }
    item.bundleID = bid
    if item.kind == "Image", let data = item.data { item.imageReference = ImageReference(data: data) }
    var next = clips
    if let index = next.firstIndex(where: {
      guard $0.kind == item.kind && $0.text == item.text && $0.html == item.html else { return false }
      if item.kind == "Image" { return $0.imageReference == item.imageReference }
      return $0.data == item.data
    }) {
      let old = next.remove(at: index)
      item.id = old.id
      item.title = old.title
      item.board = old.board
    }
    if item.kind == "Link", item.board == nil {
      ensureLinksBoard()
      item.board = Self.linksBoard
    } else if item.board == nil, item.isIPAddress {
      item.board = Self.ipBoard
    }
    next.insert(item, at: 0)
    clips = retaining(next) // Publish one complete update, never intermediate lists.
    if selected == nil || !clips.contains(where: { $0.id == selected }) { selected = item.id }
    save()
    if sensitiveProtectionEnabled,
      ProtectedPresentation.inspectedBytes(item) > Self.synchronousAssessmentLimit {
      scheduleAssessment(item, urgent: false)
    }
    if item.kind == "Image" { scheduleRecognition(item) }
  }
  private func imageContent(from pasteboard: NSPasteboard) -> (data: Data, dimensions: String)? {
    let png: Data
    if let original = pasteboard.data(forType: .png) {
      // Most screenshots are already PNG: keep their bytes without a TIFF roundtrip.
      guard original.count <= 25_000_000 else { return nil }
      png = original
    } else {
      guard let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let encoded = bitmap.representation(using: .png, properties: [:]),
        encoded.count <= 25_000_000
      else { return nil }
      png = encoded
    }
    guard let source = CGImageSourceCreateWithData(png as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int
    else { return nil }
    return (png, "\(width) × \(height)")
  }
  @discardableResult func writeClipboard(_ item: Clip, plain: Bool = false) -> Bool {
    var originalImage: Data?
    if item.kind == "Image" {
      do { originalImage = try readImage(item) }
      catch { self.error = error.localizedDescription; return false }
    }
    let p = pasteboard
    p.clearContents()
    if item.kind == "Image", let data = originalImage {
      p.setData(data, forType: .png)
    } else if item.kind == "Files" {
      p.writeObjects(
        item.text.split(separator: "\n").compactMap { URL(string: String($0)) } as [NSURL])
    } else {
      p.setString(item.text, forType: .string)
      if !plain {
        if let data = item.data { p.setData(data, forType: .rtf) }
        if let html = item.html { p.setData(html, forType: .html) }
      }
    }
    count = p.changeCount
    return true
  }
  func copy(_ item: Clip, plain: Bool = false) {
    let deferred = item.hasDeferredImage
    prepareClipboardItem(item) { [weak self] ready in
      // A delayed image read must not paste into another app after this panel closes.
      if deferred, let app = NSApp.delegate as? AppDelegate, !app.panelPresentation.isVisible { return }
      guard self?.writeClipboard(ready, plain: plain) == true else { return }
      (NSApp.delegate as? AppDelegate)?.hideAndPaste()
    }
  }
  @discardableResult func copyGeneratedPassword(_ password: String) -> Bool {
    guard !password.isEmpty else { return false }
    var item = Clip(source: "ClipNest", kind: "Text", text: password,
      title: "Password: generated", bundleID: "local.clipnest.app")
    guard writeClipboard(item) else { return false }
    // The contextual title makes this entry use the existing full-secret mask.
    var next = clips
    if let index = next.firstIndex(where: { $0.kind == "Text" && $0.text == password }) {
      let previous = next.remove(at: index)
      item.id = previous.id
      item.board = previous.board
    }
    next.insert(item, at: 0)
    clips = retaining(next)
    if selected == nil || !clips.contains(where: { $0.id == selected }) { selected = item.id }
    save()
    return true
  }
  /// Copies the text recognized in an image as plain text.
  func copyRecognizedText(_ item: Clip) {
    let text = recognizedText(for: item)
    guard !text.isEmpty, !isMasked(item) else { return }
    if writeClipboard(Clip(source: "ClipNest", kind: Clip.textKind(text), text: text)) {
      toast = "Copied text from image"
    }
  }
  func copyOnly(_ item: Clip) {
    prepareClipboardItem(item) { [weak self] ready in
      guard self?.writeClipboard(ready) == true else { return }
      self?.toast = "Copied to clipboard"
    }
  }
  private func prepareClipboardItem(_ item: Clip, ready: @escaping (Clip) -> Void) {
    clipboardActionRevision += 1
    let revision = clipboardActionRevision
    let clipboardCount = pasteboard.changeCount
    guard item.hasDeferredImage else { ready(item); return }
    requestImage(item) { [weak self] result in
      guard let self, self.clipboardActionRevision == revision,
        self.pasteboard.changeCount == clipboardCount,
        self.clips.contains(where: { $0.id == item.id && $0.imageReference == item.imageReference }) else { return }
      switch result {
      case .success(let bytes):
        var hydrated = item
        hydrated.data = bytes
        ready(hydrated)
      case .failure(let failure): self.error = failure.localizedDescription
      }
    }
  }
  private func imageReader(_ item: Clip) -> () throws -> Data {
    let database = self.database
    let queue = writerQueue
    return {
      if let data = item.data { return data }
      return try queue.sync {
        guard let database else { throw DatabaseError(message: "Clipboard database is unavailable.") }
        return try database.imageData(for: item.id, expected: item.imageReference)
      }
    }
  }
  func readImage(_ item: Clip) throws -> Data { try imageReader(item)() }
  func requestImage(_ item: Clip, completion: @escaping (Result<Data, Error>) -> Void) {
    let reader = imageReader(item)
    // The reader synchronizes with pending writes and Clear on the database queue.
    DispatchQueue.global(qos: .userInitiated).async {
      let result = Result { try reader() }
      DispatchQueue.main.async { completion(result) }
    }
  }
  @MainActor func previewImage(_ item: Clip) async -> NSImage? {
    let key = item.id.uuidString as NSString
    if let cached = PreviewCache.shared.images.object(forKey: key) { return cached }
    let reference = item.imageReference
    guard let thumbnail = await ImagePipeline.shared.thumbnail(read: imageReader(item)), !Task.isCancelled else { return nil }
    guard clips.contains(where: { $0.id == item.id && $0.imageReference == reference }) else { return nil }
    let image = NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
    PreviewCache.shared.images.setObject(image, forKey: key, cost: thumbnail.bytesPerRow * thumbnail.height)
    return image
  }
  func imageProvider(_ item: Clip) -> NSItemProvider {
    let provider = NSItemProvider()
    let reader = imageReader(item)
    provider.registerDataRepresentation(forTypeIdentifier: "public.png", visibility: .all) { completion in
      let progress = Progress(totalUnitCount: 1)
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          guard !progress.isCancelled else { throw CocoaError(.userCancelled) }
          let data = try reader()
          guard !progress.isCancelled else { throw CocoaError(.userCancelled) }
          completion(data, nil)
          progress.completedUnitCount = 1
        } catch { completion(nil, error) }
      }
      return progress
    }
    return provider
  }
  static let linksBoard = "Useful Links"
  static let ipBoard = "IP Addresses"
  static let automaticBoards = [linksBoard, ipBoard]

  private func ensureLinksBoard() {
    if !boards.contains(Self.linksBoard) {
      boards.append(Self.linksBoard)
    }
  }

  func saveLink(_ item: Clip) {
    guard let index = clips.firstIndex(where: { $0.id == item.id }),
      Clip.textKind(clips[index].text) == "Link"
    else { return }

    ensureLinksBoard()
    pin(clips[index], to: Self.linksBoard)
    toast = "Saved to Useful Links"
  }
  func pin(_ item: Clip, to board: String?) {
    if let i = clips.firstIndex(where: { $0.id == item.id }) {
      clips[i].board = board
      save()
    }
  }
  func remove(_ item: Clip) {
    forgetCachedItem(item.id)
    clips.removeAll { $0.id == item.id }
    selected = filtered.first?.id
    save()
  }
  func selectBoard(_ value: String?) {
    board = value
    selected = filtered.first?.id
  }
  func move(_ offset: Int) {
    let items = filtered
    guard !items.isEmpty else { return }
    let i = items.firstIndex { $0.id == selected } ?? 0
    selected = items[min(max(i + offset, 0), items.count - 1)].id
  }
  func createBoard() {
    let name = newBoard.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, !boards.contains(name) else { return }
    boards.append(name)
    selectBoard(name)
    newBoard = ""
    save()
  }
  func renameBoard() {
    let name = newBoard.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let old = renamingBoard, !name.isEmpty, name == old || !boards.contains(name),
      let i = boards.firstIndex(of: old)
    else { return }
    boards[i] = name
    for i in clips.indices where clips[i].board == old { clips[i].board = name }
    if board == old { board = name }
    save()
  }
  func deleteBoard(_ name: String) {
    boards.removeAll { $0 == name }
    for i in clips.indices where clips[i].board == name { clips[i].board = nil }
    if board == name { selectBoard(nil) }
    save()
  }
  func edit(_ item: Clip) {
    guard !isMasked(item) else {
      toast = "Hiện tạm nội dung trước khi chỉnh sửa."
      return
    }
    editing = item
    editedText = item.text
    editedTitle = item.title
  }
  func saveEdit() {
    guard let item = editing, let i = clips.firstIndex(where: { $0.id == item.id }) else { return }
    var updated = clips[i]
    updated.title = editedTitle
    if ["Text", "Link", "Color"].contains(item.kind) {
      updated.text = editedText
      updated.kind = Clip.textKind(editedText)
      updated.data = nil
      updated.html = nil
    }
    clips[i] = updated
    save()
    editing = nil
    editedText = ""
    editedTitle = ""
  }
}
