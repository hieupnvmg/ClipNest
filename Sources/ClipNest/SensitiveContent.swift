import Foundation

struct SensitiveAssessment {
  let maskedText: String
  let labels: [String]
  let containsSecret: Bool
  var isSensitive: Bool { containsSecret || !labels.isEmpty }
  static let secretPlaceholder = "[Nội dung nhạy cảm đã được che]"
}

// Local heuristics only. Never log, transmit, validate with a provider, or change
// the system clipboard. Compiled expressions are reused for every capture.
enum SensitiveContent {
  private struct Rule {
    let regex: NSRegularExpression
    let label: String
    let replacement: (String) -> String?
  }
  private static func regex(_ pattern: String) -> NSRegularExpression {
    try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
  }
  private static let secrets: [NSRegularExpression] = [
    regex(#"-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----"#),
    regex(
      #"(?<![A-Z0-9_])(?:sk-(?:proj-|svcacct-)?[A-Z0-9_-]{20,4096}|[sr]k_(?:live|test)_[A-Z0-9]{16,4096}|gh[pousr]_[A-Z0-9]{20,4096}|github_pat_[A-Z0-9_]{20,4096}|glpat-[A-Z0-9_-]{16,4096}|xox[baprs]-[A-Z0-9-]{10,4096}|(?:AKIA|ASIA)[A-Z0-9]{16}|AIza[A-Z0-9_-]{30,100})(?![A-Z0-9_-])"#
    ),
    regex(#"\bauthorization\s*:\s*(?:bearer|basic)\s+[^\s\"'<>]{4,4096}"#),
    regex(
      #"\b(?:password|passwd|pwd|api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|secret[_-]?key|private[_-]?key|aws[_-]?secret[_-]?access[_-]?key|token|mật\s*khẩu|mat\s*khau)\b[\"']?\s*[:=]\s*[\"']?[^\s\"'&,;<>]{1,4096}"#
    ),
    regex(
      #"(?<![A-Z0-9_-])eyJ[A-Z0-9_-]{8,4096}\.[A-Z0-9_-]{8,4096}\.[A-Z0-9_-]{8,4096}(?![A-Z0-9_-])"#
    ),
    regex(#"https?://[^/@\s:]{1,256}:[^/@\s]{1,4096}@"#),
  ]
  private static let personal: [Rule] = [
    Rule(
      regex: regex(
        #"(?<![A-Z0-9._%+-])[A-Z0-9][A-Z0-9._%+-]{0,63}@[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?(?:\.[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?)*\.[A-Z]{2,24}(?![A-Z0-9-])"#
      ), label: "Email",
      replacement: { value in
        let parts = value.split(separator: "@", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let suffix = parts[1].split(separator: ".").last.map(String.init) ?? ""
        return String(parts[0].prefix(1)) + "•••@•••." + suffix
      }),
    Rule(
      regex: regex(#"(?<!\d)(?:\d[ -]?){12,18}\d(?!\d)"#), label: "Số thẻ",
      replacement: { value in
        let digits = value.filter(\.isNumber)
        guard isPaymentCard(digits) else { return nil }
        return "•••• •••• •••• " + digits.suffix(4)
      }),
    Rule(
      regex: regex(
        #"(?<![\p{L}\p{N}])(?:\+84[ .-]?|0)(?:[ .-]?\d){9,10}(?![\p{L}\p{N}])|(?<![\p{L}\p{N}])\+[1-9](?:[ .()\-]*\d){7,14}(?![\p{L}\p{N}])|(?<!\d)\(?\d{3}\)?[ .-]\d{3}[ .-]\d{4}(?!\d)"#
      ), label: "Số điện thoại",
      replacement: { value in
        let digits = value.filter(\.isNumber)
        guard (8...15).contains(digits.count) else { return nil }
        return "•••••••" + digits.suffix(3)
      }),
  ]
  static func containsSecret(_ text: String) -> Bool {
    let range = NSRange(text.startIndex..., in: text)
    return secrets.contains { $0.firstMatch(in: text, range: range) != nil }
  }
  static func inspect(_ text: String) -> SensitiveAssessment {
    if containsSecret(text) {
      return SensitiveAssessment(
        maskedText: SensitiveAssessment.secretPlaceholder, labels: ["Mật khẩu / khóa bí mật"],
        containsSecret: true)
    }
    let source = text as NSString
    let range = NSRange(location: 0, length: source.length)
    var matches: [(range: NSRange, value: String, label: String)] = []
    var overflow = false
    for rule in personal {
      var count = 0
      rule.regex.enumerateMatches(in: text, range: range) { result, _, stop in
        guard let result, let replacement = rule.replacement(source.substring(with: result.range))
        else { return }
        count += 1
        if count > 128 {
          overflow = true
          stop.pointee = true
          return
        }
        matches.append((result.range, replacement, rule.label))
      }
    }
    let labels = Array(Set(matches.map(\.label))).sorted()
    if overflow {
      return SensitiveAssessment(
        maskedText: "[Thông tin cá nhân đã được che]", labels: labels, containsSecret: false)
    }
    // Prefer larger matches (an email/card may contain a phone-like substring).
    var accepted: [(range: NSRange, value: String, label: String)] = []
    for match in matches.sorted(by: { $0.range.length > $1.range.length }) {
      if !accepted.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }) {
        accepted.append(match)
      }
    }
    let result = NSMutableString(string: text)
    for match in accepted.sorted(by: { $0.range.location > $1.range.location }) {
      result.replaceCharacters(in: match.range, with: match.value)
    }
    return SensitiveAssessment(maskedText: result as String, labels: labels, containsSecret: false)
  }
  static func isPaymentCard(_ digits: String) -> Bool {
    guard (13...19).contains(digits.count), Set(digits).count > 1,
      digits.allSatisfy({ $0.isASCII && $0.isNumber })
    else { return false }
    let sum = digits.reversed().enumerated().reduce(0) { total, item in
      let digit = item.element.wholeNumberValue!
      let value = item.offset % 2 == 1 ? digit * 2 : digit
      return total + (value > 9 ? value - 9 : value)
    }
    return sum % 10 == 0
  }
}

final class ProtectedPresentation {
  let original: Clip
  let clip: Clip
  let isSensitive: Bool
  let containsSecret: Bool
  let label: String
  var cost: Int {
    original.text.utf8.count + original.title.utf8.count + (original.data?.count ?? 0)
      + (original.html?.count ?? 0) + clip.text.utf8.count + clip.title.utf8.count
  }
  init(_ original: Clip) {
    self.original = original
    let visibleText =
      original.kind == "Files"
      ? (original.text.removingPercentEncoding ?? original.text) : original.text
    let text = SensitiveContent.inspect(visibleText)
    let title = SensitiveContent.inspect(original.title)
    let fileTitle = original.kind == "Files" ? SensitiveContent.inspect(original.displayTitle) : nil
    // Rich-text HTML can hold credentials not present in its plain-text preview.
    let html = original.html.flatMap { String(data: $0, encoding: .utf8) }.map(
      SensitiveContent.inspect)
    let rtf =
      ["Text", "Link", "Color"].contains(original.kind)
      ? original.data.map { SensitiveContent.inspect(String(decoding: $0, as: UTF8.self)) } : nil
    containsSecret =
      text.containsSecret || title.containsSecret || html?.containsSecret == true
      || rtf?.containsSecret == true || fileTitle?.containsSecret == true
    isSensitive =
      containsSecret || text.isSensitive || title.isSensitive || html?.isSensitive == true
      || rtf?.isSensitive == true || fileTitle?.isSensitive == true
    label = Array(
      Set(
        text.labels + title.labels + (html?.labels ?? []) + (rtf?.labels ?? [])
          + (fileTitle?.labels ?? []))
    )
    .sorted().joined(
      separator: ", ")
    var safe = original
    safe.text = containsSecret ? SensitiveAssessment.secretPlaceholder : text.maskedText
    safe.title = containsSecret ? "Đã bảo vệ" : title.maskedText
    if !containsSecret && original.title.isEmpty, let fileTitle, fileTitle.isSensitive {
      safe.title = fileTitle.maskedText
    }
    if isSensitive {
      safe.data = nil
      safe.html = nil
    }
    clip = safe
  }
}
