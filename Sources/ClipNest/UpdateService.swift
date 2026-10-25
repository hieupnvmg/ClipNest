import AppKit
import Combine
import Sparkle
import SwiftUI

final class UpdateService: NSObject, ObservableObject, SPUUpdaterDelegate {
  static let shared = UpdateService()
  private var controller: SPUStandardUpdaterController!
  private var started = false
  @Published private(set) var canCheckForUpdates = false
  @Published private(set) var automaticallyChecks = false

  private override init() {
    super.init()
    controller = SPUStandardUpdaterController(
      startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
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
    if let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
      let url = URL(string: feed)
    {
      URLCache.shared.removeCachedResponse(for: URLRequest(url: url))
    }
    controller.checkForUpdates(nil)
  }
  func feedURLString(for updater: SPUUpdater) -> String? {
    guard let base = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String else {
      return nil
    }
    return UpdateFeed.freshURL(from: base)?.absoluteString
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

// A fresh, non-identifying query key bypasses stale GitHub edge-cache entries.
// The signed response body is unchanged and still verified by Sparkle.
enum UpdateFeed {
  static func freshURL(from base: String, nonce: String = UUID().uuidString) -> URL? {
    guard var components = URLComponents(string: base), components.scheme == "https",
      components.host != nil
    else { return nil }
    var query = components.queryItems ?? []
    query.removeAll { $0.name == "clipnest_check" }
    query.append(URLQueryItem(name: "clipnest_check", value: nonce))
    components.queryItems = query
    return components.url
  }
}
