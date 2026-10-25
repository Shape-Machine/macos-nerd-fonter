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
    ///
    /// Uses a classic download task because the async `download(from:delegate:)` never reports progress.
    static func download(from url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let download = Download(onProgress: progress)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.downloadTask(with: url) { temp, response, error in
                    download.finish()
                    do {
                        if let error { throw error }
                        guard let temp, let response else { throw URLError(.badServerResponse) }
                        try check(response)
                        // The system deletes `temp` when this handler returns, so move it first.
                        let kept = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
                        try FileManager.default.moveItem(at: temp, to: kept)
                        continuation.resume(returning: kept)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                download.start(task)
            }
        } onCancel: {
            download.cancel()
        }
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }
}

/// Tracks one download task: progress observation and cancellation, which may arrive before the task starts.
private final class Download: Sendable {
    private struct State {
        var task: URLSessionDownloadTask?
        var observation: NSKeyValueObservation?
        var isCancelled = false
        var lastPercent = -1
    }

    private let state = Mutex(State())
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func start(_ task: URLSessionDownloadTask) {
        let observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            self?.report(progress.fractionCompleted)
        }
        let isCancelled = state.withLock { state in
            state.task = task
            state.observation = observation
            return state.isCancelled
        }
        task.resume()
        if isCancelled { task.cancel() }
    }

    func cancel() {
        let task = state.withLock { state in
            state.isCancelled = true
            return state.task
        }
        task?.cancel()
    }

    func finish() {
        let observation = state.withLock { state in
            defer { state.observation = nil }
            return state.observation
        }
        observation?.invalidate()
    }

    private func report(_ fraction: Double) {
        let percent = Int(fraction * 100)
        let changed = state.withLock { state in
            defer { state.lastPercent = percent }
            return percent != state.lastPercent
        }
        if changed { onProgress(Double(percent) / 100) }
    }
}
