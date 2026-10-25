import AppKit

private final class PikabinStubProtocol: URLProtocol {
  static var handler: ((URLRequest) throws -> (Int, Data, [String: String]))?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    do {
      let result = try Self.handler!(request)
      let response = HTTPURLResponse(url: request.url!, statusCode: result.0, httpVersion: "HTTP/1.1", headerFields: result.2)!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: result.1)
      client?.urlProtocolDidFinishLoading(self)
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  override func stopLoading() {}
}
private struct PikabinMock: PikabinPosting {
  let action: () async throws -> URL
  func createPaste(text: String) async throws -> URL { try await action() }
}

@MainActor func runPikabinTests() async -> Int {
  var checks = 0
  func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    if !condition() { fputs("FAIL: \(name)\n", stderr); exit(1) }
    checks += 1; print("PASS: \(name)")
  }
  let token = "sample+csrf/token=="
  let html = "<html><meta content='\(token)' name='csrf-token'></html>"
  check(PikabinClient.csrfToken(in: html) == token, "PikaBin token parser accepts reversed attributes and single quotes")
  check(PikabinClient.csrfToken(in: "<META NAME=\"csrf-token\" CONTENT=\"abcDEF123+/=\">") == "abcDEF123+/=",
    "PikaBin token parser accepts normal Rails markup")
  check(PikabinClient.csrfToken(in: "<meta name='csrf-token' content='bad\r\ntoken'>") == nil,
    "Invalid CSRF header characters are rejected")
  let text = "Xin chào 👋\nA+B & C=D / #test\t100%"
  let request = PikabinClient.request(text: text, csrfToken: token)
  func fields(_ request: URLRequest) -> [String: String] {
    let data: Data
    if let body = request.httpBody { data = body }
    else if let stream = request.httpBodyStream {
      stream.open(); defer { stream.close() }
      var body = Data()
      var buffer = [UInt8](repeating: 0, count: 4096)
      while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        body.append(contentsOf: buffer.prefix(count))
      }
      data = body
    } else { return [:] }
    return Dictionary(uniqueKeysWithValues: String(decoding: data, as: UTF8.self).split(separator: "&").map {
      let pair = $0.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      let key = String(pair[0]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding!
      let value = String(pair[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding!
      return (key, value)
    })
  }
  let form = fields(request)
  check(form["document[content]"] == text && form["authenticity_token"] == token,
    "PikaBin form encoding preserves Vietnamese, emoji, newlines and URL-reserved characters")
  check(form["document[expired_at]"] == "604800" && form["document[syntax]"] == "plain",
    "PikaBin default expiration is exactly one week")
  check(form["document[title]"] == "ClipNest" && form.count == 5,
    "Only selected plain text and required form fields are uploaded")
  check(request.httpMethod == "POST" && request.url == PikabinClient.endpoint
    && request.value(forHTTPHeaderField: "X-CSRF-Token") == token
    && request.value(forHTTPHeaderField: "X-Requested-With") == "XMLHttpRequest",
    "PikaBin POST uses the verified form endpoint and CSRF headers")
  let valid = Data(#"{"message":[],"uri":"https://pikab.in/a3ef156ec2"}"#.utf8)
  check((try? PikabinClient.shareURL(from: valid))?.absoluteString == "https://pikab.in/a3ef156ec2",
    "PikaBin parses a successful share URL")
  for url in ["http://pikab.in/abc", "https://other.example/abc", "https://pikab.in/", "https://pikab.in/a/b", "https://user@pikab.in/abc", "https://pikab.in/abc?key=x", "file:///abc"] {
    let data = try! JSONSerialization.data(withJSONObject: ["uri": url])
    check((try? PikabinClient.shareURL(from: data)) == nil, "PikaBin rejects unexpected result URL: \(url)")
  }
  check((try? PikabinClient.shareURL(from: Data("not json".utf8))) == nil,
    "Malformed PikaBin response cannot replace clipboard")

  let config = URLSessionConfiguration.ephemeral
  config.protocolClasses = [PikabinStubProtocol.self]
  let client = PikabinClient(session: URLSession(configuration: config))
  var requests = 0
  var observedContent = false
  PikabinStubProtocol.handler = { request in
    requests += 1
    if request.httpMethod == "POST" {
      observedContent = fields(request)["document[content]"] == text
      return (201, valid, ["Content-Type": "application/json"])
    }
    return (200, Data(html.utf8), ["Set-Cookie": "_pikabin_session=sample; Path=/; Secure; HttpOnly"])
  }
  let result = try? await client.createPaste(text: text)
  check(result?.host == "pikab.in" && requests == 2 && observedContent,
    "PikaBin client bootstraps CSRF then submits exactly one POST")
  requests = 0
  PikabinStubProtocol.handler = { _ in requests += 1; return (200, Data("missing csrf".utf8), [:]) }
  let noToken = try? await client.createPaste(text: text)
  check(noToken == nil && requests == 1, "PikaBin never POSTs if session token is missing")
  requests = 0
  PikabinStubProtocol.handler = { request in
    requests += 1
    return request.httpMethod == "POST" ? (503, Data("untrusted server message".utf8), [:]) : (200, Data(html.utf8), [:])
  }
  do { _ = try await client.createPaste(text: text); check(false, "PikaBin HTTP failure propagated") }
  catch { check(!error.localizedDescription.contains("untrusted") && requests == 2,
    "PikaBin errors avoid raw server content and do not automatically retry POST") }
  requests = 0
  let empty = try? await client.createPaste(text: "")
  check(empty == nil && requests == 0, "Empty content is rejected before any network call")
  PikabinStubProtocol.handler = nil

  let link = URL(string: "https://pikab.in/sample1234")!
  var count = 1
  var copies = 0
  var posts = 0
  let success = PikabinMock { posts += 1; return link }
  let sharing = PikabinSharing(client: success, clipboardCount: { count }, copyLink: { _ in copies += 1; count += 1; return true })
  sharing.push(text: text)
  sharing.push(text: "Duplicate click")
  try? await Task.sleep(nanoseconds: 50_000_000)
  check(sharing.link == link && sharing.copied && copies == 1 && posts == 1,
    "Successful PikaBin share presents and copies one link; duplicate clicks do not POST twice")
  let slow = PikabinMock { try? await Task.sleep(nanoseconds: 60_000_000); return link }
  let changed = PikabinSharing(client: slow, clipboardCount: { count }, copyLink: { _ in copies += 1; return true })
  changed.push(text: text)
  count += 1
  try? await Task.sleep(nanoseconds: 100_000_000)
  check(changed.link == link && !changed.copied && copies == 1,
    "PikaBin result does not overwrite clipboard changed during upload")
  changed.copyResultLink()
  check(changed.copied && copies == 2, "PikaBin link can be copied explicitly after clipboard changes")
  changed.dismiss()
  let canceled = PikabinSharing(client: slow, clipboardCount: { count }, copyLink: { _ in copies += 1; return true })
  canceled.push(text: text)
  canceled.dismiss()
  try? await Task.sleep(nanoseconds: 100_000_000)
  check(!canceled.isPresented && canceled.link == nil && copies == 2,
    "Canceled PikaBin request cannot reopen sheet or copy a late result")
  var retryAttempts = 0
  let failed = PikabinSharing(client: PikabinMock {
    retryAttempts += 1
    if retryAttempts == 1 { throw PikabinError.http(429) }
    return link
  }, clipboardCount: { count }, copyLink: { _ in copies += 1; return true })
  failed.push(text: text)
  try? await Task.sleep(nanoseconds: 50_000_000)
  check(failed.error != nil && failed.link == nil && !failed.isUploading && copies == 2,
    "Failed PikaBin upload shows a retryable error and preserves clipboard")
  failed.retry()
  try? await Task.sleep(nanoseconds: 50_000_000)
  check(failed.link == link && failed.error == nil && retryAttempts == 2,
    "Manual PikaBin retry can recover from a failed upload")
  failed.dismiss()
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ClipNest-pikabin-tests-\(UUID())")
  let suite = "ClipNest.pikabin-tests.\(UUID())"
  let defaults = UserDefaults(suiteName: suite)!
  let pb = NSPasteboard.withUniqueName()
  defer { try? FileManager.default.removeItem(at: folder); defaults.removePersistentDomain(forName: suite); pb.releaseGlobally() }
  let store = Store(folder: folder, defaults: defaults, pasteboard: pb, monitoring: false)
  var guardedPosts = 0
  let guarded = PikabinSharing(client: PikabinMock { guardedPosts += 1; return link }, clipboardCount: { 0 }, copyLink: { _ in true })
  store.pikabin = guarded
  let secret = Clip(source: "Test", kind: "Text", text: ["password", "synthetic-pikabin-fixture"].joined(separator: "="))
  store.clips = [secret]
  store.pushToPikabin(secret)
  check(!guarded.isPresented && guardedPosts == 0, "Masked text cannot be uploaded before explicit reveal")
  store.revealSensitiveItem(secret)
  store.pushToPikabin(secret)
  try? await Task.sleep(nanoseconds: 50_000_000)
  check(guardedPosts == 1 && guarded.link == link && store.clips.first?.text == secret.text,
    "Explicitly revealed text can be shared without modifying its saved original")
  store.hideRevealedSensitiveItems()
  guarded.dismiss()
  check(PikabinSharing.supports(Clip(source: "Test", kind: "Text", text: text))
    && !PikabinSharing.supports(Clip(source: "Test", kind: "Image", text: "100 × 100"))
    && !PikabinSharing.supports(Clip(source: "Test", kind: "Files", text: "file:///tmp/sample")),
    "PikaBin share is available only for text-based clipboard items")
  return checks
}

@MainActor func runPikabinSmokeTest() async {
  // Fixed public fixture only; this command never reads a clipboard or user history.
  let sample = "ClipNest integration test — Xin chào Việt Nam 👋\nA+B & C=D\nSynthetic sample only."
  do {
    let url = try await PikabinClient().createPaste(text: sample)
    let raw = url.appendingPathExtension("raw")
    let (data, response) = try await URLSession(configuration: .ephemeral).data(from: raw)
    guard (response as? HTTPURLResponse)?.statusCode == 200,
      String(data: data, encoding: .utf8) == sample else {
      fputs("FAIL: PikaBin raw content did not match the synthetic fixture\n", stderr); exit(1)
    }
    print("PASS: Live PikaBin create + raw roundtrip, one-week expiry: \(url.absoluteString)")
  } catch {
    fputs("FAIL: PikaBin smoke test: \(error.localizedDescription)\n", stderr); exit(1)
  }
}

@MainActor func pikabinPreview() async -> PikabinSharing {
  let sharing = PikabinSharing(client: PikabinMock { URL(string: "https://pikab.in/sample1234")! },
    clipboardCount: { 0 }, copyLink: { _ in true })
  sharing.push(text: "Sample preview only")
  try? await Task.sleep(nanoseconds: 50_000_000)
  return sharing
}
