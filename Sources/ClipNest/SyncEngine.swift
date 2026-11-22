import CommonCrypto
import CryptoKit
import Foundation

/// Syncs pinned clips between Macs through a plain folder in the user's iCloud Drive.
///
/// No entitlement or developer account is needed: iCloud Drive syncs the folder itself.
/// SQLite is never placed there. Each synced clip is one small encrypted file
/// (`items/<id>.cnsync`), written whole and atomically, so two Macs never edit the same
/// database. Every file is sealed with AES-GCM using a key derived from a sync passphrase
/// the user enters on each Mac; iCloud only ever stores ciphertext.
enum SyncError: LocalizedError {
  case iCloudDriveUnavailable, wrongPassphrase, passphraseTooShort, notSetUp, alreadySetUp, corrupt
  var errorDescription: String? {
    switch self {
    case .iCloudDriveUnavailable: return "iCloud Drive is not turned on for this Mac."
    case .wrongPassphrase: return "That sync passphrase does not match the one used on your other Mac."
    case .passphraseTooShort: return "Use a sync passphrase of at least 8 characters."
    case .notSetUp: return "Sync is not set up on this Mac."
    case .alreadySetUp: return "Sync was already set up from another Mac. Enter its passphrase to join."
    case .corrupt: return "A sync file could not be read."
    }
  }
}

/// The content of one synced clip, as stored (encrypted) in iCloud Drive.
struct SyncClip: Codable, Equatable {
  var date: Date
  var source: String
  var kind: String
  var text: String
  var title: String
  var board: String
  var bundleID: String?
  var rtf: Data?
  var html: Data?
  var image: Data?
}

/// One file in `items/`: the latest state of a clip, or a tombstone once it left sync.
struct SyncRecord: Codable {
  var id: UUID
  var modified: Date
  var device: String
  var clip: SyncClip?
}

/// A local clip offered for sync. Images are loaded only when they need uploading.
struct SyncCandidate {
  var id: UUID
  var clip: SyncClip
  var imageDigest: String?
  var loadImage: (() throws -> Data)?
  /// Identifies this content without reading image bytes.
  var fingerprint: String {
    var copy = clip
    copy.image = nil
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    encoder.dateEncodingStrategy = .secondsSince1970
    let data = (try? encoder.encode(copy)) ?? Data()
    return SHA256.hash(data: data + Data((imageDigest ?? "").utf8))
      .map { String(format: "%02x", $0) }.joined()
  }
}

/// What the local history should do after a sync pass.
enum SyncChange: Equatable {
  case upsert(UUID, SyncClip)
  /// The clip left sync on another Mac: keep it in history, just unpin it.
  case unpin(UUID)
}

struct SyncOutcome {
  var changes: [SyncChange] = []
  var boards: [String] = []
  var uploaded = 0
  var syncedCount = 0
}

final class SyncEngine {
  struct Vault: Codable {
    var version = 1
    var salt: Data
    var iterations: Int
    var check: Data
  }
  private struct LocalState: Codable {
    struct Entry: Codable {
      var modified: Date
      var fingerprint: String?
    }
    var device = UUID().uuidString
    var entries: [UUID: Entry] = [:]
    var seen: [String: Date] = [:]
    var boards: [String] = []
  }

