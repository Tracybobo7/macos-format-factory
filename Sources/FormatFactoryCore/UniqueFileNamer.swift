import Foundation

/// Coordinates filename allocation for concurrent conversions in this process.
public final class UniqueFileNamer: @unchecked Sendable {
    private let lock = NSLock()
    private var reservedPaths = Set<String>()

    public init() {}

    public func reserve(in directory: URL, baseName: String, extension fileExtension: String) -> URL {
        lock.lock()
        defer { lock.unlock() }

        var suffix = 1
        while true {
            let name = suffix == 1 ? baseName : "\(baseName)_\(suffix)"
            let candidate = directory.appendingPathComponent(name).appendingPathExtension(fileExtension)
            let path = candidate.standardizedFileURL.path
            if !FileManager.default.fileExists(atPath: path), !reservedPaths.contains(path) {
                reservedPaths.insert(path)
                return candidate
            }
            suffix += 1
        }
    }

    public func release(_ url: URL) {
        lock.lock()
        reservedPaths.remove(url.standardizedFileURL.path)
        lock.unlock()
    }
}

