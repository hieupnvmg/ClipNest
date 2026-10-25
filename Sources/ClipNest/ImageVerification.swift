import AppKit
import CSQLite
import Darwin

@MainActor func runImageStorageTests() async -> Int {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ClipNest-image-tests-\(UUID())")
  let suite = "ClipNest.image-tests.\(UUID())"
  let defaults = UserDefaults(suiteName: suite)!
  let pb = NSPasteboard.withUniqueName()
  defer { try? FileManager.default.removeItem(at: folder); defaults.removePersistentDomain(forName: suite); pb.releaseGlobally() }
  var checks = 0
  func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    guard condition() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
    checks += 1; print("PASS: \(name)")
  }
  let image = NSImage(size: NSSize(width: 80, height: 50))
  image.lockFocus(); NSColor.systemBlue.setFill(); NSRect(x: 0, y: 0, width: 80, height: 50).fill(); image.unlockFocus()
  let bytes = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
  let bitmap = NSBitmapImageRep(data: bytes)!
  let dimensions = "\(bitmap.pixelsWide) × \(bitmap.pixelsHigh)"
  let originals = (0..<12).map { Clip(source: "Test", kind: "Image", text: dimensions, data: bytes, title: "Photo \($0)") }
  let db = try! HistoryDatabase(url: folder.appendingPathComponent("history.sqlite3"))
  try! db.save(originals)
  let reads = db.imagePayloadReads
  var metadata = try! db.load(includeImageData: false)
  check(metadata.count == 12 && metadata.allSatisfy { $0.data == nil && $0.hasDeferredImage },
    "Image history loads references without original BLOBs")
  check(db.imagePayloadReads == reads, "Metadata loading reads zero image payloads")
  check((try! db.imageData(for: metadata[0].id, expected: metadata[0].imageReference)) == bytes,
    "On-demand image read preserves exact PNG bytes")
  let writes = db.imagePayloadWrites
  let beforeMetadataReads = db.imagePayloadReads
  metadata[0].title = "Renamed photo"
  metadata[0].board = "Work"
  metadata.reverse()
  try! db.save(metadata)
  check(db.imagePayloadReads == beforeMetadataReads && db.imagePayloadWrites == writes,
    "Pinning, renaming and ordering deferred images neither reads nor rebinds BLOBs")
  let reopened = try! HistoryDatabase(url: db.url)
  let reloaded = try! reopened.load(includeImageData: false)
  check(reloaded == metadata && reopened.imagePayloadReads == 0,
    "Image metadata and ordering survive relaunch without loading images")
  check((try! reopened.imageData(for: metadata.last!.id)) == bytes, "Metadata updates preserve original image payload")
  var unavailable = metadata[0]
  unavailable.id = UUID()
  do { try db.save([unavailable]); check(false, "Missing deferred image rejected") }
  catch { check((try! db.load(includeImageData: false)) == metadata, "Missing deferred reference cannot overwrite valid history") }

  let largeDB = try! HistoryDatabase(url: folder.appendingPathComponent("wal/history.sqlite3"))
  let largeBytes = bytes + Data(repeating: 0, count: 2_000_000)
  try! largeDB.save([Clip(source: "Test", kind: "Image", text: dimensions, data: largeBytes)])
  try! largeDB.checkpoint()
  var largeMetadata = try! largeDB.load(includeImageData: false)
  largeMetadata[0].title = "Metadata-only update"
  try! largeDB.save(largeMetadata)
  let walBytes = ((try! FileManager.default.attributesOfItem(atPath: largeDB.url.path + "-wal")[.size]) as! NSNumber).intValue
  check(walBytes < 131_072 && largeDB.imagePayloadWrites == 1 && largeDB.imagePayloadReads == 0,
    "Renaming a 2 MB image writes only small metadata pages to SQLite WAL")
  check((try! largeDB.imageData(for: largeMetadata[0].id)) == largeBytes,
    "Separate image payload survives metadata-only writes exactly")

  let store = Store(folder: folder, defaults: defaults, pasteboard: pb, monitoring: false)
  check(store.clips.allSatisfy { $0.data == nil }, "Store retains no original image payloads after reopening")
  store.writeClipboard(store.clips[0])
  check(pb.data(forType: .png) == bytes, "Deferred image can be copied at original quality")
  let oldID = store.clips.first!.id
  let oldTitle = store.clips.first!.title
  store.pin(store.clips.first!, to: "Work")
  pb.clearContents(); pb.setData(bytes, forType: .png)
  store.capture(source: "Test", bundleID: "test.image")
  check(store.clips.count == 12 && store.clips.first?.id == oldID && store.clips.first?.title == oldTitle,
    "Image recapture deduplicates deferred references and preserves labels")
  check(store.clips.first?.data == nil && (try! store.readImage(store.clips.first!)) == bytes,
    "New image bytes are released after successful save")
  PreviewCache.shared.images.removeAllObjects()
  let preview = await store.previewImage(store.clips.first!)
  check(preview != nil && max(preview!.size.width, preview!.size.height) <= 600,
    "Deferred image thumbnail loads off-thread at bounded resolution")
  let cachedPreview = await store.previewImage(store.clips.first!)
  check(preview === cachedPreview, "Repeated visible thumbnail requests use the memory cache")
  let provider = store.imageProvider(store.clips.first!)
  let dragBytes: Data? = await withCheckedContinuation { continuation in
    provider.loadDataRepresentation(forTypeIdentifier: "public.png") { data, _ in continuation.resume(returning: data) }
  }
  check(dragBytes == bytes, "Drag provider loads original deferred PNG bytes")
  store.copyOnly(store.clips.first!)
  try? await Task.sleep(nanoseconds: 100_000_000)
  check(pb.data(forType: .png) == bytes && store.toast == "Copied to clipboard", "Copy Only completes after asynchronous original image read")

  store.copyOnly(store.clips.first!)
  store.copyOnly(Clip(source: "Test", kind: "Text", text: "Newer clipboard action"))
  try? await Task.sleep(nanoseconds: 100_000_000)
  check(pb.string(forType: .string) == "Newer clipboard action", "Delayed image copy cannot overwrite a newer clipboard action")

  let asyncStore = Store(folder: folder.appendingPathComponent("async"), defaults: defaults,
    pasteboard: pb, monitoring: false, asynchronousSaves: true)
  asyncStore.clips = [originals[0]]
  asyncStore.save()
  check(asyncStore.clips[0].data != nil, "Pending image remains in memory until disk commit")
  asyncStore.flushPendingSave()
  check(asyncStore.clips[0].hasDeferredImage && (try! asyncStore.readImage(asyncStore.clips[0])) == bytes,
    "Flush commits image then releases original bytes")
  asyncStore.clips = [originals[0], originals[0]]
  asyncStore.save(); asyncStore.flushPendingSave()
  check(asyncStore.error != nil && asyncStore.clips[0].data == bytes, "Failed image save keeps original bytes for retry")
  asyncStore.clearHistory()
  try? await Task.sleep(nanoseconds: 200_000_000)
  check((try! HistoryDatabase(url: asyncStore.url).load(includeImageData: false)).isEmpty,
    "Clear cannot be undone by a pending image write")

  // Old SQLite schema migration reads one image at a time and preserves UUID/data.
  let legacyURL = folder.appendingPathComponent("legacy/history.sqlite3")
  do {
    let legacy = try! HistoryDatabase(url: legacyURL)
    try! legacy.save([originals[0]])
  }
  var connection: OpaquePointer?
  sqlite3_open(legacyURL.path, &connection)
  let downgraded = sqlite3_exec(connection, "UPDATE clips SET payload=(SELECT payload FROM image_payloads WHERE id=clips.id) WHERE kind='Image'; DROP TABLE image_payloads; ALTER TABLE clips DROP COLUMN image_digest; PRAGMA user_version=1;", nil, nil, nil)
  sqlite3_close(connection)
  check(downgraded == SQLITE_OK, "Prepare schema-v1 image fixture")
  let upgraded = try! HistoryDatabase(url: legacyURL)
  let oldMetadata = try! upgraded.load(includeImageData: false)
  check(oldMetadata.first?.id == originals[0].id && oldMetadata.first?.hasDeferredImage == true
    && (try! upgraded.imageData(for: originals[0].id)) == bytes,
    "Schema-v1 upgrade preserves original image and builds its reference")
  let secondOpen = try! HistoryDatabase(url: legacyURL)
  _ = try! secondOpen.load(includeImageData: false)
  check(secondOpen.imagePayloadReads == 0, "Image indexing runs once; later launches read metadata only")

  let resumeURL = folder.appendingPathComponent("resume/history.sqlite3")
  do { let resume = try! HistoryDatabase(url: resumeURL); try! resume.save(Array(originals.prefix(2))) }
  sqlite3_open(resumeURL.path, &connection)
  let interruptSQL = "UPDATE clips SET payload=(SELECT payload FROM image_payloads WHERE id=clips.id),image_digest=NULL WHERE kind='Image'; DELETE FROM image_payloads; CREATE TRIGGER interrupt_move BEFORE INSERT ON image_payloads WHEN NEW.id='\(originals[1].id.uuidString)' BEGIN SELECT RAISE(ABORT,'test interruption'); END;"
  precondition(sqlite3_exec(connection, interruptSQL, nil, nil, nil) == SQLITE_OK)
  sqlite3_close(connection)
  var interrupted = false
  do { _ = try HistoryDatabase(url: resumeURL) } catch { interrupted = true }
  sqlite3_open(resumeURL.path, &connection)
  var statement: OpaquePointer?
  sqlite3_prepare_v2(connection, "SELECT (SELECT COUNT(*) FROM image_payloads),(SELECT COUNT(*) FROM clips WHERE payload IS NOT NULL)", -1, &statement, nil)
  sqlite3_step(statement)
  let durableMoves = sqlite3_column_int(statement, 0)
  let intactOriginals = sqlite3_column_int(statement, 1)
  sqlite3_finalize(statement)
  sqlite3_exec(connection, "DROP TRIGGER interrupt_move", nil, nil, nil)
  sqlite3_close(connection)
  check(interrupted && durableMoves == 1 && intactOriginals == 1,
    "Interrupted migration keeps committed image and rolls back only the failed move")
  let resumed = try! HistoryDatabase(url: resumeURL)
  let resumedItems = try! resumed.load(includeImageData: false)
  check(resumedItems.count == 2 && resumedItems.allSatisfy { (try? resumed.imageData(for: $0.id)) == bytes },
    "Image migration resumes safely without losing either original")

  let queue = OperationQueue()
  let pipeline = ImagePipeline(queue: queue)
  queue.isSuspended = true
  let counter = ImageReadCounter()
  let canceled = Task { await pipeline.thumbnail { counter.increment(); return bytes } }
  try? await Task.sleep(nanoseconds: 30_000_000)
  canceled.cancel()
  queue.isSuspended = false
  let canceledResult = await canceled.value
  check(canceledResult == nil && counter.value == 0, "Canceled offscreen thumbnail skips its queued disk read")
  let completed = await pipeline.thumbnail { counter.increment(); return bytes }
  check(completed != nil && counter.value == 1, "Thumbnail queue continues working after cancellation")
  let invalid = await pipeline.thumbnail { Data([1, 2, 3]) }
  check(invalid == nil, "Malformed image produces a safe placeholder")
  let erased = store.clips.first!
  store.clearHistory()
  let missing = await store.previewImage(erased)
  pb.clearContents(); pb.setString("Keep this clipboard", forType: .string)
  check(missing == nil && !store.writeClipboard(erased)
    && pb.string(forType: .string) == "Keep this clipboard", "Deleted image cannot repopulate cache or clear clipboard on failed copy")
  return checks
}

