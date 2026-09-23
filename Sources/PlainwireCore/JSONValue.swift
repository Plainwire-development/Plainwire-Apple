import Foundation

public enum JSONValue: Codable, Hashable, Sendable {
  case string(String)
  case int(Int64)
  case double(Double)
  case bool(Bool)
  case object([String: JSONValue])
  case array([JSONValue])
  case null

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
      return
    }
    if let value = try? container.decode(Bool.self) {
      self = .bool(value)
      return
    }
    if let value = try? container.decode(Int64.self) {
      self = .int(value)
      return
    }
    if let value = try? container.decode(Double.self) {
      self = .double(value)
      return
    }
    if let value = try? container.decode(String.self) {
      self = .string(value)
      return
    }
    if let value = try? container.decode([String: JSONValue].self) {
      self = .object(value)
      return
    }
    if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
      return
    }
    throw DecodingError.typeMismatch(
      JSONValue.self,
      .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value"))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value): try container.encode(value)
    case .int(let value): try container.encode(value)
    case .double(let value): try container.encode(value)
    case .bool(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .null: try container.encodeNil()
    }
  }

  public var stringValue: String? {
    if case .string(let v) = self { return v }
    return nil
  }
  public var intValue: Int64? {
    switch self {
    case .int(let v): return v
    case .double(let v): return Int64(v)
    case .string(let v): return Int64(v)
    default: return nil
    }
  }
  public var boolValue: Bool? {
    if case .bool(let v) = self { return v }
    return nil
  }
  public var objectValue: [String: JSONValue]? {
    if case .object(let v) = self { return v }
    return nil
  }
  public var arrayValue: [JSONValue]? {
    if case .array(let v) = self { return v }
    return nil
  }
}
