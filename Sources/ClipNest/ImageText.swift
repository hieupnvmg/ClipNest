import AppKit
import ImageIO
import Vision

/// Text recognized in an image clip, tied to the exact image bytes it came from.
struct RecognizedText: Equatable {
  let digest: String
  let text: String
}

/// Recognizes text in clipboard images with Apple's Vision framework, entirely on this Mac.
/// One image at a time at utility priority: recognition is CPU/GPU heavy and never urgent.
final class ImageTextRecognizer {
  static let shared = ImageTextRecognizer()
  /// Long side of the image handed to Vision. Larger screenshots are downscaled first;
  /// this keeps memory bounded while staying sharp enough for on-screen text.
  static let maxPixelSize = 4096
  private let queue: OperationQueue

  init() {
    queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    queue.qualityOfService = .utility
    queue.name = "local.clipnest.image-text"
  }

  func recognize(read: @escaping () throws -> Data, completion: @escaping (String?) -> Void) {
    queue.addOperation {
      let text = autoreleasepool { () -> String? in
        guard let data = try? read() else { return nil }
        return Self.recognizeText(in: data)
      }
      DispatchQueue.main.async { completion(text) }
    }
  }
  func cancelAll() { queue.cancelAllOperations() }

  /// Returns recognized lines joined by newlines, "" when the image has no text, or nil
  /// when the image could not be read.
  static func recognizeText(in data: Data) -> String? {
    guard
      let source = CGImageSourceCreateWithData(
        data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary)
    else { return nil }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    if let languages = try? request.supportedRecognitionLanguages() {
      // Vietnamese first so diacritics are kept; English covers code, logs and UI text.
      let preferred = ["vi-VT", "en-US"].filter(languages.contains)
      if !preferred.isEmpty { request.recognitionLanguages = preferred }
    }
    do {
      try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
    } catch {
      return nil
    }
    return (request.results ?? [])
      .compactMap { $0.topCandidates(1).first?.string }
      .joined(separator: "\n")
  }
}