private final class ImageReadCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0
  func increment() { lock.lock(); count += 1; lock.unlock() }
  var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

func runImageReadProbe(path: String, eager: Bool, upgrading: Bool = false) {
  let start = ProcessInfo.processInfo.systemUptime
  let db = try! HistoryDatabase(url: URL(fileURLWithPath: path))
  let clips = try! db.load(includeImageData: eager)
  let bytes = clips.reduce(0) { $0 + ($1.kind == "Image" ? ($1.data?.count ?? 0) : 0) }
  var usage = rusage()
  getrusage(RUSAGE_SELF, &usage)
  print(String(format: "%@: %d images; original bytes retained %.2f MiB; peak RSS %.2f MiB; load %.1f ms",
    upgrading ? "Upgrade v1 + lazy" : (eager ? "Eager" : "Lazy"), clips.count, Double(bytes) / 1048576, Double(usage.ru_maxrss) / 1048576,
    (ProcessInfo.processInfo.systemUptime - start) * 1000))
  withExtendedLifetime(clips) {}
}

func runImageMemoryBenchmark() {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ClipNest-image-memory-\(UUID())")
  defer { try? FileManager.default.removeItem(at: folder) }
  var pixels = [UInt32](repeating: 0, count: 1024 * 640)
  var random: UInt32 = 12345
  for i in pixels.indices { random = random &* 1664525 &+ 1013904223; pixels[i] = random | 0xff000000 }
  let data = pixels.withUnsafeBytes { Data($0) }
  let cg = CGImage(width: 1024, height: 640, bitsPerComponent: 8, bitsPerPixel: 32,
    bytesPerRow: 4096, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)),
    provider: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
  let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
  let fixture = (0..<100).map { Clip(source: "Synthetic", kind: "Image", text: "1024 × 640", data: png, title: "Photo \($0)") }
  let url = folder.appendingPathComponent("history.sqlite3")
  do { let db = try! HistoryDatabase(url: url); try! db.save(fixture); try! db.checkpoint() }
  print("Synthetic fixture: 100 PNG payloads, \(png.count) bytes each. Fresh subprocess per mode.")
  for eager in [true, false] {
    let process = Process()
    process.executableURL = Bundle.main.executableURL!
    process.arguments = ["--image-read-probe", url.path] + (eager ? ["--eager-images"] : [])
    let pipe = Pipe(); process.standardOutput = pipe
    try! process.run()
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    precondition(process.terminationStatus == 0)
    print(String(decoding: output, as: UTF8.self), terminator: "")
  }
  var connection: OpaquePointer?
  sqlite3_open(url.path, &connection)
  let result = sqlite3_exec(connection, "UPDATE clips SET payload=(SELECT payload FROM image_payloads WHERE id=clips.id) WHERE kind='Image'; DROP TABLE image_payloads; ALTER TABLE clips DROP COLUMN image_digest; PRAGMA user_version=1;", nil, nil, nil)
  sqlite3_close(connection)
  precondition(result == SQLITE_OK)
  let upgrade = Process()
  upgrade.executableURL = Bundle.main.executableURL!
  upgrade.arguments = ["--image-read-probe", url.path, "--upgrade-probe"]
  let pipe = Pipe(); upgrade.standardOutput = pipe
  try! upgrade.run()
  let output = pipe.fileHandleForReading.readDataToEndOfFile()
  upgrade.waitUntilExit()
  precondition(upgrade.terminationStatus == 0)
  print(String(decoding: output, as: UTF8.self), terminator: "")
}
