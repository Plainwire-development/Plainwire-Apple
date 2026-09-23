import Foundation

public typealias PlainwireID = Int64

public struct PWUser: Codable, Hashable, Identifiable, Sendable {
  public let id: PlainwireID
  public var username: String
  public var displayName: String
  public var bio: String
  public var avatarURL: String
  public var bannerURL: String
  public var status: String
  public var theme: String
  public var createdAt: Int64
  public var lastSeen: Int64

  enum CodingKeys: String, CodingKey {
    case id, username, bio, status, theme
    case displayName = "display_name"
    case avatarURL = "avatar_url"
    case bannerURL = "banner_url"
    case createdAt = "created_at"
    case lastSeen = "last_seen"
  }
}

public struct PWSession: Codable, Hashable, Sendable {
  public let user: PWUser
  public let csrf: String
  public let serverTime: Int64
  enum CodingKeys: String, CodingKey {
    case user, csrf
    case serverTime = "server_time"
  }
}

public struct PWReaction: Codable, Hashable, Sendable {
  public let emoji: String
  public let count: Int
  public let me: Bool
}

public struct PWReplyPreview: Codable, Hashable, Sendable {
  public let id: PlainwireID
  public let userId: PlainwireID
  public let displayName: String
  public let body: String
  enum CodingKeys: String, CodingKey {
    case id, body
    case userId = "user_id"
    case displayName = "display_name"
  }
}

public struct PWForwardPreview: Codable, Hashable, Sendable {
  public let id: PlainwireID
  public let userId: PlainwireID
  public let displayName: String
  public let body: String
  enum CodingKeys: String, CodingKey {
    case id, body
    case userId = "user_id"
    case displayName = "display_name"
  }
}

public struct PWMessage: Codable, Hashable, Identifiable, Sendable {
  public let id: PlainwireID
  public let scope: String
  public let scopeId: PlainwireID
  public let userId: PlainwireID
  public let username: String
  public let displayName: String
  public let avatarURL: String
  public var body: String
  public let replyToId: PlainwireID?
  public let replyTo: PWReplyPreview?
  public let createdAt: Int64
  public let editedAt: Int64?
  public let deletedAt: Int64?
  public let kind: String
  public let roleColor: String
  public var reactions: [PWReaction]
  public let forwardedFrom: PWForwardPreview?

  enum CodingKeys: String, CodingKey {
    case id, scope, username, body, kind, reactions
    case scopeId = "scope_id"
    case userId = "user_id"
    case displayName = "display_name"
    case avatarURL = "avatar_url"
    case replyToId = "reply_to_id"
    case replyTo = "reply_to"
    case createdAt = "created_at"
    case editedAt = "edited_at"
    case deletedAt = "deleted_at"
    case roleColor = "role_color"
    case forwardedFrom = "forwarded_from"
  }
}

public struct PWConversation: Codable, Hashable, Identifiable, Sendable {
  public let id: PlainwireID
  public var name: String
  public let avatarURL: String
  public let ownerId: PlainwireID
  public let createdAt: Int64
  public let updatedAt: Int64
  public let lastReadMessageId: PlainwireID
  public let muted: Bool
  public let requestState: String
  public let groupRole: String
  public let memberCount: Int
  public let lastBody: String
  public let lastMessageId: PlainwireID?
  public let unread: Int
  public let lastSenderId: PlainwireID?
  public let lastSenderName: String
  public let lastSenderUsername: String
  public let peerId: PlainwireID?
  public let peerName: String
  public let peerAvatarURL: String
  public let peerUsername: String

  enum CodingKeys: String, CodingKey {
    case id, name, muted, unread
    case avatarURL = "avatar_url"
    case ownerId = "owner_id"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case lastReadMessageId = "last_read_message_id"
    case requestState = "request_state"
    case groupRole = "group_role"
    case memberCount = "member_count"
    case lastBody = "last_body"
    case lastMessageId = "last_message_id"
    case lastSenderId = "last_sender_id"
    case lastSenderName = "last_sender_name"
    case lastSenderUsername = "last_sender_username"
    case peerId = "peer_id"
    case peerName = "peer_name"
    case peerAvatarURL = "peer_avatar_url"
    case peerUsername = "peer_username"
  }
}

public struct PWCreatedConversation: Codable, Hashable, Sendable {
  public let id: PlainwireID
  public let existing: Bool?
}

public struct PWConversationDetail: Codable, Hashable, Sendable {
  public let conversation: PWConversationInfo
  public let members: [PWConversationMember]
}

public struct PWConversationInfo: Codable, Hashable, Identifiable, Sendable {
  public let id: PlainwireID
  public let name: String
  public let avatarURL: String
  public let ownerId: PlainwireID
  public let createdAt: Int64
  public let updatedAt: Int64
  enum CodingKeys: String, CodingKey {
    case id, name
    case avatarURL = "avatar_url"
    case ownerId = "owner_id"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}

public struct PWConversationMember: Codable, Hashable, Sendable {
  public let user: PWUser
  public let lastReadMessageId: PlainwireID
  public let muted: Bool
  public let nickname: String
  public let joinedAt: Int64
  public let role: String
  public let groupRole: String
  enum CodingKeys: String, CodingKey {
    case user, muted, nickname, role
    case lastReadMessageId = "last_read_message_id"
    case joinedAt = "joined_at"
    case groupRole = "group_role"
  }
}

public struct PWServer: Codable, Hashable, Identifiable, Sendable {
  public let id: PlainwireID
  public let ownerId: PlainwireID
  public var name: String
  public let description: String
  public let iconURL: String
  public let bannerURL: String
  public let accentColor: String
  public let welcomeMessage: String
  public let createdAt: Int64
  public let updatedAt: Int64
  public let role: String
  public let memberCount: Int
  public let permissions: Int64

