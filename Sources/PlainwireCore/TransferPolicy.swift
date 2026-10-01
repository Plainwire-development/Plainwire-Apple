import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Applies to the actual transfer, including redirect targets and bytes on disk.
public final class PlainwireTransferDelegate: NSObject, URLSessionDownloadDelegate {
  private let configuration: PlainwireConfiguration
  private let maximumBytes: Int64
  private let restrictToOrigin: Bool
  private let transfers = TransferContinuations()

  public init(configuration: PlainwireConfiguration, maximumBytes: Int64,
              restrictToOrigin: Bool = false) {
    self.configuration = configuration
    self.maximumBytes = maximumBytes
    self.restrictToOrigin = restrictToOrigin
  }

  public func download(_ request: URLRequest, using session: URLSession) async throws -> (URL, URLResponse) {
    // Foundation's async download convenience method does not deliver the
    // progress callbacks needed to enforce limits. Use a delegate-owned task.
    #if canImport(FoundationNetworking)
      let transferSession = URLSession(configuration: session.configuration, delegate: self, delegateQueue: nil)
      defer { transferSession.invalidateAndCancel() }
    #else
      let transferSession = session
    #endif
    let cancellation = TransferCancellation()
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        let task = transferSession.downloadTask(with: request)
        #if !canImport(FoundationNetworking)
          task.delegate = self
        #endif
        transfers.insert(continuation, for: task)
        cancellation.start(task)
      }
    } onCancel: { cancellation.cancel() }
  }

  public func urlSession(_ session: URLSession, task: URLSessionTask,
                         willPerformHTTPRedirection response: HTTPURLResponse,
                         newRequest request: URLRequest,
                         completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
    guard let url = request.url,
      configuration.mediaURL(url.absoluteString) != nil,
      !restrictToOrigin || configuration.isSameOrigin(url),
      response.url?.scheme != "https" || url.scheme == "https"
    else { completionHandler(nil); return }
    completionHandler(request)
  }

  public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                         didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                         totalBytesExpectedToWrite: Int64) {
    if totalBytesWritten > maximumBytes || totalBytesExpectedToWrite > maximumBytes {
      transfers.recordLimit(max(totalBytesWritten, totalBytesExpectedToWrite), for: downloadTask)
      downloadTask.cancel()
    }
  }

  public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                         didFinishDownloadingTo location: URL) {
    do {
      let size = Int64((try location.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0)
      guard size <= maximumBytes else { throw PlainwireAPIError.uploadTooLarge(size) }
      guard let response = downloadTask.response else { throw PlainwireAPIError.invalidResponse }
      // URLSession deletes its temporary file when this callback returns.
      let owned = FileManager.default.temporaryDirectory.appendingPathComponent("plainwire-transfer-" + UUID().uuidString)
      try FileManager.default.moveItem(at: location, to: owned)
      if !transfers.finish(downloadTask, result: .success((owned, response))) {
        try? FileManager.default.removeItem(at: owned)
      }
    } catch { _ = transfers.finish(downloadTask, result: .failure(error)) }
  }

  public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    _ = transfers.finish(task, result: .failure(error ?? PlainwireAPIError.invalidResponse))
  }
}

// These small containers protect their mutable state with a lock; callbacks
// and task cancellation can arrive on different executors.
private final class TransferContinuations: @unchecked Sendable {
  private let lock = NSLock()
  private var pending: [ObjectIdentifier: CheckedContinuation<(URL, URLResponse), any Error>] = [:]
  private var limits: [ObjectIdentifier: Int64] = [:]

  func insert(_ continuation: CheckedContinuation<(URL, URLResponse), any Error>, for task: URLSessionTask) {
    lock.withLock { pending[ObjectIdentifier(task)] = continuation }
  }

  func recordLimit(_ bytes: Int64, for task: URLSessionTask) {
    lock.withLock {
      if pending[ObjectIdentifier(task)] != nil { limits[ObjectIdentifier(task)] = bytes }
    }
  }

  @discardableResult func finish(_ task: URLSessionTask, result: Result<(URL, URLResponse), any Error>) -> Bool {
    let (continuation, bytes) = lock.withLock {
      (pending.removeValue(forKey: ObjectIdentifier(task)), limits.removeValue(forKey: ObjectIdentifier(task)))
    }
    guard let continuation else { return false }
    if let bytes { continuation.resume(throwing: PlainwireAPIError.uploadTooLarge(bytes)); return false }
    continuation.resume(with: result)
    return true
  }
}

private final class TransferCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var task: URLSessionTask?
  private var cancelled = false

  func start(_ task: URLSessionTask) {
    let cancelled = lock.withLock { self.task = task; return self.cancelled }
    task.resume()
    if cancelled { task.cancel() }
  }

  func cancel() {
    let task = lock.withLock { cancelled = true; return self.task }
    task?.cancel()
  }
}
