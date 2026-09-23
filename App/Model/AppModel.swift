import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
  enum SessionState: Equatable { case booting, signedOut, ready }
  enum Section: String, CaseIterable, Identifiable {
    case messages, servers, friends, settings
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var systemImage: String {
      switch self {
      case .messages: "message.fill"
      case .servers: "rectangle.3.group.fill"
      case .friends: "person.2.fill"
      case .settings: "gearshape.fill"
      }
    }
  }

  struct MessageAttachment: Hashable, Identifiable {
    enum Kind: Hashable { case image, video, file, voice }
    let name: String
    let url: String
    let kind: Kind
    let isSpoiler: Bool
    var id: String { "\(kind):\(url):\(name):\(isSpoiler)" }
  }

  struct MessagePresentation: Identifiable {
    let message: PWMessage
    let startsGroup: Bool
    let dateHeader: String?
    let displayBody: String
    let displayMarkdown: AttributedString
    let attachments: [MessageAttachment]
    let timestampText: String
    var id: PlainwireID { message.id }
  }

  struct Room: Hashable, Identifiable, Sendable {
    let scope: String
    let roomID: PlainwireID
    let title: String
    let subtitle: String
    let avatarURL: String
    var identifier: String { "\(scope):\(roomID)" }
    var id: String { identifier }
    init(
      scope: String, roomID: PlainwireID, title: String, subtitle: String = "",
      avatarURL: String = ""
    ) {
      self.scope = scope
      self.roomID = roomID
      self.title = title
      self.subtitle = subtitle
      self.avatarURL = avatarURL
    }
  }

  private let config = PlainwireConfiguration()
  private let api: PlainwireAPIClient
  private let realtime: PlainwireRealtimeClient
  private var eventTask: Task<Void, Never>?
  private var stateTask: Task<Void, Never>?
  private var refreshTask: Task<Void, Never>?
  private var typingStopTask: Task<Void, Never>?
  private var typingExpiryTasks: [String: Task<Void, Never>] = [:]
  private var loadedRooms = Set<String>()
  private var loadingOlder = Set<String>()
  private var reachedBeginning = Set<String>()
  private var lastSyncCursor: Int64?
  private var roomAccessOrder: [String] = []
  private let maxCachedRooms = 12

  var sessionState: SessionState = .booting
  var session: PWSession?
  var selectedSection: Section = .messages
  var selectedRoom: Room?
  var selectedServerID: PlainwireID?
  var selectedChannelID: PlainwireID?
  var conversations: [PWConversation] = []
  var servers: [PWServer] = []
  var friends: [PWFriend] = []
  var serverDetails: [PlainwireID: PWServerDetail] = [:]
  var roomMessages: [String: [PWMessage]] = [:]
  private var roomPresentations: [String: [MessagePresentation]] = [:]
  var realtimeState: PlainwireRealtimeState = .stopped
  var lastSyncAt: Date?
  var errorMessage: String?
  var isBusy = false
  var syncWarning: String?
  var typingByRoom: [String: [PlainwireID: String]] = [:]
  private var livePresence: [PlainwireID: String] = [:]

  init() {
    api = PlainwireAPIClient(configuration: config)
    realtime = PlainwireRealtimeClient(configuration: config)
  }

  func start() async {
    guard sessionState == .booting else { return }
    do {
      let restored = try await api.restoreSession()
      session = restored
      try await bootstrap()
      sessionState = .ready
      startRealtimeTasks()
    } catch PlainwireAPIError.notAuthenticated {
      sessionState = .signedOut
    } catch {
      errorMessage = error.localizedDescription
      sessionState = .signedOut
    }
  }

  func login(username: String, password: String) async -> Bool {
    guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty
    else { return false }
    isBusy = true
    defer { isBusy = false }
    do {
      session = try await api.login(
        username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
      try await bootstrap()
      sessionState = .ready
      startRealtimeTasks()
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }

  func register(username: String, displayName: String, password: String) async -> Bool {
    isBusy = true
    defer { isBusy = false }
    do {
      session = try await api.register(
        username: username.trimmingCharacters(in: .whitespacesAndNewlines),
        displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines), password: password
      )
      try await bootstrap()
      sessionState = .ready
      startRealtimeTasks()
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }

  func logout() async {
    try? await api.logout()
    await realtime.stop()
    eventTask?.cancel()
    stateTask?.cancel()
    typingExpiryTasks.values.forEach { $0.cancel() }
    typingExpiryTasks = [:]
    typingByRoom = [:]
    livePresence = [:]
    session = nil
    conversations = []
    servers = []
    friends = []
    roomMessages = [:]
    roomPresentations = [:]
    roomAccessOrder = []
    serverDetails = [:]
    selectedRoom = nil
    selectedServerID = nil
    selectedChannelID = nil
    RemoteImageStore.shared.clear()
    URLCache.shared.removeAllCachedResponses()
    NotificationCoordinator.shared.updateBadgeCount(0)
    sessionState = .signedOut
  }

  func refresh() async {
    do { try await bootstrap(incremental: true) } catch PlainwireAPIError.notAuthenticated {
      await logout()
    } catch { errorMessage = error.localizedDescription }
  }

  func prepareForBackground() async {
    typingStopTask?.cancel()
    typingStopTask = nil
    if let room = selectedRoom {
      await realtime.sendTyping(scope: room.scope, id: room.roomID, active: false)
    }
    await realtime.stop()
  }

  func resumeFromForeground() async {
    guard sessionState == .ready else { return }
    await realtime.start()
    await updateRealtimeSubscriptions()
    await refresh()
  }

  func searchUsers(_ query: String) async -> [PWUser] {
    do { return try await api.searchUsers(query) } catch {
      errorMessage = error.localizedDescription
      return []
    }
  }

  func sendFriendRequest(to user: PWUser) async {
    do {
      try await api.requestFriend(userID: user.id)
      await refresh()
    } catch { errorMessage = error.localizedDescription }
  }

  func acceptFriend(_ user: PWUser) async {
    do {
      try await api.acceptFriend(userID: user.id)
      await refresh()
    } catch { errorMessage = error.localizedDescription }
  }

  func removeFriend(_ user: PWUser) async {
    do {
      try await api.removeFriend(userID: user.id)
      await refresh()
    } catch { errorMessage = error.localizedDescription }
  }

  func startConversation(with user: PWUser) async {
    do {
      let created = try await api.createConversation(userIDs: [user.id])
      try await bootstrap()
      if let conversation = conversations.first(where: { $0.id == created.id }) {
        await openConversation(conversation)
      }
    } catch { errorMessage = error.localizedDescription }
  }

  func openConversation(_ conversation: PWConversation) async {
    selectedSection = .messages
    selectedRoom = Room(
      scope: "direct", roomID: conversation.id, title: conversationDisplayName(conversation),
      subtitle: conversation.memberCount > 2
        ? "\(conversation.memberCount) members" : "@\(conversation.peerUsername)",
      avatarURL: conversationDisplayAvatar(conversation))
    await loadSelectedRoom()
    try? await api.markConversationRead(conversation.id)
    scheduleSync()
  }

  func openServer(_ server: PWServer) async {
    selectedSection = .servers
    selectedServerID = server.id
    do {
      let detail: PWServerDetail
      if let cached = serverDetails[server.id] {
        detail = cached
      } else {
        detail = try await api.server(id: server.id)
        serverDetails[server.id] = detail
        await updatePresenceWatch()
      }
      if selectedChannelID == nil
        || !detail.channels.contains(where: { $0.id == selectedChannelID })
      {
        if let channel = detail.channels.sorted(by: channelSort).first(where: { $0.kind == "text" })
        {
          await openChannel(channel, server: server)
        } else {
          selectedChannelID = nil
          selectedRoom = nil
        }
      }
      await updateRealtimeSubscriptions()
    } catch { errorMessage = error.localizedDescription }
  }

  func openChannel(_ channel: PWChannel, server: PWServer? = nil) async {
    guard channel.kind == "text" else { return }
    selectedSection = .servers
    selectedServerID = channel.serverId
    selectedChannelID = channel.id
    let serverName =
      server?.name ?? servers.first(where: { $0.id == channel.serverId })?.name ?? "Server"
    selectedRoom = Room(
      scope: "channel", roomID: channel.id, title: "# \(channel.name)",
      subtitle: channel.topic.isEmpty ? serverName : channel.topic)
    await loadSelectedRoom()
  }

  func loadSelectedRoom() async {
    guard let room = selectedRoom else { return }
    touchRoomCache(room.identifier)
    await updateRealtimeSubscriptions()
    guard !loadedRooms.contains(room.identifier) else { return }
    do {
      var messages = try await api.messages(scope: room.scope, id: room.roomID)
      messages.sort { $0.id < $1.id }
      setMessages(deduplicated(messages), roomKey: room.identifier)
      loadedRooms.insert(room.identifier)
      if messages.count < 50 { reachedBeginning.insert(room.identifier) }
    } catch { errorMessage = error.localizedDescription }
  }

  func loadOlderMessages() async {
    guard let room = selectedRoom, loadedRooms.contains(room.identifier),
      !loadingOlder.contains(room.identifier), !reachedBeginning.contains(room.identifier),
      let first = roomMessages[room.identifier]?.first
    else { return }
    loadingOlder.insert(room.identifier)
    defer { loadingOlder.remove(room.identifier) }
    do {
      let older = try await api.messages(scope: room.scope, id: room.roomID, before: first.id)
      if older.isEmpty || older.count < 50 { reachedBeginning.insert(room.identifier) }
      let combined = older.sorted { $0.id < $1.id } + (roomMessages[room.identifier] ?? [])
      setMessages(deduplicated(combined), roomKey: room.identifier)
    } catch { errorMessage = error.localizedDescription }
  }

  func sendMessage(_ text: String, replyTo: PlainwireID? = nil) async -> Bool {
    guard let room = selectedRoom else { return false }
    let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !body.isEmpty else { return false }
    do {
      let sent = try await api.sendMessage(
        scope: room.scope, id: room.roomID, body: body, replyTo: replyTo)
      upsert(sent, in: room.identifier)
      await realtime.sendTyping(scope: room.scope, id: room.roomID, active: false)
      scheduleSync()
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }

  func editMessage(_ message: PWMessage, body: String) async {
    do {
      upsert(
        try await api.editMessage(id: message.id, body: body),
        in: "\(message.scope):\(message.scopeId)")
    } catch { errorMessage = error.localizedDescription }
  }

  func deleteMessage(_ message: PWMessage) async {
    do {
      try await api.deleteMessage(id: message.id)
      removeMessage(message.id, roomKey: "\(message.scope):\(message.scopeId)")
    } catch { errorMessage = error.localizedDescription }
  }

  func toggleReaction(_ emoji: String, on message: PWMessage) async {
    do {
      let change = try await api.toggleReaction(messageID: message.id, emoji: emoji)
      applyReactionChange(
        messageID: change.messageId, emoji: change.emoji, count: change.count,
        added: change.added, userID: change.userId,
        preferredRoomKey: "\(message.scope):\(message.scopeId)")
    } catch { errorMessage = error.localizedDescription }
  }

  func noteTyping() {
    guard let room = selectedRoom else { return }
    typingStopTask?.cancel()
    Task { await realtime.sendTyping(scope: room.scope, id: room.roomID, active: true) }
    typingStopTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(2.5))
      guard !Task.isCancelled, let self, let room = self.selectedRoom else { return }
      await self.realtime.sendTyping(scope: room.scope, id: room.roomID, active: false)
    }
  }

  func upload(_ url: URL) async -> PWUpload? {
    do {
      let didAccess = url.startAccessingSecurityScopedResource()
      defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
      return try await api.upload(fileURL: url, contentType: Self.mimeType(for: url.pathExtension))
    } catch {
      errorMessage = error.localizedDescription
      return nil
    }
  }

  func attachmentMarkdown(for upload: PWUpload) -> String {
    let safeName = upload.name.replacingOccurrences(of: "]", with: "_").replacingOccurrences(
      of: "(", with: "_"
    ).replacingOccurrences(of: ")", with: "_").replacingOccurrences(of: "\n", with: "_")
    return upload.contentType.hasPrefix("image/")
      ? "![\(safeName)](\(upload.url))" : "[\(safeName)](\(upload.url))"
  }
  func mediaURL(_ value: String) -> URL? { config.mediaURL(value) }
  func messagesForSelectedRoom() -> [PWMessage] {
    guard let room = selectedRoom else { return [] }
    return roomMessages[room.identifier] ?? []
  }

  func messagePresentationsForSelectedRoom() -> [MessagePresentation] {
    guard let room = selectedRoom else { return [] }
    return roomPresentations[room.identifier] ?? []
  }

  func typingLabelForSelectedRoom() -> String? {
    guard let room = selectedRoom, let actors = typingByRoom[room.identifier], !actors.isEmpty
    else { return nil }
    let names = actors.values.sorted()
    switch names.count {
    case 1: return "\(names[0]) is typing…"
    case 2: return "\(names[0]) and \(names[1]) are typing…"
    default: return "\(names[0]), \(names[1]), and \(names.count - 2) others are typing…"
    }
  }
  func conversationDisplayName(_ c: PWConversation) -> String {
    !c.name.isEmpty ? c.name : (!c.peerName.isEmpty ? c.peerName : "Direct Message")
  }
  func conversationDisplayAvatar(_ c: PWConversation) -> String {
    !c.avatarURL.isEmpty ? c.avatarURL : c.peerAvatarURL
  }

  func presenceStatus(for user: PWUser) -> String {
    livePresence[user.id] ?? user.status
  }

  func handleDeepLink(_ url: URL) async {
    let components = url.pathComponents.filter { $0 != "/" }
    let host = url.host?.lowercased()
    if url.scheme == "plainwire" {
      let all = [host].compactMap { $0 } + components
      await routeDeepLink(parts: all)
    } else if url.host == config.baseURL.host {
      await routeDeepLink(parts: components)
    }
  }

  private func routeDeepLink(parts: [String]) async {
    guard !parts.isEmpty else { return }
    if let dmIndex = parts.firstIndex(where: { $0 == "dm" || $0 == "conversation" }),
      parts.count > dmIndex + 1, let id = Int64(parts[dmIndex + 1]),
      let conversation = conversations.first(where: { $0.id == id })
    {
      await openConversation(conversation)
      return
    }
    if let channelIndex = parts.firstIndex(of: "channel"), parts.count > channelIndex + 1,
      let id = Int64(parts[channelIndex + 1])
    {
      for server in servers {
        if serverDetails[server.id] == nil, let detail = try? await api.server(id: server.id) {
          serverDetails[server.id] = detail
        }
        if let channel = serverDetails[server.id]?.channels.first(where: { $0.id == id }) {
          await openChannel(channel, server: server)
          return
        }
      }
    }
  }

  private func updatePresenceWatch() async {
    var ids = Set<PlainwireID>()
    for friend in friends where friend.status == "accepted" { ids.insert(friend.user.id) }
    for conversation in conversations {
      if let peerID = conversation.peerId { ids.insert(peerID) }
    }
    for detail in serverDetails.values {
      for member in detail.members { ids.insert(member.user.id) }
    }
    if let ownID = session?.user.id { ids.remove(ownID) }
    await realtime.watchPresence(Array(ids.sorted().prefix(2_000)))
  }

  private func updateRealtimeSubscriptions() async {
    var subscriptions = Set<String>()
    if let room = selectedRoom { subscriptions.insert("\(room.scope):\(room.roomID)") }
    if let serverID = selectedServerID, selectedSection == .servers {
      subscriptions.insert("server:\(serverID)")
    }
    await realtime.setSubscriptions(subscriptions)
  }

  private func bootstrap(incremental: Bool = false) async throws {
    let snapshot = try await api.sync(since: incremental ? lastSyncCursor : nil)
    conversations = snapshot.conversations
    servers = snapshot.servers
    friends = snapshot.friends
    syncWarning = snapshot.syncDegraded ? snapshot.syncWarnings.joined(separator: " · ") : nil
    lastSyncCursor = snapshot.now
    lastSyncAt = Date()
    NotificationCoordinator.shared.updateBadgeCount(
      snapshot.conversations.reduce(0) { $0 + max(0, $1.unread) })
    await updatePresenceWatch()
    if let selected = selectedRoom, selected.scope == "direct",
      !conversations.contains(where: { $0.id == selected.roomID })
    {
      selectedRoom = nil
    }
  }

  private func startRealtimeTasks() {
    eventTask?.cancel()
    stateTask?.cancel()
    eventTask = Task { [weak self] in
      guard let self else { return }
      let events = await self.realtime.events()
      for await event in events {
        guard !Task.isCancelled else { break }
        await self.handle(event)
      }
    }
    stateTask = Task { [weak self] in
      guard let self else { return }
      let states = await self.realtime.states()
      for await value in states {
        guard !Task.isCancelled else { break }
        self.realtimeState = value
      }
    }
    Task { await realtime.start() }
  }

  private func handle(_ event: PlainwireRealtimeEvent) async {
    switch event.type {
    case "hello": if let refreshed = event.session { session = refreshed }
    case "message_created":
      if let message = event.message {
        upsert(message, in: "\(message.scope):\(message.scopeId)")
        notifyIncomingMessage(message)
      }
      scheduleSync()
    case "direct_message", "channel_message":
      if let message = event.message {
        upsert(message, in: "\(message.scope):\(message.scopeId)")
        notifyIncomingMessage(message)
      }
      scheduleSync()
    case "message_updated":
      if let message = event.message { upsert(message, in: "\(message.scope):\(message.scopeId)") }
    case "message_deleted":
      if let scope = event.scope, let scopeID = event.scopeID, let messageID = event.messageID {
        removeMessage(messageID, roomKey: "\(scope):\(scopeID)")
      }
    case "message_reaction_changed":
      if let messageID = event.messageID, let emoji = event.emoji,
        let count = event.reactionCount, let added = event.reactionAdded, let userID = event.userID
      {
        applyReactionChange(
          messageID: messageID, emoji: emoji, count: count, added: added, userID: userID)
      } else if let messageID = event.messageID, let room = selectedRoom {
        await refreshMessage(messageID, room: room)
      }
    case "conversation_updated", "conversation_created", "conversation_members_changed",
      "server_updated", "realtime_resync", "access_revoked":
      scheduleSync(delay: .milliseconds(250))
    case "presence_state":
      for (id, status) in event.statuses { livePresence[id] = status }
    case "presence_online", "presence_status":
      if let userID = event.userID, let status = event.status { livePresence[userID] = status }
    case "presence_offline":
      if let userID = event.userID { livePresence[userID] = "offline" }
    case "typing":
      handleTyping(event)
    case "account_deleted": await logout()
    default: break
    }
  }

  private func notifyIncomingMessage(_ message: PWMessage) {
    guard message.userId != session?.user.id else { return }
    let conversation = message.scope == "direct"
      ? conversations.first(where: { $0.id == message.scopeId }) : nil
    if conversation?.muted == true { return }
    let title = message.scope == "direct"
      ? conversation.map(conversationDisplayName)
      : serverDetails.values
        .flatMap(\.channels)
        .first(where: { $0.id == message.scopeId })
        .map { "# \($0.name)" }
    NotificationCoordinator.shared.notifyMessage(
      message, roomTitle: title, selectedRoom: selectedRoom?.identifier)
  }

  private func handleTyping(_ event: PlainwireRealtimeEvent) {
    guard let scope = event.scope, let scopeID = event.scopeID, let userID = event.userID,
      userID != session?.user.id
    else { return }
    let roomKey = "\(scope):\(scopeID)"
    let taskKey = "\(roomKey):\(userID)"
    typingExpiryTasks[taskKey]?.cancel()
    if event.active == true {
      var actors = typingByRoom[roomKey] ?? [:]
      let displayName = event.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
      actors[userID] =
        (displayName?.isEmpty == false ? displayName : nil) ?? event.username ?? "Someone"
      typingByRoom[roomKey] = actors
      typingExpiryTasks[taskKey] = Task { [weak self] in
        try? await Task.sleep(for: .seconds(7.5))
        guard !Task.isCancelled else { return }
        self?.removeTypingActor(userID, roomKey: roomKey, taskKey: taskKey)
      }
    } else {
      removeTypingActor(userID, roomKey: roomKey, taskKey: taskKey)
    }
  }

  private func removeTypingActor(_ userID: PlainwireID, roomKey: String, taskKey: String) {
    typingExpiryTasks[taskKey]?.cancel()
    typingExpiryTasks.removeValue(forKey: taskKey)
    typingByRoom[roomKey]?[userID] = nil
    if typingByRoom[roomKey]?.isEmpty == true { typingByRoom[roomKey] = nil }
  }

  private func applyReactionChange(
    messageID: PlainwireID, emoji: String, count: Int, added: Bool, userID: PlainwireID,
    preferredRoomKey: String? = nil
  ) {
    let keys: [String]
    if let preferredRoomKey {
      keys = [preferredRoomKey] + roomMessages.keys.filter { $0 != preferredRoomKey }
    } else {
      keys = Array(roomMessages.keys)
    }

    for key in keys {
      guard var list = roomMessages[key],
        let messageIndex = list.firstIndex(where: { $0.id == messageID })
      else { continue }

      var message = list[messageIndex]
      let wasMine = message.reactions.first(where: { $0.emoji == emoji })?.me ?? false
      let nextMine = userID == session?.user.id ? added : wasMine
      message.reactions.removeAll { $0.emoji == emoji }
      if count > 0 {
        message.reactions.append(PWReaction(emoji: emoji, count: count, me: nextMine))
      }
      list[messageIndex] = message
      setMessages(list, roomKey: key)
      return
    }
  }

  private func refreshMessage(_ id: PlainwireID, room: Room) async {
    guard let existing = roomMessages[room.identifier],
      let index = existing.firstIndex(where: { $0.id == id })
    else { return }
    do {
      let fresh = try await api.messages(scope: room.scope, id: room.roomID, after: max(0, id - 1))
      if let replacement = fresh.first(where: { $0.id == id }) {
        var list = existing
        list[index] = replacement
        setMessages(list, roomKey: room.identifier)
      }
    } catch {}
  }

  private func upsert(_ message: PWMessage, in roomKey: String) {
    var list = roomMessages[roomKey] ?? []
    if let index = list.firstIndex(where: { $0.id == message.id }) {
      list[index] = message
    } else {
      list.append(message)
      list.sort { $0.id < $1.id }
    }
    setMessages(list, roomKey: roomKey)
  }

  private func removeMessage(_ id: PlainwireID, roomKey: String) {
    guard var list = roomMessages[roomKey] else { return }
    list.removeAll { $0.id == id }
    setMessages(list, roomKey: roomKey)
  }

  private func setMessages(_ messages: [PWMessage], roomKey: String) {
    let previousPresentations = roomPresentations[roomKey] ?? []
    roomMessages[roomKey] = messages
    roomPresentations[roomKey] = buildPresentations(messages, reusing: previousPresentations)
    touchRoomCache(roomKey)
  }

  private func touchRoomCache(_ roomKey: String) {
    roomAccessOrder.removeAll { $0 == roomKey }
    roomAccessOrder.append(roomKey)

    let protectedRoom = selectedRoom?.identifier
    while roomAccessOrder.count > maxCachedRooms {
      guard let evictionIndex = roomAccessOrder.firstIndex(where: { $0 != protectedRoom }) else {
        break
      }
      let evicted = roomAccessOrder.remove(at: evictionIndex)
      roomMessages.removeValue(forKey: evicted)
      roomPresentations.removeValue(forKey: evicted)
      loadedRooms.remove(evicted)
      loadingOlder.remove(evicted)
      reachedBeginning.remove(evicted)
      typingByRoom.removeValue(forKey: evicted)
    }
  }

  private func buildPresentations(
    _ messages: [PWMessage], reusing existing: [MessagePresentation]
  ) -> [MessagePresentation] {
    let cached = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
    var previous: PWMessage?
    return messages.map { message in
      let messageDate = Date(timeIntervalSince1970: TimeInterval(message.createdAt) / 1000)
      let previousDate = previous.map {
        Date(timeIntervalSince1970: TimeInterval($0.createdAt) / 1000)
      }
      let startsDay = previousDate.map { !Calendar.current.isDate($0, inSameDayAs: messageDate) }
        ?? true
      let dateHeader: String? = startsDay
        ? (Calendar.current.isDateInToday(messageDate) ? "Today"
          : Calendar.current.isDateInYesterday(messageDate) ? "Yesterday"
          : messageDate.formatted(date: .complete, time: .omitted))
        : nil
      let startsGroup: Bool
      if let previous {
        startsGroup =
          startsDay || previous.userId != message.userId
          || message.createdAt - previous.createdAt > 5 * 60 * 1000
      } else {
        startsGroup = true
      }

      let reusable = cached[message.id].flatMap { old -> MessagePresentation? in
        guard old.message.body == message.body, old.message.createdAt == message.createdAt else {
          return nil
        }
        return old
      }

      let displayBody: String
      let markdown: AttributedString
      let attachments: [MessageAttachment]
      let timestampText: String

      if let reusable {
        displayBody = reusable.displayBody
        markdown = reusable.displayMarkdown
        attachments = reusable.attachments
        timestampText = reusable.timestampText
      } else {
        let parsed = Self.parseMessageBody(message.body)
        displayBody = parsed.text
        markdown =
          (try? AttributedString(
            markdown: displayBody,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
          ?? AttributedString(displayBody)
        attachments = parsed.attachments
        timestampText = Self.messageTimestamp(message.createdAt)
      }

      previous = message
      return MessagePresentation(
        message: message,
        startsGroup: startsGroup,
        dateHeader: dateHeader,
        displayBody: displayBody,
        displayMarkdown: markdown,
        attachments: attachments,
        timestampText: timestampText)
    }
  }

  private static func messageTimestamp(_ milliseconds: Int64) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    return date.formatted(
      date: Calendar.current.isDateInToday(date) ? .omitted : .abbreviated,
      time: .shortened)
  }

  private static let attachmentRegex = try? NSRegularExpression(
    pattern: #"(!?)\[([^\]\r\n]{0,240})\]\(([^)\r\n]{1,8192})\)"#)
  private static let embeddedImageDataRegex = try? NSRegularExpression(
    pattern: #"data:image/[A-Za-z0-9.+-]+;base64,[A-Za-z0-9+/=\r\n]{128,}"#,
    options: [.caseInsensitive])

  private static func parseMessageBody(_ body: String) -> (
    text: String, attachments: [MessageAttachment]
  ) {
    var working = body
    var attachments: [MessageAttachment] = []

    if let regex = attachmentRegex {
      let matches = regex.matches(in: body, range: NSRange(body.startIndex..., in: body))
      for match in matches.reversed() {
        guard let whole = Range(match.range(at: 0), in: working),
          let imageFlag = Range(match.range(at: 1), in: working),
          let nameRange = Range(match.range(at: 2), in: working),
          let urlRange = Range(match.range(at: 3), in: working)
        else { continue }

        let name = String(working[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let url = String(working[urlRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let isImage = !String(working[imageFlag]).isEmpty
        let isVoice = url.contains("#plainwire-voice-note")
        let isPlainwireFile = url.contains("/api/files/") || url.contains("/api/media/")
        guard isImage || isVoice || isPlainwireFile else { continue }
        let fileExtension = (name as NSString).pathExtension.lowercased()
        let isVideo = ["mp4", "mov", "m4v"].contains(fileExtension)
          || ["mp4", "mov", "m4v"].contains(
            ((URLComponents(string: url)?.path ?? "") as NSString).pathExtension.lowercased())
        let kind: MessageAttachment.Kind = isVoice ? .voice : (isImage ? .image : (isVideo ? .video : .file))
        let hasSpoilerPrefix = working[..<whole.lowerBound].hasSuffix("||")
        let hasSpoilerSuffix = working[whole.upperBound...].hasPrefix("||")
        let isSpoiler = hasSpoilerPrefix && hasSpoilerSuffix
        attachments.insert(
          MessageAttachment(
            name: name.isEmpty ? (isImage ? "Image" : (isVideo ? "Video" : "Attachment")) : name,
            url: url, kind: kind, isSpoiler: isSpoiler),
          at: 0)
        if isSpoiler {
          let start = working.index(whole.lowerBound, offsetBy: -2)
          let end = working.index(whole.upperBound, offsetBy: 2)
          working.removeSubrange(start..<end)
        } else {
          working.removeSubrange(whole)
        }
      }
    }

    if let dataRegex = embeddedImageDataRegex {
      working = dataRegex.stringByReplacingMatches(
        in: working, range: NSRange(working.startIndex..., in: working),
        withTemplate: "[Image attachment]")
    }

    let text =
      working
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map(String.init)
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return (text, attachments)
  }

  private func deduplicated(_ input: [PWMessage]) -> [PWMessage] {
    var seen = Set<PlainwireID>()
    return input.filter { seen.insert($0.id).inserted }
  }
  private func channelSort(_ lhs: PWChannel, _ rhs: PWChannel) -> Bool {
    lhs.position == rhs.position ? lhs.id < rhs.id : lhs.position < rhs.position
  }

  private func scheduleSync(delay: Duration = .milliseconds(450)) {
    refreshTask?.cancel()
    refreshTask = Task { [weak self] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      await self?.refresh()
    }
  }

  private static func mimeType(for ext: String) -> String {
    switch ext.lowercased() {
    case "png": "image/png"
    case "jpg", "jpeg": "image/jpeg"
    case "gif": "image/gif"
    case "webp": "image/webp"
    case "heic": "image/heic"
    case "pdf": "application/pdf"
    case "txt", "md": "text/plain"
    case "mp4": "video/mp4"
    case "mov": "video/quicktime"
    case "mp3": "audio/mpeg"
    case "m4a": "audio/mp4"
    default: "application/octet-stream"
    }
  }
}
