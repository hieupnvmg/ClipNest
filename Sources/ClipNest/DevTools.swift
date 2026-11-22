import CryptoKit
import Foundation

/// JSON that keeps object keys in their original order (Foundation's parser does not),
/// so formatting and YAML conversion read like the input.
indirect enum JSONValue: Equatable {
  case object([(String, JSONValue)])
  case array([JSONValue])
  case string(String)
  case number(String)
  case bool(Bool)
  case null

  static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
    switch (lhs, rhs) {
    case (.object(let a), .object(let b)):
      return a.count == b.count && zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
    case (.array(let a), .array(let b)): return a == b
    case (.string(let a), .string(let b)): return a == b
    case (.number(let a), .number(let b)): return a == b
    case (.bool(let a), .bool(let b)): return a == b
    case (.null, .null): return true
    default: return false
    }
  }

  struct ParseError: LocalizedError {
    let message: String
    let offset: Int
    var errorDescription: String? { "\(message) at character \(offset + 1)" }
  }

  /// Parses one JSON value; trailing text is allowed only when `allowTrailing` is true.
  static func parse(_ text: String, allowTrailing: Bool = false) throws -> (JSONValue, Int) {
    var parser = Parser(bytes: Array(text.utf8))
    parser.skipSpace()
    let value = try parser.value(depth: 0)
    parser.skipSpace()
    if !allowTrailing, parser.index < parser.bytes.count {
      throw ParseError(message: "Unexpected text after JSON", offset: parser.index)
    }
    return (value, parser.index)
  }

  private struct Parser {
    let bytes: [UInt8]
    var index = 0
    mutating func skipSpace() {
      while index < bytes.count, [0x20, 0x0A, 0x0D, 0x09].contains(bytes[index]) { index += 1 }
    }
    func fail(_ message: String) -> ParseError { ParseError(message: message, offset: index) }
    mutating func expect(_ literal: String) throws {
      let utf8 = Array(literal.utf8)
      guard index + utf8.count <= bytes.count, Array(bytes[index..<index + utf8.count]) == utf8
      else { throw fail("Expected \(literal)") }
      index += utf8.count
    }
    mutating func value(depth: Int) throws -> JSONValue {
      guard depth < 512 else { throw fail("JSON is nested too deeply") }
      guard index < bytes.count else { throw fail("Unexpected end of JSON") }
      switch bytes[index] {
      case UInt8(ascii: "{"):
        index += 1
        var members: [(String, JSONValue)] = []
        skipSpace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "}") { index += 1; return .object(members) }
        while true {
          skipSpace()
          guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw fail("Expected a quoted key") }
          let key = try string()
          skipSpace()
          try expect(":")
          skipSpace()
          members.append((key, try value(depth: depth + 1)))
          skipSpace()
          guard index < bytes.count else { throw fail("Unexpected end of JSON") }
          if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
          if bytes[index] == UInt8(ascii: "}") { index += 1; return .object(members) }
          throw fail("Expected , or }")
        }
      case UInt8(ascii: "["):
        index += 1
        var items: [JSONValue] = []
        skipSpace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
        while true {
          skipSpace()
          items.append(try value(depth: depth + 1))
          skipSpace()
          guard index < bytes.count else { throw fail("Unexpected end of JSON") }
          if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
          if bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
          throw fail("Expected , or ]")
        }
      case UInt8(ascii: "\""): return .string(try string())
      case UInt8(ascii: "t"): try expect("true"); return .bool(true)
      case UInt8(ascii: "f"): try expect("false"); return .bool(false)
      case UInt8(ascii: "n"): try expect("null"); return .null
      default: return .number(try number())
      }
    }
    mutating func number() throws -> String {
      let start = index
      if index < bytes.count, bytes[index] == UInt8(ascii: "-") { index += 1 }
      func digits() -> Int {
        let begin = index
        while index < bytes.count, (48...57).contains(bytes[index]) { index += 1 }
        return index - begin
      }
      guard digits() > 0 else { throw fail("Unexpected character") }
      if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
        index += 1
        guard digits() > 0 else { throw fail("Expected digits after .") }
      }
      if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
        index += 1
        if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") { index += 1 }
        guard digits() > 0 else { throw fail("Expected exponent digits") }
      }
      return String(decoding: bytes[start..<index], as: UTF8.self)
    }
    mutating func string() throws -> String {
      index += 1
      var scalars = String.UnicodeScalarView()
      var raw: [UInt8] = []
      func flush() {
        scalars.append(contentsOf: String(decoding: raw, as: UTF8.self).unicodeScalars)
        raw.removeAll()
      }
      while index < bytes.count {
        let byte = bytes[index]
        if byte == UInt8(ascii: "\"") { index += 1; flush(); return String(scalars) }
        if byte < 0x20 { throw fail("Control character in string") }
        if byte != UInt8(ascii: "\\") { raw.append(byte); index += 1; continue }
        flush()
        index += 1
        guard index < bytes.count else { break }
        let escape = bytes[index]
        index += 1
        switch escape {
        case UInt8(ascii: "\""): scalars.append("\"")
        case UInt8(ascii: "\\"): scalars.append("\\")
        case UInt8(ascii: "/"): scalars.append("/")
        case UInt8(ascii: "b"): scalars.append("\u{08}")
        case UInt8(ascii: "f"): scalars.append("\u{0C}")
        case UInt8(ascii: "n"): scalars.append("\n")
        case UInt8(ascii: "r"): scalars.append("\r")
        case UInt8(ascii: "t"): scalars.append("\t")
        case UInt8(ascii: "u"):
          var code = try hex4()
          if (0xD800...0xDBFF).contains(code), index + 1 < bytes.count,
            bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u")
          {
            index += 2
            let low = try hex4()
            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
          }
          scalars.append(Unicode.Scalar(code) ?? "\u{FFFD}")
        default: throw fail("Invalid escape")
        }
      }
      throw fail("Unterminated string")
    }
    mutating func hex4() throws -> UInt32 {
      guard index + 4 <= bytes.count,
        let value = UInt32(String(decoding: bytes[index..<index + 4], as: UTF8.self), radix: 16)
      else { throw fail("Invalid \\u escape") }
      index += 4
      return value
    }
  }

  func formatted(indent: Int = 0, step: Int = 2) -> String {
    let pad = String(repeating: " ", count: indent + step)
    let close = String(repeating: " ", count: indent)
    switch self {
    case .object(let members):
      guard !members.isEmpty else { return "{}" }
      let body = members.map { "\(pad)\(JSONValue.quote($0.0)): \($0.1.formatted(indent: indent + step, step: step))" }
      return "{\n" + body.joined(separator: ",\n") + "\n\(close)}"
    case .array(let items):
      guard !items.isEmpty else { return "[]" }
      return "[\n" + items.map { pad + $0.formatted(indent: indent + step, step: step) }
        .joined(separator: ",\n") + "\n\(close)]"
    default: return minified
    }
  }
  var minified: String {
    switch self {
    case .object(let members):
      return "{" + members.map { "\(JSONValue.quote($0.0)):\($0.1.minified)" }.joined(separator: ",") + "}"
    case .array(let items): return "[" + items.map(\.minified).joined(separator: ",") + "]"
    case .string(let value): return JSONValue.quote(value)
    case .number(let value): return value
    case .bool(let value): return value ? "true" : "false"
    case .null: return "null"
    }
  }
  static func quote(_ text: String) -> String {
    var result = "\""
    for scalar in text.unicodeScalars {
      switch scalar {
      case "\"": result += "\\\""
      case "\\": result += "\\\\"
      case "\n": result += "\\n"
      case "\r": result += "\\r"
      case "\t": result += "\\t"
      case _ where scalar.value < 0x20: result += String(format: "\\u%04x", scalar.value)
      default: result.unicodeScalars.append(scalar)
      }
    }
    return result + "\""
  }

  // MARK: YAML

  var yaml: String {
    switch self {
    case .object(let members) where !members.isEmpty: return yamlLines(indent: 0).joined(separator: "\n")
    case .array(let items) where !items.isEmpty: return yamlLines(indent: 0).joined(separator: "\n")
    default: return yamlScalar(indent: 0)
    }
  }
  private func yamlLines(indent: Int) -> [String] {
    let pad = String(repeating: " ", count: indent)
    switch self {
    case .object(let members):
      return members.flatMap { key, value -> [String] in
        let name = JSONValue.yamlKey(key)
        switch value {
        case .object(let inner) where !inner.isEmpty:
          return ["\(pad)\(name):"] + value.yamlLines(indent: indent + 2)
        case .array(let inner) where !inner.isEmpty:
          return ["\(pad)\(name):"] + value.yamlLines(indent: indent)
        default:
          return ["\(pad)\(name): \(value.yamlScalar(indent: indent + 2))"]
        }
      }
    case .array(let items):
      return items.flatMap { item -> [String] in
        func nested() -> [String] {
          var lines = item.yamlLines(indent: indent + 2)
          let first = lines.removeFirst().dropFirst(indent + 2)
          return ["\(pad)- \(first)"] + lines
        }
        switch item {
        case .object(let inner) where !inner.isEmpty: return nested()
        case .array(let inner) where !inner.isEmpty: return nested()
        default: return ["\(pad)- \(item.yamlScalar(indent: indent + 2))"]
        }
      }
    default:
      return [pad + yamlScalar(indent: indent)]
    }
  }
  private func yamlScalar(indent: Int) -> String {
    switch self {
    case .object: return "{}"
    case .array: return "[]"
    case .number(let value): return value
    case .bool(let value): return value ? "true" : "false"
    case .null: return "null"
    case .string(let value):
      if value.contains("\n"), !value.hasSuffix(" ") {
        let pad = String(repeating: " ", count: indent)
        let chomp = value.hasSuffix("\n") ? "" : "-"
        let body = value.hasSuffix("\n") ? String(value.dropLast()) : value
        return "|\(chomp)\n" + body.split(separator: "\n", omittingEmptySubsequences: false)
          .map { $0.isEmpty ? "" : pad + $0 }.joined(separator: "\n")
      }
      return JSONValue.yamlNeedsQuotes(value) ? JSONValue.quote(value) : value
    }
  }
  private static func yamlKey(_ key: String) -> String { yamlNeedsQuotes(key) ? quote(key) : key }
  static func yamlNeedsQuotes(_ value: String) -> Bool {
    if value.isEmpty || value != value.trimmingCharacters(in: .whitespaces) { return true }
    let reserved: Set<String> = [
      "true", "false", "yes", "no", "on", "off", "null", "~", "y", "n",
    ]
    if reserved.contains(value.lowercased()) || Double(value) != nil { return true }
    if let first = value.unicodeScalars.first, "-?:,[]{}#&*!|>'\"%@`".unicodeScalars.contains(first) {
      return true
    }
    return value.contains(": ") || value.contains(" #") || value.hasSuffix(":")
      || value.unicodeScalars.contains { $0.value < 0x20 }
  }
}

