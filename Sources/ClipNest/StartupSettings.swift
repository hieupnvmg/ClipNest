import AppKit
import ServiceManagement
import SwiftUI

final class LoginItemService: ObservableObject {
  static let shared = LoginItemService()
  @Published private(set) var status: SMAppService.Status
  @Published private(set) var error: String?
  private let readStatus: () -> SMAppService.Status
  private let register: () throws -> Void
  private let unregister: () throws -> Void

  init(
    readStatus: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
    register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
    unregister: @escaping () throws -> Void = { try SMAppService.mainApp.unregister() }
  ) {
    self.readStatus = readStatus
    self.register = register
    self.unregister = unregister
    status = readStatus()
  }
  var isRegistered: Bool { status == .enabled || status == .requiresApproval }
  func refresh() { status = readStatus() }
  func setEnabled(_ enabled: Bool) {
    refresh()
    error = nil
    guard enabled != isRegistered else { return }
    do {
      if enabled { try register() } else { try unregister() }
    } catch {
      self.error = "Could not change launch at login: \(error.localizedDescription)"
    }
    refresh() // System state is the source of truth, including failed requests.
  }
}

struct StartupSettings: View {
  @ObservedObject private var service = LoginItemService.shared
  @Environment(\.scenePhase) private var scenePhase
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Startup").font(.headline)
      Toggle("Launch at login", isOn: Binding(
        get: { service.isRegistered }, set: { service.setEnabled($0) }))
      Text("Start ClipNest automatically when you sign in to your Mac.")
        .font(.caption).foregroundStyle(.secondary)
      if service.status == .requiresApproval {
        Text("Allow ClipNest in macOS Login Items to finish enabling this option.")
          .font(.caption).foregroundStyle(.secondary)
        Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
      }
      if let error = service.error { Text(error).font(.caption).foregroundStyle(.red) }
    }
    .onAppear { service.refresh() }
    .onChange(of: scenePhase) { _ in service.refresh() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) {
      _ in service.refresh()
    }
  }
}

// Remember the automatic onboarding request across launches, even when permission is
// denied or a new ad-hoc build loses macOS trust. Explicit Settings requests still work.
enum AccessibilityOnboarding {
  static func consumeAutomaticRequest(trusted: Bool, defaults: UserDefaults) -> Bool {
    let key = "accessibilityOnboardingCompleted"
    if trusted {
      defaults.set(true, forKey: key)
      return false
    }
    guard !defaults.bool(forKey: key) else { return false }
    defaults.set(true, forKey: key)
    return true
  }
}
