import AppKit

@MainActor func runSyncTests() async -> Int {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClipNest-sync-tests-\(UUID())")
  let cloud = root.appendingPathComponent("iCloud Drive/ClipNest Sync")
  try? FileManager.default.createDirectory(at: cloud.deletingLastPathComponent(), withIntermediateDirectories: true)
  let suites = ["ClipNest.sync-a.\(UUID())", "ClipNest.sync-b.\(UUID())"]
  let pb = NSPasteboard.withUniqueName()
  defer {
    try? FileManager.default.removeItem(at: root)
    for suite in suites { UserDefaults().removePersistentDomain(forName: suite) }
    pb.releaseGlobally()
  }
  var checks = 0
  func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    guard condition() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
    checks += 1
    print("PASS: \(name)")
  }
  func mac(_ name: String, _ suite: String) -> Store {
    Store(folder: root.appendingPathComponent(name), defaults: UserDefaults(suiteName: suite)!,
      pasteboard: pb, monitoring: false, syncFolder: cloud)
  }
  func sync(_ store: Store) async {
    await withCheckedContinuation { done in store.syncNow { done.resume() } }
  }
  func setUp(_ store: Store, _ passphrase: String, join: Bool) async -> Error? {
    await withCheckedContinuation { done in
      store.setUpSync(passphrase: passphrase, join: join) { done.resume(returning: $0) }
    }
  }
  let a = mac("mac-a", suites[0])
  let b = mac("mac-b", suites[1])
  check(!a.syncStatus.configured && !a.syncStatus.vaultExists && a.syncStatus.cloudAvailable,
    "Sync starts off, with the iCloud Drive folder available")
  let tooShort = await setUp(a, "short", join: false)
  check(tooShort is SyncError, "Sync passphrases must be at least 8 characters")
  let created = await setUp(a, "correct horse battery", join: false)
  check(created == nil && a.syncStatus.configured,
    "The first Mac creates the encrypted sync vault")
  b.refreshSyncStatus()
  check(b.syncStatus.vaultExists && !b.syncStatus.configured, "Another Mac sees that it can join")
  let wrong = await setUp(b, "wrong passphrase", join: true)
  check((wrong as? SyncError) == .wrongPassphrase && !b.syncStatus.configured, "A wrong passphrase is rejected")
  let joined = await setUp(b, "correct horse battery", join: true)
  check(joined == nil && b.syncStatus.configured,
    "The second Mac joins with the same passphrase")

  // Mac A: one pinned note, plus items that must not leave the Mac.
  let note = Clip(source: "Notes", kind: "Text", text: "Deploy checklist v2", board: "Work", title: "Runbook")
  let loose = Clip(source: "Notes", kind: "Text", text: "Unpinned scratch")
  let link = Clip(source: "Safari", kind: "Link", text: "https://example.com", board: Store.linksBoard)
  let secret = Clip(source: "Terminal", kind: "Text", text: "password=hunter2", board: "Work")
  a.clips = [note, loose, link, secret]
  a.save()
  await sync(a)
  let files = (try? FileManager.default.contentsOfDirectory(atPath: cloud.appendingPathComponent("items").path)) ?? []
  check(files == ["\(note.id.uuidString).cnsync"],
    "Only pinned items on your own boards sync; automatic boards and sensitive items stay local")
  let raw = (try? Data(contentsOf: cloud.appendingPathComponent("items/\(files.first ?? "")"))) ?? Data()
  check(!raw.isEmpty && raw.range(of: Data("Deploy".utf8)) == nil && raw.range(of: Data("Work".utf8)) == nil,
    "Files in iCloud Drive are encrypted")

  await sync(b)
  check(b.clips.first { $0.id == note.id }.map { $0.text == note.text && $0.board == "Work" && $0.title == "Runbook" } == true
      && !b.clips.contains { $0.id == loose.id || $0.id == secret.id },
    "A pinned note appears on the other Mac with its pinboard and label")

  // Images travel with their bytes.
  let image = NSImage(size: NSSize(width: 40, height: 30))
  image.lockFocus(); NSColor.systemTeal.setFill(); NSRect(x: 0, y: 0, width: 40, height: 30).fill(); image.unlockFocus()
  let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
  var shot = Clip(source: "Screenshot", kind: "Image", text: "40 × 30", data: png, board: "Projects")
  shot.imageReference = ImageReference(data: png)
  a.boards.append("Projects")
  a.clips.insert(shot, at: 0)
  a.save()
  await sync(a)
  await sync(b)
  let received = b.clips.first { $0.id == shot.id }
  check(received != nil && (try? b.readImage(received!)) == png && b.boards.contains("Projects"),
    "Pinned images and new pinboards sync to the other Mac")

  // Edits flow back, and unpinning keeps the item but takes it out of sync.
  if let index = b.clips.firstIndex(where: { $0.id == note.id }) { b.clips[index].title = "Runbook (edited)" }
  b.save()
  await sync(b)
  await sync(a)
  check(a.clips.first { $0.id == note.id }?.title == "Runbook (edited)", "Edits on one Mac reach the other")
  if let index = a.clips.firstIndex(where: { $0.id == note.id }) { a.clips[index].board = nil }
  a.save()
  await sync(a)
  await sync(b)
  check(b.clips.first { $0.id == note.id }.map { $0.board == nil } == true,
    "Unpinning on one Mac unpins on the other without deleting history")

  a.syncIncludeSensitive = true
  await sync(a)
  await sync(b)
  check(b.clips.contains { $0.id == secret.id }, "Sensitive items sync only when included")

  b.leaveSync()
  check(!b.syncStatus.configured && b.syncStatus.vaultExists && b.clips.contains { $0.id == shot.id },
    "Stopping sync on a Mac keeps its history and the shared folder")
  return checks
}
