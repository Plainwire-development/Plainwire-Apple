import Foundation
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PlainwireCore

@Test func missingProfileStatusDoesNotInventOnlinePresence() throws {
  let user = try JSONDecoder().decode(PWUser.self, from: Data(#"{"id":7,"username":"alice"}"#.utf8))
  #expect(user.status == "offline")
  #expect(PWPresence().status(for: user.id) == nil)
}

@Test func presenceSnapshotsReplaceStaleUsersAndPlatforms() {
  var presence = PWPresence()
  presence.apply(.init(type: "presence_state", payload: [
    "statuses": .object(["7": .string("online"), "9": .string("away")]),
    "platforms": .object(["7": .string("macos"), "9": .string("ios")]),
  ]))
  #expect(presence.status(for: 7) == "online")
  #expect(presence.platform(for: 7) == "macos")
  presence.apply(.init(type: "presence_state", payload: [
    "statuses": .object(["9": .string("offline")]),
    "platforms": .object(["9": .string("ios")]),
  ]))
  #expect(presence.status(for: 7) == nil)
  #expect(presence.platform(for: 7) == nil)
  #expect(presence.status(for: 9) == "offline")
  #expect(presence.platform(for: 9) == nil)
  presence.apply(.init(type: "presence_state", payload: ["statuses": .object([:])]))
  #expect(presence.status(for: 9) == nil)
}

@Test func presenceTransitionsNeverPreserveOfflinePlatformBadges() {
  var presence = PWPresence()
  presence.apply(.init(type: "presence_online", payload: ["user_id": .int(7), "platform": .string("macos")]))
  #expect(presence.status(for: 7) == "online")
  #expect(presence.platform(for: 7) == "macos")
  presence.apply(.init(type: "presence_offline", payload: ["user_id": .int(7)]))
  #expect(presence.status(for: 7) == "offline")
  #expect(presence.platform(for: 7) == nil)
  presence.apply(.init(type: "presence_status", payload: ["user_id": .int(7), "status": .string("invisible"), "platform": .string("macos")]))
  #expect(presence.status(for: 7) == "offline")
  #expect(presence.platform(for: 7) == nil)
  presence.reset()
  #expect(presence.status(for: 7) == nil)
}

@Test func removedPresenceWatchesForgetTheirState() {
  var presence = PWPresence()
  presence.apply(.init(type: "presence_state", payload: ["statuses": .object(["7": .string("online"), "9": .string("busy")])]))
  presence.retainUsers([9])
  #expect(presence.status(for: 7) == nil)
  #expect(presence.status(for: 9) == "busy")
}

@Test func originPolicyIncludesSchemeCredentialsAndEffectivePort() {
  let config = PlainwireConfiguration(baseURL: URL(string: "https://plainwire.example")!)
  #expect(config.isSameOrigin(URL(string: "https://plainwire.example:443/media")!))
  for url in ["https://plainwire.example:444/media", "http://plainwire.example/media",
              "https://plainwire.example.attacker.example/media", "https://user@plainwire.example/media"] {
    #expect(!config.isSameOrigin(URL(string: url)!))
  }
}

@Test func authenticatedRedirectsRejectCrossOriginAndDowngrades() async {
  let config = PlainwireConfiguration(baseURL: URL(string: "https://plainwire.example")!)
  let delegate = PlainwireTransferDelegate(configuration: config, maximumBytes: 1024, restrictToOrigin: true)
  let session = URLSession(configuration: .ephemeral)
  defer { session.invalidateAndCancel() }
  let response = HTTPURLResponse(url: config.baseURL, statusCode: 302, httpVersion: nil, headerFields: nil)!
  let task = session.dataTask(with: config.baseURL)
  for target in ["https://attacker.example/api", "http://plainwire.example/api"] {
    let result: URLRequest? = await withCheckedContinuation { continuation in
      delegate.urlSession(session, task: task, willPerformHTTPRedirection: response,
        newRequest: URLRequest(url: URL(string: target)!)) { continuation.resume(returning: $0) }
    }
    #expect(result == nil)
  }
  let result: URLRequest? = await withCheckedContinuation { continuation in
    delegate.urlSession(session, task: task, willPerformHTTPRedirection: response,
      newRequest: URLRequest(url: URL(string: "https://plainwire.example:443/api/me")!)) { continuation.resume(returning: $0) }
  }
  #expect(result?.url?.path == "/api/me")
}

@Test func mediaRedirectsAllowCDNsButRejectPlaintextLocalServices() async {
  let config = PlainwireConfiguration()
  let delegate = PlainwireTransferDelegate(configuration: config, maximumBytes: 1024)
  let session = URLSession(configuration: .ephemeral)
  defer { session.invalidateAndCancel() }
  let response = HTTPURLResponse(url: config.baseURL, statusCode: 302, httpVersion: nil, headerFields: nil)!
  let task = session.downloadTask(with: config.baseURL)
  for (target, allowed) in [("https://cdn.example/image.png", true), ("http://127.0.0.1/image.png", false)] {
    let result: URLRequest? = await withCheckedContinuation { continuation in
      delegate.urlSession(session, task: task, willPerformHTTPRedirection: response,
        newRequest: URLRequest(url: URL(string: target)!)) { continuation.resume(returning: $0) }
    }
    #expect((result != nil) == allowed)
  }
}

@Test func attachmentNamesStayWithinTheirDirectoryAndFilesystemLimit() {
  #expect(PWAttachment.safeFilename("../report.pdf") == "report.pdf")
  #expect(PWAttachment.safeFilename("..\\report.pdf") == "report.pdf")
  #expect(PWAttachment.safeFilename("..") == "Attachment")
  #expect(PWAttachment.safeFilename(".") == "Attachment")
  #expect(PWAttachment.safeFilename("\n\u{0}") == "Attachment")
  let name = PWAttachment.safeFilename(String(repeating: "😀", count: 100) + ".mp4")
  #expect(name.utf8.count <= 240)
  #expect(name.hasSuffix(".mp4"))
}
