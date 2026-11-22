import Foundation

/// A copied `ansible`, `ansible-playbook`, … command line, understood well enough to
/// show its target and to warn before it runs against production.
struct AnsibleCommand: Equatable {
  static let tools: Set<String> = [
    "ansible", "ansible-playbook", "ansible-vault", "ansible-galaxy", "ansible-inventory",
    "ansible-pull", "ansible-console", "ansible-doc", "ansible-config",
  ]
  /// Options that take a value, so the value is not mistaken for a playbook.
  private static let valueOptions: Set<String> = [
    "-i", "--inventory", "--inventory-file", "-l", "--limit", "-t", "--tags", "--skip-tags",
    "-e", "--extra-vars", "-m", "--module-name", "-a", "--args", "-u", "--user", "-f", "--forks",
    "-c", "--connection", "-M", "--module-path", "--vault-id", "--vault-password-file",
    "--vault-pass-file", "--private-key", "--key-file", "-T", "--timeout", "--start-at-task",
    "--become-user", "--become-method", "-P", "--poll", "-B", "--background", "--ssh-common-args",
    "--ssh-extra-args", "--scp-extra-args", "--sftp-extra-args", "-o", "--output",
  ]

  var prefix: [String] = []
  var tool: String
  var arguments: [String] = []
  var inventories: [String] = []
  var playbooks: [String] = []
  var hostPattern: String?
  var limit: String?
  var tags: String?
  var skipTags: String?
  var extraVars: [String] = []
  var module: String?
  var check = false
  var diff = false
  var become = false

