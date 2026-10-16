import Foundation

public enum PWForumLimits {
  public static let name = 80
  public static let slug = 40
  public static let description = 280
  public static let title = 160
  public static let body = 12_000
  public static let search = 80

  // The reference server trims UTF-8 bytes, not Swift Character counts.
  public static func prefix(_ text: String, maximumBytes: Int) -> String {
    var result = ""
    var bytes = 0
    for character in text {
      let count = String(character).utf8.count
      guard bytes + count <= maximumBytes else { break }
      result.append(character)
      bytes += count
    }
    return result
  }
}

public struct PWForum: Decodable, Hashable, Identifiable, Sendable {
  public let id: PlainwireID
  public let slug: String
  public let name: String
  public let description: String
  public let position: Int
  public let ownerId: PlainwireID?
  public let threadCount: Int
  public let replyCount: Int
  public let lastAt: Int64?
  public let memberCount: Int
  public let joined: Bool

  enum CodingKeys: String, CodingKey {
    case id, slug, name, description, position, joined
    case ownerId = "owner_id", threadCount = "thread_count", replyCount = "reply_count"
    case lastAt = "last_at", memberCount = "member_count"
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.wireInteger(Int64.self, forKey: .id)
    slug = try c.decodeIfPresent(String.self, forKey: .slug) ?? ""
    name = try c.decode(String.self, forKey: .name)
    description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
    position = try c.optionalWireInteger(Int.self, forKey: .position) ?? 0
    ownerId = try c.optionalWireInteger(Int64.self, forKey: .ownerId)
    threadCount = try c.optionalWireInteger(Int.self, forKey: .threadCount) ?? 0
    replyCount = try c.optionalWireInteger(Int.self, forKey: .replyCount) ?? 0
    lastAt = try c.optionalWireInteger(Int64.self, forKey: .lastAt)
    memberCount = try c.optionalWireInteger(Int.self, forKey: .memberCount) ?? 0
    joined = try c.decodeIfPresent(Bool.self, forKey: .joined) ?? false
  }
}

public struct PWForumThread: Decodable, Hashable, Identifiable, Sendable {
  public let id: PlainwireID
  public let forumId: PlainwireID
  public let forumName: String
  public let userId: PlainwireID
  public let username: String
  public let displayName: String
  public let avatarURL: String
  public let title: String
  public let body: String
  public let rawBody: String
  public let createdAt: Int64
  public let updatedAt: Int64
  public let replyCount: Int
  public let locked: Bool
  public let pinned: Bool
  public let views: Int
  public var score: Int
  public var userVote: Int
  public let viewerJoined: Bool
  public let canEdit: Bool
  public let canDelete: Bool
  public let canModerate: Bool

  enum CodingKeys: String, CodingKey {
    case id, username, title, body, locked, pinned, views, score
    case forumId = "forum_id", forumName = "forum_name", userId = "user_id"
    case displayName = "display_name", avatarURL = "avatar_url", rawBody = "raw_body"
    case createdAt = "created_at", updatedAt = "updated_at", replyCount = "reply_count"
    case userVote = "user_vote", viewerJoined = "viewer_joined"
    case canEdit = "can_edit", canDelete = "can_delete", canModerate = "can_moderate"
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.wireInteger(Int64.self, forKey: .id)
    forumId = try c.wireInteger(Int64.self, forKey: .forumId)
    userId = try c.wireInteger(Int64.self, forKey: .userId)
    forumName = try c.decodeIfPresent(String.self, forKey: .forumName) ?? ""
    username = try c.decode(String.self, forKey: .username)
    displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? username
    avatarURL = try c.decodeIfPresent(String.self, forKey: .avatarURL) ?? ""
    title = try c.decode(String.self, forKey: .title)
    body = try c.decode(String.self, forKey: .body)
    rawBody = try c.decodeIfPresent(String.self, forKey: .rawBody) ?? body
    createdAt = try c.optionalWireInteger(Int64.self, forKey: .createdAt) ?? 0
    updatedAt = try c.optionalWireInteger(Int64.self, forKey: .updatedAt) ?? createdAt
    replyCount = try c.optionalWireInteger(Int.self, forKey: .replyCount) ?? 0
    views = try c.optionalWireInteger(Int.self, forKey: .views) ?? 0
    score = try c.optionalWireInteger(Int.self, forKey: .score) ?? 0
    userVote = try c.optionalWireInteger(Int.self, forKey: .userVote) ?? 0
    locked = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? false
    pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
    viewerJoined = try c.decodeIfPresent(Bool.self, forKey: .viewerJoined) ?? false
    // Missing permissions are never inferred from authorship or a cached profile.
    canEdit = try c.decodeIfPresent(Bool.self, forKey: .canEdit) ?? false
    canDelete = try c.decodeIfPresent(Bool.self, forKey: .canDelete) ?? false
    canModerate = try c.decodeIfPresent(Bool.self, forKey: .canModerate) ?? false
  }
}

public struct PWForumReply: Decodable, Hashable, Identifiable, Sendable {
  public let id: PlainwireID
  public let threadId: PlainwireID
  public let userId: PlainwireID
  public let username: String
  public let displayName: String
  public let avatarURL: String
  public let body: String
  public let rawBody: String
  public let createdAt: Int64
  public let updatedAt: Int64
  public let canEdit: Bool
  public let canDelete: Bool

  enum CodingKeys: String, CodingKey {
    case id, username, body
    case threadId = "thread_id", userId = "user_id", displayName = "display_name"
    case avatarURL = "avatar_url", rawBody = "raw_body", createdAt = "created_at", updatedAt = "updated_at"
    case canEdit = "can_edit", canDelete = "can_delete"
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.wireInteger(Int64.self, forKey: .id)
    threadId = try c.wireInteger(Int64.self, forKey: .threadId)
    userId = try c.wireInteger(Int64.self, forKey: .userId)
    username = try c.decode(String.self, forKey: .username)
    displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? username
    avatarURL = try c.decodeIfPresent(String.self, forKey: .avatarURL) ?? ""
    body = try c.decode(String.self, forKey: .body)
    rawBody = try c.decodeIfPresent(String.self, forKey: .rawBody) ?? body
    createdAt = try c.optionalWireInteger(Int64.self, forKey: .createdAt) ?? 0
    updatedAt = try c.optionalWireInteger(Int64.self, forKey: .updatedAt) ?? createdAt
    canEdit = try c.decodeIfPresent(Bool.self, forKey: .canEdit) ?? false
    canDelete = try c.decodeIfPresent(Bool.self, forKey: .canDelete) ?? false
  }
}

public struct PWForumThreadDetail: Decodable, Sendable {
  public var thread: PWForumThread
  public var replies: [PWForumReply]
}

public struct PWForumVote: Decodable, Sendable {
  public let threadId: PlainwireID
  public let score: Int
  public let userVote: Int
  enum CodingKeys: String, CodingKey {
    case threadId = "thread_id", score, userVote = "user_vote"
  }
}

public struct PWCreatedForumResource: Decodable, Sendable {
  public let id: PlainwireID
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.wireInteger(Int64.self, forKey: .id)
  }
  enum CodingKeys: String, CodingKey { case id }
}
