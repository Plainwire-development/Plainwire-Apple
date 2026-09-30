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
  public var email: String?
  public var emailVerified: Bool?

  enum CodingKeys: String, CodingKey {
    case id, username, bio, status, theme
    case displayName = "display_name"
    case avatarURL = "avatar_url"
    case bannerURL = "banner_url"
    case createdAt = "created_at"
    case lastSeen = "last_seen"
    case email
    case emailVerified = "email_verified"
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.wireInteger(PlainwireID.self, forKey: .id)
    username = try c.decode(String.self, forKey: .username)
    displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? username
    bio = try c.decodeIfPresent(String.self, forKey: .bio) ?? ""
    avatarURL = try c.decodeIfPresent(String.self, forKey: .avatarURL) ?? ""
    bannerURL = try c.decodeIfPresent(String.self, forKey: .bannerURL) ?? ""
    status = try c.decodeIfPresent(String.self, forKey: .status) ?? "online"
    theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? "system"
    createdAt = try c.optionalWireInteger(Int64.self, forKey: .createdAt) ?? 0
    lastSeen = try c.optionalWireInteger(Int64.self, forKey: .lastSeen) ?? 0
    email = try c.decodeIfPresent(String.self, forKey: .email)
    emailVerified = try c.decodeIfPresent(Bool.self, forKey: .emailVerified)
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

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    user = try c.decode(PWUser.self, forKey: .user)
    csrf = try c.decode(String.self, forKey: .csrf)
    serverTime = try c.wireInteger(Int64.self, forKey: .serverTime)
  }
}

public struct PWProfile: Codable, Hashable, Sendable {
  public let user: PWUser
  public let relationship: JSONValue?

  enum CodingKeys: String, CodingKey { case user, relationship }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    user = try c.decode(PWUser.self, forKey: .user)
    relationship = try c.decodeIfPresent(JSONValue.self, forKey: .relationship)
  }
}

public struct PWAccountSession: Codable, Hashable, Identifiable, Sendable {
  public let id: PlainwireID
  public let current: Bool
  public let createdAt: Int64
  public let lastSeen: Int64
  public let expiresAt: Int64
  enum CodingKeys: String, CodingKey {
    case id, current
    case createdAt = "created_at"
    case lastSeen = "last_seen"
    case expiresAt = "expires_at"
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.wireInteger(PlainwireID.self, forKey: .id)
    current = try c.decodeIfPresent(Bool.self, forKey: .current) ?? false
    createdAt = try c.optionalWireInteger(Int64.self, forKey: .createdAt) ?? 0
    lastSeen = try c.optionalWireInteger(Int64.self, forKey: .lastSeen) ?? 0
    expiresAt = try c.optionalWireInteger(Int64.self, forKey: .expiresAt) ?? 0
  }
}

public struct PWInvite: Codable, Hashable, Identifiable, Sendable {
  public let code: String
  public let channelId: PlainwireID?
  public let maxUses: Int?
  public let uses: Int?
  public let createdAt: Int64?
  public let expiresAt: Int64?
  public let revoked: Bool?
  public var id: String { code }
  enum CodingKeys: String, CodingKey {
    case code, uses, revoked
    case channelId = "channel_id"
    case maxUses = "max_uses"
    case createdAt = "created_at"
    case expiresAt = "expires_at"
  }


  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    code = try c.decode(String.self, forKey: .code)
    channelId = try c.optionalWireInteger(PlainwireID.self, forKey: .channelId)
    maxUses = try c.optionalWireInteger(Int.self, forKey: .maxUses)
    uses = try c.optionalWireInteger(Int.self, forKey: .uses)
    createdAt = try c.optionalWireInteger(Int64.self, forKey: .createdAt)
    expiresAt = try c.optionalWireInteger(Int64.self, forKey: .expiresAt)
    revoked = try c.decodeIfPresent(Bool.self, forKey: .revoked)
  }
}

public struct PWReaction: Codable, Hashable, Sendable {
  public let emoji: String
  public let count: Int
  public let me: Bool

  enum CodingKeys: String, CodingKey { case emoji, count, me }

  public init(emoji: String, count: Int, me: Bool) {
    self.emoji = emoji
    self.count = count
    self.me = me
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    emoji = try c.decode(String.self, forKey: .emoji)
    count = try c.optionalWireInteger(Int.self, forKey: .count) ?? 0
    me = try c.decodeIfPresent(Bool.self, forKey: .me) ?? false
  }
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

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.wireInteger(PlainwireID.self, forKey: .id)
    userId = try c.wireInteger(PlainwireID.self, forKey: .userId)
    displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
    body = try c.decode(String.self, forKey: .body)
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

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.wireInteger(PlainwireID.self, forKey: .id)
    userId = try c.wireInteger(PlainwireID.self, forKey: .userId)
    displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
    body = try c.decode(String.self, forKey: .body)
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
  public var pinned: Bool
  public let isBot: Bool