  static let checkPlaintext = Data("clipnest-sync-v1".utf8)
  static let iterations = 600_000
  /// Images above this size stay on this Mac.
  static let maxImageBytes = 10 * 1024 * 1024
  static var iCloudDriveFolder: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
  }

  let cloud: URL
  private let local: URL
  private var key: SymmetricKey?
  private var state = LocalState()
  /// Last bytes written to sync-state.json; unchanged passes skip the disk write.
  private var savedState: Data?
  private let now: () -> Date

  /// - Parameters:
  ///   - cloud: the shared folder (`ClipNest Sync` in iCloud Drive).
  ///   - local: this Mac's private folder for the key and sync bookkeeping.
  init(cloud: URL, local: URL, now: @escaping () -> Date = Date.init) {
    self.cloud = cloud
    self.local = local
    self.now = now
    if let data = try? Data(contentsOf: keyURL), data.count == 32 { key = SymmetricKey(data: data) }
    if let data = try? Data(contentsOf: stateURL),
      let saved = try? JSONDecoder().decode(LocalState.self, from: data)
    {
      state = saved
    }
  }

  private var keyURL: URL { local.appendingPathComponent("sync.key") }
  private var stateURL: URL { local.appendingPathComponent("sync-state.json") }
  private var vaultURL: URL { cloud.appendingPathComponent("vault.json") }
  private var itemsURL: URL { cloud.appendingPathComponent("items", isDirectory: true) }
  private var boardsURL: URL { cloud.appendingPathComponent("boards.cnsync") }

  var isConfigured: Bool { key != nil }
  var vaultExists: Bool { FileManager.default.fileExists(atPath: vaultURL.path) }
  var cloudAvailable: Bool {
    FileManager.default.fileExists(atPath: cloud.deletingLastPathComponent().path)
  }

  // MARK: Setup

  /// Creates the shared vault from this Mac (first Mac only).
  func create(passphrase: String) throws {
    guard passphrase.count >= 8 else { throw SyncError.passphraseTooShort }
    guard cloudAvailable else { throw SyncError.iCloudDriveUnavailable }
    guard !vaultExists else { throw SyncError.alreadySetUp }
    var salt = Data(count: 16)
    _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
    let derived = Self.deriveKey(passphrase, salt: salt, iterations: Self.iterations)
    let check = try AES.GCM.seal(Self.checkPlaintext, using: derived).combined!
    try FileManager.default.createDirectory(at: itemsURL, withIntermediateDirectories: true)
    let vault = Vault(salt: salt, iterations: Self.iterations, check: check)
    try JSONEncoder().encode(vault).write(to: vaultURL, options: .atomic)
    try store(key: derived)
  }

  /// Joins a vault created on another Mac.
  func join(passphrase: String) throws {
    guard cloudAvailable else { throw SyncError.iCloudDriveUnavailable }
    guard let data = try? Data(contentsOf: vaultURL),
      let vault = try? JSONDecoder().decode(Vault.self, from: data)
    else { throw SyncError.notSetUp }
    let derived = Self.deriveKey(passphrase, salt: vault.salt, iterations: vault.iterations)
    guard let box = try? AES.GCM.SealedBox(combined: vault.check),
      (try? AES.GCM.open(box, using: derived)) == Self.checkPlaintext
    else { throw SyncError.wrongPassphrase }
    try FileManager.default.createDirectory(at: itemsURL, withIntermediateDirectories: true)
    try store(key: derived)
  }

  /// Stops syncing on this Mac. Data in iCloud Drive and local history are kept.
  func leave() {
    key = nil
    state = LocalState()
    try? FileManager.default.removeItem(at: keyURL)
    try? FileManager.default.removeItem(at: stateURL)
  }

  private func store(key derived: SymmetricKey) throws {
    try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
    let raw = derived.withUnsafeBytes { Data($0) }
    // Same protection as the local history database it guards: readable by this user only.
    FileManager.default.createFile(
      atPath: keyURL.path, contents: raw, attributes: [.posixPermissions: 0o600])
    key = derived
    state = LocalState()
    try saveState()
  }

  static func deriveKey(_ passphrase: String, salt: Data, iterations: Int) -> SymmetricKey {
    var derived = [UInt8](repeating: 0, count: 32)
    let password = Array(passphrase.precomposedStringWithCanonicalMapping.utf8)
    _ = salt.withUnsafeBytes { saltBytes in
      CCKeyDerivationPBKDF(
        CCPBKDFAlgorithm(kCCPBKDF2), password.map { CChar(bitPattern: $0) }, password.count,
        saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations), &derived, derived.count)
    }
    return SymmetricKey(data: derived)
  }

  // MARK: Sync pass

  /// Imports newer records from other Macs, then uploads local changes and tombstones.
  /// `local` is every clip this Mac wants in sync; `dirty` are ids changed locally since
  /// the last pass (a local edit wins over an older remote one).
  func sync(local candidates: [SyncCandidate], boards localBoards: [String]) throws -> SyncOutcome {
    guard let key else { throw SyncError.notSetUp }
    try FileManager.default.createDirectory(at: itemsURL, withIntermediateDirectories: true)
    var outcome = SyncOutcome()
    let byID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })

    // 1. Import records written by other Macs since the last pass.
    let files = (try? FileManager.default.contentsOfDirectory(
      at: itemsURL, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
    for file in files {
      let name = file.lastPathComponent
      if name.hasPrefix("."), name.hasSuffix(".icloud") {
        // Not downloaded yet ("Optimize Mac Storage"): ask iCloud for it, read next pass.
        try? FileManager.default.startDownloadingUbiquitousItem(at: file)
        continue
      }
      guard name.hasSuffix(".cnsync"), let id = UUID(uuidString: String(name.dropLast(7))) else {
        continue
      }
      let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
        .contentModificationDate ?? .distantPast
      if let seen = state.seen[name], seen >= modified { continue }
      guard let record = try? open(file, id: id), record.id == id else { continue }
      state.seen[name] = modified
      guard record.device != state.device else { continue }
      let known = state.entries[id]
      if let known, known.modified >= record.modified { continue }
      // Unsynced local edit: keep it; it is uploaded below with a newer timestamp.
      if let candidate = byID[id], let known, candidate.fingerprint != known.fingerprint { continue }
      if let clip = record.clip {
        outcome.changes.append(.upsert(id, clip))
        var incoming = SyncCandidate(id: id, clip: clip, imageDigest: nil)
        if let image = clip.image { incoming.imageDigest = ImageReference(data: image).digest }
        state.entries[id] = .init(modified: record.modified, fingerprint: incoming.fingerprint)
      } else {
        if byID[id] != nil { outcome.changes.append(.unpin(id)) }
        state.entries[id] = .init(modified: record.modified, fingerprint: nil)
      }
    }
    let applied = Set(outcome.changes.map { change -> UUID in
      switch change { case .upsert(let id, _), .unpin(let id): return id }
    })

    // 2. Upload local clips that are new or changed.
    for candidate in candidates where !applied.contains(candidate.id) {
      let fingerprint = candidate.fingerprint
      if state.entries[candidate.id]?.fingerprint == fingerprint { continue }
      var clip = candidate.clip
      if let load = candidate.loadImage {
        guard let image = try? load(), image.count <= Self.maxImageBytes else { continue }
        clip.image = image
      }
      let record = SyncRecord(id: candidate.id, modified: now(), device: state.device, clip: clip)
      try write(record, key: key)
      state.entries[candidate.id] = .init(modified: record.modified, fingerprint: fingerprint)
      outcome.uploaded += 1
    }

    // 3. Clips that left sync here (unpinned, deleted, now sensitive): write tombstones.
    for (id, entry) in state.entries where entry.fingerprint != nil && byID[id] == nil
      && !applied.contains(id)
    {
      let record = SyncRecord(id: id, modified: now(), device: state.device, clip: nil)
      try write(record, key: key)
      state.entries[id] = .init(modified: record.modified, fingerprint: nil)
      outcome.uploaded += 1
    }

    // 4. Pinboard names: a union across Macs (removing a board stays local for now).
    var boards = state.boards
    if let data = try? Data(contentsOf: boardsURL), let remote = try? openBoards(data) {
      for name in remote where !boards.contains(name) { boards.append(name) }
    }
    for name in localBoards where !boards.contains(name) { boards.append(name) }
    if boards != state.boards || !FileManager.default.fileExists(atPath: boardsURL.path) {
      try seal(JSONEncoder().encode(boards), key: key, aad: Data("boards".utf8))
        .write(to: boardsURL, options: .atomic)
    }
    state.boards = boards
    outcome.boards = boards.filter { !localBoards.contains($0) }
    outcome.syncedCount = state.entries.values.filter { $0.fingerprint != nil }.count
    try saveState()
    return outcome
  }

  // MARK: Files

  private static let magic = Data("CNS1".utf8)
  private func seal(_ plaintext: Data, key: SymmetricKey, aad: Data) throws -> Data {
    Self.magic + (try AES.GCM.seal(plaintext, using: key, authenticating: aad).combined!)
  }
  private func unseal(_ data: Data, aad: Data) throws -> Data {
    guard let key, data.starts(with: Self.magic),
      let box = try? AES.GCM.SealedBox(combined: data.dropFirst(Self.magic.count))
    else { throw SyncError.corrupt }
    return try AES.GCM.open(box, using: key, authenticating: aad)
  }
  private func write(_ record: SyncRecord, key: SymmetricKey) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    // The record id is authenticated, so a file cannot be swapped onto another clip.
    let sealed = try seal(encoder.encode(record), key: key, aad: Data(record.id.uuidString.utf8))
    let url = itemsURL.appendingPathComponent("\(record.id.uuidString).cnsync")
    try sealed.write(to: url, options: .atomic)
    if let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
      .contentModificationDate
    {
      state.seen[url.lastPathComponent] = modified
    }
  }
  private func open(_ url: URL, id: UUID) throws -> SyncRecord {
    let plaintext = try unseal(Data(contentsOf: url), aad: Data(id.uuidString.utf8))
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    return try decoder.decode(SyncRecord.self, from: plaintext)
  }
  private func openBoards(_ data: Data) throws -> [String] {
    try JSONDecoder().decode([String].self, from: unseal(data, aad: Data("boards".utf8)))
  }
  private func saveState() throws {
    let data = try JSONEncoder().encode(state)
    guard data != savedState else { return }
    try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
    try data.write(to: stateURL, options: .atomic)
    savedState = data
  }
}

struct SyncStatus: Equatable {
  var configured = false
  var vaultExists = false
  var cloudAvailable = false
  var busy = false
  var lastSync: Date?
  var synced = 0
  var error: String?
}
