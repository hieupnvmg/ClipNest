import AppKit
import Combine
import Sparkle
import SwiftUI

final class UpdateService: ObservableObject {
  static let shared = UpdateService()
  private let controller: SPUStandardUpdaterController
  private var started = false
  @Published private(set) var canCheckForUpdates = false
  @Published private(set) var automaticallyChecks = false

  private init() {
    controller = SPUStandardUpdaterController(
      startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    controller.updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main).assign(
      to: &$canCheckForUpdates)
    controller.updater.publisher(for: \.automaticallyChecksForUpdates).receive(on: RunLoop.main)
      .assign(to: &$automaticallyChecks)
  }
  func start() {
    guard !started else { return }
    started = true
    controller.startUpdater()
  }
  func checkForUpdates() {
    guard canCheckForUpdates else { return }
    controller.checkForUpdates(nil)
  }
  func setAutomaticChecks(_ value: Bool) {
    controller.updater.automaticallyChecksForUpdates = value
  }
}

struct UpdateSettings: View {
  @ObservedObject var service = UpdateService.shared
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Updates").font(.headline)
        Spacer()
        Button("Check for Updates…") { service.checkForUpdates() }.disabled(
          !service.canCheckForUpdates)
      }
      Toggle(
        "Automatically check for updates",
        isOn: Binding(get: { service.automaticallyChecks }, set: { service.setAutomaticChecks($0) })
      )
      Text(
        "ClipNest checks GitHub for new versions. Downloads are verified before installation. Your clipboard history is never sent."
      ).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
  }
}

struct AppearancePreferences {
  static let defaultOpacity = 0.9
  static func normalize(_ value: Double) -> Double {
    value.isFinite ? min(max(value, 0.35), 1) : defaultOpacity
  }
  static func load(from defaults: UserDefaults) -> Double {
    guard defaults.object(forKey: "backgroundOpacity") != nil else { return defaultOpacity }
    return normalize(defaults.double(forKey: "backgroundOpacity"))
  }
}
