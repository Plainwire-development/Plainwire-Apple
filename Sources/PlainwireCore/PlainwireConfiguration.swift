import Foundation

public enum PlainwireClientInfo {
  public static let version = "1.1.0"
  public static let userAgent = "Plainwire-Apple/\(version)"
}

public struct PlainwireConfiguration: Hashable, Sendable {
  public let baseURL: URL

  public init(baseURL: URL = URL(string: "https://plainwi.re")!) {
    precondition(
      baseURL.scheme == "https" || baseURL.host == "localhost" || baseURL.host == "127.0.0.1",
      "Plainwire requires HTTPS outside local development")
    self.baseURL = baseURL
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

    guard let relative = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL else { return nil }
    return isAllowedMediaURL(relative) ? relative : nil
  }

  private func isAllowedMediaURL(_ url: URL) -> Bool {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      components.user == nil, components.password == nil,
      let scheme = components.scheme?.lowercased(), let host = components.host?.lowercased()
    else { return false }

    if scheme == "https" { return true }
    guard scheme == "http" else { return false }

    let baseHost = baseURL.host?.lowercased()
    return host == "localhost" || host == "127.0.0.1"
      || (baseURL.scheme == "http" && host == baseHost)
  }
}