/// One-click conversions offered on text clips. Detection is cheap (prefix and character
/// checks) because the card menu is built while rendering; the work runs only on click.
enum DevTransform: String, CaseIterable, Identifiable {
  case jsonPretty, jsonMinify, jsonToYAML
  case jwtDecode, base64Decode, base64Encode, urlDecode, urlEncode
  case timestamp, sha256
  case stripANSI, joinLines, shellQuote, jsonEscape
  case ansibleError, ansibleRetry, ansibleDryRun

  var id: String { rawValue }
  var title: String {
    switch self {
    case .jsonPretty: return "Format JSON"
    case .jsonMinify: return "Minify JSON"
    case .jsonToYAML: return "Convert JSON to YAML"
    case .jwtDecode: return "Decode JWT"
    case .base64Decode: return "Decode Base64"
    case .base64Encode: return "Encode Base64"
    case .urlDecode: return "Decode URL"
    case .urlEncode: return "Encode for URL"
    case .timestamp: return "Convert Unix Timestamp"
    case .sha256: return "SHA-256 Hash"
    case .stripANSI: return "Remove Terminal Colors"
    case .joinLines: return "Join Lines"
    case .shellQuote: return "Quote for Shell"
    case .jsonEscape: return "Escape as JSON String"
    case .ansibleError: return "Readable Ansible Error"
    case .ansibleRetry: return "Copy Retry Command for Failed Hosts"
    case .ansibleDryRun: return "Copy as Dry Run (--check --diff)"
    }
  }
  /// Largest clip offered transforms; bigger texts are logs better handled elsewhere.
  static let maxBytes = 512 * 1024

