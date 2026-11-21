import AppKit
import Combine
import Sparkle
import SwiftUI

final class UpdateService: NSObject, ObservableObject, SPUUpdaterDelegate {
  static let shared = UpdateService()
  let userDriver = ClipNestUpdateDriver()
  private var updater: SPUUpdater!
  private var started = false
  @Published private(set) var canCheckForUpdates = false
  @Published private(set) var automaticallyChecks = false
  @Published private(set) var lastCheck: Date?

  private override init() {
    super.init()
    updater = SPUUpdater(
      hostBundle: .main, applicationBundle: .main, userDriver: userDriver, delegate: self)
    updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main).assign(
      to: &$canCheckForUpdates)
    updater.publisher(for: \.automaticallyChecksForUpdates).receive(on: RunLoop.main)
      .assign(to: &$automaticallyChecks)
    updater.publisher(for: \.lastUpdateCheckDate).receive(on: RunLoop.main)
      .assign(to: &$lastCheck)
  }
  func start() {
    guard !started else { return }
    started = true
    do { try updater.start() } catch { NSLog("ClipNest updater could not start: \(error)") }
  }
  func checkForUpdates() {
    guard canCheckForUpdates else { return }
    if let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
      let url = URL(string: feed)
    {
      URLCache.shared.removeCachedResponse(for: URLRequest(url: url))
    }
    updater.checkForUpdates()
  }
  func feedParameters(for updater: SPUUpdater, sendingSystemProfile: Bool) -> [[String: String]] {
    UpdateFeed.requestParameters()
  }
  var feedHTTPHeaders: [String: String] { updater.httpHeaders ?? [:] }
  func setAutomaticChecks(_ value: Bool) {
    updater.automaticallyChecksForUpdates = value
  }
}

struct UpdateSettings: View {
  @ObservedObject var service = UpdateService.shared
  private var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
  }
  var body: some View {
    Section {
      LabeledContent("Current version") {
        Text(version).monospacedDigit().foregroundStyle(.secondary)
      }
      LabeledContent("Last checked") {
        Text(service.lastCheck.map { $0.formatted(.relative(presentation: .named)) } ?? "Never")
          .foregroundStyle(.secondary)
      }
      Toggle(
        "Check for updates automatically",
        isOn: Binding(get: { service.automaticallyChecks }, set: { service.setAutomaticChecks($0) }))
      HStack {
        Spacer()
        Button("Check for Updates…") { service.checkForUpdates() }
          .disabled(!service.canCheckForUpdates)
      }
    } footer: {
      SettingsFootnote(
        "ClipNest checks GitHub for new versions. Downloads are verified before installation. Update checks never include clipboard contents.")
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

// Keep Sparkle's base feed URL stable; add freshness parameters only to requests.
// Use a direct XML endpoint: Sparkle overrides Accept with application/rss+xml.
// GitHub Contents API would return JSON under that header and fail signature validation.
enum UpdateFeed {
  static func requestParameters(nonce: String = UUID().uuidString) -> [[String: String]] {
    [
      [
        "key": "clipnest_check", "value": nonce, "displayKey": "Update request",
        "displayValue": "One-time refresh",
      ]
    ]
  }
}
