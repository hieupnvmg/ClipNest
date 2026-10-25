import AppKit
import ServiceManagement
import CSQLite
import Carbon
import SwiftUI

func runSelfTests() {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
    "ClipNest-tests-\(UUID().uuidString)")
  let suite = "ClipNest.tests.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suite)!
  let pb = NSPasteboard.withUniqueName()
  defer {
    try? FileManager.default.removeItem(at: folder)
    defaults.removePersistentDomain(forName: suite)
    pb.releaseGlobally()
  }
  let s = Store(folder: folder, defaults: defaults, pasteboard: pb, monitoring: false)
  var checks = 0
  func check(_ value: @autoclosure () -> Bool, _ name: String) {
    if !value() {
      fputs("FAIL: \(name)\n", stderr)
      exit(1)
    }
    checks += 1
    print("PASS: \(name)")
  }
  func capture(_ text: String, bid: String = "test.app") {
    pb.clearContents()
    pb.setString(text, forType: .string)
    s.capture(source: "Test App", bundleID: bid)
  }
  capture("Hello, clipboard\nXin chào 👋")
  check(s.clips.count == 1 && s.clips[0].kind == "Text", "Unicode multiline text capture")
  let first = s.clips[0]
  s.pin(first, to: s.boards[0])
  capture(first.text)
  check(
    s.clips.count == 1 && s.clips[0].board == s.boards[0] && s.clips[0].id == first.id,
    "Dedup preserves pin and identity")
  s.query = "XIN CHÀO"
  check(s.filtered.count == 1, "Case-insensitive Unicode search")
  s.query = ""
  capture("https://example.com/docs")
  check(s.clips[0].kind == "Link", "HTTP link detection")
  capture("https://example.com\nmore text")
  check(s.clips[0].kind == "Text", "Multiline text is not misclassified as URL")
  capture("#FF5733")
  check(s.clips[0].kind == "Color", "Hex color capture")
  let before = s.clips.count
  s.paused = true
  capture("paused")
  s.paused = false
  check(s.clips.count == before, "Pause excludes new copies")
  capture("secret", bid: "com.apple.keychainaccess")
  check(s.clips.count == before, "Excluded application skipped")
  pb.clearContents()
  pb.setString("secret marker", forType: .string)
  pb.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
  s.capture(source: "Test", bundleID: "test.app")
  check(s.clips.count == before, "Concealed clipboard marker skipped")
  let rtf = try! NSAttributedString(
    string: "Bold text", attributes: [.font: NSFont.boldSystemFont(ofSize: 14)]
  ).data(
    from: NSRange(location: 0, length: 9),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
  pb.clearContents()
  pb.setString("Bold text", forType: .string)
  pb.setData(rtf, forType: .rtf)
  s.capture(source: "Test", bundleID: "test.app")
  let rich = s.clips[0]
  s.writeClipboard(rich)
  check(pb.data(forType: .rtf) == rtf, "Rich text roundtrip")
  s.writeClipboard(rich, plain: true)
  check(
    pb.data(forType: .rtf) == nil && pb.string(forType: .string) == rich.text,
    "Plain text removes formatting")
  let image = NSImage(size: NSSize(width: 40, height: 20))
  image.lockFocus()
  NSColor.red.setFill()
  NSRect(x: 0, y: 0, width: 40, height: 20).fill()
  image.unlockFocus()
  pb.clearContents()
  pb.writeObjects([image])
  s.capture(source: "Test", bundleID: "test.app")
  check(s.clips[0].kind == "Image" && s.clips[0].data != nil, "Image capture")
  let originalPNG = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(
    using: .png, properties: [:])!
  pb.clearContents()
  pb.setData(originalPNG, forType: .png)
  s.capture(source: "Test", bundleID: "test.app")
  check(s.clips[0].data == originalPNG, "PNG capture preserves original bytes without re-encoding")
  let file = folder.appendingPathComponent("example.txt")
  try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  try! Data("file".utf8).write(to: file)
  pb.clearContents()
  pb.writeObjects([file as NSURL])
  s.capture(source: "Finder", bundleID: "com.apple.finder")
  check(s.clips[0].kind == "Files", "File URL capture")
  s.writeClipboard(s.clips[0])
  check((pb.readObjects(forClasses: [NSURL.self]) as? [URL])?.first == file, "File URL roundtrip")
  s.newBoard = "New Board"
  s.createBoard()
  s.pin(s.clips[0], to: "New Board")
  s.renamingBoard = "New Board"
  s.newBoard = "Renamed"
  s.renameBoard()
  check(
    s.clips[0].board == "Renamed" && s.boards.contains("Renamed"),
    "Rename updates pinboard references")
  s.deleteBoard("Renamed")
  check(s.clips[0].board == nil, "Removing board keeps its items")
  s.retention = 2
  s.trim()
  s.save()
  check(
    s.clips.filter { $0.board == nil }.count == 2 && s.clips.contains { $0.id == first.id },
    "Retention preserves pinned items")
  let restored = Store(folder: folder, defaults: defaults, pasteboard: pb, monitoring: false)
  check(
    restored.clips.count == s.clips.count && restored.clips.last?.id == s.clips.last?.id,
    "Archive survives relaunch")
  check(restored.error == nil, "No storage errors")
  let databaseSize = [s.url.path, s.url.path + "-wal", s.url.path + "-shm"].reduce(Int64(0)) {
    $0 + ((try! FileManager.default.attributesOfItem(atPath: $1)[.size]) as! NSNumber).int64Value
  }
  check(
    s.storageBytes == databaseSize && s.storageBytes > 0,
    "Storage includes SQLite database and WAL files")
  s.clearHistory()
  check(
    s.clips.isEmpty && s.selected == nil && s.boards.count > 0,
    "Clear removes pinned and unpinned items but keeps boards")
  let cleared = Store(folder: folder, defaults: defaults, pasteboard: pb, monitoring: false)
  check(
    cleared.clips.isEmpty && s.storageBytes > 0 && s.error == nil,
    "Clear persists empty SQLite history and refreshes usage")
  let brokenFolder = folder.appendingPathComponent("broken")
  try! FileManager.default.createDirectory(at: brokenFolder, withIntermediateDirectories: true)
  let brokenURL = brokenFolder.appendingPathComponent("history.sqlite3")
  try! Data("corrupt".utf8).write(to: brokenURL)
  let broken = Store(folder: brokenFolder, defaults: defaults, pasteboard: pb, monitoring: false)
  broken.save()
  check(
    broken.error != nil && (try? String(contentsOf: brokenURL)) == "corrupt",
    "Unreadable SQLite database is not overwritten")
  // Regression checks for cache invalidation, edits and background writes.
  let cacheFolder = folder.appendingPathComponent("cached")
  let cacheStore = Store(folder: cacheFolder, defaults: defaults, pasteboard: pb, monitoring: false)
  cacheStore.clips = [
    Clip(source: "Notes", kind: "Text", text: "alpha"),
    Clip(source: "Safari", kind: "Link", text: "https://example.org", board: "Work"),
  ]
  _ = cacheStore.filtered
  cacheStore.query = "alpha"
  check(cacheStore.filtered.count == 1, "Search cache invalidates on query changes")
  cacheStore.clips[0].text = "beta"
  check(cacheStore.filtered.isEmpty, "Search cache invalidates on item edits")
  cacheStore.query = ""
  cacheStore.kind = "Link"
  cacheStore.board = "Work"
  check(cacheStore.filtered.count == 1, "Search cache respects type and pinboard filters")
  cacheStore.edit(cacheStore.clips[1])
  cacheStore.editedText = "ordinary note"
  cacheStore.saveEdit()
  check(
    cacheStore.clips[1].kind == "Text" && cacheStore.filtered.isEmpty,
    "Edited links update content classification and filters")
  check(Clip.textKind("#FF#3333") == "Text", "Malformed hex colors are treated as text")
  let largeImage = NSImage(size: NSSize(width: 2000, height: 1000))
  largeImage.lockFocus()
  NSColor.blue.setFill()
  NSRect(x: 0, y: 0, width: 2000, height: 1000).fill()
  largeImage.unlockFocus()
  let largeClip = Clip(
    source: "Test", kind: "Image", text: "2000 × 1000", data: largeImage.tiffRepresentation)
  let thumbnail = PreviewCache.shared.image(largeClip)
  check(
    thumbnail != nil && max(thumbnail!.size.width, thumbnail!.size.height) <= 600,
    "Image preview is downsampled to bounded dimensions")
  let asyncFolder = folder.appendingPathComponent("async")
  let asyncStore = Store(
    folder: asyncFolder, defaults: defaults, pasteboard: pb, monitoring: false,
    asynchronousSaves: true)
  for index in 0..<30 {
    asyncStore.clips = [Clip(source: "Test", kind: "Text", text: "Snapshot \(index)")]
    asyncStore.save()
  }
  asyncStore.flushPendingSave()
  var diskClips = try! HistoryDatabase(url: asyncStore.url).load()
  check(
    diskClips.count == 1 && diskClips[0].text == "Snapshot 29",
    "Flush commits latest rapid background save before exit")
  RunLoop.current.run(until: Date().addingTimeInterval(0.25))
  diskClips = try! HistoryDatabase(url: asyncStore.url).load()
  check(diskClips[0].text == "Snapshot 29", "Canceled older saves cannot overwrite newer data")
  asyncStore.clips.append(Clip(source: "Test", kind: "Text", text: "Must be cleared"))
  asyncStore.save()
  asyncStore.clearHistory()
  RunLoop.current.run(until: Date().addingTimeInterval(0.25))
  diskClips = try! HistoryDatabase(url: asyncStore.url).load()
  check(
    diskClips.isEmpty && asyncStore.error == nil,
    "Clear cannot be undone by a queued background write")
  let failureFolder = folder.appendingPathComponent("retry")
  let retryStore = Store(
    folder: failureFolder, defaults: defaults, pasteboard: pb, monitoring: false)
  let validClip = Clip(source: "Test", kind: "Text", text: "Recoverable")
  retryStore.clips = [validClip, validClip]
  retryStore.save()
  check(retryStore.error != nil, "Write failures are surfaced")
  retryStore.clips = [validClip]
  retryStore.save()
  check(
    retryStore.error == nil && FileManager.default.fileExists(atPath: retryStore.url.path),
    "Database write error can recover without restarting")
  // Migration preserves every field and keeps a backup until the user clears it.
  let legacyFolder = folder.appendingPathComponent("migration")
  try! FileManager.default.createDirectory(at: legacyFolder, withIntermediateDirectories: true)
  let legacyURL = legacyFolder.appendingPathComponent("history.json")
  let legacyClips = [
    Clip(
      date: Date(timeIntervalSinceReferenceDate: 1234.25), source: "Notes", kind: "Text",
      text: "Tiếng Việt 👋\nNUL:\0'end", data: Data([0, 1, 2, 255]), board: "Work",
      title: "Pinned note", bundleID: "com.apple.Notes", html: Data()),
    Clip(source: "Photos", kind: "Image", text: "Test image", data: originalPNG),
  ]
  let legacyBytes = try! JSONEncoder().encode(legacyClips)
  try! legacyBytes.write(to: legacyURL)
  let migrated = Store(folder: legacyFolder, defaults: defaults, pasteboard: pb, monitoring: false)
  let backupURL = legacyFolder.appendingPathComponent("history.json.backup")
  check(
    migrated.error == nil && migrated.clips == legacyClips,
    "JSON migration preserves order, UUIDs, dates, Unicode, pins and binary payloads")
  check(
    (try? Data(contentsOf: backupURL)) == legacyBytes
      && !FileManager.default.fileExists(atPath: legacyURL.path),
    "Original JSON is retained as a migration backup")
  let reopened = Store(folder: legacyFolder, defaults: defaults, pasteboard: pb, monitoring: false)
  check(
    reopened.clips == legacyClips, "SQLite relaunch preserves all fields without duplicate import")
  migrated.clearHistory()
  check(
    !FileManager.default.fileExists(atPath: backupURL.path) && migrated.clips.isEmpty,
    "Clear also removes the legacy migration backup")
  try! legacyBytes.write(to: legacyURL)
  let afterClear = Store(
    folder: legacyFolder, defaults: defaults, pasteboard: pb, monitoring: false)
  check(
    afterClear.clips.isEmpty && afterClear.error == nil,
    "Migration marker prevents reimporting old JSON after Clear")
  let badLegacyFolder = folder.appendingPathComponent("bad-legacy")
  try! FileManager.default.createDirectory(at: badLegacyFolder, withIntermediateDirectories: true)
  let badLegacyURL = badLegacyFolder.appendingPathComponent("history.json")
  try! Data("unreadable JSON".utf8).write(to: badLegacyURL)
  let badLegacy = Store(
    folder: badLegacyFolder, defaults: defaults, pasteboard: pb, monitoring: false)
  badLegacy.save()
  check(
    badLegacy.error != nil && (try? String(contentsOf: badLegacyURL)) == "unreadable JSON",
    "Failed migration preserves unreadable JSON and blocks writes")
  badLegacy.clearHistory()
  check(
    badLegacy.error == nil && badLegacy.clips.isEmpty,
    "Explicit Clear can recover from an unreadable legacy archive")
  let incremental = try! HistoryDatabase(
    url: folder.appendingPathComponent("incremental/history.sqlite3"))
  try! incremental.save(legacyClips)
  let previousChanges = incremental.totalChanges
  try! incremental.save(legacyClips)
  check(
    incremental.totalChanges == previousChanges, "Saving unchanged history performs zero row writes"
  )
  var edited = legacyClips
  edited[0].title = "Updated label"
  try! incremental.save(edited)
  check(
    incremental.totalChanges == previousChanges + 1 && (try! incremental.load()) == edited,
    "Editing one item updates exactly one record")
  try! incremental.save(Array(edited.reversed()))
  check(
    (try! incremental.load()).map(\.id) == edited.reversed().map(\.id),
    "Reordering persists independently of clipboard payloads")
  do { try incremental.save([edited[0], edited[0]]) } catch {}
  check(
    (try! incremental.load()).count == 2, "Rejected duplicate IDs leave committed history intact")
  let beforeRollback = try! incremental.load()
  var testConnection: OpaquePointer?
  check(
    sqlite3_open(incremental.url.path, &testConnection) == SQLITE_OK,
    "Open independent connection for transaction failure test")
  let trigger =
    "CREATE TRIGGER reject_test_title BEFORE UPDATE OF title ON clips WHEN NEW.title='REJECT' BEGIN SELECT RAISE(ABORT,'test failure'); END;"
  check(
    sqlite3_exec(testConnection, trigger, nil, nil, nil) == SQLITE_OK,
    "Install test-only transaction failure trigger")
  sqlite3_close(testConnection)
  var rejected = beforeRollback
  rejected[0].title = "This update must roll back"
  rejected[1].title = "REJECT"
  var rejectedTransaction = false
  do { try incremental.save(rejected) } catch { rejectedTransaction = true }
  check(
    rejectedTransaction && (try! incremental.load()) == beforeRollback,
    "Failure partway through a transaction rolls back every changed record")
  try! incremental.save([edited[0]])
  check((try! incremental.load()).count == 1, "Deleted records are removed from SQLite")
  let beforeClearSize = incremental.storageBytes
  try! incremental.clear()
  check(
    (try! incremental.load()).isEmpty && incremental.storageBytes <= beforeClearSize,
    "SQLite Clear compacts database and journal files")
  let standardShortcut = KeyboardShortcut.default
  check(
    standardShortcut.keyCode == UInt32(kVK_ANSI_V)
      && standardShortcut.modifiers == UInt32(cmdKey | shiftKey),
    "Default shortcut remains Command-Shift-V")
  check(
    KeyboardShortcut.load(from: defaults) == standardShortcut,
    "Missing shortcut preference uses the default")
  let customShortcut = KeyboardShortcut(
    keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(cmdKey | optionKey))
  customShortcut.save(to: defaults)
  check(
    KeyboardShortcut.load(from: defaults) == customShortcut,
    "Custom shortcut survives preference reload")
  let shortcutStore = Store(
    folder: folder.appendingPathComponent("shortcut-relaunch"), defaults: defaults, pasteboard: pb,
    monitoring: false)
  check(shortcutStore.shortcut == customShortcut, "Store loads the saved shortcut on relaunch")
  check(
    !KeyboardShortcut(keyCode: 9, modifiers: 0).isValid
      && !KeyboardShortcut(keyCode: 9, modifiers: UInt32(shiftKey)).isValid,
    "Plain keys and Shift-only shortcuts are rejected")
  check(
    !KeyboardShortcut(keyCode: 53, modifiers: UInt32(cmdKey)).isValid,
    "Escape is reserved for cancel and close")
  check(
    !KeyboardShortcut(keyCode: 9, modifiers: UInt32(cmdKey) | 1).isValid,
    "Unsupported modifier bits are rejected")
  defaults.set(Data("invalid preference".utf8), forKey: "globalShortcut")
  check(
    KeyboardShortcut.load(from: defaults) == standardShortcut,
    "Malformed shortcut preference safely falls back to default")
  let keyEvent = NSEvent.keyEvent(
    with: .keyDown, location: .zero, modifierFlags: [.command, .option, .capsLock], timestamp: 0,
    windowNumber: 0, context: nil, characters: "b", charactersIgnoringModifiers: "b",
    isARepeat: false, keyCode: UInt16(kVK_ANSI_B))!
  check(
    KeyboardShortcut(event: keyEvent) == customShortcut && customShortcut.label == "⌥⌘B",
    "Recorder normalizes modifier flags and formats shortcut label")
  var registrations = 0
  var releases = 0
  var rejectRegistration = false
  let registrar = ShortcutRegistrar(
    register: { _, handle in
      registrations += 1
      if rejectRegistration { return OSStatus(-9878) }
      handle = EventHotKeyRef(bitPattern: registrations)
      return noErr
    }, unregister: { _ in releases += 1 })
  check(registrar.replace(with: standardShortcut), "Shortcut registrar accepts initial shortcut")
  let initialRegistrations = registrations
  check(
    registrar.replace(with: standardShortcut) && registrations == initialRegistrations,
    "Unchanged shortcut does not register twice")
  rejectRegistration = true
  check(
    !registrar.replace(with: customShortcut) && registrar.active == standardShortcut
      && releases == 0, "Conflicting shortcut leaves previous registration intact")
  rejectRegistration = false
  check(
    registrar.replace(with: customShortcut) && registrar.active == customShortcut && releases == 1,
    "Successful shortcut change releases the old registration")
  registrar.suspend()
  registrar.suspend()
  check(releases == 2, "Recording suspension releases a shortcut only once")
  check(
    registrar.replace(with: customShortcut) && registrar.active == customShortcut,
    "Canceling recording can restore the previous shortcut")
  check(
    registrar.replace(with: standardShortcut) && registrar.active == standardShortcut,
    "Reset restores the default shortcut")
  defaults.removeObject(forKey: "globalShortcut")
  check(
    AppearancePreferences.load(from: defaults) == AppearancePreferences.defaultOpacity,
    "Missing appearance preference uses readable default")
  check(
    AppearancePreferences.normalize(0) == 0.35 && AppearancePreferences.normalize(2) == 1,
    "Background opacity is clamped to supported range")
  check(
    AppearancePreferences.normalize(.nan) == AppearancePreferences.defaultOpacity
      && AppearancePreferences.normalize(.infinity) == AppearancePreferences.defaultOpacity,
    "Invalid opacity values fall back safely")
  shortcutStore.backgroundOpacity = 0.55
  let appearanceRelaunch = Store(
    folder: folder.appendingPathComponent("appearance-relaunch"), defaults: defaults,
    pasteboard: pb, monitoring: false)
  check(
    appearanceRelaunch.backgroundOpacity == 0.55,
    "Opacity changes are saved immediately and survive relaunch")
  shortcutStore.backgroundOpacity = 0.1
  check(
    shortcutStore.backgroundOpacity == 0.35 && defaults.double(forKey: "backgroundOpacity") == 0.35,
    "Opacity cannot make the panel unreadably transparent")
  check(
    shortcutStore.accessibilityGranted == AXIsProcessTrusted(),
    "Accessibility status is read without prompting during initialization")
  let updateInfo = Bundle.main.infoDictionary ?? [:]
  let feed = (updateInfo["SUFeedURL"] as? String).flatMap(URL.init(string:))
  check(
    feed?.scheme == "https" && feed?.host == "raw.githubusercontent.com"
      && feed?.path == "/hieupnvmg/ClipNest/main/updates/appcast.xml",
    "Update feed uses the expected HTTPS repository")
  let publicKey = (updateInfo["SUPublicEDKey"] as? String).flatMap { Data(base64Encoded: $0) }
  check(publicKey?.count == 32, "Updater embeds a valid Ed25519 public key")
  check(
    updateInfo["SUVerifyUpdateBeforeExtraction"] as? Bool == true
      && updateInfo["SURequireSignedFeed"] as? Bool == true,
    "OTA requires signed feed and verified archives before extraction")
  check(
    updateInfo["SUEnableSystemProfiling"] as? Bool == false
      && updateInfo["SUAutomaticallyUpdate"] as? Bool == false,
    "Updater does not enable profiling or silent installs by default")
  let framework = Bundle.main.bundleURL.appendingPathComponent(
    "Contents/Frameworks/Sparkle.framework")
  check(
    FileManager.default.fileExists(atPath: framework.path),
    "Sparkle framework is bundled with the app")
  defaults.removeObject(forKey: "backgroundOpacity")
  check(
    ClipboardNavigation.offset(keyCode: 123, modifiers: [], hasMarkedText: false) == -1
      && ClipboardNavigation.offset(keyCode: 124, modifiers: [], hasMarkedText: false) == 1,
    "Left and Right select cards even when search holds focus")
  check(
    ClipboardNavigation.offset(keyCode: 126, modifiers: [], hasMarkedText: false) == -1
      && ClipboardNavigation.offset(keyCode: 125, modifiers: [], hasMarkedText: false) == 1,
    "Up and Down also navigate clipboard items")
  check(
    ClipboardNavigation.offset(keyCode: 124, modifiers: [], hasMarkedText: true) == nil,
    "Arrow keys are left to IME while composing text")
  check(
    [NSEvent.ModifierFlags.command, .option, .control, .shift].allSatisfy {
      ClipboardNavigation.offset(keyCode: 123, modifiers: $0, hasMarkedText: false) == nil
    }, "Modified arrows preserve text editing and selection")
  check(
    ClipboardNavigation.offset(
      keyCode: 124, modifiers: [.capsLock, .numericPad], hasMarkedText: false) == 1,
    "Caps Lock and native arrow-key flags do not block navigation")
  check(
    ClipboardNavigation.offset(keyCode: 0, modifiers: [], hasMarkedText: false) == nil,
    "Normal typing is not consumed by navigation")
  cacheStore.query = ""
  cacheStore.kind = "All types"
  cacheStore.board = nil
  cacheStore.selected = cacheStore.filtered.first?.id
  cacheStore.move(1)
  check(
    cacheStore.selected == cacheStore.filtered.last?.id, "Navigation updates the selected result")
  cacheStore.move(1)
  check(cacheStore.selected == cacheStore.filtered.last?.id, "Navigation stops at the final item")
  cacheStore.move(-1)
  cacheStore.move(-1)
  check(cacheStore.selected == cacheStore.filtered.first?.id, "Navigation stops at the first item")
  cacheStore.query = "no matches"
  cacheStore.move(1)
  check(cacheStore.selectedClip == nil, "Empty search results safely ignore navigation")
  // Exercise the actual controller with a native text-view first responder.
  // This panel is never ordered onto the user's screen.
  let testPanel = NavigationTestPanel(
    contentRect: NSRect(x: 0, y: 0, width: 500, height: 200), styleMask: [.borderless],
    backing: .buffered, defer: false)
  testPanel.isReleasedWhenClosed = false
  let textEditor = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
  testPanel.contentView!.addSubview(textEditor)
  check(
    testPanel.makeFirstResponder(textEditor) && testPanel.firstResponder === textEditor,
    "Native text editor can hold keyboard focus in navigation regression fixture")
  let controller = AppDelegate()
  controller.panel = testPanel
  controller.store = cacheStore
  cacheStore.query = ""
  cacheStore.selected = cacheStore.filtered.first?.id
  let nativeRight = NSEvent.keyEvent(
    with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
    windowNumber: testPanel.windowNumber, context: nil, characters: "",
    charactersIgnoringModifiers: "", isARepeat: false, keyCode: 124)!
  check(
    controller.handleKey(nativeRight) == nil && cacheStore.selected == cacheStore.filtered.last?.id
      && testPanel.firstResponder === textEditor,
    "Controller selects next card while native search editor retains focus")
  let otherPanel = NSPanel(
    contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
  otherPanel.isReleasedWhenClosed = false
  let otherEvent = NSEvent.keyEvent(
    with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
    windowNumber: otherPanel.windowNumber, context: nil, characters: "",
    charactersIgnoringModifiers: "", isARepeat: false, keyCode: 123)!
  check(
    controller.handleKey(otherEvent) === otherEvent
      && cacheStore.selected == cacheStore.filtered.last?.id,
    "Keys belonging to another window are not intercepted")
  controller.focusCards()
  let nativeLeft = NSEvent.keyEvent(
    with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
    windowNumber: testPanel.windowNumber, context: nil, characters: "",
    charactersIgnoringModifiers: "", isARepeat: false, keyCode: 123)!
  check(
    controller.handleKey(nativeLeft) == nil && cacheStore.selected == cacheStore.filtered.first?.id,
    "Controller also navigates after removing text-field focus")
  otherPanel.close()
  testPanel.close()
  let firstParameters = UpdateFeed.requestParameters(nonce: "first-check")
  let nextParameters = UpdateFeed.requestParameters(nonce: "next-check")
  check(
    firstParameters != nextParameters && firstParameters.first?["key"] == "clipnest_check",
    "Update requests use a fresh one-time cache parameter")
  check(
    Set(firstParameters[0].keys) == Set(["key", "value", "displayKey", "displayValue"])
      && firstParameters[0]["value"] == "first-check",
    "Update freshness parameters contain no device identifier or clipboard content")
  check(
    UpdateService.shared.feedHTTPHeaders["Accept"] == nil,
    "Updater does not rely on an Accept header that Sparkle overrides")
  check(
    UpdateService.shared.responds(
      to: NSSelectorFromString("feedParametersForUpdater:sendingSystemProfile:"))
      && !UpdateService.shared.responds(to: NSSelectorFromString("feedURLStringForUpdater:")),
    "Updater adds request parameters without changing Sparkle base URL or scheduler")
  var loginStatus = SMAppService.Status.notRegistered
  var loginRegistrations = 0
  var loginUnregistrations = 0
  var failRegistration = false
  let login = LoginItemService(
    readStatus: { loginStatus },
    register: {
      loginRegistrations += 1
      if failRegistration { throw NSError(domain: "LoginTest", code: 1) }
      loginStatus = .requiresApproval
    },
    unregister: { loginUnregistrations += 1; loginStatus = .notRegistered })
  check(!login.isRegistered && loginRegistrations == 0, "Reading login state does not register app")
  login.setEnabled(true)
  check(login.isRegistered && login.status == .requiresApproval, "Login approval remains visible as pending")
  login.setEnabled(true)
  check(loginRegistrations == 1, "Pending login item is not registered twice")
  loginStatus = .enabled
  login.refresh()
  check(login.isRegistered && login.status == .enabled, "Login UI reflects system approval")
  login.setEnabled(false)
  check(!login.isRegistered && loginUnregistrations == 1, "Disabling unregisters login item")
  failRegistration = true
  login.setEnabled(true)
  check(!login.isRegistered && login.error != nil, "Failed login registration restores actual system state")
  let onboardingSuite = "ClipNest.onboarding-test.\(UUID().uuidString)"
  let onboarding = UserDefaults(suiteName: onboardingSuite)!
  defer { onboarding.removePersistentDomain(forName: onboardingSuite) }
  check(AccessibilityOnboarding.consumeAutomaticRequest(trusted: false, defaults: onboarding),
    "First untrusted launch may ask for Accessibility")
  let onboardingRelaunch = UserDefaults(suiteName: onboardingSuite)!
  check(!AccessibilityOnboarding.consumeAutomaticRequest(trusted: false, defaults: onboardingRelaunch),
    "Denied or revoked Accessibility does not prompt again on relaunch")
  onboarding.removePersistentDomain(forName: onboardingSuite)
  check(!AccessibilityOnboarding.consumeAutomaticRequest(trusted: true, defaults: onboarding),
    "Trusted launch never asks for Accessibility")
  check(!AccessibilityOnboarding.consumeAutomaticRequest(trusted: false, defaults: onboarding),
    "Previously trusted user is not prompted again after trust changes")
  check(InterfaceStyle.load(from: defaults) == .liquidGlass, "New appearance defaults to Liquid Glass")
  shortcutStore.interfaceStyle = .standard
  let styleRelaunch = Store(folder: folder.appendingPathComponent("style-relaunch"),
    defaults: defaults, pasteboard: pb, monitoring: false)
  check(styleRelaunch.interfaceStyle == .standard, "Appearance style survives relaunch")
  defaults.set("unknown-style", forKey: "interfaceStyle")
  check(InterfaceStyle.load(from: defaults) == .liquidGlass, "Unknown appearance falls back safely")
  check(GlassRendering.resolve(style: .liquidGlass, reduceTransparency: false, supportsLiquid: true) == .liquid,
    "Liquid Glass uses native rendering on supported macOS")
  check(GlassRendering.resolve(style: .liquidGlass, reduceTransparency: false, supportsLiquid: false) == .material,
    "Older macOS uses built-in material")
  check(GlassRendering.resolve(style: .standard, reduceTransparency: false, supportsLiquid: true) == .material,
    "Standard style remains available on new macOS")
  check(GlassRendering.resolve(style: .liquidGlass, reduceTransparency: true, supportsLiquid: true) == .solid
    && GlassRendering.resolve(style: .standard, reduceTransparency: true, supportsLiquid: false) == .solid,
    "Reduce Transparency replaces either style with an opaque backdrop")
  checks += runSensitiveContentTests()
  print("All \(checks) integration checks passed. General system clipboard was not modified.")
}
@MainActor func renderPreview(to path: String, settings: Bool = false, privacy: Bool = false) {
  let suite = "ClipNest.preview.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suite)!
  defer { defaults.removePersistentDomain(forName: suite) }
  let pb = NSPasteboard.withUniqueName()
  defer { pb.releaseGlobally() }
  let previewFolder = FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: previewFolder) }
  let store = Store(
    folder: previewFolder,
    defaults: defaults, pasteboard: pb, monitoring: false)
  if CommandLine.arguments.contains("--standard-preview") { store.interfaceStyle = .standard }
  store.boards = ["Useful Links", "Important Notes", "Email Templates", "Code Snippets"]
  // Synthetic sample content used only for the preview; never added to real history.
  let img = NSImage(size: NSSize(width: 500, height: 400))
  img.lockFocus()
  NSGradient(colors: [
    NSColor(calibratedRed: 0.18, green: 0.42, blue: 0.61, alpha: 1),
    NSColor(calibratedRed: 0.98, green: 0.73, blue: 0.46, alpha: 1),
  ])!.draw(in: NSRect(x: 0, y: 0, width: 500, height: 400), angle: -90)
  let mountains = NSBezierPath()
  mountains.move(to: .init(x: 0, y: 0))
  mountains.line(to: .init(x: 0, y: 120))
  mountains.line(to: .init(x: 150, y: 280))
  mountains.line(to: .init(x: 280, y: 100))
  mountains.line(to: .init(x: 380, y: 215))
  mountains.line(to: .init(x: 500, y: 90))
  mountains.line(to: .init(x: 500, y: 0))
  mountains.close()
  NSColor(calibratedRed: 0.17, green: 0.30, blue: 0.32, alpha: 1).setFill()
  mountains.fill()
  img.unlockFocus()
  let png = NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(
    using: .png, properties: [:])!
  store.clips = [
    Clip(
      date: Date().addingTimeInterval(-60), source: "Safari", kind: "Link",
      text: "https://developer.apple.com/design", title: "Human Interface Guidelines",
      bundleID: "com.apple.Safari"),
    Clip(
      date: Date().addingTimeInterval(-180), source: "Notes", kind: "Text",
      text:
        "A little less searching.\nA little more creating.\n\nKeep the things you copy close — ideas, links, notes, and everything in between.",
      bundleID: "com.apple.Notes"),
    Clip(
      date: Date().addingTimeInterval(-600), source: "Photos", kind: "Image", text: "500 × 400",
      data: png, bundleID: "com.apple.Photos"),
    Clip(
      date: Date().addingTimeInterval(-1200), source: "TextEdit", kind: "Color", text: "#758B79",
      bundleID: "com.apple.TextEdit"),
    Clip(
      date: Date().addingTimeInterval(-3600), source: "Finder", kind: "Files",
      text: "file:///tmp/Brand%20Guidelines.pdf", bundleID: "com.apple.finder"),
    Clip(
      date: Date().addingTimeInterval(-7200), source: "Notes", kind: "Text",
      text:
        "Hi Alex,\n\nThanks for sharing the latest designs. The new direction looks great.\n\nLet's catch up tomorrow.",
      board: "Email Templates", title: "Quick follow-up", bundleID: "com.apple.Notes"),
  ]
  if privacy {
    store.clips.insert(
      contentsOf: [
        Clip(
          source: "Contacts", kind: "Text", text: "Email: demo@example.com\nPhone: +84 912 345 678",
          title: "Thông tin liên hệ", bundleID: "com.apple.AddressBook"),
        Clip(
          source: "Notes", kind: "Text", text: "4111 1111 1111 1111", title: "Thẻ dùng thử",
          bundleID: "com.apple.Notes"),
        Clip(
          source: "Terminal", kind: "Text",
          text: ["password", "unit-test-placeholder"].joined(separator: "="),
          title: "Mục cũ đã bảo vệ", bundleID: "com.apple.Terminal"),
      ], at: 0)
  }
  store.selected = store.clips.first?.id
  if CommandLine.arguments.contains("--search-preview") { store.searchVisible = true }
  if let i = CommandLine.arguments.firstIndex(of: "--preview-query"), i + 1 < CommandLine.arguments.count {
    store.searchVisible = true
    store.query = CommandLine.arguments[i + 1]
    store.selected = store.filtered.first?.id
  }
  if let i = CommandLine.arguments.firstIndex(of: "--preview-selection"), i + 1 < CommandLine.arguments.count,
    let index = Int(CommandLine.arguments[i + 1]), store.filtered.indices.contains(index)
  {
    store.selected = store.filtered[index].id
  }
  let dark = CommandLine.arguments.contains("--dark-preview")
  let width: CGFloat = settings ? 560 : 1440
  let height: CGFloat = settings ? 740 : 346
  let content =
    settings
    ? AnyView(ClipboardContent(store: store).preferences) : AnyView(ClipboardContent(store: store))
  let root = content.frame(width: width, height: height).background(
    Color(nsColor: .windowBackgroundColor)
  ).environment(\.colorScheme, dark ? .dark : .light)
  let hosting = NSHostingView(rootView: root)
  hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
  let window = NSWindow(
    contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
  window.contentView = hosting
  window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
  hosting.layoutSubtreeIfNeeded()
  RunLoop.current.run(until: Date().addingTimeInterval(0.3))
  hosting.layoutSubtreeIfNeeded()
  guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { exit(1) }
  hosting.cacheDisplay(in: hosting.bounds, to: rep)
  try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
  print("Preview saved: \(path)")
}

private final class NavigationTestPanel: NSPanel {
  override var isVisible: Bool { true }
}