  static func available(for text: String) -> [DevTransform] {
    guard !text.isEmpty, text.utf8.count <= maxBytes else { return [] }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    var result: [DevTransform] = []
    if AnsibleOutput.hasFailure(text) { result.append(.ansibleError) }
    if AnsibleOutput.hasRecap(text) { result.append(.ansibleRetry) }
    if trimmed.contains("ansible-playbook"), let command = AnsibleCommand.parse(trimmed),
      command.tool == "ansible-playbook", !command.check || !command.diff
    {
      result.append(.ansibleDryRun)
    }
    if let first = trimmed.first, first == "{" || first == "[" {
      result += [.jsonPretty, .jsonMinify, .jsonToYAML]
    }
    if trimmed.utf8.count < 16_384, JWT.looksLike(trimmed) { result.append(.jwtDecode) }
    if Self.looksLikeBase64(trimmed) { result.append(.base64Decode) }
    if trimmed.contains("%"), trimmed.removingPercentEncoding != trimmed { result.append(.urlDecode) }
    if Self.timestampValue(trimmed) != nil { result.append(.timestamp) }
    if text.contains("\u{1B}[") { result.append(.stripANSI) }
    if trimmed.contains("\n") { result.append(.joinLines) }
    result += [.shellQuote, .jsonEscape, .base64Encode, .urlEncode, .sha256]
    return result
  }

