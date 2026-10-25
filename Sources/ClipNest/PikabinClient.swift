import Foundation

protocol PikabinPosting {
  func createPaste(text: String) async throws -> URL
}

enum PikabinError: LocalizedError {
  case empty, tooLarge, unavailable, invalidResponse, http(Int)
  var errorDescription: String? {
    switch self {
    case .empty: return "Không có nội dung text để gửi."
    case .tooLarge: return "Nội dung quá lớn để gửi lên pikab.in."
    case .unavailable: return "Không lấy được phiên gửi của pikab.in. Hãy thử lại sau."
    case .invalidResponse: return "pikab.in không trả về link hợp lệ."
    case .http(let code):
      if code == 429 { return "pikab.in đang giới hạn lượt gửi. Hãy thử lại sau." }
      if code == 413 { return "pikab.in từ chối nội dung quá lớn." }
      return "Không gửi được lên pikab.in (HTTP \(code)). Hãy thử lại sau."
    }
  }
}

private final class PikabinRedirectPolicy: NSObject, URLSessionTaskDelegate {
  func urlSession(_ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void) {
    // This endpoint does not need redirects. Never forward clipboard content elsewhere.
    completionHandler(nil)
  }
}

final class PikabinClient: PikabinPosting {
  static let endpoint = URL(string: "https://pikab.in/")!
  static let expiration = 604800
  private let session: URLSession
  init(session: URLSession? = nil) {
    if let session { self.session = session }
    else {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.urlCache = nil
      configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
      configuration.timeoutIntervalForRequest = 30
      configuration.timeoutIntervalForResource = 60
      self.session = URLSession(configuration: configuration, delegate: PikabinRedirectPolicy(), delegateQueue: nil)
    }
  }
  deinit { session.invalidateAndCancel() }

  func createPaste(text: String) async throws -> URL {
    guard !text.isEmpty else { throw PikabinError.empty }
    guard text.utf8.count < 5_000_000 else { throw PikabinError.tooLarge }
    var bootstrap = URLRequest(url: Self.endpoint)
    bootstrap.setValue("text/html", forHTTPHeaderField: "Accept")
    let (html, initial) = try await session.data(for: bootstrap)
    try validate(initial, expectedStatus: 200)
    guard html.count < 1_000_000, let page = String(data: html, encoding: .utf8),
      let token = Self.csrfToken(in: page) else { throw PikabinError.unavailable }
    try Task.checkCancellation()
    let request = Self.request(text: text, csrfToken: token)
    let (data, response) = try await session.data(for: request)
    try validate(response, expectedStatus: 201)
    try Task.checkCancellation()
    return try Self.shareURL(from: data)
  }
  private func validate(_ response: URLResponse, expectedStatus: Int) throws {
    guard let response = response as? HTTPURLResponse,
      response.url?.scheme == "https", response.url?.host?.lowercased() == "pikab.in"
    else { throw PikabinError.invalidResponse }
    guard response.statusCode == expectedStatus else { throw PikabinError.http(response.statusCode) }
  }
  static func request(text: String, csrfToken: String) -> URLRequest {
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
    request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
    request.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-Token")
    request.setValue(endpoint.absoluteString, forHTTPHeaderField: "Referer")
    // An ASCII title avoids a known server error with some Vietnamese titles.
    // Only the selected plain text is uploaded; no source-app metadata, rich text or history.
    let fields = [
      ("authenticity_token", csrfToken), ("document[content]", text),
      ("document[title]", "ClipNest"), ("document[expired_at]", String(expiration)),
      ("document[syntax]", "plain"),
    ]
    request.httpBody = fields.map { encode($0.0) + "=" + encode($0.1) }.joined(separator: "&").data(using: .utf8)
    return request
  }
  private static func encode(_ text: String) -> String {
    let hex = Array("0123456789ABCDEF".utf8)
    var bytes: [UInt8] = []
    bytes.reserveCapacity(text.utf8.count * 2)
    for byte in text.utf8 {
      switch byte {
      case 65...90, 97...122, 48...57, 45, 46, 95, 126: bytes.append(byte)
      case 32: bytes.append(43)
      default: bytes.append(37); bytes.append(hex[Int(byte >> 4)]); bytes.append(hex[Int(byte & 15)])
      }
    }
    return String(decoding: bytes, as: UTF8.self)
  }

  static func csrfToken(in html: String) -> String? {
    let tag = try! NSRegularExpression(pattern: #"<meta\b[^>]*>"#, options: .caseInsensitive)
    let attribute = try! NSRegularExpression(pattern: #"([\w-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')"#)
    let source = html as NSString
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=_-")
    for match in tag.matches(in: html, range: NSRange(location: 0, length: source.length)) {
      let text = source.substring(with: match.range) as NSString
      var values: [String: String] = [:]
      for field in attribute.matches(in: text as String, range: NSRange(location: 0, length: text.length)) {
        let value = field.range(at: 2).location != NSNotFound ? field.range(at: 2) : field.range(at: 3)
        values[text.substring(with: field.range(at: 1)).lowercased()] = text.substring(with: value)
      }
      if values["name"]?.lowercased() == "csrf-token", let token = values["content"],
        !token.isEmpty, token.utf8.count <= 4096,
        token.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
        return token
      }
    }
    return nil
  }
  static func shareURL(from data: Data) throws -> URL {
    struct Response: Decodable { let uri: String }
    guard data.count < 64_000, let response = try? JSONDecoder().decode(Response.self, from: data),
      let url = URL(string: response.uri), let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      components.scheme == "https", components.host?.lowercased() == "pikab.in",
      components.user == nil, components.password == nil,
      components.port == nil || components.port == 443,
      components.query == nil, components.fragment == nil,
      url.path.range(of: #"^/[A-Za-z0-9_-]{1,128}$"#, options: .regularExpression) != nil
    else { throw PikabinError.invalidResponse }
    return url
  }
}
