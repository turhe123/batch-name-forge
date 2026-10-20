import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Which file date a date rule inserts.
enum DateSource { case modified, created, capture }

/// Thread-safe, lazily filled cache of file dates (filesystem, EXIF and video metadata).
final class MetadataCache: @unchecked Sendable {
    private var cache: [String: Date?] = [:]
    private let lock = NSLock()

    func date(_ source: DateSource, for url: URL) -> Date? {
        let key = "\(source)|\(url.path)"
        lock.lock()
        if let cached = cache[key] { lock.unlock(); return cached }
        lock.unlock()
        let value = load(source, url: url)
        lock.lock()
        cache[key] = value
        lock.unlock()
        return value
    }

    private func load(_ source: DateSource, url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey, .contentTypeKey])
        switch source {
        case .modified: return values?.contentModificationDate
        case .created: return values?.creationDate
        case .capture:
            guard let type = values?.contentType else { return nil }
            if type.conforms(to: .image) { return Self.exifDate(url) }
            if type.conforms(to: .audiovisualContent) { return Self.videoDate(url) }
            return nil
        }
    }

    /// Reads DateTimeOriginal (falling back to TIFF DateTime) via ImageIO.
    private static func exifDate(_ url: URL) -> Date? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return nil }
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let raw = (exif?[kCGImagePropertyExifDateTimeOriginal] ?? exif?[kCGImagePropertyExifDateTimeDigitized]
            ?? tiff?[kCGImagePropertyTIFFDateTime]) as? String
        guard let raw else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: raw)
    }

    private final class Box { var date: Date? }

    /// Reads a movie's creation date via AVFoundation. Must not be called on the main thread.
    private static func videoDate(_ url: URL) -> Date? {
        let asset = AVURLAsset(url: url)
        let box = Box()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            box.date = try? await asset.load(.creationDate)?.load(.dateValue)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5)
        return box.date
    }
}