  enum CodingKeys: String, CodingKey {
    case id, scope, username, body, kind, reactions, pinned
    case isBot = "is_bot"
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

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.wireInteger(PlainwireID.self, forKey: .id)
    scope = try c.decode(String.self, forKey: .scope)
    scopeId = try c.wireInteger(PlainwireID.self, forKey: .scopeId)
    userId = try c.wireInteger(PlainwireID.self, forKey: .userId)
    username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
    displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? (username.isEmpty ? "Unknown member" : username)
    avatarURL = try c.decodeIfPresent(String.self, forKey: .avatarURL) ?? ""
    body = try c.decode(String.self, forKey: .body)
    replyToId = try c.optionalWireInteger(PlainwireID.self, forKey: .replyToId)
    replyTo = try c.decodeIfPresent(PWReplyPreview.self, forKey: .replyTo)
    createdAt = try c.optionalWireInteger(Int64.self, forKey: .createdAt) ?? 0
    editedAt = try c.optionalWireInteger(Int64.self, forKey: .editedAt)
    deletedAt = try c.optionalWireInteger(Int64.self, forKey: .deletedAt)
    kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "text"
    roleColor = try c.decodeIfPresent(String.self, forKey: .roleColor) ?? ""
    reactions = try c.decodeIfPresent([PWReaction].self, forKey: .reactions) ?? []
    forwardedFrom = try c.decodeIfPresent(PWForwardPreview.self, forKey: .forwardedFrom)
    pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
    isBot = try c.decodeIfPresent(Bool.self, forKey: .isBot) ?? false
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

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.wireInteger(PlainwireID.self, forKey: .id)
    name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    avatarURL = try c.decodeIfPresent(String.self, forKey: .avatarURL) ?? ""
    ownerId = try c.wireInteger(PlainwireID.self, forKey: .ownerId)
    createdAt = try c.optionalWireInteger(Int64.self, forKey: .createdAt) ?? 0
    updatedAt = try c.optionalWireInteger(Int64.self, forKey: .updatedAt) ?? 0
    lastReadMessageId = try c.optionalWireInteger(PlainwireID.self, forKey: .lastReadMessageId) ?? 0
    muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? false
    requestState = try c.decodeIfPresent(String.self, forKey: .requestState) ?? "accepted"
    groupRole = try c.decodeIfPresent(String.self, forKey: .groupRole) ?? "member"
    memberCount = try c.optionalWireInteger(Int.self, forKey: .memberCount) ?? 1
    lastBody = try c.decodeIfPresent(String.self, forKey: .lastBody) ?? ""
    lastMessageId = try c.optionalWireInteger(PlainwireID.self, forKey: .lastMessageId)
    unread = try c.optionalWireInteger(Int.self, forKey: .unread) ?? 0
    lastSenderId = try c.optionalWireInteger(PlainwireID.self, forKey: .lastSenderId)
    lastSenderName = try c.decodeIfPresent(String.self, forKey: .lastSenderName) ?? ""
    lastSenderUsername = try c.decodeIfPresent(String.self, forKey: .lastSenderUsername) ?? ""
    peerId = try c.optionalWireInteger(PlainwireID.self, forKey: .peerId)
    peerName = try c.decodeIfPresent(String.self, forKey: .peerName) ?? ""
    peerAvatarURL = try c.decodeIfPresent(String.self, forKey: .peerAvatarURL) ?? ""
    peerUsername = try c.decodeIfPresent(String.self, forKey: .peerUsername) ?? ""
  }
}

public struct PWCreatedConversation: Codable, Hashable, Sendable {
  public let id: PlainwireID
  public let existing: Bool?

  enum CodingKeys: String, CodingKey { case id, existing }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.wireInteger(PlainwireID.self, forKey: .id)
    existing = try c.decodeIfPresent(Bool.self, forKey: .existing)
  }
}

public struct PWConversationDetail: Codable, Hashable, Sendable {
  public let conversation: PWConversationInfo
  public let members: [PWConversationMember]

