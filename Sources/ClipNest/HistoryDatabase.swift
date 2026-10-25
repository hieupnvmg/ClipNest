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
      guard version <= 1 else {
        throw DatabaseError(message: "History database was created by a newer version of ClipNest.")
      }
      if version == 0 {
        try execute(
          """
          BEGIN IMMEDIATE;
          CREATE TABLE IF NOT EXISTS clips (
            id TEXT PRIMARY KEY NOT NULL, copied_at REAL NOT NULL, source TEXT NOT NULL,
            kind TEXT NOT NULL, content TEXT NOT NULL, payload BLOB, board TEXT,
            title TEXT NOT NULL, bundle_id TEXT, html BLOB
          );
          CREATE TABLE IF NOT EXISTS clip_order (
            id TEXT PRIMARY KEY NOT NULL REFERENCES clips(id) ON DELETE CASCADE,
            position INTEGER NOT NULL
          );
          CREATE INDEX IF NOT EXISTS clip_order_position ON clip_order(position);
          CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);
          PRAGMA user_version=1;
          COMMIT;
          """)
      }
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
    var result = try load()
    let migrated =
      try scalar("SELECT COUNT(*) FROM metadata WHERE key='legacy_migration_complete'") > 0
    if !migrated {
      let legacy = url.deletingLastPathComponent().appendingPathComponent("history.json")
      if result.isEmpty && FileManager.default.fileExists(atPath: legacy.path) {
        let old = try JSONDecoder().decode([Clip].self, from: Data(contentsOf: legacy))
        // Import and migration marker are committed in the same transaction.
        try save(old, markMigration: true)
        result = old
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
  func load() throws -> [Clip] {
    let statement = try prepare(
      "SELECT c.id,c.copied_at,c.source,c.kind,c.content,c.payload,c.board,c.title,c.bundle_id,c.html,o.position FROM clips c JOIN clip_order o ON c.id=o.id ORDER BY o.position"
    )
    defer { sqlite3_finalize(statement) }
    var result: [Clip] = []
    var loadedPositions: [UUID: Int] = [:]
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
      loadedPositions[id] = Int(sqlite3_column_int64(statement, 10))
    }
    persisted = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
    positions = loadedPositions
    return result
  }
  func save(_ clips: [Clip], markMigration: Bool = false) throws {
    let ids = Set(clips.map(\.id))
    guard ids.count == clips.count else {
      throw DatabaseError(message: "Duplicate clipboard IDs; history has not been modified.")
    }
    try execute("BEGIN IMMEDIATE")
    do {
      let remove = try prepare("DELETE FROM clips WHERE id=?")
      defer { sqlite3_finalize(remove) }
      for id in persisted.keys where !ids.contains(id) {
        try bind(id.uuidString, to: 1, in: remove)
        try step(remove)
      }
      let upsert = try prepare(
        """
        INSERT INTO clips(id,copied_at,source,kind,content,payload,board,title,bundle_id,html) VALUES(?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET copied_at=excluded.copied_at,source=excluded.source,kind=excluded.kind,content=excluded.content,payload=excluded.payload,board=excluded.board,title=excluded.title,bundle_id=excluded.bundle_id,html=excluded.html
        """)
      defer { sqlite3_finalize(upsert) }
      let order = try prepare(
        "INSERT INTO clip_order(id,position) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET position=excluded.position"
      )
      defer { sqlite3_finalize(order) }
      for (index, clip) in clips.enumerated() {
        if persisted[clip.id] != clip {
          try bind(clip.id.uuidString, to: 1, in: upsert)
          guard
            sqlite3_bind_double(upsert, 2, clip.date.timeIntervalSinceReferenceDate) == SQLITE_OK
          else { throw failure() }
          try bind(clip.source, to: 3, in: upsert)
          try bind(clip.kind, to: 4, in: upsert)
          try bind(clip.text, to: 5, in: upsert)
          try bind(clip.data, to: 6, in: upsert)
          try bind(clip.board, to: 7, in: upsert)
          try bind(clip.title, to: 8, in: upsert)
          try bind(clip.bundleID, to: 9, in: upsert)
          try bind(clip.html, to: 10, in: upsert)
          try step(upsert)
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
      persisted = Dictionary(uniqueKeysWithValues: clips.map { ($0.id, $0) })
      positions = Dictionary(
        uniqueKeysWithValues: clips.enumerated().map { ($0.element.id, $0.offset) })
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
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
