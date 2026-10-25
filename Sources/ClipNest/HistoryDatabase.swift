import CSQLite
import Foundation

struct DatabaseError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

// Opened during Store initialization, then accessed only on Store's serial writer queue.
final class HistoryDatabase {
  private var connection: OpaquePointer?
  private var persisted: [UUID: Clip] = [:]
  private var positions: [UUID: Int] = [:]
  private(set) var writeTransactions = 0
  private(set) var imagePayloadReads = 0
  private(set) var imagePayloadWrites = 0
  let url: URL
  private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  init(url: URL) throws {
    self.url = url
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard
      sqlite3_open_v2(
        url.path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
        nil) == SQLITE_OK
    else {
      let message = failure().message
      if let connection { sqlite3_close(connection) }
      connection = nil
      throw DatabaseError(message: message)
    }
    do {
      sqlite3_busy_timeout(connection, 5000)
      try execute(
        "PRAGMA foreign_keys=ON; PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA secure_delete=ON;"
      )
      let version = try scalar("PRAGMA user_version")
      guard version <= 2 else {
        throw DatabaseError(message: "History database was created by a newer version of ClipNest.")
      }
      if version == 0 {
        try execute(
          """
          BEGIN IMMEDIATE;
          CREATE TABLE IF NOT EXISTS clips (
            id TEXT PRIMARY KEY NOT NULL, copied_at REAL NOT NULL, source TEXT NOT NULL,
            kind TEXT NOT NULL, content TEXT NOT NULL, payload BLOB, board TEXT,
            title TEXT NOT NULL, bundle_id TEXT, html BLOB, image_digest TEXT
          );
          CREATE TABLE IF NOT EXISTS clip_order (
            id TEXT PRIMARY KEY NOT NULL REFERENCES clips(id) ON DELETE CASCADE,
            position INTEGER NOT NULL
          );
          CREATE INDEX IF NOT EXISTS clip_order_position ON clip_order(position);
          CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);
          PRAGMA user_version=2;
          COMMIT;
          """)
      }
      if version == 1 {
        try execute("BEGIN IMMEDIATE; ALTER TABLE clips ADD COLUMN image_digest TEXT; PRAGMA user_version=2; COMMIT;")
      }
      try execute("CREATE TABLE IF NOT EXISTS image_payloads (id TEXT PRIMARY KEY NOT NULL REFERENCES clips(id) ON DELETE CASCADE, payload BLOB NOT NULL)")
      try indexLegacyImages()
    } catch {
      if let connection { sqlite3_close(connection) }
      connection = nil
      throw error
    }
  }
  deinit { if let connection { sqlite3_close(connection) } }
  private func failure() -> DatabaseError {
    DatabaseError(
      message: connection.map { String(cString: sqlite3_errmsg($0)) }
        ?? "Cannot open clipboard database.")
  }
  private func execute(_ sql: String) throws {
    guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
  }
  private func prepare(_ sql: String) throws -> OpaquePointer {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement
    else { throw failure() }
    return statement
  }
  private func scalar(_ sql: String) throws -> Int {
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { throw failure() }
    return Int(sqlite3_column_int64(statement, 0))
  }
  private func bind(_ value: String?, to index: Int32, in statement: OpaquePointer) throws {
    let result: Int32
    if let value {
      result = value.withCString {
        sqlite3_bind_text(statement, index, $0, Int32(value.utf8.count), transient)
      }
    } else {
      result = sqlite3_bind_null(statement, index)
    }
    guard result == SQLITE_OK else { throw failure() }
  }
  private func bind(_ value: Data?, to index: Int32, in statement: OpaquePointer) throws {
    let result: Int32
    if let value {
      if value.isEmpty {
        result = sqlite3_bind_zeroblob(statement, index, 0)
      } else {
        result = value.withUnsafeBytes {
          sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), transient)
        }
      }
    } else {
      result = sqlite3_bind_null(statement, index)
    }
    guard result == SQLITE_OK else { throw failure() }
  }
  private func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
    guard sqlite3_column_type(statement, column) != SQLITE_NULL,
      let bytes = sqlite3_column_text(statement, column)
    else { return nil }
    return String(
      decoding: UnsafeBufferPointer(
        start: bytes, count: Int(sqlite3_column_bytes(statement, column))), as: UTF8.self)
  }
  private func blob(_ statement: OpaquePointer, _ column: Int32) -> Data? {
    guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
    let size = Int(sqlite3_column_bytes(statement, column))
    guard size > 0, let bytes = sqlite3_column_blob(statement, column) else { return Data() }
    return Data(bytes: bytes, count: size)
  }
  private func step(_ statement: OpaquePointer) throws {
    guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    sqlite3_reset(statement)
    sqlite3_clear_bindings(statement)
  }
  func loadAndMigrate() throws -> [Clip] {
    var result = try load(includeImageData: false)
    let migrated =
      try scalar("SELECT COUNT(*) FROM metadata WHERE key='legacy_migration_complete'") > 0
    if !migrated {
      let legacy = url.deletingLastPathComponent().appendingPathComponent("history.json")
      if result.isEmpty && FileManager.default.fileExists(atPath: legacy.path) {
        let old = try JSONDecoder().decode([Clip].self, from: Data(contentsOf: legacy))
        // Import and migration marker are committed in the same transaction.
        try save(old, markMigration: true)
        result = try load(includeImageData: false)
        let backup = url.deletingLastPathComponent().appendingPathComponent("history.json.backup")
        if !FileManager.default.fileExists(atPath: backup.path) {
          // The SQLite commit already succeeded; a backup rename failure must not
          // invalidate it or cause a second import on the next launch.
          try? FileManager.default.moveItem(at: legacy, to: backup)
        }
      } else {
        try save(result, markMigration: true)
      }
    }
    return result
  }
  // Explicit eager mode is retained for diagnostics/export; Store always uses metadata only.
  func load(includeImageData: Bool = true) throws -> [Clip] {
    let payload = includeImageData ? "CASE WHEN c.kind='Image' THEN p.payload ELSE c.payload END" : "CASE WHEN c.kind='Image' THEN NULL ELSE c.payload END"
    let statement = try prepare(
      "SELECT c.id,c.copied_at,c.source,c.kind,c.content,\(payload),c.board,c.title,c.bundle_id,c.html,o.position,c.image_digest,length(p.payload) FROM clips c JOIN clip_order o ON c.id=o.id LEFT JOIN image_payloads p ON p.id=c.id ORDER BY o.position"
    )
    defer { sqlite3_finalize(statement) }
    var result: [Clip] = []
    var loadedPositions: [UUID: Int] = [:]
    var loadedMetadata: [UUID: Clip] = [:]
    while true {
      let status = sqlite3_step(statement)
      if status == SQLITE_DONE { break }
      guard status == SQLITE_ROW, let id = text(statement, 0).flatMap(UUID.init(uuidString:)) else {
        throw failure()
      }
      result.append(
        Clip(
          id: id, date: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 1)),
          source: text(statement, 2) ?? "", kind: text(statement, 3) ?? "Text",
          text: text(statement, 4) ?? "", data: blob(statement, 5), board: text(statement, 6),
          title: text(statement, 7) ?? "", bundleID: text(statement, 8), html: blob(statement, 9)))
      if result[result.count - 1].kind == "Image", let digest = text(statement, 11) {
        let reference = ImageReference(digest: digest, byteCount: Int(sqlite3_column_int64(statement, 12)))
        var metadata = result[result.count - 1]
        metadata.data = nil
        metadata.imageReference = reference
        loadedMetadata[id] = metadata
        if !includeImageData { result[result.count - 1] = metadata }
        else { imagePayloadReads += 1 }
      } else {
        loadedMetadata[id] = result[result.count - 1]
      }
      loadedPositions[id] = Int(sqlite3_column_int64(statement, 10))
    }
    persisted = loadedMetadata
    positions = loadedPositions
    return result
  }
  func save(_ clips: [Clip], markMigration: Bool = false) throws {
    let metadata = clips.map { $0.imageMetadata() }
    // No lock, transaction or statement preparation for an unchanged snapshot.
    // Migration/Clear must still commit their metadata even when history is empty.
    if !markMigration, clips.count == persisted.count,
      metadata.enumerated().allSatisfy({ positions[$0.element.id] == $0.offset && persisted[$0.element.id] == $0.element })
    { return }
    let ids = Set(clips.map(\.id))
    guard ids.count == clips.count else {
      throw DatabaseError(message: "Duplicate clipboard IDs; history has not been modified.")
    }
    try execute("BEGIN IMMEDIATE")
    writeTransactions += 1
    do {
      let remove = try prepare("DELETE FROM clips WHERE id=?")
      defer { sqlite3_finalize(remove) }
      for id in persisted.keys where !ids.contains(id) {
        try bind(id.uuidString, to: 1, in: remove)
        try step(remove)
      }
      let upsert = try prepare(
        """
        INSERT INTO clips(id,copied_at,source,kind,content,payload,board,title,bundle_id,html,image_digest) VALUES(?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET copied_at=excluded.copied_at,source=excluded.source,kind=excluded.kind,content=excluded.content,payload=excluded.payload,board=excluded.board,title=excluded.title,bundle_id=excluded.bundle_id,html=excluded.html,image_digest=excluded.image_digest
        """)
      defer { sqlite3_finalize(upsert) }
      let imageUpsert = try prepare("INSERT INTO image_payloads(id,payload) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload")
      defer { sqlite3_finalize(imageUpsert) }
      let imageRemove = try prepare("DELETE FROM image_payloads WHERE id=?")
      defer { sqlite3_finalize(imageRemove) }
      let imageMetadataUpdate = try prepare(
        "UPDATE clips SET copied_at=?,source=?,content=?,board=?,title=?,bundle_id=?,html=? WHERE id=? AND kind='Image' AND image_digest=?")
      defer { sqlite3_finalize(imageMetadataUpdate) }
      let order = try prepare(
        "INSERT INTO clip_order(id,position) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET position=excluded.position"
      )
      defer { sqlite3_finalize(order) }
      for (index, clip) in clips.enumerated() {
        let compact = metadata[index]
        if persisted[clip.id] != compact {
          if clip.hasDeferredImage || (clip.kind == "Image" && compact.imageReference != nil && persisted[clip.id]?.imageReference == compact.imageReference) {
            guard let reference = compact.imageReference,
              persisted[clip.id]?.imageReference == reference else {
              throw DatabaseError(message: "Stored image is unavailable; history has not been modified.")
            }
            guard sqlite3_bind_double(imageMetadataUpdate, 1, clip.date.timeIntervalSinceReferenceDate) == SQLITE_OK else { throw failure() }
            try bind(clip.source, to: 2, in: imageMetadataUpdate)
            try bind(clip.text, to: 3, in: imageMetadataUpdate)
            try bind(clip.board, to: 4, in: imageMetadataUpdate)
            try bind(clip.title, to: 5, in: imageMetadataUpdate)
            try bind(clip.bundleID, to: 6, in: imageMetadataUpdate)
            try bind(clip.html, to: 7, in: imageMetadataUpdate)
            try bind(clip.id.uuidString, to: 8, in: imageMetadataUpdate)
            try bind(reference.digest, to: 9, in: imageMetadataUpdate)
            try step(imageMetadataUpdate)
            guard sqlite3_changes(connection) == 1 else { throw failure() }
          } else {
            try bind(clip.id.uuidString, to: 1, in: upsert)
            guard
              sqlite3_bind_double(upsert, 2, clip.date.timeIntervalSinceReferenceDate) == SQLITE_OK
            else { throw failure() }
            try bind(clip.source, to: 3, in: upsert)
            try bind(clip.kind, to: 4, in: upsert)
            try bind(clip.text, to: 5, in: upsert)
            try bind(clip.kind == "Image" ? nil as Data? : clip.data, to: 6, in: upsert)
            try bind(clip.board, to: 7, in: upsert)
            try bind(clip.title, to: 8, in: upsert)
            try bind(clip.bundleID, to: 9, in: upsert)
            try bind(clip.html, to: 10, in: upsert)
            try bind(compact.imageReference?.digest, to: 11, in: upsert)
            try step(upsert)
            if clip.kind == "Image", let data = clip.data {
              try bind(clip.id.uuidString, to: 1, in: imageUpsert)
              try bind(data, to: 2, in: imageUpsert)
              try step(imageUpsert)
              imagePayloadWrites += 1
            } else if persisted[clip.id]?.kind == "Image" {
              try bind(clip.id.uuidString, to: 1, in: imageRemove)
              try step(imageRemove)
            }
          }
        }
        if positions[clip.id] != index {
          try bind(clip.id.uuidString, to: 1, in: order)
          guard sqlite3_bind_int64(order, 2, Int64(index)) == SQLITE_OK else { throw failure() }
          try step(order)
        }
      }
      if markMigration {
        try execute(
          "INSERT OR REPLACE INTO metadata(key,value) VALUES('legacy_migration_complete','1')")
      }
      try execute("COMMIT")
      persisted = Dictionary(uniqueKeysWithValues: metadata.map { ($0.id, $0) })
      positions = Dictionary(
        uniqueKeysWithValues: clips.enumerated().map { ($0.element.id, $0.offset) })
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }
  var imageReferences: [UUID: ImageReference] {
    persisted.compactMapValues { $0.imageReference }
  }
  func imageData(for id: UUID, expected: ImageReference? = nil) throws -> Data {
    let statement = try prepare("SELECT COALESCE(p.payload,c.payload),c.image_digest FROM clips c LEFT JOIN image_payloads p ON p.id=c.id WHERE c.id=? AND c.kind='Image'")
    defer { sqlite3_finalize(statement) }
    try bind(id.uuidString, to: 1, in: statement)
    guard sqlite3_step(statement) == SQLITE_ROW, let data = blob(statement, 0),
      expected == nil || (text(statement, 1) == expected?.digest && data.count == expected?.byteCount)
    else { throw DatabaseError(message: "This image is no longer available in clipboard history.") }
    imagePayloadReads += 1
    return data
  }
  private func indexLegacyImages() throws {
    let select = try prepare("SELECT id FROM clips WHERE kind='Image' AND payload IS NOT NULL ORDER BY rowid")
    var ids: [UUID] = []
    while true {
      let status = sqlite3_step(select)
      if status == SQLITE_DONE { break }
      guard status == SQLITE_ROW, let id = text(select, 0).flatMap(UUID.init(uuidString:)) else {
        sqlite3_finalize(select)
        throw failure()
      }
      ids.append(id)
    }
    sqlite3_finalize(select)
    guard !ids.isEmpty else { return }
    let update = try prepare("UPDATE clips SET image_digest=?,payload=NULL WHERE id=?")
    defer { sqlite3_finalize(update) }
    let move = try prepare("INSERT INTO image_payloads(id,payload) SELECT id,payload FROM clips WHERE id=?")
    defer { sqlite3_finalize(move) }
    // Commit each move atomically to bound dirty-page memory. An interrupted
    // upgrade resumes from rows that still contain their original inline payload.
    for id in ids {
      try execute("BEGIN IMMEDIATE")
      do {
        let reference = try autoreleasepool { ImageReference(data: try imageData(for: id)) }
        try bind(id.uuidString, to: 1, in: move)
        try step(move)
        try bind(reference.digest, to: 1, in: update)
        try bind(id.uuidString, to: 2, in: update)
        try step(update)
        try execute("COMMIT")
      } catch { try? execute("ROLLBACK"); throw error }
    }
    try execute("PRAGMA shrink_memory")
  }

  func clear() throws {
    // Remove JSON backup too: Clear must not leave old clipboard contents behind.
    for name in ["history.json", "history.json.backup"] {
      let old = url.deletingLastPathComponent().appendingPathComponent(name)
      if FileManager.default.fileExists(atPath: old.path) {
        try FileManager.default.removeItem(at: old)
      }
    }
    try save([], markMigration: true)
    try? execute("PRAGMA wal_checkpoint(TRUNCATE); VACUUM; PRAGMA wal_checkpoint(TRUNCATE);")
  }
  var totalChanges: Int32 { sqlite3_total_changes(connection) }
  func checkpoint() throws { try execute("PRAGMA wal_checkpoint(TRUNCATE)") }
  var storageBytes: Int64 {
    [
      url.path, url.path + "-wal", url.path + "-shm",
      url.deletingLastPathComponent().appendingPathComponent("history.json").path,
      url.deletingLastPathComponent().appendingPathComponent("history.json.backup").path,
    ].reduce(0) {
      $0
        + (((try? FileManager.default.attributesOfItem(atPath: $1)[.size]) as? NSNumber)?.int64Value
          ?? 0)
    }
  }
}