  enum CodingKeys: String, CodingKey {
    case id, name, description, role, permissions
    case ownerId = "owner_id"
    case iconURL = "icon_url"
    case bannerURL = "banner_url"
    case accentColor = "accent_color"
    case welcomeMessage = "welcome_message"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case memberCount = "member_count"
  }
}

public struct PWChannel: Codable, Hashable, Identifiable, Sendable {
  public let id: PlainwireID
  public let serverId: PlainwireID
  public let name: String
  public let kind: String
  public let position: Int
  public let topic: String
  public let createdAt: Int64
  public let categoryId: PlainwireID?
  enum CodingKeys: String, CodingKey {
    case id, name, kind, position, topic
    case serverId = "server_id"
    case createdAt = "created_at"
    case categoryId = "category_id"
  }
}

public struct PWCategory: Codable, Hashable, Identifiable, Sendable {
  public let id: PlainwireID
  public let serverId: PlainwireID
  public let name: String
  public let position: Int
  public let createdAt: Int64
  enum CodingKeys: String, CodingKey {
    case id, name, position
    case serverId = "server_id"
    case createdAt = "created_at"
  }
}

public struct PWServerMember: Codable, Hashable, Sendable {
  public let user: PWUser
  public let role: String
  public let muted: Bool
  public let joinedAt: Int64
  public let nickname: String?
  public let serverAvatarURL: String?
  public let serverBio: String?
  public let roleColor: String?
  public let roleNames: String?
  enum CodingKeys: String, CodingKey {
    case user, role, muted, nickname
    case joinedAt = "joined_at"
    case serverAvatarURL = "server_avatar_url"
    case serverBio = "server_bio"
    case roleColor = "role_color"
    case roleNames = "role_names"
  }
}

public struct PWServerDetail: Codable, Hashable, Sendable {
  public let server: PWServerInfo
  public let channels: [PWChannel]
  public let members: [PWServerMember]
  public let categories: [PWCategory]
}

public struct PWServerInfo: Codable, Hashable, Identifiable, Sendable {
  public let id: PlainwireID
  public let ownerId: PlainwireID
  public let name: String
  public let description: String
  public let iconURL: String
  public let bannerURL: String
  public let accentColor: String
  public let welcomeMessage: String
  public let createdAt: Int64
  public let updatedAt: Int64
  public let role: String
  public let defaultPermissions: Int64?
  enum CodingKeys: String, CodingKey {
    case id, name, description, role
    case ownerId = "owner_id"
    case iconURL = "icon_url"
    case bannerURL = "banner_url"
    case accentColor = "accent_color"
    case welcomeMessage = "welcome_message"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case defaultPermissions = "default_permissions"
  }
}

public struct PWFriend: Codable, Hashable, Sendable {
  public let status: String
  public let incoming: Bool
  public let outgoing: Bool
  public let blockedByMe: Bool
  public let user: PWUser
  enum CodingKeys: String, CodingKey {
    case status, incoming, outgoing, user
    case blockedByMe = "blocked_by_me"
  }
}

public struct PWNotification: Codable, Hashable, Identifiable, Sendable {
  public let id: PlainwireID
  public let kind: String
  public let body: String
  public let url: String
  public let seen: Bool
  public let createdAt: Int64
  enum CodingKeys: String, CodingKey {
    case id, kind, body, url, seen
    case createdAt = "created_at"
  }
}

public struct PWSyncSnapshot: Codable, Hashable, Sendable {
  public let now: Int64
  public let since: Int64
  public let notifications: [PWNotification]
  public let conversations: [PWConversation]
  public let servers: [PWServer]
  public let friends: [PWFriend]
  public let syncDegraded: Bool
  public let syncWarnings: [String]
  enum CodingKeys: String, CodingKey {
    case now, since, notifications, conversations, servers, friends
    case syncDegraded = "sync_degraded"
    case syncWarnings = "sync_warnings"
  }
}

public struct PWReactionChange: Codable, Hashable, Sendable {
  public let messageId: PlainwireID
  public let emoji: String
  public let count: Int
  public let added: Bool
  public let userId: PlainwireID
  enum CodingKeys: String, CodingKey {
    case emoji, count, added
    case messageId = "message_id"
    case userId = "user_id"
  }
}

public struct PWUpload: Codable, Hashable, Sendable {
  public let id: String
  public let name: String
  public let contentType: String
  public let size: Int64
  public let url: String
  enum CodingKeys: String, CodingKey {
    case id, name, size, url
    case contentType = "content_type"
  }
}

public struct PWRTCConfiguration: Codable, Hashable, Sendable {
  public struct IceServer: Codable, Hashable, Sendable {
    public let urls: [String]
    public let username: String?
    public let credential: String?
    public init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      if let list = try? c.decode([String].self, forKey: .urls) {
        urls = list
      } else if let one = try? c.decode(String.self, forKey: .urls) {
        urls = [one]
      } else {
        urls = []
      }
      username = try c.decodeIfPresent(String.self, forKey: .username)
      credential = try c.decodeIfPresent(String.self, forKey: .credential)
    }
    enum CodingKeys: String, CodingKey { case urls, username, credential }
  }
  public let iceServers: [IceServer]
  public let iceTransportPolicy: String?
  public let validUntil: Int64?
  public let turnStatus: String?
  enum CodingKeys: String, CodingKey {
    case iceServers = "iceServers"
    case iceTransportPolicy = "iceTransportPolicy"
    case validUntil = "validUntil"
    case turnStatus = "turnStatus"
  }
}