  struct Failure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
  }

  /// Applies the transform. `history` supplies earlier clips for commands that need them.
  func apply(to text: String, history: [String] = [], now: Date = Date()) throws -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    switch self {
    case .jsonPretty: return try JSONValue.parse(trimmed).0.formatted()
    case .jsonMinify: return try JSONValue.parse(trimmed).0.minified
    case .jsonToYAML: return try JSONValue.parse(trimmed).0.yaml
    case .jwtDecode: return try JWT.describe(trimmed, now: now)
    case .base64Decode:
      guard let data = Self.base64Data(trimmed) else { throw Failure(message: "Not valid Base64.") }
      guard let decoded = String(data: data, encoding: .utf8) else {
        throw Failure(message: "Base64 decodes to \(data.count) bytes of binary data, not text.")
      }
      return decoded
    case .base64Encode: return Data(text.utf8).base64EncodedString()
    case .urlDecode:
      guard let decoded = trimmed.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
      else { throw Failure(message: "Not valid percent-encoding.") }
      return decoded
    case .urlEncode:
      var allowed = CharacterSet.alphanumerics
      allowed.insert(charactersIn: "-._~")
      return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    case .timestamp:
      guard let date = Self.timestampValue(trimmed) else { throw Failure(message: "Not a Unix timestamp.") }
      return Self.describe(date, now: now)
    case .sha256:
      return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    case .stripANSI: return Self.stripANSI(text)
    case .joinLines:
      return trimmed.split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        .map { $0.hasSuffix("\\") ? String($0.dropLast()).trimmingCharacters(in: .whitespaces) : $0 }
        .joined(separator: " ")
    case .shellQuote: return "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    case .jsonEscape: return JSONValue.quote(text)
    case .ansibleError:
      let failures = AnsibleOutput.failures(in: text)
      guard !failures.isEmpty else { throw Failure(message: "No Ansible failure found.") }
      return failures.map(\.readable).joined(separator: "\n\n")
    case .ansibleRetry:
      let hosts = AnsibleOutput.recap(in: text).filter(\.needsRetry).map(\.host)
      guard !hosts.isEmpty else { throw Failure(message: "Every host in this recap succeeded.") }
      return AnsibleCommand.retryCommand(hosts: hosts, history: history)
    case .ansibleDryRun:
      guard let command = AnsibleCommand.parse(trimmed) else { throw Failure(message: "Not an Ansible command.") }
      return command.dryRun
    }
  }

  static func stripANSI(_ text: String) -> String {
    text.replacingOccurrences(
      of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]|\u{1B}\\][^\u{07}\u{1B}]*(?:\u{07}|\u{1B}\\\\)",
      with: "", options: .regularExpression)
  }
  static func looksLikeBase64(_ text: String) -> Bool {
    guard text.count >= 8, text.utf8.count <= maxBytes, !text.contains(" ") else { return false }
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=-_\n\r")
    guard text.unicodeScalars.allSatisfy(allowed.contains) else { return false }
    // Plain words and numbers are valid Base64 too; require some sign of encoding.
    let hasDigit = text.contains { $0.isNumber }
    let hasUpper = text.contains { $0.isUppercase }
    let hasLower = text.contains { $0.isLowercase }
    return (hasDigit || text.hasSuffix("=")) && hasUpper && hasLower && base64Data(text) != nil
  }
  static func base64Data(_ text: String) -> Data? {
    var normalized = text.filter { !$0.isWhitespace }
      .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while normalized.count % 4 != 0 { normalized += "=" }
    return Data(base64Encoded: normalized)
  }
  /// Seconds (10 digits) or milliseconds (13 digits) between 2001 and 2100.
  static func timestampValue(_ text: String) -> Date? {
    guard [10, 13].contains(text.count), text.allSatisfy(\.isNumber), let value = Double(text)
    else { return nil }
    let seconds = text.count == 13 ? value / 1000 : value
    guard (978_307_200...4_102_444_800).contains(seconds) else { return nil }
    return Date(timeIntervalSince1970: seconds)
  }
  static func describe(_ date: Date, now: Date) -> String {
    let utc = ISO8601DateFormatter()
    utc.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let local = ISO8601DateFormatter()
    local.timeZone = .current
    local.formatOptions = [.withInternetDateTime]
    let relative = RelativeDateTimeFormatter()
    relative.locale = Locale(identifier: "en_US")
    return """
      UTC:   \(utc.string(from: date))
      Local: \(local.string(from: date)) (\(TimeZone.current.identifier))
      \(relative.localizedString(for: date, relativeTo: now))
      """
  }
}

