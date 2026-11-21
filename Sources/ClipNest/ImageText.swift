import AppKit
import ImageIO
import Vision

/// Text recognized in an image clip, tied to the exact image bytes it came from.
struct RecognizedText: Equatable {
  let digest: String
  let text: String
}

/// Recognizes text in clipboard images with Apple's Vision framework, entirely on this Mac.
///
/// Vision keeps its recognition models (~100 MB) resident for the life of the process that
/// used them, so recognition runs in a short-lived helper: this same executable started
/// with `--image-text-helper`. It handles every queued image, then exits and macOS reclaims
/// all of its memory. A crash on a malformed image also only takes down the helper.
final class ImageTextRecognizer {
  static let shared = ImageTextRecognizer()
  /// Long side of the image handed to Vision. Larger screenshots are downscaled first;
  /// this keeps memory bounded while staying sharp enough for on-screen text.
  static let maxPixelSize = 4096
  static let helperArgument = "--image-text-helper"
  /// macOS prepares its recognition models once per machine, which can take a minute.
  static let timeout: TimeInterval = 180
  private let queue: OperationQueue
  // Touched only from the serial operation queue.
  private var helper: HelperConnection?
  private let state = NSLock()
  private var running = false

  init() {
    queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    queue.qualityOfService = .utility
    queue.name = "local.clipnest.image-text"
    // Writing to a helper that just exited must fail with an error, not kill the app.
    signal(SIGPIPE, SIG_IGN)
  }

  /// True while a helper process is alive.
  var isHelperRunning: Bool { state.lock(); defer { state.unlock() }; return running }

  func recognize(read: @escaping () throws -> Data, completion: @escaping (String?) -> Void) {
    queue.addOperation { [weak self] in
      guard let self else { return }
      let text = autoreleasepool { () -> String? in
        guard let data = try? read() else { return nil }
        return self.recognizeInHelper(data)
      }
      // Last queued image: let the helper exit so its memory goes back to the system.
      if self.queue.operationCount <= 1 { self.stopHelper() }
      DispatchQueue.main.async { completion(text) }
    }
  }
  func cancelAll() { queue.cancelAllOperations() }

  private func recognizeInHelper(_ data: Data) -> String? {
    for attempt in 0..<2 {
      if helper == nil { helper = HelperConnection.launch() }
      setRunning(helper != nil)
      guard let connection = helper else { return nil }
      switch connection.recognize(data, timeout: Self.timeout) {
      case .text(let text): return text
      case .unreadable: return nil
      case .failed:
        // The helper crashed, hung or was killed: start a fresh one and retry once.
        stopHelper()
        if attempt == 1 { return nil }
      }
    }
    return nil
  }
  private func stopHelper() {
    helper?.close()
    helper = nil
    setRunning(false)
  }
  private func setRunning(_ value: Bool) { state.lock(); running = value; state.unlock() }

  /// Returns recognized lines joined by newlines, "" when the image has no text, or nil
  /// when the image could not be read.
  static func recognizeText(in data: Data) -> String? {
    guard
      let source = CGImageSourceCreateWithData(
        data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary)
    else { return nil }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    // Avoid waiting on Neural Engine model compilation in the OCR helper.
    request.usesCPUOnly = true
    request.usesLanguageCorrection = true
    if let languages = try? request.supportedRecognitionLanguages() {
      // Vietnamese first so diacritics are kept; English covers code, logs and UI text.
      let preferred = ["vi-VT", "en-US"].filter(languages.contains)
      if !preferred.isEmpty { request.recognitionLanguages = preferred }
    }
    do {
      try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
    } catch {
      return nil
    }
    return (request.results ?? [])
      .compactMap { $0.topCandidates(1).first?.string }
      .joined(separator: "\n")
  }
}

/// Pipe protocol between the app and its helper. Request: UInt32 length + image bytes.
/// Response: one status byte (0 text, 1 unreadable) + UInt32 length + UTF-8 text.
enum ImageTextProtocol {
  static func frame(_ payload: Data) -> Data {
    var length = UInt32(payload.count).bigEndian
    return Data(bytes: &length, count: 4) + payload
  }
  static func readExactly(_ count: Int, from handle: FileHandle) -> Data? {
    var result = Data()
    while result.count < count {
      guard let chunk = try? handle.read(upToCount: count - result.count), !chunk.isEmpty else {
        return nil
      }
      result.append(chunk)
    }
    return result
  }
  static func readLength(from handle: FileHandle) -> Int? {
    guard let bytes = readExactly(4, from: handle) else { return nil }
    return Int(bytes.reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
  }
  /// Upper bound for one image (the app never stores images over 25 MB).
  static let maxRequest = 64 * 1024 * 1024
}

/// Helper side: answer requests until the app closes stdin, then exit.
func runImageTextHelper() -> Never {
  let input = FileHandle.standardInput
  let output = FileHandle.standardOutput
  signal(SIGPIPE, SIG_IGN)
  while let length = ImageTextProtocol.readLength(from: input), length <= ImageTextProtocol.maxRequest,
    let image = ImageTextProtocol.readExactly(length, from: input)
  {
    let text = autoreleasepool { ImageTextRecognizer.recognizeText(in: image) }
    let status: UInt8 = text == nil ? 1 : 0
    var reply = Data([status])
    reply.append(ImageTextProtocol.frame(Data((text ?? "").utf8)))
    do { try output.write(contentsOf: reply) } catch { exit(1) }
  }
  exit(0)
}

/// App side of one running helper process.
final class HelperConnection {
  enum Reply { case text(String), unreadable, failed }
  private let process: Process
  private let input: FileHandle
  private let output: FileHandle

  private init(process: Process, input: FileHandle, output: FileHandle) {
    self.process = process
    self.input = input
    self.output = output
  }
  static func launch() -> HelperConnection? {
    guard let executable = Bundle.main.executableURL else { return nil }
    let process = Process()
    process.executableURL = executable
    process.arguments = [ImageTextRecognizer.helperArgument]
    let stdin = Pipe()
    let stdout = Pipe()
    process.standardInput = stdin
    process.standardOutput = stdout
    process.standardError = FileHandle.nullDevice
    process.qualityOfService = .utility
    do { try process.run() } catch { return nil }
    // Drop the parent's copies of the child's ends, so a crashed helper reads as EOF.
    try? stdin.fileHandleForReading.close()
    try? stdout.fileHandleForWriting.close()
    return HelperConnection(
      process: process, input: stdin.fileHandleForWriting, output: stdout.fileHandleForReading)
  }
  func recognize(_ image: Data, timeout: TimeInterval) -> Reply {
    // A hung helper is terminated, which ends the blocking read below with EOF.
    let watchdog = DispatchWorkItem { [process] in if process.isRunning { process.terminate() } }
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)
    defer { watchdog.cancel() }
    do { try input.write(contentsOf: ImageTextProtocol.frame(image)) } catch { return .failed }
    guard let status = ImageTextProtocol.readExactly(1, from: output)?.first,
      let length = ImageTextProtocol.readLength(from: output),
      let text = ImageTextProtocol.readExactly(length, from: output)
    else { return .failed }
    return status == 0 ? .text(String(decoding: text, as: UTF8.self)) : .unreadable
  }
  func close() {
    try? input.close()
    // The helper exits on EOF; don't leave it running if it is stuck in Vision.
    let process = self.process
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) {
      if process.isRunning { process.terminate() }
    }
  }
}
