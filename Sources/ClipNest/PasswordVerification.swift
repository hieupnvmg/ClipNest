import AppKit

@MainActor func runPasswordTests() -> Int {
  var checks = 0
  func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    guard condition() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
    checks += 1; print("PASS: \(name)")
  }
  var generated = Set<String>()
  for length in [12, 20, 64] {
    for symbols in [false, true] {
      var valid = true
      for _ in 0..<20 {
        let password = try! PasswordGenerator.generate(length: length, includeSymbols: symbols)
        let bytes = Array(password.utf8)
        valid = valid && bytes.count == length && bytes.contains(where: PasswordGenerator.lower.contains)
          && bytes.contains(where: PasswordGenerator.upper.contains)
          && bytes.contains(where: PasswordGenerator.digits.contains)
          && (symbols ? bytes.contains(where: PasswordGenerator.symbols.contains) : !bytes.contains(where: PasswordGenerator.symbols.contains))
        generated.insert(password)
      }
      check(valid, "Password samples meet length \(length) and requested character categories")
    }
  }
  check(generated.count == 120, "Independent secure generation produces distinct sample passwords")
  let deterministic = try! PasswordGenerator.generate(length: 12, randomBytes: { _ in
    [255, 0, 26, 52, 62] + Array(repeating: 0, count: 20)
  })
  check(deterministic.hasPrefix("aA0!"), "Password sampling rejects bytes outside the unbiased range")
  for length in [0, 11, 65, 1000] {
    check((try? PasswordGenerator.generate(length: length)) == nil, "Invalid password length is rejected")
  }
  check((try? PasswordGenerator.generate(randomBytes: { _ in throw PasswordGenerationError.randomFailure })) == nil,
    "Secure random failure never falls back to predictable passwords")
  check((try? PasswordGenerator.generate(randomBytes: { _ in [255] })) == nil,
    "Unusable random stream fails with bounded work")
  let model = PasswordGeneratorModel()
  model.open()
  check(model.isPresented && model.password.count == 20 && !model.revealed,
    "Password generator opens with a hidden 20-character password")
  model.revealed = true
  model.setLength(32)
  check(model.password.count == 32 && !model.revealed && !model.copied,
    "Changing length regenerates and hides the new password")
  model.setSymbols(false)
  check(!model.password.utf8.contains(where: PasswordGenerator.symbols.contains),
    "Symbols toggle applies immediately")
  let before = model.password
  model.regenerate()
  check(model.password != before, "Generate again replaces the password")
  var copied = ""
  model.copy { copied = $0; return true }
  check(model.copied && copied == model.password, "Copy uses the exact displayed generator value")
  model.dismiss()
  check(model.password.isEmpty && !model.revealed && !model.isPresented, "Closing generator clears its temporary password")
  let broken = PasswordGeneratorModel(generate: { _, _ in throw PasswordGenerationError.randomFailure })
  broken.open()
  var attemptedCopy = false
  broken.copy { _ in attemptedCopy = true; return true }
  check(broken.password.isEmpty && broken.error != nil && !attemptedCopy,
    "Generator errors cannot copy an empty or stale secret")

  let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ClipNest-password-tests-\(UUID())")
  let suite = "ClipNest.password-tests.\(UUID())"
  let defaults = UserDefaults(suiteName: suite)!
  let pb = NSPasteboard.withUniqueName()
  defer { defaults.removePersistentDomain(forName: suite); pb.releaseGlobally(); try? FileManager.default.removeItem(at: folder) }
  let store = Store(folder: folder, defaults: defaults, pasteboard: pb, monitoring: false)
  let password = try! PasswordGenerator.generate()
  check(store.copyGeneratedPassword(password) && pb.string(forType: .string) == password,
    "Generated password copies unchanged to the private test clipboard")
  check(store.clips.count == 1 && store.isMasked(store.clips[0])
    && !store.displayClip(store.clips[0]).text.contains(password),
    "Generated password is retained in history with a full sensitive-content mask")
  let id = store.clips[0].id
  store.pin(store.clips[0], to: "Work")
  store.copyGeneratedPassword(password)
  check(store.clips.count == 1 && store.clips[0].id == id && store.clips[0].board == "Work",
    "Copying the generated password twice preserves identity and pin")
  let reopened = Store(folder: folder, defaults: defaults, pasteboard: pb, monitoring: false)
  check(reopened.isMasked(reopened.clips[0]) && reopened.clips[0].text == password,
    "Generated password original and mask survive restart")
  reopened.writeClipboard(reopened.clips[0])
  check(pb.string(forType: .string) == password, "Masked generated password pastes its exact original")
  let count = pb.changeCount
  check(!store.copyGeneratedPassword("") && pb.changeCount == count, "Empty generated value leaves clipboard intact")
  return checks
}