/// Decodes JSON Web Tokens for reading. Signatures are not verified.
enum JWT {
  static func looksLike(_ text: String) -> Bool {
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    return parts.count == 3 && text.hasPrefix("eyJ")
      && parts.prefix(2).allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } }
  }
  static func describe(_ token: String, now: Date) throws -> String {
    let parts = token.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3,
      let header = DevTransform.base64Data(String(parts[0])).flatMap({ String(data: $0, encoding: .utf8) }),
      let payload = DevTransform.base64Data(String(parts[1])).flatMap({ String(data: $0, encoding: .utf8) })
    else { throw DevTransform.Failure(message: "Not a valid JWT.") }
    var lines = [
      "Header:", (try? JSONValue.parse(header).0.formatted()) ?? header,
      "", "Payload:", (try? JSONValue.parse(payload).0.formatted()) ?? payload,
    ]
    if case .object(let claims)? = try? JSONValue.parse(payload).0 {
      var times: [String] = []
      for (name, label) in [("exp", "Expires"), ("iat", "Issued"), ("nbf", "Not before")] {
        if case .number(let raw)? = claims.first(where: { $0.0 == name })?.1, let seconds = Double(raw) {
          let date = Date(timeIntervalSince1970: seconds)
          let relative = RelativeDateTimeFormatter()
          relative.locale = Locale(identifier: "en_US")
          let formatter = ISO8601DateFormatter()
          formatter.timeZone = .current
          times.append("\(label): \(formatter.string(from: date)) (\(relative.localizedString(for: date, relativeTo: now)))")
        }
      }
      if !times.isEmpty { lines += [""] + times }
    }
    lines += ["", "Signature not verified."]
    return lines.joined(separator: "\n")
  }
}
