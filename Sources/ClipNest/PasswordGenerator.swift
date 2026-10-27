import AppKit
import Security
import SwiftUI

enum PasswordGenerationError: LocalizedError {
  case invalidLength, randomFailure
  var errorDescription: String? {
    switch self {
    case .invalidLength: return "Choose a password length from 12 to 64."
    case .randomFailure: return "Could not generate a secure password. Please try again."
    }
  }
}

enum PasswordGenerator {
  static let defaultLength = 20
  static let lower = Array("abcdefghijklmnopqrstuvwxyz".utf8)
  static let upper = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ".utf8)
  static let digits = Array("0123456789".utf8)
  static let symbols = Array("!@#$%^&*()-_=+[]{}:,.?".utf8)

  static func generate(length: Int = defaultLength, includeSymbols: Bool = true,
    randomBytes: (Int) throws -> [UInt8] = secureBytes) throws -> String {
    guard (12...64).contains(length) else { throw PasswordGenerationError.invalidLength }
    let groups = [lower, upper, digits] + (includeSymbols ? [symbols] : [])
    let alphabet = groups.flatMap { $0 }
    let limit = 256 - (256 % alphabet.count)
    // Rejection sampling avoids modulo bias. Reject complete candidates missing a
    // chosen character category rather than forcing predictable positions.
    for _ in 0..<128 {
      var candidate: [UInt8] = []
      for _ in 0..<128 {
        let bytes = try randomBytes(max(32, length * 2))
        guard !bytes.isEmpty else { throw PasswordGenerationError.randomFailure }
        for byte in bytes where Int(byte) < limit {
          candidate.append(alphabet[Int(byte) % alphabet.count])
          if candidate.count == length { break }
        }
        if candidate.count == length { break }
      }
      guard candidate.count == length else { throw PasswordGenerationError.randomFailure }
      if groups.allSatisfy({ group in candidate.contains(where: { group.contains($0) }) }) {
        return String(decoding: candidate, as: UTF8.self)
      }
    }
    throw PasswordGenerationError.randomFailure
  }
  static func secureBytes(_ count: Int) throws -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: count)
    let status = bytes.withUnsafeMutableBytes {
      SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!)
    }
    guard status == errSecSuccess else { throw PasswordGenerationError.randomFailure }
    return bytes
  }
}

@MainActor final class PasswordGeneratorModel: ObservableObject {
  @Published var isPresented = false
  @Published private(set) var password = ""
  @Published private(set) var length = PasswordGenerator.defaultLength
  @Published private(set) var includeSymbols = true
  @Published var revealed = false
  @Published private(set) var copied = false
  @Published private(set) var error: String?
  private let generate: (Int, Bool) throws -> String
  init(generate: @escaping (Int, Bool) throws -> String = {
    try PasswordGenerator.generate(length: $0, includeSymbols: $1)
  }) { self.generate = generate }
  func open() { isPresented = true; regenerate() }
  func setLength(_ value: Int) { length = min(max(value, 12), 64); regenerate() }
  func setSymbols(_ value: Bool) { includeSymbols = value; regenerate() }
  func regenerate() {
    password = ""; copied = false; revealed = false; error = nil
    do { password = try generate(length, includeSymbols) }
    catch { self.error = error.localizedDescription }
  }
  func copy(using action: (String) -> Bool) {
    guard !password.isEmpty, error == nil else { return }
    copied = action(password)
  }
  func dismiss() { password = ""; revealed = false; copied = false; isPresented = false }
}

struct PasswordGeneratorPresentation: ViewModifier {
  @ObservedObject var model: PasswordGeneratorModel
  let store: Store
  func body(content: Content) -> some View {
    content.sheet(isPresented: $model.isPresented, onDismiss: { model.dismiss() }) {
      PasswordGeneratorSheet(model: model, store: store)
    }.onDisappear { model.dismiss() }
  }
}

struct PasswordGeneratorSheet: View {
  @ObservedObject var model: PasswordGeneratorModel
  let store: Store
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Label("Generate password", systemImage: "key.fill").font(.title2.bold())
      HStack {
        Text(model.revealed ? model.password : String(repeating: "•", count: min(model.length, 24)))
          .font(.system(.body, design: .monospaced)).lineLimit(3)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityLabel(model.revealed ? model.password : "Password hidden")
        Button { model.revealed.toggle() } label: {
          Image(systemName: model.revealed ? "eye.slash" : "eye")
        }.buttonStyle(.plain).help(model.revealed ? "Hide password" : "Show password")
          .accessibilityLabel(model.revealed ? "Hide password" : "Show password")
      }.padding(14).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
      Stepper("Length: \(model.length)", value: Binding(
        get: { model.length }, set: { model.setLength($0) }), in: 12...64)
      Toggle("Include symbols", isOn: Binding(
        get: { model.includeSymbols }, set: { model.setSymbols($0) }))
      Text("Uppercase, lowercase and numbers are always included. Copied passwords are saved in clipboard history and masked when sensitive-content protection is enabled.")
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      if let error = model.error { Text(error).foregroundStyle(.red).font(.caption) }
      if model.copied { Label("Copied to clipboard", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green) }
      HStack {
        Button("Generate again") { model.regenerate() }
        Spacer()
        Button("Copy") { model.copy { store.copyGeneratedPassword($0) } }
          .buttonStyle(.borderedProminent).disabled(model.password.isEmpty)
        Button("Done") { model.dismiss() }.keyboardShortcut(.cancelAction)
      }
    }.padding(24).frame(width: 460)
  }
}
