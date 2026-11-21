import AppKit

@MainActor func runImageTextTests() async -> Int {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ClipNest-ocr-tests-\(UUID())")
  let suite = "ClipNest.ocr-tests.\(UUID())"
  let defaults = UserDefaults(suiteName: suite)!
  let pb = NSPasteboard.withUniqueName()
  defer {
    try? FileManager.default.removeItem(at: folder)
    defaults.removePersistentDomain(forName: suite)
    pb.releaseGlobally()
  }
  var checks = 0
  func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    guard condition() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
    checks += 1
    print("PASS: \(name)")
  }
  // Synthetic screenshots with large, high-contrast text.
  func screenshot(_ lines: [String]) -> Data {
    let size = NSSize(width: 900, height: 120 * CGFloat(lines.count) + 60)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 64, weight: .medium), .foregroundColor: NSColor.black,
    ]
    for (index, line) in lines.enumerated() {
      (line as NSString).draw(
        at: NSPoint(x: 40, y: size.height - 120 * CGFloat(index + 1)), withAttributes: attributes)
    }
    image.unlockFocus()
    return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
  }
  func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<1000 where !condition() { try? await Task.sleep(nanoseconds: 10_000_000) }
  }

  let recognized = ImageTextRecognizer.recognizeText(in: screenshot(["Deploy failed", "Xin chào ClipNest"])) ?? ""
  check(recognized.contains("Deploy failed") && recognized.localizedCaseInsensitiveContains("clipnest"),
    "Vision recognizes text in a screenshot on this Mac")
  check(ImageTextRecognizer.recognizeText(in: Data("not an image".utf8)) == nil,
    "Unreadable image data is reported without recognized text")

  let store = Store(folder: folder, defaults: defaults, pasteboard: pb, monitoring: false)
  check(store.imageTextRecognition, "Image text recognition is enabled by default")
  func copyImage(_ data: Data) {
    pb.clearContents()
    pb.setData(data, forType: .png)
    store.capture(source: "Screenshot", bundleID: "test.ocr")
  }
  copyImage(screenshot(["Deploy failed", "Xin chào ClipNest"]))
  let shot = store.clips[0]
  await waitUntil { !store.recognizedText(for: shot).isEmpty }
  store.query = "deploy FAILED"
  check(store.filtered.map(\.id) == [shot.id], "Search finds a screenshot by the words in it")
  store.query = ""
  check(!store.isMasked(shot), "Ordinary screenshots are not masked")

  copyImage(screenshot(["password: hunter2"]))
  let secret = store.clips[0]
  await waitUntil { !store.recognizedText(for: secret).isEmpty }
  check(store.isMasked(secret) && store.protection(for: secret).containsSecret,
    "Screenshots that show a password are masked")
  store.copyRecognizedText(secret)
  check(pb.string(forType: .string) == nil, "Masked screenshot text cannot be copied before reveal")
  store.revealSensitiveItem(secret)
  store.copyRecognizedText(shot)
  check(pb.string(forType: .string)?.contains("Deploy failed") == true,
    "Copy Text from Image puts the recognized text on the clipboard")

  await waitUntil { !ImageTextRecognizer.shared.isHelperRunning }
  check(!ImageTextRecognizer.shared.isHelperRunning,
    "Recognition runs in a helper process that exits when the queue is empty")
  try? await Task.sleep(nanoseconds: 500_000_000)
  let helpers = Process()
  helpers.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
  helpers.arguments = ["-P", String(ProcessInfo.processInfo.processIdentifier), "-f", ImageTextRecognizer.helperArgument]
  let helperList = Pipe()
  helpers.standardOutput = helperList
  try? helpers.run()
  helpers.waitUntilExit()
  check(helperList.fileHandleForReading.readDataToEndOfFile().isEmpty,
    "No helper process is left running after recognition")
  store.flushPendingSave()
  let reopened = Store(folder: folder, defaults: defaults, pasteboard: pb, monitoring: false)
  check(reopened.recognizedText(for: reopened.clips.first { $0.id == shot.id }!).contains("Deploy failed"),
    "Recognized text is stored and loaded with history")
  reopened.remove(reopened.clips.first { $0.id == shot.id }!)
  reopened.flushPendingSave()
  let afterRemove = try! HistoryDatabase(url: folder.appendingPathComponent("history.sqlite3")).imageTexts()
  check(afterRemove[shot.id] == nil && afterRemove[secret.id] != nil,
    "Deleting an image also deletes its recognized text")
  reopened.clearHistory()
  let afterClear = try! HistoryDatabase(url: folder.appendingPathComponent("history.sqlite3")).imageTexts()
  check(afterClear.isEmpty && reopened.imageText.isEmpty, "Clear removes all recognized text")
  return checks
}
