import Foundation
@main struct TransferSmoke {
 static func main() async throws {
  let base = URL(string: "FIXTURE_BASE_URL")!
  let config = PlainwireConfiguration(baseURL: base)
  let policy = PlainwireTransferDelegate(configuration: config, maximumBytes: 1024)
  let session = URLSession(configuration: .ephemeral, delegate: policy, delegateQueue: nil)
  defer { session.invalidateAndCancel() }
  let (file, _) = try await policy.download(URLRequest(url: base.appendingPathComponent("small")), using: session)
  guard try Data(contentsOf: file).count == 512 else { fatalError("Small transfer failed") }
  try FileManager.default.removeItem(at: file)
  for path in ["large", "unknown"] {
   do {
    let (file, _) = try await policy.download(URLRequest(url: base.appendingPathComponent(path)), using: session)
    try? FileManager.default.removeItem(at: file)
    fatalError("Oversized transfer was allowed: " + path)
   } catch let error as PlainwireAPIError { guard case .uploadTooLarge = error else { throw error } }
  }
  let api = PlainwireAPIClient(configuration: config)
  let restoration = Task { try await api.restoreSession() }
  for _ in 0..<100 {
   let (data, _) = try await session.data(from: base.appendingPathComponent("started"))
   if String(decoding: data, as: UTF8.self) == "yes" { break }
   try await Task.sleep(for: .milliseconds(10))
  }
  try? await api.logout()
  do { _ = try await restoration.value; fatalError("Old session was restored after logout") }
  catch is CancellationError {}
  guard await api.currentCSRFToken() == nil else { fatalError("Old CSRF survived logout") }
  print("Transfer smoke passed: small download, known/unknown size limits, and in-flight session invalidation.")
 }
}
