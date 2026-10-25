import AppKit

// Route navigation independently of the current first responder. Search remains
// ready for typing while plain arrow keys select cards in the clipboard panel.
enum ClipboardNavigation {
  static func offset(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, hasMarkedText: Bool) -> Int?
  {
    guard !hasMarkedText, modifiers.intersection([.command, .option, .control, .shift]).isEmpty
    else { return nil }
    switch keyCode {
    case 123, 126: return -1  // Left / Up
    case 124, 125: return 1  // Right / Down
    default: return nil
    }
  }
}
