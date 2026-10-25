import AppKit

func runSensitiveContentTests() -> Int {
  var count = 0
  func check(_ result: @autoclosure () -> Bool, _ name: String) {
    guard result() else {
      fputs("FAIL: \(name)\n", stderr)
      exit(1)
    }
    count += 1
    print("PASS: \(name)")
  }
  let apiKey = ["sk", "proj", String(repeating: "A", count: 32)].joined(separator: "-")
  let githubToken = "ghp_" + String(repeating: "b", count: 36)
  let stripeKey = ["sk", "live", String(repeating: "c", count: 24)].joined(separator: "_")
  let password = ["password", "unit-test-value"].joined(separator: "=")
  let privateKey = "-----BEGIN " + "PRIVATE KEY-----\nunit-test-only\n-----END PRIVATE KEY-----"
  let bearer = "Authorization: " + "Bearer " + String(repeating: "d", count: 24)
  for (name, value) in [
    ("API key", apiKey), ("GitHub token", githubToken), ("Stripe secret key", stripeKey),
    ("password assignment", password), ("private key", privateKey),
    ("authorization header", bearer),
  ] {
    let assessment = SensitiveContent.inspect(value)
    check(
      assessment.containsSecret && assessment.maskedText == SensitiveAssessment.secretPlaceholder,
      "Detect and fully mask \(name)")
  }
  let jwt = [
    "eyJhbGciOiJIUzI1NiJ9", "eyJzdWIiOiJ1bml0LXRlc3QifQ", String(repeating: "a", count: 24),
  ].joined(separator: ".")
  check(SensitiveContent.containsSecret(jwt), "JWT-shaped tokens are recognized")
  check(
    SensitiveContent.containsSecret("https://unit:fixture@example.com/path"),
    "Credentials embedded in URLs are recognized")
  check(
    !SensitiveContent.inspect("A normal note about a project.").isSensitive,
    "Ordinary prose is unchanged")
  check(
    !SensitiveContent.inspect("Order 2026-10-25 #123456").isSensitive,
    "Dates and short order IDs are unchanged")
  check(
    !SensitiveContent.containsSecret("ssh-rsa public-material"),
    "Public SSH key labels are not mistaken for private keys")
  let email = "hieu@example.com"
  let emailResult = SensitiveContent.inspect("Xin chào 👋 " + email)
  check(
    emailResult.isSensitive && !emailResult.containsSecret
      && !emailResult.maskedText.contains(email) && emailResult.maskedText.hasPrefix("Xin chào 👋 "),
    "Email masking preserves Unicode surrounding text")
  check(
    emailResult.maskedText.contains("h•••@•••.com"),
    "Email masking reveals only minimal identifying characters")
  let phone = "+84 912 345 678"
  let phoneResult = SensitiveContent.inspect("Call " + phone)
  check(
    phoneResult.isSensitive && !phoneResult.maskedText.contains(phone)
      && phoneResult.maskedText.hasSuffix("678"),
    "Vietnamese phone number is masked with a three-digit suffix")
  let international = SensitiveContent.inspect("Call +1 (415) 555-0123")
  check(
    international.isSensitive && !international.maskedText.contains("555-0123"),
    "International formatted phone numbers are masked")
  let card = "4111 1111 1111 1111"
  let cardResult = SensitiveContent.inspect(card)
  check(
    cardResult.isSensitive && cardResult.maskedText == "•••• •••• •••• 1111",
    "Luhn-valid payment card is masked with last four digits")
  check(
    !SensitiveContent.isPaymentCard("4111111111111112")
      && !SensitiveContent.isPaymentCard("0000000000000000"),
    "Invalid checksums and uniform digits are not recognized as cards")
  check(
    !SensitiveContent.inspect("4111111111111112").isSensitive,
    "Invalid card-like number is not redacted")
  let many = Array(repeating: email, count: 150).joined(separator: "\n")
  let saturated = SensitiveContent.inspect(many)
  check(
    saturated.isSensitive && !saturated.maskedText.contains("example.com"),
    "Large numbers of matches fall back to full masking without leaking the remainder")

  let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
    "ClipNest-privacy-\(UUID().uuidString)")
  let suite = "ClipNest.privacy.tests.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suite)!
  let board = NSPasteboard.withUniqueName()
  defer {
    try? FileManager.default.removeItem(at: folder)
    defaults.removePersistentDomain(forName: suite)
    board.releaseGlobally()
  }
  let store = Store(folder: folder, defaults: defaults, pasteboard: board, monitoring: false)
  func copy(_ text: String, html: String? = nil) {
    board.clearContents()
    board.setString(text, forType: .string)
    if let html { board.setData(Data(html.utf8), forType: .html) }
    store.capture(source: "Privacy Fixture", bundleID: "test.privacy")
  }
  check(
    store.sensitiveProtectionEnabled && store.personalDataAction == "mask",
    "Automatic sensitive-content protection is enabled by default")
  for value in [apiKey, githubToken, password, privateKey, bearer] { copy(value) }
  check(store.clips.isEmpty, "Detected credentials never enter clipboard history")
  check(
    board.string(forType: .string) == bearer,
    "Skipping sensitive history does not modify the active clipboard")
  let reopenedEmpty = Store(
    folder: folder, defaults: defaults, pasteboard: board, monitoring: false)
  check(reopenedEmpty.clips.isEmpty, "Skipped credentials are not written to SQLite")
  copy(
    "Click here",
    html: "<a href=\"https://example.com/?api_key=" + String(repeating: "q", count: 24)
      + "\">Click here</a>")
  check(store.clips.isEmpty, "Credentials hidden in rich-text HTML are also skipped")
  board.clearContents()
  board.setString("Plain preview", forType: .string)
  board.setData(Data(("{\\rtf1 " + password + "}").utf8), forType: .rtf)
  store.capture(source: "RTF Fixture", bundleID: "test.privacy")
  check(store.clips.isEmpty, "Credentials in rich-text RTF payload are skipped before persistence")
  copy("Contact " + email)
  let saved = store.clips[0]
  check(
    saved.text.contains(email) && store.isMasked(saved),
    "Personal content retains original data but defaults to masked presentation")
  let safe = store.displayClip(saved)
  check(
    !safe.text.contains(email) && !safe.displayTitle.contains(email) && safe.data == nil
      && safe.html == nil, "Masked presentation contains no original email or rich-text payload")
  store.writeClipboard(saved)
  check(
    board.string(forType: .string) == saved.text,
    "Explicit paste preserves the original personal content")
  store.revealSensitiveItem(saved, duration: 0.02)
  check(
    !store.isMasked(saved) && store.displayClip(saved).text == saved.text,
    "Explicit temporary reveal shows original content")
  RunLoop.current.run(until: Date().addingTimeInterval(0.06))
  check(store.isMasked(saved), "Temporary reveal automatically expires")
  store.revealSensitiveItem(saved)
  store.hideRevealedSensitiveItems()
  check(
    store.isMasked(saved) && store.revealedSensitiveIDs.isEmpty,
    "Closing or hiding the panel resets all reveals")
  store.personalDataAction = "skip"
  let before = store.clips.count
  copy("Other person other@example.net")
  check(
    store.clips.count == before
      && board.string(forType: .string) == "Other person other@example.net",
    "Do-not-save mode skips personal data without changing clipboard")
  let strictReload = Store(folder: folder, defaults: defaults, pasteboard: board, monitoring: false)
  check(
    strictReload.personalDataAction == "skip", "Personal data handling preference survives relaunch"
  )
  store.sensitiveProtectionEnabled = false
  copy(password)
  check(
    store.clips.first?.text == password && !store.isMasked(store.clips[0]),
    "Disabling protection is an explicit opt-out")
  let disabledReload = Store(
    folder: folder, defaults: defaults, pasteboard: board, monitoring: false)
  check(!disabledReload.sensitiveProtectionEnabled, "Protection opt-out survives relaunch")
  store.sensitiveProtectionEnabled = true
  store.personalDataAction = "mask"
  let legacy = store.clips[0]
  check(
    store.isMasked(legacy)
      && store.displayClip(legacy).text == SensitiveAssessment.secretPlaceholder,
    "Previously stored credentials are masked when protection is enabled")
  check(
    store.clips.contains { $0.id == legacy.id },
    "Enabling protection does not silently delete existing history")
  var titled = Clip(source: "Test", kind: "Text", text: "Ordinary body", title: email)
  check(
    store.isMasked(titled) && !store.displayClip(titled).title.contains(email),
    "Sensitive labels are masked too")
  titled.title = "Normal title"
  check(!store.isMasked(titled), "Presentation cache invalidates when a label changes")
  copy("A normal editable note")
  let editable = store.clips[0]
  store.edit(editable)
  store.editedText = password
  store.saveEdit()
  check(
    store.clips.first?.text == editable.text && store.editingPrivacyMessage != nil,
    "Editor refuses newly entered credentials without changing the original item")
  store.editing = nil
  store.editedText = ""
  store.edit(saved)
  check(store.editing == nil, "Masked content cannot leak through the editor before reveal")
  store.revealSensitiveItem(saved, duration: 0.02)
  store.edit(saved)
  check(store.editing?.id == saved.id, "Revealed content can be edited explicitly")
  RunLoop.current.run(until: Date().addingTimeInterval(0.06))
  check(
    store.editing == nil && store.editedText.isEmpty,
    "Reveal expiry closes sensitive editor and clears its draft")
  store.revealSensitiveItem(saved)
  store.clearHistory()
  check(
    store.clips.isEmpty && store.revealedSensitiveIDs.isEmpty,
    "Clear removes history and temporary reveals together")
  let encodedFile = Clip(
    source: "Finder", kind: "Files", text: "file:///tmp/demo%40example.com.txt")
  check(
    store.isMasked(encodedFile)
      && !store.displayClip(encodedFile).displayTitle.contains("example.com"),
    "Decoded file names do not leak a masked email")
  check(
    !store.displayClip(encodedFile).text.contains("example.com"),
    "Encoded file URI is masked consistently with its visible file name")
  return count
}
