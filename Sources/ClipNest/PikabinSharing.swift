import AppKit
import SwiftUI

@MainActor final class PikabinSharing: ObservableObject {
  @Published var isPresented = false
  @Published private(set) var isUploading = false
  @Published private(set) var link: URL?
  @Published private(set) var copied = false
  @Published private(set) var error: String?
  private let client: PikabinPosting
  private let copyLink: (URL) -> Bool
  private let clipboardCount: () -> Int
  private var draft: String?
  private var task: Task<Void, Never>?
  private var generation = UUID()
  init(client: PikabinPosting = PikabinClient(), clipboardCount: @escaping () -> Int,
    copyLink: @escaping (URL) -> Bool) {
    self.client = client
    self.clipboardCount = clipboardCount
    self.copyLink = copyLink
  }
  nonisolated static func supports(_ item: Clip) -> Bool { ["Text", "Link", "Color"].contains(item.kind) && !item.text.isEmpty }
  func push(text: String) {
    guard !isUploading else { return }
    draft = text
    start()
  }
  func retry() { guard !isUploading, draft != nil else { return }; start() }
  private func start() {
    guard let text = draft else { return }
    task?.cancel()
    let token = UUID()
    generation = token
    let previousClipboard = clipboardCount()
    link = nil; copied = false; error = nil
    isPresented = true; isUploading = true
    task = Task { [weak self, client] in
      do {
        let url = try await client.createPaste(text: text)
        guard !Task.isCancelled, let self, self.generation == token else { return }
        self.link = url
        self.isUploading = false
        self.draft = nil
        self.task = nil
        if self.clipboardCount() == previousClipboard { self.copyResultLink() }
      } catch {
        guard !Task.isCancelled, let self, self.generation == token else { return }
        self.isUploading = false
        self.task = nil
        if let error = error as? PikabinError { self.error = error.localizedDescription }
        else if (error as? URLError)?.code == .timedOut { self.error = "Kết nối pikab.in hết thời gian chờ. Bạn có thể thử lại." }
        else { self.error = "Không kết nối được pikab.in. Kiểm tra mạng rồi thử lại." }
      }
    }
  }
  func copyResultLink() {
    guard let link else { return }
    copied = copyLink(link)
  }
  deinit { task?.cancel() }
  func dismiss() {
    generation = UUID()
    task?.cancel(); task = nil
    draft = nil; isUploading = false; isPresented = false
  }
}

extension Store {
  @MainActor func pushToPikabin(_ item: Clip) {
    guard PikabinSharing.supports(item) else { return }
    guard !isMasked(item) else {
      toast = "Hiện tạm nội dung trước khi gửi lên pikab.in."
      return
    }
    pikabin.push(text: item.text)
  }
}

struct PikabinPresentation: ViewModifier {
  @ObservedObject var sharing: PikabinSharing
  func body(content: Content) -> some View {
    content.sheet(isPresented: $sharing.isPresented, onDismiss: { sharing.dismiss() }) {
      PikabinShareSheet(sharing: sharing)
    }
    .onDisappear { sharing.dismiss() }
  }
}

struct PikabinShareSheet: View {
  @ObservedObject var sharing: PikabinSharing
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Image(systemName: "link.circle.fill").font(.system(size: 30)).foregroundStyle(.blue)
        VStack(alignment: .leading, spacing: 3) {
          Text("Push to pikab.in").font(.title2.bold())
          Text("Lưu 1 tuần · Ai có link đều có thể đọc").font(.caption).foregroundStyle(.secondary)
        }
      }
      if sharing.isUploading {
        HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Đang gửi nội dung text…") }
      } else if let url = sharing.link {
        Text("Link của bạn").font(.headline)
        Text(url.absoluteString).font(.system(.body, design: .monospaced))
          .textSelection(.enabled).padding(12).frame(maxWidth: .infinity, alignment: .leading)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        Text(sharing.copied ? "Link đã được copy vào clipboard." : "Nội dung clipboard hiện tại được giữ nguyên. Chọn Copy link để lấy link.")
          .font(.caption).foregroundStyle(.secondary)
      } else if let error = sharing.error {
        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
          .fixedSize(horizontal: false, vertical: true)
      }
      HStack {
        Spacer()
        if sharing.error != nil { Button("Thử lại") { sharing.retry() } }
        if sharing.link != nil { Button("Copy link") { sharing.copyResultLink() }.buttonStyle(.borderedProminent) }
        Button(sharing.isUploading ? "Hủy" : "Đóng") { sharing.dismiss() }
          .keyboardShortcut(.cancelAction)
      }
    }.padding(24).frame(width: 480)
  }
}
