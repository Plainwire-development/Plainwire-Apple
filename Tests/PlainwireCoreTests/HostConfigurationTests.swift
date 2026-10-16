import Foundation
import Testing
@testable import PlainwireCore

@Test func hostAddressesNormalizeWithoutLosingDeploymentIdentity() throws {
  let configuration = try PlainwireConfiguration(serverAddress: "  HTTPS://Chat.Example:443/plainwire///  ")
  #expect(configuration.baseURL.absoluteString == "https://chat.example/plainwire")
  #expect(configuration.originHeader == "https://chat.example")
  #expect(try configuration.apiURL("me").absoluteString == "https://chat.example/plainwire/api/me")
  #expect(configuration.websocketURL.absoluteString == "wss://chat.example/plainwire/ws")
  #expect(configuration.appURL(fragment: "wire/abc").absoluteString == "https://chat.example/plainwire/#wire/abc")
  #expect(configuration.mediaURL("avatar.gif")?.absoluteString == "https://chat.example/plainwire/avatar.gif")
  #expect(configuration.mediaURL("/api/media/avatar.gif")?.absoluteString == "https://chat.example/plainwire/api/media/avatar.gif")
  #expect(configuration.isAppURL(configuration.appURL(fragment: "dm/1")))
  #expect(!configuration.isAppURL(URL(string: "https://chat.example/another/#dm/1")!))
  #expect(try PlainwireConfiguration(serverAddress: "chat.example").baseURL.absoluteString == "https://chat.example")
}

@Test(arguments: ["", " ", "https://", "file:///tmp/plainwire", "ftp://chat.example",
  "javascript:alert(1)", "https://user:password@chat.example", "https://chat.example?token=secret",
  "https://chat.example/#wire/invite", "https://chat.example:0", "https://chat.example:65536",
  "http://chat.example", "http://127.0.0.1.evil.example", "http://10.chat.0.0.4",
  "http://127.0.0.1..", "https://chat.example/a b"])
func invalidHostAddressesFailWithoutCrashing(_ address: String) {
  #expect(throws: PlainwireConfiguration.ServerAddressError.self) {
    try PlainwireConfiguration(serverAddress: address)
  }
}

@Test(arguments: ["http://localhost:8080", "http://127.0.0.1:8080", "http://[::1]:8080",
  "http://10.0.0.4:8080", "http://172.16.0.4", "http://192.168.1.5", "http://plainwire.local"])
func localSelfHostedServersSupportHTTP(_ address: String) throws {
  let configuration = try PlainwireConfiguration(serverAddress: address)
  #expect(configuration.websocketURL.scheme == "ws")
  #expect(configuration.mediaURL("/api/media/1")?.scheme == "http")
  #expect(configuration.mediaURL("http://unrelated.example/media") == nil)
}

@Test func portsAndPathsKeepDifferentDatabasesSeparate() throws {
  let first = try PlainwireConfiguration(serverAddress: "https://chat.example:8443/first")
  let second = try PlainwireConfiguration(serverAddress: "https://chat.example:9443/first")
  let third = try PlainwireConfiguration(serverAddress: "https://chat.example:8443/second")
  #expect(first.storageIdentifier != second.storageIdentifier)
  #expect(first.storageIdentifier != third.storageIdentifier)
  #expect(!first.isSameOrigin(second.baseURL))
  #expect(first.mediaURL("https://cdn.example/banner.gif") != nil)
  #expect(first.mediaURL("http://chat.example:8443/banner.gif") == nil)
}
