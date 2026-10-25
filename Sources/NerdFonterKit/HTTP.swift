import Foundation
import Synchronization

/// Network access for the live app. We cache what we need ourselves, so skip URLSession's on-disk HTTP cache.
enum HTTP {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    static func data(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        try check(response)
        return data
    }

    /// Downloads to a temporary file the caller must move. Reports progress in whole-percent steps.
    static func download(from url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let (file, response) = try await session.download(from: url, delegate: ProgressDelegate(progress))
        try check(response)
        return file
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }
}

private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private let lastPercent = Mutex(-1)

    init(_ onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let percent = Int(100 * totalBytesWritten / totalBytesExpectedToWrite)
        let changed = lastPercent.withLock { last in
            defer { last = percent }
            return percent != last
        }
        if changed { onProgress(Double(percent) / 100) }
    }
}