  /// Parses a single command line; returns nil for anything else.
  static func parse(_ text: String) -> AnsibleCommand? {
    guard text.utf8.count <= 8192 else { return nil }
    var line = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if line.hasPrefix("$ ") { line.removeFirst(2) }
    guard line.contains("ansible"), let tokens = ShellWords.split(line), !tokens.isEmpty else { return nil }
    var index = 0
    var prefix: [String] = []
    while index < tokens.count {
      let token = tokens[index]
      if token.range(of: #"^[A-Za-z_][A-Za-z0-9_]*="#, options: .regularExpression) != nil
        || ["sudo", "time", "exec", "command"].contains(token)
      {
        prefix.append(token)
        index += 1
      } else {
        break
      }
    }
    guard index < tokens.count else { return nil }
    let tool = (tokens[index] as NSString).lastPathComponent
    guard tools.contains(tool) else { return nil }
    var command = AnsibleCommand(prefix: prefix, tool: tool)
    command.arguments = Array(tokens[(index + 1)...])
    var position = 0
    let args = command.arguments
    func value(_ option: String) -> String? {
      if position + 1 < args.count { position += 1; return args[position] }
      return nil
    }
    while position < args.count {
      var arg = args[position]
      var inline: String?
      if arg.hasPrefix("--"), let equals = arg.firstIndex(of: "=") {
        inline = String(arg[arg.index(after: equals)...])
        arg = String(arg[..<equals])
      }
      func take() -> String? { inline ?? value(arg) }
      switch arg {
      case "-i", "--inventory", "--inventory-file": take().map { command.inventories.append($0) }
      case "-l", "--limit": command.limit = take()
      case "-t", "--tags": command.tags = take()
      case "--skip-tags": command.skipTags = take()
      case "-e", "--extra-vars": take().map { command.extraVars.append($0) }
      case "-m", "--module-name": command.module = take()
      case "-C", "--check": command.check = true
      case "-D", "--diff": command.diff = true
      case "-b", "--become": command.become = true
      default:
        if valueOptions.contains(arg) {
          _ = take()
        } else if arg.hasPrefix("-"), !arg.hasPrefix("--"), arg.count > 2,
          arg.dropFirst().allSatisfy({ "bKkCDv".contains($0) })
        {
          // Combined short flags such as -bK or -CD.
          if arg.contains("C") { command.check = true }
          if arg.contains("D") { command.diff = true }
          if arg.contains("b") { command.become = true }
        } else if !arg.hasPrefix("-") {
          if tool == "ansible-playbook" {
            command.playbooks.append(arg)
          } else if tool == "ansible", command.hostPattern == nil {
            command.hostPattern = arg
          }
        }
      }
      position += 1
    }
    return command
  }

  /// True when an inventory, limit or host pattern names a production environment.
  func targetsProduction(keywords: [String]) -> Bool {
    let words = Set(keywords.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    guard !words.isEmpty else { return false }
    let targets = inventories + [limit, hostPattern].compactMap { $0 }
    return targets.contains { target in
      target.lowercased().split { !$0.isLetter && !$0.isNumber }.contains { words.contains(String($0)) }
    }
  }

  struct Issue: Equatable {
    /// Full sentence for the paste review.
    let message: String
    /// A few words for the card.
    let short: String
  }
  func issues(productionKeywords: [String]) -> [Issue] {
    var result: [Issue] = []
    let production = targetsProduction(keywords: productionKeywords)
    if production, tool == "ansible-playbook", limit == nil {
      result.append(Issue(message: "Runs on every host in a production inventory — no --limit.", short: "Production, all hosts"))
    }
    if production, tool == "ansible", ["all", "*"].contains(hostPattern ?? "") {
      result.append(Issue(
        message: "Runs on every production host (pattern “\(hostPattern ?? "")”).", short: "Production, all hosts"))
    }
    if production, tool == "ansible-playbook", !check {
      result.append(Issue(message: "Makes real changes in production — no --check.", short: "No --check"))
    }
    let secret = #"(?i)(pass(word|wd)?|secret|token|api[_-]?key|private[_-]?key)["']?\s*[=:]"#
    if extraVars.contains(where: { !$0.hasPrefix("@") && $0.range(of: secret, options: .regularExpression) != nil }) {
      result.append(Issue(message: "A secret is passed with -e and will stay in shell history.", short: "Secret in -e"))
    }
    return result
  }
  func warnings(productionKeywords: [String]) -> [String] {
    issues(productionKeywords: productionKeywords).map(\.message)
  }

  /// The same command with `--check --diff` added (for a dry run before the real one).
  var dryRun: String {
    var copy = self
    var args = arguments
    if !check { args.append("--check") }
    if !diff { args.append("--diff") }
    copy.arguments = args
    return copy.commandLine
  }
  /// The same command limited to `hosts`, replacing any existing --limit.
  func limited(to hosts: [String]) -> String {
    var copy = self
    var args: [String] = []
    var index = 0
    while index < arguments.count {
      let arg = arguments[index]
      if arg == "-l" || arg == "--limit" {
        index += 2
        continue
      }
      if arg.hasPrefix("--limit=") { index += 1; continue }
      args.append(arg)
      index += 1
    }
    args += ["--limit", hosts.joined(separator: ",")]
    copy.arguments = args
    return copy.commandLine
  }
  var commandLine: String { (prefix + [tool] + arguments).map(ShellWords.quote).joined(separator: " ") }

  /// A command to rerun the latest copied playbook on `hosts`, or just the --limit option.
  static func retryCommand(hosts: [String], history: [String]) -> String {
    for text in history {
      if let command = parse(text), command.tool == "ansible-playbook" {
        return command.limited(to: hosts)
      }
    }
    return "--limit " + ShellWords.quote(hosts.joined(separator: ","))
  }
}

/// Minimal POSIX shell word splitting: quotes, backslash escapes and line continuations.
enum ShellWords {
  static func split(_ text: String) -> [String]? {
    var words: [String] = []
    var current = ""
    var inWord = false
    var quote: Character?
    var iterator = text.makeIterator()
    while let char = iterator.next() {
      if let open = quote {
        if char == open {
          quote = nil
        } else if open == "\"", char == "\\", let next = iterator.next() {
          if next == "\n" { continue }
          if "\"\\$`".contains(next) { current.append(next) } else { current += "\\\(next)" }
        } else {
          current.append(char)
        }
        continue
      }
      switch char {
      case "'", "\"":
        quote = char
        inWord = true
      case "\\":
        guard let next = iterator.next() else { break }
        if next == "\n" { continue }
        current.append(next)
        inWord = true
      case " ", "\t":
        if inWord { words.append(current); current = ""; inWord = false }
      case "\n", ";", "|", "&":
        // A second command (or a pipeline) is not a single command line.
        return nil
      default:
        current.append(char)
        inWord = true
      }
    }
    guard quote == nil else { return nil }
    if inWord { words.append(current) }
    return words
  }
  static func quote(_ word: String) -> String {
    if !word.isEmpty, word.range(of: #"^[A-Za-z0-9_@%+=:,./-]+$"#, options: .regularExpression) != nil {
      return word
    }
    return "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }
}

/// Reads copied ansible-playbook output: the PLAY RECAP table and task failures.
enum AnsibleOutput {
  struct RecapEntry: Equatable {
    var host: String
    var ok = 0, changed = 0, unreachable = 0, failed = 0, skipped = 0, rescued = 0, ignored = 0
    var needsRetry: Bool { failed > 0 || unreachable > 0 }
  }
  struct Failure: Equatable {
    var host: String
    var task: String?
    var unreachable: Bool
    var details: JSONValue?
    var raw: String

    var readable: String {
      var lines = ["✗ \(host)" + (task.map { " — \($0)" } ?? "") + (unreachable ? " (unreachable)" : "")]
      guard case .object(let fields)? = details else {
        lines.append(raw)
        return lines.joined(separator: "\n")
      }
      func field(_ name: String) -> JSONValue? { fields.first { $0.0 == name }?.1 }
      func text(_ value: JSONValue?) -> String? {
        switch value {
        case .string(let string)?: return string.isEmpty ? nil : string
        case .number(let number)?: return number
        case .bool(let flag)?: return flag ? "true" : "false"
        case .array(let items)?:
          let joined = items.map { item -> String in
            if case .string(let string) = item { return string }
            return item.minified
          }.joined(separator: "\n")
          return joined.isEmpty ? nil : joined
        case .object?: return value?.formatted()
        default: return nil
        }
      }
      if let cmd = text(field("cmd")) { lines.append("cmd: \(cmd.replacingOccurrences(of: "\n", with: " "))") }
      if let rc = text(field("rc")) { lines.append("rc: \(rc)") }
      if let msg = text(field("msg")) { lines.append("msg: \(msg)") }
      for (title, names) in [
        ("stderr", ["stderr_lines", "stderr"]), ("stdout", ["stdout_lines", "stdout"]),
        ("module_stderr", ["module_stderr"]), ("module_stdout", ["module_stdout"]),
      ] {
        if let body = names.lazy.compactMap({ text(field($0)) }).first {
          lines.append("\(title):")
          lines += body.split(separator: "\n", omittingEmptySubsequences: false).map { "    \($0)" }
        }
      }
      return lines.joined(separator: "\n")
    }
  }

  static func hasRecap(_ text: String) -> Bool { text.containsBytes("PLAY RECAP") }
  static func hasFailure(_ text: String) -> Bool {
    text.containsBytes("FAILED! =>") || text.containsBytes("UNREACHABLE! =>")
  }

  static func recap(in text: String) -> [RecapEntry] {
    let clean = DevTransform.stripANSI(text)
    guard let start = clean.range(of: "PLAY RECAP") else { return [] }
    var entries: [RecapEntry] = []
    for line in clean[start.upperBound...].split(whereSeparator: \.isNewline) {
      let parts = line.split(separator: ":", maxSplits: 1)
      guard parts.count == 2 else { continue }
      let host = parts[0].trimmingCharacters(in: .whitespaces)
      guard !host.isEmpty, !host.contains(" ") else { continue }
      var entry = RecapEntry(host: host)
      var found = false
      for pair in parts[1].split(separator: " ") {
        let kv = pair.split(separator: "=")
        guard kv.count == 2, let number = Int(kv[1]) else { continue }
        found = true
        switch kv[0] {
        case "ok": entry.ok = number
        case "changed": entry.changed = number
        case "unreachable": entry.unreachable = number
        case "failed": entry.failed = number
        case "skipped": entry.skipped = number
        case "rescued": entry.rescued = number
        case "ignored": entry.ignored = number
        default: break
        }
      }
      if found { entries.append(entry) }
    }
    return entries
  }

  static func failures(in text: String) -> [Failure] {
    let clean = DevTransform.stripANSI(text)
    let lines = clean.components(separatedBy: .newlines)
    var task: String?
    var result: [Failure] = []
    for (index, line) in lines.enumerated() {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("TASK ["), let end = trimmed.range(of: "]", options: .backwards) {
        task = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 6)..<end.lowerBound])
        continue
      }
      guard trimmed.hasPrefix("fatal: [") || trimmed.hasPrefix("failed: ["),
        let close = trimmed.firstIndex(of: "]"),
        let arrow = trimmed.range(of: "! => ")
      else { continue }
      let host = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: trimmed.hasPrefix("fatal") ? 8 : 9)..<close])
      let unreachable = trimmed[..<arrow.lowerBound].hasSuffix("UNREACHABLE")
      // The JSON usually fits on the line; verbose callbacks may continue it below.
      let rest = String(trimmed[arrow.upperBound...]) + "\n" + lines[(index + 1)...].joined(separator: "\n")
      let details = try? JSONValue.parse(rest, allowTrailing: true).0
      result.append(Failure(host: host, task: task, unreachable: unreachable, details: details, raw: trimmed))
    }
    return result
  }
}

/// A paste into a terminal that is waiting for the user's confirmation.
struct PendingPaste: Identifiable, Equatable {
  let id = UUID()
  let text: String
  /// What the sheet shows: masked when the clip is sensitive, so review never reveals it.
  var display: String? = nil
  let target: String
  let lines: Int
  let warnings: [String]
  /// The same Ansible command with --check --diff, offered as the safer choice.
  let dryRun: String?
}

/// What ClipNest understands about a text clip, computed once per clip version.
final class ClipInsight {
  let transforms: [DevTransform]
  let command: AnsibleCommand?
  let recap: [AnsibleOutput.RecapEntry]
  let failures: [AnsibleOutput.Failure]
  init(_ text: String) {
    transforms = DevTransform.available(for: text)
    let small = text.utf8.count <= DevTransform.maxBytes
    command = text.utf8.count <= 8192 && text.containsBytes("ansible") ? AnsibleCommand.parse(text) : nil
    recap = small && AnsibleOutput.hasRecap(text) ? AnsibleOutput.recap(in: text) : []
    failures = small && AnsibleOutput.hasFailure(text) ? AnsibleOutput.failures(in: text) : []
  }
  var isEmpty: Bool { command == nil && recap.isEmpty && failures.isEmpty }
}
