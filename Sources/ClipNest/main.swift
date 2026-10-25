import AppKit
import Carbon
import SwiftUI

final class ClipboardPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
  lazy var store = Store()
  var panel: NSPanel!
  var status: NSStatusItem!
  var previous: NSRunningApplication?
  let shortcuts = ShortcutRegistrar()
  var keyMonitor: Any?
  var clickMonitor: Any?
  var workspaceMonitor: NSObjectProtocol?
  func applicationDidFinishLaunching(_ notification: Notification) {
    // Reopening the same bundle brings its existing panel forward.
    let others = NSRunningApplication.runningApplications(
      withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.clipnest.app"
    ).filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    if !others.isEmpty {
      DistributedNotificationCenter.default().post(name: .init("local.clipnest.show"), object: nil)
      NSApp.terminate(nil)
      return
    }
    NSApp.setActivationPolicy(.accessory)
    panel = ClipboardPanel(
      contentRect: NSRect(x: 0, y: 0, width: 1200, height: 346),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.title = "ClipNest Clipboard"
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.hidesOnDeactivate = false
    panel.contentView = NSHostingView(rootView: Content(store: store))
    status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    status.button?.image = NSImage(
      systemSymbolName: "square.on.square", accessibilityDescription: "ClipNest")
    status.button?.target = self
    status.button?.action = #selector(statusClicked)
    status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    status.button?.toolTip = "ClipNest · \(store.shortcut.label)"
    var type = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, _ in
        (NSApp.delegate as? AppDelegate)?.toggle()
        return noErr
      }, 1, &type, nil, nil)
    if !shortcuts.replace(with: store.shortcut) {
      store.shortcutError = "This shortcut is unavailable. Choose another combination."
      store.toast = "\(store.shortcut.label) is unavailable. Open ClipNest from the menu bar."
    }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self else { return event }
      return self.handleKey(event)
    }
    clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
      [weak self] _ in if self?.panel.attachedSheet == nil { self?.hide() }
    }
    workspaceMonitor = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { [weak self] n in
      guard let self,
        let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
        app.processIdentifier != ProcessInfo.processInfo.processIdentifier
      else { return }
      self.previous = app
      if self.panel.isVisible && self.panel.attachedSheet == nil { self.hide() }
    }
    DistributedNotificationCenter.default().addObserver(
      self, selector: #selector(show), name: .init("local.clipnest.show"), object: nil)
    show()
    UpdateService.shared.start()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
      self?.store.requestAccessibilityPermission()
    }
  }
  @objc func checkForUpdates() { UpdateService.shared.checkForUpdates() }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    show()
    return true
  }
  @objc func statusClicked() {
    if NSApp.currentEvent?.type == .rightMouseUp {
      let menu = NSMenu()
      menu.addItem(withTitle: "Open ClipNest", action: #selector(show), keyEquivalent: "")
      menu.addItem(withTitle: "Preferences…", action: #selector(preferences), keyEquivalent: "")
      menu.addItem(
        withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
      menu.addItem(.separator())
      menu.addItem(withTitle: "Quit ClipNest", action: #selector(quit), keyEquivalent: "q")
      for item in menu.items { item.target = self }
      status.menu = menu
      status.button?.performClick(nil)
      status.menu = nil
    } else {
      toggle()
    }
  }
  @objc func preferences() {
    show()
    store.settings = true
  }
  @objc func toggle() { panel.isVisible ? hide() : show() }
  @objc func show() {
    if let front = NSWorkspace.shared.frontmostApplication,
      front.processIdentifier != ProcessInfo.processInfo.processIdentifier
    {
      previous = front
    }
    let screen =
      NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
      ?? NSScreen.main
    let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
    panel.setFrame(
      NSRect(x: frame.minX + 8, y: frame.minY + 8, width: frame.width - 16, height: 346),
      display: true)
    store.searchVisible = true
    store.selected = store.filtered.first?.id
    panel.makeKeyAndOrderFront(nil)
    focusSearch()
  }
  func hide() {
    if store.recordingShortcut { cancelShortcutRecording() }
    panel.orderOut(nil)
  }
  func beginShortcutRecording() {
    shortcuts.suspend()
    store.shortcutError = nil
    store.recordingShortcut = true
  }
  func cancelShortcutRecording() {
    store.recordingShortcut = false
    if !shortcuts.replace(with: store.shortcut) {
      store.shortcutError = "Shortcut unavailable. Choose another combination."
    }
  }
  func applyShortcut(_ shortcut: KeyboardShortcut) {
    guard shortcuts.replace(with: shortcut) else {
      store.shortcutError = "That shortcut is in use or unavailable. Try another combination."
      return
    }
    store.shortcut = shortcut
    shortcut.save(to: store.defaults)
    store.recordingShortcut = false
    store.shortcutError = nil
    store.toast = nil
    status.button?.toolTip = "ClipNest · \(shortcut.label)"
  }
  func focusCards() { panel.makeFirstResponder(nil) }
  func focusSearch() {
    store.searchVisible = true
    // Wait for SwiftUI to insert the native search field before assigning focus.
    DispatchQueue.main.async { [weak self] in
      guard let self, self.panel.isVisible else { return }
      func findSearch(in view: NSView) -> NSSearchField? {
        if let field = view as? NSSearchField, field.identifier?.rawValue == "clipboard-search" {
          return field
        }
        for child in view.subviews { if let field = findSearch(in: child) { return field } }
        return nil
      }
      if let content = self.panel.contentView, let field = findSearch(in: content) {
        self.panel.makeFirstResponder(field)
        field.currentEditor()?.selectedRange = NSRange(
          location: field.stringValue.utf16.count, length: 0)
      }
    }
  }
  func handleKey(_ event: NSEvent) -> NSEvent? {
    guard panel.isVisible else { return event }
    if store.recordingShortcut {
      guard event.window === panel || event.window === panel.attachedSheet else { return event }
      if event.keyCode == 53 || event.keyCode == 48 {
        cancelShortcutRecording()
        return nil
      }
      if let shortcut = KeyboardShortcut(event: event) {
        applyShortcut(shortcut)
      } else {
        store.shortcutError =
          "Use Command, Option or Control together with a letter, number, Space or function key."
      }
      return nil
    }
    guard panel.attachedSheet == nil, event.window === panel else { return event }
    let cmd = event.modifierFlags.contains(.command)
    if event.keyCode == 53 {
      hide()
      return nil
    }
    if cmd && event.charactersIgnoringModifiers == "f" {
      focusSearch()
      return nil
    }
    if cmd, let text = event.charactersIgnoringModifiers, let number = Int(text), number >= 1,
      number <= 9
    {
      let items = store.filtered
      if number <= items.count { store.copy(items[number - 1]) }
      return nil
    }
    let editor = panel.firstResponder as? NSTextView
    let hasMarkedText = editor?.hasMarkedText() == true
    if let offset = ClipboardNavigation.offset(
      keyCode: event.keyCode, modifiers: event.modifierFlags, hasMarkedText: hasMarkedText)
    {
      store.move(offset)
      return nil
    }
    if hasMarkedText { return event }
    if event.keyCode == 36, let clip = store.selectedClip {
      store.copy(clip, plain: event.modifierFlags.contains(.shift))
      return nil
    }
    return event
  }

  func hideAndPaste() {
    hide()
    previous?.activate(options: [.activateIgnoringOtherApps])
    guard let target = previous, !target.isTerminated, AXIsProcessTrusted() else {
      store.toast = "Copied — press ⌘V to paste. Enable direct paste in Preferences."
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
      // Do not type into an unrelated app if focus changed while hiding.
      guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier
      else { return }
      let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true)
      down?.flags = .maskCommand
      let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false)
      up?.flags = .maskCommand
      down?.post(tap: .cghidEventTap)
      up?.post(tap: .cghidEventTap)
    }
  }
  func applicationWillTerminate(_ notification: Notification) {
    guard panel != nil else { return }
    store.flushPendingSave()
    shortcuts.suspend()
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
    if let workspaceMonitor {
      NSWorkspace.shared.notificationCenter.removeObserver(workspaceMonitor)
    }
    DistributedNotificationCenter.default().removeObserver(self)
  }
  @objc func quit() { NSApp.terminate(nil) }
}
let app = NSApplication.shared
if CommandLine.arguments.contains("--self-test") {
  runSelfTests()
  exit(0)
}
if let i = CommandLine.arguments.firstIndex(of: "--render-preview"),
  i + 1 < CommandLine.arguments.count
{
  DispatchQueue.main.async {
    renderPreview(
      to: CommandLine.arguments[i + 1], settings: CommandLine.arguments.contains("--settings"))
    exit(0)
  }
  app.run()
  exit(0)
}
let delegate = AppDelegate()
app.delegate = delegate
app.run()
