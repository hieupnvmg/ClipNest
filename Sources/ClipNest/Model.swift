import AppKit
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
    }
  }
  @Published private(set) var revealedSensitiveIDs: Set<UUID> = []
  private var revealTasks: [UUID: DispatchWorkItem] = [:]
  private let protectedPresentations: NSCache<NSUUID, ProtectedPresentation> = {
    let cache = NSCache<NSUUID, ProtectedPresentation>()
    cache.totalCostLimit = 16 * 1024 * 1024
    cache.countLimit = 128
    return cache
  }()
  @Published var accessibilityGranted = AXIsProcessTrusted()
  @Published var shortcut: KeyboardShortcut
  @Published var recordingShortcut = false
  @Published var shortcutError: String?
  @Published var newBoard = ""
  @Published var adding = false
  @Published var settings = false
  @Published var editing: Clip?
  @Published var editedText = ""
  @Published var editedTitle = ""
  @Published var selected: UUID?
  @Published var clips: [Clip] = [] { didSet { cachedFiltered = nil } }
  @Published var boards: [String]
  @Published var query = "" { didSet { cachedFiltered = nil } }
  @Published var board: String? { didSet { cachedFiltered = nil } }
  @Published var kind = "All types" { didSet { cachedFiltered = nil } }
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
    monitoring: Bool = true, asynchronousSaves: Bool? = nil
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
    shortcut = KeyboardShortcut.load(from: defaults)
    self.defaults = defaults
    self.pasteboard = pasteboard
    count = pasteboard.changeCount
    boards = defaults.stringArray(forKey: "boards") ?? ["Useful Links", "Important Notes", "Work"]
    excluded =
      defaults.string(forKey: "excluded")
      ?? "com.1password.1password,com.agilebits.onepassword7,com.apple.keychainaccess"
    retention = defaults.object(forKey: "retention") as? Int ?? 1000
    do {
      let database = try HistoryDatabase(url: url)
      self.database = database
      clips = try database.loadAndMigrate()
    } catch {
      archiveUnreadable = true
      self.error =
        "Could not open clipboard history. Existing files have been kept. \(error.localizedDescription)"
    }
    selected = clips.first?.id
    refreshStorageUsage()
    if monitoring {
      timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
        self?.capture()
        if self?.settings == true { self?.refreshAccessibilityStatus() }
      }
      timer?.tolerance = 0.1
    }
  }
  deinit { timer?.invalidate() }
  var filtered: [Clip] {
    if let result = cachedFiltered { return result }
    let result = clips.filter { item in
      (board == nil || item.board == board) && (kind == "All types" || item.kind == kind)
        && (query.isEmpty || item.text.localizedCaseInsensitiveContains(query)
          || item.source.localizedCaseInsensitiveContains(query)
          || item.title.localizedCaseInsensitiveContains(query))
    }
    cachedFiltered = result
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
          protectedPresentations.removeObject(forKey: compact[i].id as NSUUID)
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
      protectedPresentations.removeAllObjects()
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
    let key = item.id as NSUUID
    if let cached = protectedPresentations.object(forKey: key), cached.original == item {
      return cached
    }
    let result = ProtectedPresentation(item)
    protectedPresentations.setObject(result, forKey: key, cost: result.cost)
    return result
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
    protectedPresentations.removeObject(forKey: id as NSUUID)
    PreviewCache.shared.images.removeObject(forKey: id.uuidString as NSString)
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
    next.insert(item, at: 0)
    clips = retaining(next) // Publish one complete update, never intermediate lists.
    if selected == nil || !clips.contains(where: { $0.id == selected }) { selected = item.id }
    save()
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