  enum CodingKeys: String, CodingKey { case conversation, members }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    conversation = try c.decode(PWConversationInfo.self, forKey: .conversation)
    members = try c.decodeIfPresent([PWConversationMember].self, forKey: .members) ?? []
  }
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

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.wireInteger(PlainwireID.self, forKey: .id)
    name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    avatarURL = try c.decodeIfPresent(String.self, forKey: .avatarURL) ?? ""
    ownerId = try c.wireInteger(PlainwireID.self, forKey: .ownerId)
    createdAt = try c.optionalWireInteger(Int64.self, forKey: .createdAt) ?? 0
    updatedAt = try c.optionalWireInteger(Int64.self, forKey: .updatedAt) ?? 0
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

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    user = try c.decode(PWUser.self, forKey: .user)
    lastReadMessageId = try c.optionalWireInteger(PlainwireID.self, forKey: .lastReadMessageId) ?? 0
    muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? false
    nickname = try c.decodeIfPresent(String.self, forKey: .nickname) ?? ""
    joinedAt = try c.optionalWireInteger(Int64.self, forKey: .joinedAt) ?? 0
    role = try c.decodeIfPresent(String.self, forKey: .role) ?? "member"
    groupRole = try c.decodeIfPresent(String.self, forKey: .groupRole) ?? "member"
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

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.wireInteger(PlainwireID.self, forKey: .id)
    ownerId = try c.wireInteger(PlainwireID.self, forKey: .ownerId)
    name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
    iconURL = try c.decodeIfPresent(String.self, forKey: .iconURL) ?? ""
    bannerURL = try c.decodeIfPresent(String.self, forKey: .bannerURL) ?? ""
    accentColor = try c.decodeIfPresent(String.self, forKey: .accentColor) ?? ""
    welcomeMessage = try c.decodeIfPresent(String.self, forKey: .welcomeMessage) ?? ""
    createdAt = try c.optionalWireInteger(Int64.self, forKey: .createdAt) ?? 0
    updatedAt = try c.optionalWireInteger(Int64.self, forKey: .updatedAt) ?? 0
    role = try c.decodeIfPresent(String.self, forKey: .role) ?? "member"
    memberCount = try c.optionalWireInteger(Int.self, forKey: .memberCount) ?? 1
    permissions = try c.optionalWireInteger(Int64.self, forKey: .permissions) ?? 0
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
  public let slowmodeSeconds: Int
  enum CodingKeys: String, CodingKey {
    case id, name, kind, position, topic
    case serverId = "server_id"
    case createdAt = "created_at"
    case categoryId = "category_id"
    case slowmodeSeconds = "slowmode_seconds"
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.wireInteger(PlainwireID.self, forKey: .id)
    serverId = try c.wireInteger(PlainwireID.self, forKey: .serverId)
    name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "text"
    position = try c.optionalWireInteger(Int.self, forKey: .position) ?? 0
    topic = try c.decodeIfPresent(String.self, forKey: .topic) ?? ""
    createdAt = try c.optionalWireInteger(Int64.self, forKey: .createdAt) ?? 0
    categoryId = try c.optionalWireInteger(PlainwireID.self, forKey: .categoryId)
    slowmodeSeconds = try c.optionalWireInteger(Int.self, forKey: .slowmodeSeconds) ?? 0
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

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.wireInteger(PlainwireID.self, forKey: .id)
    serverId = try c.wireInteger(PlainwireID.self, forKey: .serverId)
    name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    position = try c.optionalWireInteger(Int.self, forKey: .position) ?? 0
    createdAt = try c.optionalWireInteger(Int64.self, forKey: .createdAt) ?? 0
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

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    user = try c.decode(PWUser.self, forKey: .user)
    role = try c.decodeIfPresent(String.self, forKey: .role) ?? "member"
    muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? false
    joinedAt = try c.optionalWireInteger(Int64.self, forKey: .joinedAt) ?? 0
    nickname = try c.decodeIfPresent(String.self, forKey: .nickname)
    serverAvatarURL = try c.decodeIfPresent(String.self, forKey: .serverAvatarURL)
    serverBio = try c.decodeIfPresent(String.self, forKey: .serverBio)
    roleColor = try c.decodeIfPresent(String.self, forKey: .roleColor)
    roleNames = try c.decodeIfPresent(String.self, forKey: .roleNames)
  }
}

public struct PWServerDetail: Codable, Hashable, Sendable {
  public let server: PWServerInfo
  public let channels: [PWChannel]
  public let members: [PWServerMember]
  public let categories: [PWCategory]

