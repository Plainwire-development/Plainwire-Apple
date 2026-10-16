import Foundation

public enum PlainwireClientInfo {
  public static let version = "2.3.0"
  public static var platform: String {
    #if os(macOS)
      "macos"
    #elseif os(iOS)
      "ios"
    #else
      "other"
    #endif
  }
  public static let userAgent = "Plainwire-Apple/\(version) (\(platform))"
}

public struct PlainwireConfiguration: Hashable, Sendable {
  public static let defaultServerAddress = "https://plainwi.re"
  public let baseURL: URL

  public init(baseURL: URL = URL(string: "https://plainwi.re")!) {
    precondition(
      Self.isValidBaseURL(baseURL),
      "Plainwire requires HTTPS outside local development")
    self.baseURL = baseURL
  }

  /// Validate user-entered addresses without a precondition failure. A deployment
  /// may include a reverse-proxy path and a nonstandard port.
  public init(serverAddress: String) throws {
    let address = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !address.isEmpty, !address.contains(where: \.isWhitespace),
      var components = URLComponents(string: address.contains("://") ? address : "https://" + address),
      components.query == nil, components.fragment == nil,
      let url = components.url, Self.isValidBaseURL(url)
    else { throw ServerAddressError.invalidAddress }
    components.scheme = components.scheme?.lowercased()
    components.host = components.host?.lowercased()
    if (components.scheme == "https" && components.port == 443)
      || (components.scheme == "http" && components.port == 80) { components.port = nil }
    while components.path.hasSuffix("/") { components.path.removeLast() }
    guard let normalized = components.url else { throw ServerAddressError.invalidAddress }
    baseURL = normalized
  }

  public enum ServerAddressError: LocalizedError, Sendable {
    case invalidAddress
    public var errorDescription: String? {
      "Enter a Plainwire server URL, such as https://chat.example.com. HTTP is supported for local servers only."
    }
  }

  private static func isValidBaseURL(_ url: URL) -> Bool {
    guard let host = url.host?.lowercased(), !host.isEmpty,
      url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
      url.port.map({ (1...65535).contains($0) }) ?? true
    else { return false }
    if url.scheme?.lowercased() == "https" { return true }
    guard url.scheme?.lowercased() == "http" else { return false }
    if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local")
      || host == "[::1]" || host == "::1" { return true }
    let parts = host.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 4,
      parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) })
    else { return false }
    let octets = parts.compactMap { UInt8($0) }
    guard octets.count == 4 else { return false }
    return octets[0] == 127 || octets[0] == 10
      || (octets[0] == 192 && octets[1] == 168)
      || (octets[0] == 172 && (16...31).contains(octets[1]))
      || (octets[0] == 169 && octets[1] == 254)
  }

  /// Full deployment identity, including its port and reverse-proxy path.
  public var storageIdentifier: String { baseURL.absoluteString }

  public func appURL(fragment: String? = nil) -> URL {
    var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
    if !components.path.hasSuffix("/") { components.path += "/" }
    components.fragment = fragment
    return components.url!
  }

  public func isAppURL(_ url: URL) -> Bool {
    guard isSameOrigin(url) else { return false }
    let prefix = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return prefix.isEmpty || url.path == "/" + prefix || url.path.hasPrefix("/" + prefix + "/")
  }

  public func apiURL(_ path: String, query: [URLQueryItem] = []) throws -> URL {
    var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
    let prefix = components?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
    let suffix = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let joined = [prefix, "api", suffix].filter { !$0.isEmpty }.joined(separator: "/")
    components?.path = "/" + joined
    components?.queryItems = query.isEmpty ? nil : query
    guard let url = components?.url else { throw PlainwireAPIError.invalidURL }
    return url
  }

  public var originHeader: String {
    var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
    components.path = ""
    components.query = nil
    components.fragment = nil
    return components.url!.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
  }

  public var websocketURL: URL {
    var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
    components.scheme = components.scheme == "https" ? "wss" : "ws"
    let prefix = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    components.path = "/" + [prefix, "ws"].filter { !$0.isEmpty }.joined(separator: "/")
    components.query = nil
    components.fragment = nil
    return components.url!
  }

  public func mediaURL(_ value: String) -> URL? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if let absolute = URL(string: trimmed), absolute.scheme != nil {
      return isAllowedMediaURL(absolute) ? absolute : nil
    }

    // The backend emits root-relative /api/files and /api/media paths even
    // when a reverse proxy mounts this installation below a path prefix.
    let relativeValue = trimmed.hasPrefix("/api/") && !baseURL.path.isEmpty
      ? baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + trimmed
      : trimmed
    let relativeBase = relativeValue == trimmed ? appURL() : URL(string: originHeader + "/")!
    guard let relative = URL(string: relativeValue, relativeTo: relativeBase)?.absoluteURL else { return nil }
    return isAllowedMediaURL(relative) ? relative : nil
  }

  public func isSameOrigin(_ url: URL) -> Bool {
    let port = url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80)
    let basePort = baseURL.port ?? (baseURL.scheme?.lowercased() == "https" ? 443 : 80)
    return url.scheme?.lowercased() == baseURL.scheme?.lowercased()
      && url.host?.lowercased() == baseURL.host?.lowercased() && port == basePort
      && url.user == nil && url.password == nil
  }

  private func isAllowedMediaURL(_ url: URL) -> Bool {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      components.user == nil, components.password == nil,
      let scheme = components.scheme?.lowercased(), components.host != nil
    else { return false }

    if scheme == "https" { return true }
    guard scheme == "http" else { return false }

    // Remote messages must not initiate plaintext requests to local services.
    return baseURL.scheme == "http" && isSameOrigin(url)
  }
}
