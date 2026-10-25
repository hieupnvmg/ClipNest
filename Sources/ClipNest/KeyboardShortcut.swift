import AppKit
import Carbon

struct KeyboardShortcut: Codable, Equatable {
  let keyCode: UInt32
  let modifiers: UInt32
  static let `default` = KeyboardShortcut(
    keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey))
  static let keyNames: [UInt32: String] = [
    0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
    12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4",
    22: "6", 23: "5",
    24: "=", 25: "9", 26: "7", 27: "−", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[",
    34: "I", 35: "P",
    37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M",
    47: ".", 49: "Space", 50: "`",
    96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11", 105: "F13",
    106: "F16",
    107: "F14", 109: "F10", 111: "F12", 113: "F15", 118: "F4", 120: "F2", 122: "F1",
  ]
  var isValid: Bool {
    let allowed = UInt32(cmdKey | shiftKey | optionKey | controlKey)
    let required = UInt32(cmdKey | optionKey | controlKey)
    return Self.keyNames[keyCode] != nil && modifiers & required != 0 && modifiers & ~allowed == 0
  }
  var label: String {
    var symbols = ""
    if modifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
    if modifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
    if modifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
    if modifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
    return symbols + (Self.keyNames[keyCode] ?? "?")
  }
  init(keyCode: UInt32, modifiers: UInt32) {
    self.keyCode = keyCode
    self.modifiers = modifiers
  }
  init?(event: NSEvent) {
    var flags: UInt32 = 0
    if event.modifierFlags.contains(.command) { flags |= UInt32(cmdKey) }
    if event.modifierFlags.contains(.shift) { flags |= UInt32(shiftKey) }
    if event.modifierFlags.contains(.option) { flags |= UInt32(optionKey) }
    if event.modifierFlags.contains(.control) { flags |= UInt32(controlKey) }
    self.init(keyCode: UInt32(event.keyCode), modifiers: flags)
    guard isValid else { return nil }
  }
  static func load(from defaults: UserDefaults) -> KeyboardShortcut {
    guard let data = defaults.data(forKey: "globalShortcut"),
      let shortcut = try? JSONDecoder().decode(Self.self, from: data), shortcut.isValid
    else { return .default }
    return shortcut
  }
  func save(to defaults: UserDefaults) {
    if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: "globalShortcut") }
  }
}

// Register the replacement before releasing the old combination. Failed changes
// keep the existing shortcut, while recording temporarily suspends it.
final class ShortcutRegistrar {
  typealias Registration = (KeyboardShortcut, inout EventHotKeyRef?) -> OSStatus
  private let register: Registration
  private let unregister: (EventHotKeyRef) -> Void
  private var reference: EventHotKeyRef?
  private(set) var active: KeyboardShortcut?
  init(register: Registration? = nil, unregister: ((EventHotKeyRef) -> Void)? = nil) {
    self.register =
      register ?? { shortcut, reference in
        RegisterEventHotKey(
          shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: 0x434C_4950, id: 1),
          GetApplicationEventTarget(), 0, &reference)
      }
    self.unregister = unregister ?? { _ = UnregisterEventHotKey($0) }
  }
  @discardableResult func replace(with shortcut: KeyboardShortcut) -> Bool {
    guard shortcut.isValid else { return false }
    if active == shortcut && reference != nil { return true }
    var replacement: EventHotKeyRef?
    guard register(shortcut, &replacement) == noErr, let replacement else { return false }
    if let reference { unregister(reference) }
    reference = replacement
    active = shortcut
    return true
  }
  func suspend() {
    if let reference { unregister(reference) }
    reference = nil
  }
  deinit { suspend() }
}
