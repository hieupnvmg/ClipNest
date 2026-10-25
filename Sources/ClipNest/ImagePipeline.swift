import AppKit
import ImageIO
import SwiftUI

// A serial decode queue bounds transient memory to one original image per preview.
// Operation cancellation prevents offscreen cards from reading queued BLOBs.
final class ImagePipeline {
  static let shared = ImagePipeline()
  private let queue: OperationQueue
  init(queue: OperationQueue = OperationQueue()) {
    self.queue = queue
    queue.maxConcurrentOperationCount = 1
    queue.qualityOfService = .utility
    queue.name = "local.clipnest.thumbnails"
  }
  private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: CGImage?
    var image: CGImage? {
      get { lock.lock(); defer { lock.unlock() }; return value }
      set { lock.lock(); defer { lock.unlock() }; value = newValue }
    }
  }
  func thumbnail(read: @escaping () throws -> Data) async -> CGImage? {
    let operation = BlockOperation()
    let result = ResultBox()
    operation.addExecutionBlock { [weak operation] in
      autoreleasepool {
        guard operation?.isCancelled == false, let data = try? read(),
          operation?.isCancelled == false,
          let source = CGImageSourceCreateWithData(data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary) else { return }
        guard operation?.isCancelled == false else { return }
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: 600,
          kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary), operation?.isCancelled == false,
          let bitmap = CGContext(data: nil, width: thumbnail.width, height: thumbnail.height,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        // Detach the cached pixels from ImageIO's source/provider and original PNG bytes.
        bitmap.draw(thumbnail, in: CGRect(x: 0, y: 0, width: thumbnail.width, height: thumbnail.height))
        result.image = bitmap.makeImage()
      }
    }
    return await withTaskCancellationHandler(operation: {
      await withCheckedContinuation { continuation in
        operation.completionBlock = { continuation.resume(returning: result.image) }
        queue.addOperation(operation)
      }
    }, onCancel: { operation.cancel() })
  }
}

private final class ThumbnailState: ObservableObject {
  @Published var image: NSImage?
}
struct DeferredImagePreview: View {
  let clip: Clip
  let store: Store
  @StateObject private var state = ThumbnailState()
  var body: some View {
    Group {
      if let image = state.image {
        GeometryReader { geo in
          Image(nsImage: image).resizable().scaledToFill()
            .frame(width: geo.size.width, height: geo.size.height).clipped()
        }
      } else {
        Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .overlay(alignment: .bottom) {
      Text(clip.text).font(.system(size: 10)).padding(.horizontal, 7).padding(.vertical, 3)
        .background(.regularMaterial, in: Capsule()).padding(9)
    }
    .task(id: clip.imageReference) {
      let loaded = await store.previewImage(clip)
      if !Task.isCancelled { state.image = loaded }
    }
    .onDisappear { state.image = nil }
  }
}
