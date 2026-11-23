import Foundation

/// Case-folded UTF-8 copies of each clip's text and title, so a search compares raw bytes
/// (memmem) instead of running a locale-aware, case-insensitive string search over the whole
/// history on every keystroke. A copy is made the first time a clip is searched and reused
/// until that clip's text or title changes.
final class SearchIndex {
  private struct Entry {
    let text: String
    let title: String
    let foldedText: [UInt8]
    let foldedTitle: [UInt8]
  }
  private var entries: [UUID: Entry] = [:]

  static func fold(_ value: String) -> [UInt8] {
    Array(value.folding(options: [.caseInsensitive], locale: .current)
      .precomposedStringWithCanonicalMapping.utf8)
  }

  enum Match { case none, prefix, contains }

  /// Where `query` (already folded) appears in the clip's text or title.
  func match(_ clip: Clip, folded query: [UInt8]) -> Match {
    let entry = self.entry(for: clip)
    if entry.foldedText.starts(with: query) || entry.foldedTitle.starts(with: query) { return .prefix }
    if Self.contains(entry.foldedText, query) || Self.contains(entry.foldedTitle, query) { return .contains }
    return .none
  }

  /// Drops copies for clips that are gone, once there are noticeably more copies than clips.
  func prune(keeping clips: [Clip]) {
    guard entries.count > clips.count + 256 else { return }
    let ids = Set(clips.lazy.map(\.id))
    entries = entries.filter { ids.contains($0.key) }
  }

  var count: Int { entries.count }

  /// Folds the whole history on a background queue, so even the first search after launch
  /// only compares bytes. Clips edited in the meantime are folded again when searched.
  func warm(_ clips: [Clip]) {
    let snapshot = clips.map { ($0.id, $0.text, $0.title) }
    DispatchQueue.global(qos: .utility).async {
      let built = snapshot.map { id, text, title in
        (id, Entry(text: text, title: title, foldedText: Self.fold(text), foldedTitle: Self.fold(title)))
      }
      DispatchQueue.main.async {
        for (id, entry) in built where self.entries[id] == nil { self.entries[id] = entry }
      }
    }
  }

  private func entry(for clip: Clip) -> Entry {
    // String equality is instant when both sides share storage, which they do until an edit.
    if let entry = entries[clip.id], entry.text == clip.text, entry.title == clip.title { return entry }
    let entry = Entry(text: clip.text, title: clip.title,
      foldedText: Self.fold(clip.text), foldedTitle: Self.fold(clip.title))
    entries[clip.id] = entry
    return entry
  }

  static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
    if needle.isEmpty { return true }
    if needle.count > haystack.count { return false }
    return haystack.withUnsafeBytes { h in
      needle.withUnsafeBytes { n in memmem(h.baseAddress, h.count, n.baseAddress, n.count) != nil }
    }
  }
}
