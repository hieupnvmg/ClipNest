import AppKit
import ImageIO
import SwiftUI

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
    Int64, Error
  > {
    Result {
      guard let database else { throw DatabaseError(message: "Clipboard database is unavailable.") }
      try database.save(snapshot)
      return database.storageBytes
    }
  }
  private func didWrite(_ result: Result<Int64, Error>, revision: Int) {
    guard revision == saveRevision else { return }
    switch result {
    case .success(let bytes):
      storageBytes = bytes
      error = nil
      pendingSnapshot = nil
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
    let result: Result<Int64, Error> = writerQueue.sync {
      Result {
        guard let database else {
          throw DatabaseError(message: "Clipboard database is unavailable.")
        }
        if let snapshot { try database.save(snapshot) }
        try database.checkpoint()
        return database.storageBytes
      }
    }
    didWrite(result, revision: saveRevision)
  }
  func trim() {
    guard retention > 0 else { return }
    var unpinned = 0
    clips = clips.filter {
      if $0.board != nil { return true }
      unpinned += 1
      return unpinned <= retention
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
    if let old = clips.first(where: {
      $0.kind == item.kind && $0.text == item.text && $0.data == item.data && $0.html == item.html
    }) {
      item.id = old.id
      item.title = old.title
      item.board = old.board
      clips.removeAll { $0.id == old.id }
    }
    clips.insert(item, at: 0)
    if selected == nil { selected = item.id }
    trim()
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
  func writeClipboard(_ item: Clip, plain: Bool = false) {
    let p = pasteboard
    p.clearContents()
    if item.kind == "Image", let data = item.data {
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
  }
  func copy(_ item: Clip, plain: Bool = false) {
    writeClipboard(item, plain: plain)
    (NSApp.delegate as? AppDelegate)?.hideAndPaste()
  }
  func pin(_ item: Clip, to board: String?) {
    if let i = clips.firstIndex(where: { $0.id == item.id }) {
      clips[i].board = board
      save()
    }
  }
  func remove(_ item: Clip) {
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
    editing = item
    editedText = item.text
    editedTitle = item.title
  }
  func saveEdit() {
    if let item = editing, let i = clips.firstIndex(where: { $0.id == item.id }) {
      clips[i].title = editedTitle
      if item.kind == "Text" || item.kind == "Link" || item.kind == "Color" {
        clips[i].text = editedText
        clips[i].kind = Clip.textKind(editedText)
        clips[i].data = nil
        clips[i].html = nil
      }
      save()
    }
    editing = nil
  }
}
