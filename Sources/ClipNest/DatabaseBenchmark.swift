import AppKit

/// Times the history database on a temporary copy, so the real one is never written.
/// Used by Settings › Clipboard and by `--database-benchmark <folder>`.
struct DatabaseBenchmark {
  enum Moment: String, CaseIterable { case launch = "At launch", copy = "While you copy and paste", quit = "On quit" }
  struct Step: Identifiable, Equatable {
    var id: String { title }
    let title: String
    let moment: Moment
    let milliseconds: Double
  }

  /// One frame at 60 Hz: anything below it cannot be felt.
  static let frameBudget = 16.7
  var clips = 0
  var images = 0
  var databaseBytes: Int64 = 0
  var imageBytes: Int64 = 0
  var steps: [Step] = []
  var date = Date()

  /// Work that happens while the app is in use, as opposed to once at launch.
  var interactiveSteps: [Step] { steps.filter { $0.moment != .launch } }
  var slowestInteractive: Step? { interactiveSteps.max { $0.milliseconds < $1.milliseconds } }
  var launchMilliseconds: Double { steps.filter { $0.moment == .launch }.reduce(0) { $0 + $1.milliseconds } }

  /// Copies history.sqlite3 and its WAL files from `folder` into `destination`.
  /// The caller must make sure nothing writes the database while this runs.
  static func copyDatabase(from folder: URL, to destination: URL) throws {
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    for suffix in ["", "-wal", "-shm"] {
      let from = folder.appendingPathComponent("history.sqlite3" + suffix)
      if FileManager.default.fileExists(atPath: from.path) {
        try FileManager.default.copyItem(at: from, to: destination.appendingPathComponent("history.sqlite3" + suffix))
      }
    }
  }

  /// Runs every measurement on the database in `work`, which must already be a copy.
  static func run(in work: URL, repeats: Int = 20) throws -> DatabaseBenchmark {
    func ms(_ body: () throws -> Void) rethrows -> Double {
      let start = ProcessInfo.processInfo.systemUptime
      try body()
      return (ProcessInfo.processInfo.systemUptime - start) * 1000
    }
    var result = DatabaseBenchmark()
    var steps: [Step] = []
    func add(_ title: String, _ moment: Moment, _ value: Double) {
      steps.append(Step(title: title, moment: moment, milliseconds: value))
    }
    let url = work.appendingPathComponent("history.sqlite3")
    var opened: HistoryDatabase?
    var clips: [Clip] = []
    add("Open database", .launch, try ms { opened = try HistoryDatabase(url: url) })
    guard let db = opened else { return result }
    add("Load history", .launch, try ms { clips = try db.loadAndMigrate() })
    add("Load text found in images", .launch, try ms { _ = try db.imageTexts() })
    let imageClips = clips.filter { $0.kind == "Image" }
    result.clips = clips.count
    result.images = imageClips.count
    result.databaseBytes = db.storageBytes
    result.imageBytes = imageClips.reduce(0) { $0 + Int64($1.imageReference?.byteCount ?? 0) }

    var history = clips
    add("Save with nothing changed", .copy, try ms { for _ in 0..<repeats { try db.save(history) } } / Double(repeats))
    add("Save a new text copy", .copy, try ms {
      for index in 0..<repeats {
        history.insert(Clip(source: "Benchmark", kind: "Text", text: "New copy \(index) \(UUID())"), at: 0)
        try db.save(history)
      }
    } / Double(repeats))
    if history.count > 2 {
      add("Copy an older item again", .copy, try ms {
        for _ in 0..<repeats {
          let moved = history.remove(at: history.count / 2)
          history.insert(moved, at: 0)
          try db.save(history)
        }
      } / Double(repeats))
      add("Rename an item", .copy, try ms {
        for index in 0..<repeats {
          history[1].title = "Renamed \(index)"
          try db.save(history)
        }
      } / Double(repeats))
    }
    let png = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 1600, pixelsHigh: 1000, bitsPerSample: 8, samplesPerPixel: 4,
      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
      .representation(using: .png, properties: [:])!
    add("Save a new screenshot", .copy, try ms {
      var image = Clip(source: "Benchmark", kind: "Image", text: "1600 × 1000", data: png)
      image.imageReference = ImageReference(data: png)
      history.insert(image, at: 0)
      try db.save(history)
    })
    if let largest = imageClips.max(by: { ($0.imageReference?.byteCount ?? 0) < ($1.imageReference?.byteCount ?? 0) }) {
      let size = ByteCountFormatter.string(fromByteCount: Int64(largest.imageReference?.byteCount ?? 0), countStyle: .file)
      add("Paste the largest image (\(size))", .copy, try ms {
        for _ in 0..<10 { _ = try db.imageData(for: largest.id, expected: largest.imageReference) }
      } / 10)
    }
    add("Write everything to disk", .quit, try ms { try db.checkpoint() })
    result.steps = steps
    result.date = Date()
    return result
  }

  /// Copies the database in `folder` to a temporary folder, measures it and deletes the copy.
  static func measure(copyOf folder: URL) throws -> DatabaseBenchmark {
    let work = FileManager.default.temporaryDirectory.appendingPathComponent("ClipNest-db-bench-\(UUID())")
    defer { try? FileManager.default.removeItem(at: work) }
    try copyDatabase(from: folder, to: work)
    return try run(in: work)
  }
}
