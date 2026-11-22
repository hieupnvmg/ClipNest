import AppKit

@MainActor func runDevToolsTests() async -> Int {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ClipNest-dev-tests-\(UUID())")
  let suite = "ClipNest.dev-tests.\(UUID())"
  let defaults = UserDefaults(suiteName: suite)!
  let pb = NSPasteboard.withUniqueName()
  defer {
    try? FileManager.default.removeItem(at: folder)
    defaults.removePersistentDomain(forName: suite)
    pb.releaseGlobally()
  }
  var checks = 0
  func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    guard condition() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
    checks += 1
    print("PASS: \(name)")
  }
  func run(_ transform: DevTransform, _ text: String, history: [String] = []) -> String? {
    try? transform.apply(to: text, history: history, now: Date(timeIntervalSince1970: 1_700_003_600))
  }

  // JSON and YAML keep the input's key order.
  check(run(.jsonPretty, #"{"b":1,"a":[true,null]}"#) == "{\n  \"b\": 1,\n  \"a\": [\n    true,\n    null\n  ]\n}",
    "Format JSON keeps key order and indents by two spaces")
  check(run(.jsonMinify, "{\n  \"x\" : [ 1 , \"é\\u00e9\\ud83d\\ude00\" ]\n}") == #"{"x":[1,"éé😀"]}"#,
    "Minify JSON decodes escapes, including surrogate pairs")
  do {
    _ = try DevTransform.jsonPretty.apply(to: #"{"a": 1,}"#)
    check(false, "Invalid JSON reports where it fails")
  } catch {
    check(error.localizedDescription.contains("character"), "Invalid JSON reports where it fails")
  }
  let yaml = run(.jsonToYAML, #"{"name":"web","ports":[80,443],"env":{"MODE":"prod","EMPTY":"","YES":"yes"},"hosts":[{"name":"a","ip":"10.0.0.1"}],"note":"line1\nline2","flag":true,"nothing":null}"#)
  check(yaml == """
    name: web
    ports:
    - 80
    - 443
    env:
      MODE: prod
      EMPTY: ""
      "YES": "yes"
    hosts:
    - name: a
      ip: 10.0.0.1
    note: |-
      line1
      line2
    flag: true
    nothing: null
    """, "JSON converts to YAML with quoting for booleans, empties and multi-line text")

  // Tokens, encodings and time.
  func b64url(_ text: String) -> String {
    Data(text.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  }
  let jwt = b64url(#"{"alg":"HS256","typ":"JWT"}"#) + "." + b64url(#"{"sub":"ops","exp":1700000000}"#) + ".c2ln"
  let decoded = run(.jwtDecode, jwt) ?? ""
  check(JWT.looksLike(jwt) && decoded.contains("\"sub\": \"ops\"") && decoded.contains("Expires:")
      && decoded.contains("1 hour ago") && decoded.contains("Signature not verified"),
    "Decode JWT shows header, payload and expiry without verifying")
  check(run(.base64Decode, "SGVsbG8gQ2xpcE5lc3Q=") == "Hello ClipNest" && run(.base64Encode, "Hello ClipNest") == "SGVsbG8gQ2xpcE5lc3Q=",
    "Base64 decodes and encodes")
  check(DevTransform.looksLikeBase64("SGVsbG8gQ2xpcE5lc3Q=") && !DevTransform.looksLikeBase64("hello world")
      && !DevTransform.looksLikeBase64("deployment"), "Base64 is offered only for text that looks encoded")
  check(run(.urlDecode, "a%20b%2Fc+d") == "a b/c d" && run(.urlEncode, "a b/c") == "a%20b%2Fc", "URL decode and encode")
  check(run(.timestamp, "1700000000")?.contains("UTC:   2023-11-14T22:13:20.000Z") == true
      && run(.timestamp, "1700000000000")?.contains("1 hour ago") == true
      && DevTransform.timestampValue("9999999999") == nil,
    "Unix timestamps in seconds or milliseconds convert to UTC and local time")
  check(run(.sha256, "abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "SHA-256 hash")
  check(run(.stripANSI, "\u{1B}[0;31mfatal\u{1B}[0m: [web]") == "fatal: [web]", "Terminal colors are removed")
  check(run(.joinLines, "ansible-playbook site.yml \\\n   --limit web\n  --check\n") == "ansible-playbook site.yml --limit web --check",
    "Join Lines merges continued command lines")
  check(run(.shellQuote, "it's here") == #"'it'\''s here'"# && run(.jsonEscape, "a\"b\n") == #""a\"b\n""#,
    "Text is quoted for the shell and escaped for JSON")

  // Ansible commands.
  let risky = "ANSIBLE_FORCE_COLOR=1 ansible-playbook -i inventories/production/hosts.yml site.yml --tags nginx -e 'db_password=hunter2' -bK"
  let command = AnsibleCommand.parse(risky)
  check(command?.tool == "ansible-playbook" && command?.inventories == ["inventories/production/hosts.yml"]
      && command?.playbooks == ["site.yml"] && command?.tags == "nginx" && command?.become == true
      && command?.extraVars == ["db_password=hunter2"] && command?.prefix == ["ANSIBLE_FORCE_COLOR=1"],
    "ansible-playbook commands are parsed with inventory, playbook, tags, extra vars and flags")
  let warnings = command?.warnings(productionKeywords: ["prod", "production"]) ?? []
  check(warnings.count == 3 && warnings.contains { $0.contains("no --limit") }
      && warnings.contains { $0.contains("no --check") } && warnings.contains { $0.contains("secret") },
    "Production runs without --limit or --check, and secrets in -e, are flagged")
  check(AnsibleCommand.parse("ansible-playbook -i inventories/production/hosts.yml site.yml --limit web-01 --check")?
      .warnings(productionKeywords: ["prod", "production"]).isEmpty == true
      && AnsibleCommand.parse("ansible-playbook -i inventories/staging/hosts.yml site.yml")?
      .warnings(productionKeywords: ["prod", "production"]).isEmpty == true
      && AnsibleCommand.parse("ansible-playbook -i inventories/product-catalog/hosts site.yml")?
      .warnings(productionKeywords: ["prod"]).isEmpty == true,
    "Limited dry runs and non-production inventories are not flagged")
  check(AnsibleCommand.parse("ansible all -i inventories/prod/hosts -m ping")?
      .warnings(productionKeywords: ["prod"]).first?.contains("every production host") == true,
    "Ad-hoc commands against all production hosts are flagged")
  check(AnsibleCommand.parse("echo ansible") == nil && AnsibleCommand.parse("ansible-playbook a.yml && rm -rf /tmp/x") == nil
      && AnsibleCommand.parse("ansible-playbook site.yml \\\n  --limit web")?.limit == "web",
    "Only single Ansible command lines are recognized, including continued lines")
  check(command?.dryRun.hasSuffix("--check --diff") == true
      && AnsibleCommand.parse("ansible-playbook site.yml -l old")?.limited(to: ["a", "b"]) == "ansible-playbook site.yml --limit a,b",
    "Dry-run and limited variants rewrite the command")

  // Ansible output.
  let output = """
    TASK [nginx : Install packages] ************************************************
    fatal: [web-02]: FAILED! => {"changed": false, "cmd": ["apt-get", "install", "nginx"], "msg": "non-zero return code", "rc": 100, "stderr": "E: Unable to locate package nginx\\n", "stderr_lines": ["E: Unable to locate package nginx"], "stdout": "", "stdout_lines": []}
    fatal: [db-01]: UNREACHABLE! => {"changed": false, "msg": "Failed to connect to the host via ssh", "unreachable": true}

    PLAY RECAP *********************************************************************
    \u{1B}[0;32mweb-01\u{1B}[0m                     : ok=12   changed=3    unreachable=0    failed=0    skipped=1    rescued=0    ignored=0
    \u{1B}[0;31mweb-02\u{1B}[0m                     : ok=4    changed=0    unreachable=0    failed=1    skipped=0    rescued=0    ignored=0
    db-01                      : ok=0    changed=0    unreachable=1    failed=0    skipped=0    rescued=0    ignored=0
    """
  let recap = AnsibleOutput.recap(in: output)
  check(recap.map(\.host) == ["web-01", "web-02", "db-01"] && recap[0].ok == 12 && recap[0].changed == 3
      && recap.filter(\.needsRetry).map(\.host) == ["web-02", "db-01"],
    "PLAY RECAP is parsed, ignoring terminal colors")
  check(run(.ansibleRetry, output, history: ["git status", "ansible-playbook -i inventories/production/hosts.yml site.yml -l web"])
      == "ansible-playbook -i inventories/production/hosts.yml site.yml --limit web-02,db-01"
      && run(.ansibleRetry, output) == "--limit web-02,db-01",
    "Retry command reruns the latest copied playbook on failed and unreachable hosts")
  let readable = run(.ansibleError, output) ?? ""
  check(readable.contains("✗ web-02 — nginx : Install packages") && readable.contains("cmd: apt-get install nginx")
      && readable.contains("rc: 100") && readable.contains("    E: Unable to locate package nginx")
      && readable.contains("✗ db-01 — nginx : Install packages (unreachable)"),
    "Ansible failures become a readable summary with task, command, exit code and stderr")
  check(DevTransform.available(for: output).prefix(2) == [.ansibleError, .ansibleRetry]
      && DevTransform.available(for: risky).contains(.ansibleDryRun)
      && DevTransform.available(for: #"{"a":1}"#).contains(.jsonPretty),
    "Transforms offered match the copied content")

  // Ansible secrets.
  check(SensitiveContent.inspect("$ANSIBLE_VAULT;1.1;AES256\n6162636465663031323334").containsSecret
      && SensitiveContent.inspect("ansible_become_pass: hunter2").containsSecret
      && SensitiveContent.inspect("vault_password=abc123").containsSecret
      && SensitiveContent.inspect("-e db_password=hunter2").containsSecret
      && SensitiveContent.inspect("mysql_root_password: s3cr3t").containsSecret
      && !SensitiveContent.inspect("password_policy is documented in the wiki").containsSecret,
    "Ansible Vault blocks and Ansible password variables are masked")

  // Store: Ansible board, transforms and terminal paste review.
  let store = Store(folder: folder, defaults: defaults, pasteboard: pb, monitoring: false)
  check(!store.boards.contains(Store.ansibleBoard), "The Ansible board appears only when needed")
  pb.clearContents()
  pb.setString("ansible-playbook -i inventories/staging/hosts site.yml --limit web", forType: .string)
  store.capture(source: "Terminal", bundleID: "com.apple.Terminal")
  check(store.clips.first?.board == Store.ansibleBoard && store.boards.contains(Store.ansibleBoard),
    "Copied Ansible commands collect on the Ansible board")
  store.collectAnsibleCommands = false
  pb.clearContents()
  pb.setString("ansible all -m ping", forType: .string)
  store.capture(source: "Terminal", bundleID: "com.apple.Terminal")
  check(store.clips.first?.board == nil, "Collecting Ansible commands can be turned off")

  let json = Clip(source: "Test", kind: "Text", text: #"{"b":1,"a":2}"#)
  store.clips.insert(json, at: 0)
  store.applyTransform(.jsonPretty, to: json)
  check(store.clips.first?.text == "{\n  \"b\": 1,\n  \"a\": 2\n}" && pb.string(forType: .string) == store.clips.first?.text,
    "A transform copies its result and adds it to history")
  let token = Clip(source: "Test", kind: "Text", text: "password=hunter2")
  store.clips.insert(token, at: 0)
  let before = store.clips.count
  store.applyTransform(.base64Encode, to: token)
  check(store.clips.count == before && store.toast?.contains("Hiện tạm") == true, "Masked items are not transformed")

  var target = "com.apple.Terminal"
  store.pasteTarget = { target }
  store.copy(Clip(source: "Test", kind: "Text", text: "ls -la\n"))
  check(pb.string(forType: .string) == "ls -la" && store.pendingPaste == nil,
    "A single command pastes into a terminal without its trailing newline")
  store.copy(Clip(source: "Test", kind: "Text", text: "cd /tmp\nrm -rf build\n"))
  check(store.pendingPaste?.lines == 2 && store.pendingPaste?.text == "cd /tmp\nrm -rf build",
    "Several lines into a terminal ask for confirmation first")
  store.pendingPaste = nil
  check(store.terminalReview(for: Clip(source: "Test", kind: "Text", text: "ansible-playbook site.yml \\\n  --limit web\n"))?.lines == 1,
    "Lines continued with a backslash count as one command")
  store.copy(Clip(source: "Test", kind: "Text", text: risky))
  check(store.pendingPaste?.warnings.count == 3 && store.pendingPaste?.dryRun?.hasSuffix("--check --diff") == true,
    "Risky Ansible commands offer a --check --diff paste")
  check(store.pendingPaste?.display?.contains("hunter2") == false,
    "The paste review never shows a masked secret")
  store.pasteText(store.pendingPaste!.dryRun!)
  check(store.pendingPaste == nil && pb.string(forType: .string)?.hasSuffix("--check --diff") == true,
    "Choosing the dry run pastes the safer command")
  target = "com.apple.TextEdit"
  check(store.terminalReview(for: Clip(source: "Test", kind: "Text", text: "a\nb")) == nil,
    "Pastes into other apps are unchanged")
  target = "com.apple.Terminal"
  store.safeTerminalPaste = false
  check(store.terminalReview(for: Clip(source: "Test", kind: "Text", text: "a\nb")) == nil,
    "Terminal paste review can be turned off")
  // Typed search text must start after the magnifier, with or without a bezel.
  for bezeled in [false, true] {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 60), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let field = ClipboardSearchField(frame: NSRect(x: 20, y: 15, width: 220, height: 24))
    field.bezelStyle = .roundedBezel
    field.isBezeled = bezeled
    field.drawsBackground = bezeled
    window.contentView?.addSubview(field)
    window.makeFirstResponder(field)
    field.currentEditor()?.insertText("curl")
    let cell = field.cell as! NSSearchFieldCell
    let magnifier = cell.searchButtonRect(forBounds: field.bounds)
    let editor = field.currentEditor()!
    let typed = field.convert(editor.superview!.frame, from: editor.superview!.superview)
    check(typed.minX >= magnifier.maxX - 2 && field.stringValue == "curl",
      "Search text starts after the magnifier \(bezeled ? "with" : "without") a bezel")
    window.close()
  }
  return checks
}
