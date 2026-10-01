import Foundation

public enum PlainwireAPIError: Error, LocalizedError, Equatable, Sendable {
  case invalidURL
  case invalidResponse
  case notAuthenticated
  case server(status: Int, code: String, message: String?)
  case decoding(String)
  case transport(String)
  case uploadTooLarge(Int64)
  case invalidFile

  public var errorDescription: String? {
    switch self {
    case .invalidURL: return "Plainwire returned an invalid URL."
    case .invalidResponse: return "Plainwire returned an invalid response."
    case .notAuthenticated: return "Your Plainwire session has expired."
    case .server(_, let code, let message):
      return message?.isEmpty == false
        ? message : code.replacingOccurrences(of: "_", with: " ").capitalized
    case .decoding(let field):
      return "Unable to read the Plainwire response (\(field)). Refresh to try again."
    case .transport(let message): return message
    case .uploadTooLarge(let bytes): return "This file is too large (\(bytes) bytes)."
    case .invalidFile: return "The selected file could not be read."
    }
  }
}

struct APIEnvelope<T: Decodable>: Decodable {
  let ok: Bool
  let data: T?
  let error: String?
  let message: String?
}

struct EmptyPayload: Codable, Sendable {}