  enum CodingKeys: String, CodingKey { case server, channels, members, categories }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    server = try c.decode(PWServerInfo.self, forKey: .server)
    channels = try c.decodeIfPresent([PWChannel].self, forKey: .channels) ?? []
    members = try c.decodeIfPresent([PWServerMember].self, forKey: .members) ?? []
    categories = try c.decodeIfPresent([PWCategory].self, forKey: .categories) ?? []
  }
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

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.wireInteger(PlainwireID.self, forKey: .id)
    ownerId = try c.wireInteger(PlainwireID.self, forKey: .ownerId)
    name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
    iconURL = try c.decodeIfPresent(String.self, forKey: .iconURL) ?? ""
    bannerURL = try c.decodeIfPresent(String.self, forKey: .bannerURL) ?? ""
    accentColor = try c.decodeIfPresent(String.self, forKey: .accentColor) ?? ""
    welcomeMessage = try c.decodeIfPresent(String.self, forKey: .welcomeMessage) ?? ""
    createdAt = try c.optionalWireInteger(Int64.self, forKey: .createdAt) ?? 0
    updatedAt = try c.optionalWireInteger(Int64.self, forKey: .updatedAt) ?? 0
    role = try c.decodeIfPresent(String.self, forKey: .role) ?? "member"
    defaultPermissions = try c.optionalWireInteger(Int64.self, forKey: .defaultPermissions)
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

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    status = try c.decodeIfPresent(String.self, forKey: .status) ?? "accepted"
    incoming = try c.decodeIfPresent(Bool.self, forKey: .incoming) ?? false
    outgoing = try c.decodeIfPresent(Bool.self, forKey: .outgoing) ?? false
    blockedByMe = try c.decodeIfPresent(Bool.self, forKey: .blockedByMe) ?? false
    user = try c.decode(PWUser.self, forKey: .user)
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

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.wireInteger(PlainwireID.self, forKey: .id)
    kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "text"
    body = try c.decode(String.self, forKey: .body)
    url = try c.decode(String.self, forKey: .url)
    seen = try c.decodeIfPresent(Bool.self, forKey: .seen) ?? false
    createdAt = try c.optionalWireInteger(Int64.self, forKey: .createdAt) ?? 0
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

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    now = try c.optionalWireInteger(Int64.self, forKey: .now) ?? 0
    since = try c.optionalWireInteger(Int64.self, forKey: .since) ?? 0
    notifications = try c.decodeIfPresent([PWNotification].self, forKey: .notifications) ?? []
    conversations = try c.decodeIfPresent([PWConversation].self, forKey: .conversations) ?? []
    servers = try c.decodeIfPresent([PWServer].self, forKey: .servers) ?? []
    friends = try c.decodeIfPresent([PWFriend].self, forKey: .friends) ?? []
    syncDegraded = try c.decodeIfPresent(Bool.self, forKey: .syncDegraded) ?? false
    syncWarnings = try c.decodeIfPresent([String].self, forKey: .syncWarnings) ?? []
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

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    messageId = try c.optionalWireInteger(PlainwireID.self, forKey: .messageId) ?? 0
    emoji = try c.decode(String.self, forKey: .emoji)
    count = try c.optionalWireInteger(Int.self, forKey: .count) ?? 0
    added = try c.decodeIfPresent(Bool.self, forKey: .added) ?? false
    userId = try c.wireInteger(PlainwireID.self, forKey: .userId)
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

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    contentType = try c.decodeIfPresent(String.self, forKey: .contentType) ?? ""
    size = try c.optionalWireInteger(Int64.self, forKey: .size) ?? 0
    url = try c.decode(String.self, forKey: .url)
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

// Some older endpoints serialize IDs as decimal strings. Decode those losslessly;
// malformed or out-of-range values still produce a useful decoding error.
private extension KeyedDecodingContainer {
  func wireInteger<T: FixedWidthInteger & Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
    if let number = try? decode(T.self, forKey: key) { return number }
    let text = try decode(String.self, forKey: key)
    guard let number = T(text) else {
      throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Invalid integer")
    }
    return number
  }

  func optionalWireInteger<T: FixedWidthInteger & Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
    guard contains(key), try !decodeNil(forKey: key) else { return nil }
    // Unnormalized SQL null atoms become "null" strings in pw_util:jsonable.
    // Older optional invite channel IDs also use an empty string for no channel.
    if let text = try? decode(String.self, forKey: key), text.isEmpty || text == "null" { return nil }
    return try wireInteger(type, forKey: key)
  }
}

public struct PWMessageSearch: Decodable, Sendable {
  public let messages: [PWMessage]
  public let query: String
  public let index: JSONValue?
  public var indexingComplete: Bool { index?.objectValue?["complete"]?.boolValue ?? true }
}

public struct PWMessageContext: Decodable, Sendable {
  public let targetId: PlainwireID
  public let scope: String
  public let scopeId: PlainwireID
  public let messages: [PWMessage]
  enum CodingKeys: String, CodingKey {
    case scope, messages
    case targetId = "target_id"
    case scopeId = "scope_id"
  }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    targetId = try c.wireInteger(Int64.self, forKey: .targetId)
    scope = try c.decode(String.self, forKey: .scope)
    scopeId = try c.wireInteger(Int64.self, forKey: .scopeId)
    messages = try c.decode([PWMessage].self, forKey: .messages)
  }
}
