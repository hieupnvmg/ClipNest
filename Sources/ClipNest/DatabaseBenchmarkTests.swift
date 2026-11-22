import AppKit
import CryptoKit

@MainActor func runDatabaseBenchmarkTests() async -> Int {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ClipNest-bench-tests-\(UUID())")
  let suite = "ClipNest.bench-tests.\(UUID())"
  let pb = NSPasteboard.withUniqueName()
  defer {
    try? FileManager.default.removeItem(at: folder)
    UserDefaults().removePersistentDomain(forName: suite)
    pb.releaseGlobally()
  }
  var checks = 0
  func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    guard condition() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
    checks += 1
    print("PASS: \(name)")
  }
  func fingerprint() -> String {
    ["", "-wal"].map { suffix -> String in
      let data = (try? Data(contentsOf: folder.appendingPathComponent("history.sqlite3" + suffix))) ?? Data()
      return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }.joined(separator: ":")
  }
  func leftovers() -> Int {
    ((try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)) ?? [])
      .filter { $0.hasPrefix("ClipNest-db-bench-") }.count
  }

  let store = Store(folder: folder, defaults: UserDefaults(suiteName: suite)!, pasteboard: pb, monitoring: false)
  let png = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 30, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    .representation(using: .png, properties: [:])!
  for index in 0..<30 { store.clips.append(Clip(source: "Test", kind: "Text", text: "benchmark item \(index)")) }
  var image = Clip(source: "Test", kind: "Image", text: "40 × 30", data: png)
  image.imageReference = ImageReference(data: png)
  store.clips.append(image)
  store.save()
  store.flushPendingSave()
  let before = fingerprint()
  let tempBefore = leftovers()

  await withCheckedContinuation { done in store.runDatabaseBenchmark { done.resume() } }
  let result = store.databaseBenchmark
  check(result != nil && store.databaseBenchmarkError == nil && !store.databaseBenchmarkRunning,
    "The database benchmark finishes without an error")
  check(result?.clips == 31 && result?.images == 1 && (result?.imageBytes ?? 0) == Int64(png.count),
    "The benchmark measures the saved history: 31 items, 1 image")
  check(Set(result?.steps.map(\.moment) ?? []) == Set(DatabaseBenchmark.Moment.allCases)
    && result?.steps.contains { $0.title.hasPrefix("Paste the largest image") } == true
    && result?.steps.allSatisfy { $0.milliseconds >= 0 } == true,
    "The benchmark times launch, copy/paste and quit, including reading an image")
  check(result?.interactiveSteps.contains { $0.moment == .launch } == false
    && result?.slowestInteractive != nil,
    "Launch work is kept apart from the work done while copying")
  check(fingerprint() == before && store.clips.count == 31,
    "The benchmark never changes the real database")
  check(leftovers() == tempBefore, "The temporary copy is deleted afterwards")
  check(DatabasePerformanceSection.format(4.04) == "4.0 ms" && DatabasePerformanceSection.format(38.8) == "39 ms",
    "Benchmark times are shown with one decimal below 10 ms")
  return checks
}
