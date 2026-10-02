import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor
@Observable
final class AppModel {
  enum SessionState: Equatable { case booting, signedOut, ready, unavailable }
  enum Section: String, CaseIterable, Identifiable {
    case messages, servers, friends, activity, settings
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var systemImage: String {
      switch self {
      case .messages: "message.fill"
      case .servers: "rectangle.3.group.fill"
      case .friends: "person.2.fill"
      case .activity: "bell.fill"
      case .settings: "gearshape.fill"
      }
    }
  }

  typealias MessageAttachment = PWAttachment

  struct MessagePresentation: Identifiable {
    let message: PWMessage
    let startsGroup: Bool
    let dateHeader: String?
    let displayBody: String
    let textBlocks: [MessageTextBlock]
    let redactedTextBlocks: [MessageTextBlock]
    let attachments: [MessageAttachment]
    let timestampText: String
    var id: PlainwireID { message.id }
  }

  struct MessageTextBlock: Identifiable {
    let id: Int
    let block: PWTextBlock
    let markdown: AttributedString
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
  private var refreshTask: Task<Void, Never>?
  private var realtimeWork: [String: Task<Void, Never>] = [:]
  private var typingStopTask: Task<Void, Never>?
  private var typingExpiryTasks: [String: Task<Void, Never>] = [:]
  private var sessionGeneration = 0
  private var signingOut = false
  private var refreshing = false
  private var loadingRooms = Set<String>()
  private var reconcilingRooms = Set<String>()
  private var deletedMessages: [PlainwireID: Date] = [:]
  private var revokedRooms = Set<String>()
  private var roomRevisions: [String: Int] = [:]
  private var messageOperations = Set<String>()
  private var lastAcknowledgedMessageIDs: [PlainwireID: PlainwireID] = [:]
  private var readingConversations = Set<PlainwireID>()
  var applicationActive = true
  var readingRoomID: String?
  private var lastTypingSent: [String: Date] = [:]
  private var lastDirectRoomID: PlainwireID?
  private var pendingDeepLink: URL?
  private var draftSaveTask: Task<Void, Never>?
  var drafts: [String: String] = [:] { didSet { scheduleDraftSave() } }
  var notifications: [PWNotification] = []
  var previewFileURL: URL?
  var downloadingAttachment = false
  private var downloadFolder: URL?
  var replyTarget: PWMessage?
  var showMessageSearch = false
  var showNewConversation = false
  var recordingVoiceNote = false
  var navigationRoom: Room?
  var messageJumpID: PlainwireID?
  var contextRooms = Set<String>()
  var workspace = WorkspaceController()
  var showWorkspace = false
  var showSettings = false
  var calls = CallController()
  var unreadActivityCount: Int { notifications.filter { !$0.seen }.count }
  var unreadMessageCount: Int { conversations.reduce(0) { $0 + max(0, $1.unread) } }

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
  var conversationDetails: [PlainwireID: PWConversationDetail] = [:]
  private(set) var loadingConversationDetails: Set<PlainwireID> = []
  var roomMessages: [String: [PWMessage]] = [:]
  private var roomPresentations: [String: [MessagePresentation]] = [:]
  var realtimeState: PlainwireRealtimeState = .stopped
  var lastSyncAt: Date?
  var errorMessage: String?
  var isBusy = false
  var syncWarning: String?
  var typingByRoom: [String: [PlainwireID: String]] = [:]
  private var presence = PWPresence()

  init() {
    api = PlainwireAPIClient(configuration: config)
    realtime = PlainwireRealtimeClient(configuration: config)
    calls.send = { [weak self] payload in
      guard let self, self.sessionState == .ready else { return }
      try await self.realtime.send(payload)
    }
    calls.loadConfiguration = { [api] in try await api.rtcConfiguration() }
  }

  private var draftStorageKey: String? {
    session.map { "plainwire.apple.drafts.\(config.baseURL.host ?? "plainwire").\($0.user.id)" }
  }

  private func scheduleDraftSave() {
    draftSaveTask?.cancel()
    guard sessionState == .ready else { return }
    draftSaveTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(400))
      guard !Task.isCancelled else { return }
      self?.flushDrafts()
    }
  }

  func flushDrafts() {
    draftSaveTask?.cancel()
    draftSaveTask = nil
    guard sessionState == .ready, let key = draftStorageKey else { return }
    UserDefaults.standard.set(drafts.filter { !$0.value.isEmpty }, forKey: key)
  }

  func start() async {
    guard sessionState == .booting else { return }
    do {
      let restored = try await api.restoreSession()
      session = restored
      await finishSignIn()
    } catch PlainwireAPIError.notAuthenticated {
      sessionState = .signedOut
    } catch {
      errorMessage = error.localizedDescription
      sessionState = .unavailable
    }
  }

  func retryStart() async {
    errorMessage = nil
    sessionState = .booting
    await start()
  }

  private func finishSignIn() async {
    sessionGeneration += 1
    let generation = sessionGeneration
    if let key = draftStorageKey { drafts = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:] }
    do { try await bootstrap() }
    catch PlainwireAPIError.notAuthenticated { await logout(); return }
    catch { if generation == sessionGeneration { errorMessage = error.localizedDescription } }
    guard generation == sessionGeneration, session != nil else { return }
    // An unavailable panel must not discard a valid authenticated session.
    sessionState = .ready
    startRealtimeTasks()
    if let link = pendingDeepLink {
      pendingDeepLink = nil
      await handleDeepLink(link)
    }
  }

  func login(username: String, password: String) async -> Bool {
    guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty
    else { return false }
    guard !isBusy else { return false }
    isBusy = true
    defer { isBusy = false }
    do {
      session = try await api.login(
        username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
      await finishSignIn()
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }

  func register(username: String, displayName: String, password: String) async -> Bool {
    guard !isBusy else { return false }
    isBusy = true
    defer { isBusy = false }
    do {
      session = try await api.register(
        username: username.trimmingCharacters(in: .whitespacesAndNewlines),
        displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines), password: password
      )
      await finishSignIn()
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }

  func logout() async {
    guard !signingOut, sessionState != .signedOut || session != nil else { return }
    signingOut = true
    await calls.end()
    calls.reset()
    showWorkspace = false
    showSettings = false
    sessionState = .signedOut
    isBusy = true
    defer { isBusy = false; signingOut = false }
    sessionGeneration += 1
    let signOut = Task { try? await api.logout() }
    draftSaveTask?.cancel()
    draftSaveTask = nil
    if let key = draftStorageKey { UserDefaults.standard.removeObject(forKey: key) }
    refreshTask?.cancel()
    refreshTask = nil
    realtimeWork.values.forEach { $0.cancel() }
    realtimeWork.removeAll()
    typingStopTask?.cancel()
    loadedRooms = []
    loadingRooms = []
    loadingOlder = []
    reconcilingRooms = []
    reachedBeginning = []
    contextRooms = []
    lastDirectRoomID = nil
    lastSyncCursor = nil
    lastSyncAt = nil
    lastTypingSent = [:]
    deletedMessages = [:]
    revokedRooms = []
    roomRevisions = [:]
    messageOperations = []
    lastAcknowledgedMessageIDs = [:]
    readingConversations = []
    readingRoomID = nil
    drafts = [:]
    draftSaveTask?.cancel()
    draftSaveTask = nil
    notifications = []
    messageJumpID = nil
    replyTarget = nil
    navigationRoom = nil
    showMessageSearch = false
    showNewConversation = false
    previewFileURL = nil
    downloadingAttachment = false
    if let folder = downloadFolder { try? FileManager.default.removeItem(at: folder) }
    downloadFolder = nil
    workspace.reset()
    errorMessage = nil
    syncWarning = nil
    await realtime.stop()
    await realtime.unsubscribeAll()
    await realtime.watchPresence([])
    eventTask?.cancel()
    typingExpiryTasks.values.forEach { $0.cancel() }
    typingExpiryTasks = [:]
    typingByRoom = [:]
    presence.reset()
    session = nil
    conversations = []
    servers = []
    friends = []
    roomMessages = [:]
    roomPresentations = [:]
    roomAccessOrder = []
    serverDetails = [:]
    conversationDetails = [:]
    loadingConversationDetails = []
    selectedRoom = nil
    selectedServerID = nil
    selectedChannelID = nil
    RemoteImageStore.shared.clear()
    URLCache.shared.removeAllCachedResponses()
    NotificationCoordinator.shared.updateBadgeCount(0)
    NotificationCoordinator.shared.clearSessionNotifications()
    selectedSection = .messages
    sessionState = .signedOut
    await signOut.value
  }

  func refresh() async {
    guard sessionState == .ready, !refreshing else { return }
    refreshing = true
    let generation = sessionGeneration
    defer { refreshing = false }
    do {
      let restored = try await api.restoreSession()
      guard generation == sessionGeneration else { return }
      session = restored
      try await bootstrap(incremental: true)
      if let room = selectedRoom { await reconcileRoom(room) }
      if let id = selectedServerID, selectedSection == .servers {
        let detail = try await api.server(id: id)
        guard generation == sessionGeneration else { return }
        serverDetails[id] = detail
      }
    } catch PlainwireAPIError.notAuthenticated {
      if generation == sessionGeneration { await logout() }
    } catch {
      if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }
    }
  }

  func prepareForBackground() async {
    await calls.end()
    flushDrafts()
    typingStopTask?.cancel()
    typingStopTask = nil
    if let room = selectedRoom {
      await realtime.sendTyping(scope: room.scope, id: room.roomID, active: false)
    }
    presence.reset()
    await realtime.stop()
  }

  func resumeFromForeground() async {
    guard sessionState == .ready else { return }
    await realtime.start()
    await updateRealtimeSubscriptions()
    await refresh()
  }

  func searchUsers(_ query: String) async -> [PWUser] {
    let generation = sessionGeneration
    do {
      let users = try await api.searchUsers(query)
      return generation == sessionGeneration && !Task.isCancelled ? users : []
    } catch {
      if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }
      return []
    }
  }

  func profile(id: PlainwireID) async -> PWProfile? {
    let generation = sessionGeneration
    do {
      let result = try await api.profile(id: id)
      guard generation == sessionGeneration, !Task.isCancelled else { return nil }
      return result
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }; return nil }
  }

  func saveProfile(
    displayName: String, bio: String, status: String, avatarURL: String,
    bannerURL: String, theme: String
  ) async -> Bool {
    let generation = sessionGeneration
    do {
      try await api.updateProfile(
        displayName: displayName, bio: bio, status: status, avatarURL: avatarURL,
        bannerURL: bannerURL, theme: theme)
      let restored = try await api.restoreSession()
      guard generation == sessionGeneration else { return false }
      session = restored
      return true
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }; return false }
  }

  func accountSessions() async -> [PWAccountSession] {
    let generation = sessionGeneration
    do {
      let result = try await api.accountSessions()
      guard generation == sessionGeneration, !Task.isCancelled else { return [] }
      return result
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }; return [] }
  }

  func logoutOtherSessions() async -> Bool {
    let generation = sessionGeneration
    do {
      _ = try await api.logoutOtherSessions()
      guard generation == sessionGeneration, !Task.isCancelled else { return false }
      return true
    }
    catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }; return false }
  }

  func changePassword(current: String, new: String) async -> Bool {
    let generation = sessionGeneration
    do {
      try await api.changePassword(current: current, new: new)
      guard generation == sessionGeneration, !Task.isCancelled else { return false }
      return true
    }
    catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }; return false }
  }

  func changeUsername(current: String, new: String) async -> Bool {
    let generation = sessionGeneration
    guard let expected = session?.user.username else { return false }
    do {
      try await api.changeUsername(current: current, new: new, expected: expected)
      let restored = try await api.restoreSession()
      guard generation == sessionGeneration else { return false }
      session = restored
      return true
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }; return false }
  }

  func updateEmail(_ email: String, password: String) async -> String? {
    let generation = sessionGeneration
    do {
      let result = try await api.updateEmail(email, password: password)
      let restored = try await api.restoreSession()
      guard generation == sessionGeneration else { return nil }
      session = restored
      return result.objectValue?["email_delivery"]?.boolValue == false
        ? "Email saved, but the verification message could not be sent."
        : "Email saved. Check your inbox for verification."
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }; return nil }
  }

  func removeEmail(password: String) async -> Bool {
    let generation = sessionGeneration
    do {
      try await api.removeEmail(password: password)
      let restored = try await api.restoreSession()
      guard generation == sessionGeneration else { return false }
      session = restored
      return true
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }; return false }
  }

  func resendEmailVerification() async -> String? {
    let generation = sessionGeneration
    do {
      let result = try await api.resendEmailVerification()
      guard generation == sessionGeneration, !Task.isCancelled else { return nil }
      if result.objectValue?["already_verified"]?.boolValue == true { return "Email is already verified." }
      return result.objectValue?["email_delivery"]?.boolValue == false
        ? "The verification message could not be sent."
        : "Verification email sent."
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }; return nil }
  }

  func closeAccount(password: String, permanently: Bool) async -> Bool {
    let generation = sessionGeneration
    do {
      if permanently { try await api.deleteAccount(password: password) }
      else { try await api.disableAccount(password: password) }
      guard generation == sessionGeneration else { return false }
      await logout()
      return true
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }; return false }
  }

  func createServer(name: String, description: String) async -> Bool {
    let generation = sessionGeneration
    do {
      let result = try await api.createServer(name: name, description: description)
      guard generation == sessionGeneration, !Task.isCancelled else { return false }
      await refresh()
      if let id = result.objectValue?["id"]?.intValue,
        let server = servers.first(where: { $0.id == id }) { await openServer(server) }
      return true
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }; return false }
  }

  func ensureServerDetails(_ id: PlainwireID) async {
    guard serverDetails[id] == nil, !Task.isCancelled else { return }
    let generation = sessionGeneration
    do {
      let detail = try await api.server(id: id)
      guard generation == sessionGeneration, !Task.isCancelled else { return }
      serverDetails[id] = detail
      await updatePresenceWatch()
    } catch { if !Task.isCancelled, generation == sessionGeneration { errorMessage = error.localizedDescription } }
  }

  func reloadServer(_ id: PlainwireID) async {
    let generation = sessionGeneration
    do {
      let detail = try await api.server(id: id)
      guard generation == sessionGeneration else { return }
      serverDetails[id] = detail
      await refresh()
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription } }
  }

  func saveServer(id: PlainwireID, fields: [String: String]) async -> Bool {
    let generation = sessionGeneration
    do {
      try await api.updateServer(id: id, fields: fields)
      guard generation == sessionGeneration, !Task.isCancelled else { return false }
      await reloadServer(id)
      guard generation == sessionGeneration, !Task.isCancelled else { return false }
      return true
    }
    catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }; return false }
  }

  func createCategory(serverID: PlainwireID, name: String) async -> Bool {
    let generation = sessionGeneration
    do {
      try await api.createCategory(serverID: serverID, name: name)
      guard generation == sessionGeneration, !Task.isCancelled else { return false }
      await reloadServer(serverID)
      guard generation == sessionGeneration, !Task.isCancelled else { return false }
      return true
    }
    catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }; return false }
  }

  func createChannel(
    serverID: PlainwireID, name: String, kind: String, categoryID: PlainwireID?
  ) async -> Bool {
    let generation = sessionGeneration
    do {
      try await api.createChannel(serverID: serverID, name: name, kind: kind, categoryID: categoryID)
      guard generation == sessionGeneration, !Task.isCancelled else { return false }
      await reloadServer(serverID)
      return true
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }; return false }
  }

  func saveChannel(_ channel: PWChannel, name: String, topic: String, slowmodeSeconds: Int) async -> Bool {
    let generation = sessionGeneration
    do {
      try await api.updateChannel(id: channel.id, name: name, topic: topic, slowmodeSeconds: slowmodeSeconds)
      guard generation == sessionGeneration, !Task.isCancelled else { return false }
      await reloadServer(channel.serverId)
      if selectedChannelID == channel.id,
        let updated = serverDetails[channel.serverId]?.channels.first(where: { $0.id == channel.id }) {
        await openChannel(updated)
      }
      return true
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }; return false }
  }

  func invites(serverID: PlainwireID) async -> [PWInvite] {
    let generation = sessionGeneration
    do {
      let result = try await api.invites(serverID: serverID)
      guard generation == sessionGeneration, !Task.isCancelled else { return [] }
      return result
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }; return [] }
  }

  func createInvite(serverID: PlainwireID, channelID: PlainwireID?) async -> PWInvite? {
    let generation = sessionGeneration
    do {
      let result = try await api.createInvite(serverID: serverID, channelID: channelID)
      guard generation == sessionGeneration, !Task.isCancelled else { return nil }
      return result
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }; return nil }
  }

  func revokeInvite(serverID: PlainwireID, code: String) async -> Bool {
    let generation = sessionGeneration
    do {
      try await api.revokeInvite(serverID: serverID, code: code)
      guard generation == sessionGeneration, !Task.isCancelled else { return false }
      return true
    }
    catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }; return false }
  }

  func invitePreview(code: String) async -> JSONValue? {
    let generation = sessionGeneration
    do {
      let result = try await api.invitePreview(code: code)
      guard generation == sessionGeneration, !Task.isCancelled else { return nil }
      return result
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }; return nil }
  }

  func joinInvite(code: String) async -> Bool {
    let generation = sessionGeneration
    do {
      let result = try await api.joinInvite(code: code)
      guard generation == sessionGeneration, !Task.isCancelled else { return false }
      await refresh()
      if let serverID = result.objectValue?["server_id"]?.intValue,
        let server = servers.first(where: { $0.id == serverID }) { await openServer(server) }
      return true
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }; return false }
  }

  func saveMemberProfile(
    serverID: PlainwireID, nickname: String, bio: String, avatarURL: String
  ) async -> Bool {
    let generation = sessionGeneration
    guard let userID = session?.user.id else { return false }
    do {
      try await api.updateMemberProfile(
        serverID: serverID, userID: userID, nickname: nickname, bio: bio,
        avatarURL: avatarURL)
      guard generation == sessionGeneration, !Task.isCancelled else { return false }
      await reloadServer(serverID)
      return true
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }; return false }
  }

  func sendFriendRequest(to user: PWUser) async {
    let generation = sessionGeneration
    do {
      try await api.requestFriend(userID: user.id)
      guard generation == sessionGeneration, !Task.isCancelled else { return }
      await refresh()
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription } }
  }

  func acceptFriend(_ user: PWUser) async {
    let generation = sessionGeneration
    do {
      try await api.acceptFriend(userID: user.id)
      guard generation == sessionGeneration, !Task.isCancelled else { return }
      await refresh()
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription } }
  }

  func removeFriend(_ user: PWUser) async {
    let generation = sessionGeneration
    do {
      try await api.removeFriend(userID: user.id)
      guard generation == sessionGeneration, !Task.isCancelled else { return }
      await refresh()
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription } }
  }

  func startConversation(with user: PWUser) async {
    let generation = sessionGeneration
    do {
      let created = try await api.createConversation(userIDs: [user.id])
      guard generation == sessionGeneration, !Task.isCancelled else { return }
      try await bootstrap()
      if let conversation = conversations.first(where: { $0.id == created.id }) {
        await openConversation(conversation)
        guard generation == sessionGeneration, selectedRoom?.identifier == "direct:\(created.id)" else { return }
        navigationRoom = selectedRoom
      }
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription } }
  }

  func createConversation(users: [PWUser], name: String) async -> Bool {
    let generation = sessionGeneration
    do {
      let created = try await api.createConversation(userIDs: users.map(\.id), name: name)
      guard generation == sessionGeneration, !Task.isCancelled else { return false }
      try await bootstrap()
      guard let conversation = conversations.first(where: { $0.id == created.id }) else { return false }
      await openConversation(conversation)
      guard generation == sessionGeneration, selectedRoom?.identifier == "direct:\(created.id)" else { return false }
      navigationRoom = selectedRoom
      return true
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }; return false }
  }

  func updateConversation(id: PlainwireID, name: String) async -> Bool {
    let generation = sessionGeneration
    do {
      try await api.updateConversation(id: id, fields: ["name": .string(name)])
      guard generation == sessionGeneration, !Task.isCancelled else { return false }
      await loadConversationDetails(id)
      guard generation == sessionGeneration, !Task.isCancelled else { return false }
      try await bootstrap()
      if selectedRoom?.roomID == id, let conversation = conversations.first(where: { $0.id == id }) {
        await openConversation(conversation)
      }
      return true
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }; return false }
  }

  func addMembers(id: PlainwireID, users: [PWUser]) async -> Bool {
    let generation = sessionGeneration
    do {
      try await api.addConversationMembers(id: id, userIDs: users.map(\.id))
      guard generation == sessionGeneration, !Task.isCancelled else { return false }
      await loadConversationDetails(id)
      guard generation == sessionGeneration, !Task.isCancelled else { return false }
      try await bootstrap()
      return true
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }; return false }
  }

  func setMemberRole(conversationID: PlainwireID, userID: PlainwireID, moderator: Bool) async -> Bool {
    let generation = sessionGeneration
    do {
      try await api.setConversationRole(id: conversationID, userID: userID, moderator: moderator)
      guard generation == sessionGeneration, !Task.isCancelled else { return false }
      await loadConversationDetails(conversationID)
      return true
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }; return false }
  }
  func removeMember(conversationID: PlainwireID, userID: PlainwireID) async -> Bool {
    let generation = sessionGeneration
    do {
      try await api.removeConversationMember(id: conversationID, userID: userID)
      guard generation == sessionGeneration, !Task.isCancelled else { return false }
      await loadConversationDetails(conversationID)
      guard generation == sessionGeneration, !Task.isCancelled else { return false }
      await refresh()
      return true
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }; return false }
  }

  func conversationAction(_ conversation: PWConversation, action: PlainwireAPIClient.ConversationAction) async -> Bool {
    let generation = sessionGeneration
    do {
      try await api.conversationAction(id: conversation.id, action: action)
      guard generation == sessionGeneration, !Task.isCancelled else { return false }
      try await bootstrap()
      if action != .accept, selectedRoom?.roomID == conversation.id, selectedRoom?.scope == "direct" {
        selectedRoom = nil
        navigationRoom = nil
      }
      return true
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }; return false }
  }

  func blockUser(_ user: PWUser, blocked: Bool) async -> Bool {
    let generation = sessionGeneration
    do {
      try await api.blockUser(id: user.id, blocked: blocked)
      guard generation == sessionGeneration, !Task.isCancelled else { return false }
      await refresh()
      return true
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }; return false }
  }

  func searchMessages(_ query: String, before: PlainwireID? = nil) async throws -> PWMessageSearch {
    try await api.searchMessages(query, before: before)
  }

  func pinnedMessages(channelID: PlainwireID) async throws -> [PWMessage] {
    try await api.pinnedMessages(channelID: channelID)
  }

  func togglePin(_ message: PWMessage) async -> Bool {
    let generation = sessionGeneration
    let key = "pin:\(message.id)"
    guard messageOperations.insert(key).inserted else { return false }
    defer { if generation == sessionGeneration { messageOperations.remove(key) } }
    do {
      try await api.setPinned(messageID: message.id, pinned: !message.pinned)
      guard generation == sessionGeneration else { return false }
      var updated = roomMessages["\(message.scope):\(message.scopeId)"]?.first(where: { $0.id == message.id }) ?? message
      updated.pinned = !message.pinned
      upsert(updated, in: "\(message.scope):\(message.scopeId)")
      return true
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }; return false }
  }

  func forward(_ message: PWMessage, to room: Room) async -> Bool {
    let generation = sessionGeneration
    do {
      let sent = try await api.forwardMessage(id: message.id, scope: room.scope, targetID: room.roomID)
      guard generation == sessionGeneration else { return false }
      upsert(sent, in: room.identifier)
      scheduleSync()
      return true
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }; return false }
  }

  func jumpToMessage(id: PlainwireID) async {
    let generation = sessionGeneration
    if let room = selectedRoom, let message = roomMessages[room.identifier]?.first(where: { $0.id == id }) {
      messageJumpID = nil
      messageJumpID = message.id
    } else {
      do {
        let context = try await api.messageContext(id: id)
        guard generation == sessionGeneration else { return }
        guard generation == sessionGeneration, let room = selectedRoom, room.scope == context.scope, room.roomID == context.scopeId else { return }
        contextRooms.insert(room.identifier)
        reachedBeginning.remove(room.identifier)
        setMessages(context.messages.sorted { $0.id < $1.id }, roomKey: room.identifier)
        messageJumpID = id
      } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription } }
    }
  }

  func openMessage(_ message: PWMessage) async {
    let generation = sessionGeneration
    messageJumpID = nil
    do {
      let context = try await api.messageContext(id: message.id)
      guard generation == sessionGeneration else { return }
      if message.scope == "direct", let conversation = conversations.first(where: { $0.id == message.scopeId }) {
        await openConversation(conversation)
      } else if message.scope == "channel" {
        for server in servers {
          if serverDetails[server.id] == nil {
            let detail = try await api.server(id: server.id)
            guard generation == sessionGeneration else { return }
            serverDetails[server.id] = detail
          }
          if let channel = serverDetails[server.id]?.channels.first(where: { $0.id == message.scopeId }) {
            await openChannel(channel, server: server)
            break
          }
        }
      }
      guard generation == sessionGeneration, let room = selectedRoom, room.scope == context.scope, room.roomID == context.scopeId else { return }
      contextRooms.insert(room.identifier)
      reachedBeginning.remove(room.identifier)
      setMessages(context.messages.sorted { $0.id < $1.id }, roomKey: room.identifier)
      messageJumpID = context.targetId
      navigationRoom = room
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription } }
  }

  func returnToLive() async {
    guard let room = selectedRoom else { return }
    contextRooms.remove(room.identifier)
    loadedRooms.remove(room.identifier)
    reachedBeginning.remove(room.identifier)
    setMessages([], roomKey: room.identifier)
    messageJumpID = nil
    await loadSelectedRoom()
  }

  func refreshActivity() async throws {
    let generation = sessionGeneration
    let fetched = try await api.notifications()
    guard generation == sessionGeneration else { return }
    notifications = fetched
  }

  func markActivitySeen() async {
    do {
      try await api.markNotificationsSeen()
      try await refreshActivity()
    } catch { errorMessage = error.localizedDescription }
  }

  func clearActivity() async {
    let generation = sessionGeneration
    do {
      try await api.clearNotifications()
      notifications = []
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription } }
  }

  func openWorkspace(fragment: String? = nil) {
    workspace.route(fragment)
    showWorkspace = true
  }

  func startCall(in room: Room) {
    guard !recordingVoiceNote else { errorMessage = "Finish recording your voice note before starting a call."; return }
    guard room.scope == "direct" else {
      errorMessage = "Choose a voice channel from your server to join a call."
      return
    }
    calls.start(kind: .direct, id: room.roomID, title: room.title, userID: session?.user.id ?? 0)
  }

  func joinVoice(_ channel: PWChannel) {
    guard !recordingVoiceNote else { errorMessage = "Finish recording your voice note before joining voice."; return }
    calls.start(kind: .voice, id: channel.id, title: channel.name, userID: session?.user.id ?? 0)
  }

  func openConversation(_ conversation: PWConversation) async {
    if let previous = selectedRoom, previous.scope != "direct" || previous.roomID != conversation.id {
      Task { await realtime.sendTyping(scope: previous.scope, id: previous.roomID, active: false) }
    }
    messageJumpID = nil
    lastDirectRoomID = conversation.id
    selectedSection = .messages
    selectedRoom = Room(
      scope: "direct", roomID: conversation.id, title: conversationDisplayName(conversation),
      subtitle: conversation.memberCount > 2
        ? "\(conversation.memberCount) members" : "@\(conversation.peerUsername)",
      avatarURL: conversationDisplayAvatar(conversation))
    await loadSelectedRoom()
    await markRead(room: selectedRoom)
  }

  func loadConversationDetails(_ id: PlainwireID) async {
    let generation = sessionGeneration
    let revision = roomRevisions["direct:\(id)", default: 0]
    guard loadingConversationDetails.insert(id).inserted else { return }
    defer { if generation == sessionGeneration { loadingConversationDetails.remove(id) } }
    do {
      let detail = try await api.conversation(id: id)
      guard generation == sessionGeneration, !Task.isCancelled,
        revision == roomRevisions["direct:\(id)", default: 0] else { return }
      conversationDetails[id] = detail
      await updatePresenceWatch()
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription } }
  }

  func openServer(_ server: PWServer) async {
    let generation = sessionGeneration
    selectedSection = .servers
    selectedServerID = server.id
    do {
      let detail: PWServerDetail
      if let cached = serverDetails[server.id] {
        detail = cached
      } else {
        detail = try await api.server(id: server.id)
        guard generation == sessionGeneration else { return }
        serverDetails[server.id] = detail
        await updatePresenceWatch()
      }
      guard generation == sessionGeneration, selectedSection == .servers, selectedServerID == server.id else { return }
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
      if let id = selectedChannelID, let channel = detail.channels.first(where: { $0.id == id }),
        selectedRoom?.scope != "channel" || selectedRoom?.roomID != id {
        await openChannel(channel, server: server)
      }
      await updateRealtimeSubscriptions()
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription } }
  }

  func openChannel(_ channel: PWChannel, server: PWServer? = nil) async {
    guard channel.kind == "text" else {
      openWorkspace(fragment: "voice/\(channel.id)")
      return
    }
    if let previous = selectedRoom, previous.scope != "channel" || previous.roomID != channel.id {
      Task { await realtime.sendTyping(scope: previous.scope, id: previous.roomID, active: false) }
    }
    messageJumpID = nil
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

  var canSendInSelectedRoom: Bool {
    guard let room = selectedRoom else { return false }
    if room.scope == "direct" {
      guard let conversation = conversations.first(where: { $0.id == room.roomID }), conversation.requestState == "accepted" else { return false }
      return !friends.contains { $0.status == "blocked" && $0.user.id == conversation.peerId }
    }
    guard let server = servers.first(where: { $0.id == selectedServerID }) else { return false }
    return server.ownerId == session?.user.id || server.role == "owner" || server.role == "admin"
      || server.permissions & ((1 << 1) | (1 << 30)) != 0
  }
  var canPinMessages: Bool {
    guard let server = servers.first(where: { $0.id == selectedServerID }) else { return false }
    return server.ownerId == session?.user.id || server.role == "owner" || server.role == "admin"
      || server.permissions & ((1 << 2) | (1 << 30)) != 0
  }
  func canLoadOlder(_ room: Room) -> Bool {
    loadedRooms.contains(room.identifier) && !reachedBeginning.contains(room.identifier)
  }
  func isLoadingOlder(_ room: Room) -> Bool { loadingOlder.contains(room.identifier) }

  func isLoadingRoom(_ room: Room) -> Bool { loadingRooms.contains(room.identifier) }
  func hasLoadedRoom(_ room: Room) -> Bool { loadedRooms.contains(room.identifier) }

  func loadSelectedRoom() async {
    guard let room = selectedRoom else { return }
    touchRoomCache(room.identifier)
    await updateRealtimeSubscriptions()
    guard !loadedRooms.contains(room.identifier) else {
      await reconcileRoom(room)
      return
    }
    guard loadingRooms.insert(room.identifier).inserted else { return }
    let generation = sessionGeneration
    defer { if generation == sessionGeneration { loadingRooms.remove(room.identifier) } }
    let revision = roomRevisions[room.identifier, default: 0]
    do {
      let messages = try await api.messages(scope: room.scope, id: room.roomID)
      guard generation == sessionGeneration, !Task.isCancelled,
        revision == roomRevisions[room.identifier, default: 0] else { return }
      revokedRooms.remove(room.identifier)
      // Preserve realtime messages that arrived while the initial request was in flight.
      let combined = (roomMessages[room.identifier] ?? []) + messages
      setMessages(deduplicated(combined).sorted { $0.id < $1.id }, roomKey: room.identifier)
      loadedRooms.insert(room.identifier)
      if messages.count < 50 { reachedBeginning.insert(room.identifier) }
    } catch {
      if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }
    }
  }

  private func reconcileRoom(_ room: Room) async {
    guard loadedRooms.contains(room.identifier), !contextRooms.contains(room.identifier),
      reconcilingRooms.insert(room.identifier).inserted else { return }
    let generation = sessionGeneration
    let revision = roomRevisions[room.identifier, default: 0]
    defer { if generation == sessionGeneration { reconcilingRooms.remove(room.identifier) } }
    do {
      // Refresh the live tail to catch edits and deletions during a disconnect.
      let baseline = roomMessages[room.identifier] ?? []
      let tail = try await api.messages(scope: room.scope, id: room.roomID)
      guard generation == sessionGeneration, !Task.isCancelled,
        revision == roomRevisions[room.identifier, default: 0] else { return }
      let existing = roomMessages[room.identifier] ?? []
      if let first = tail.map(\.id).min() {
        let recentIDs = Set(tail.map(\.id))
        let older = existing.filter { $0.id < first || recentIDs.contains($0.id) }
        let baselineByID = Dictionary(uniqueKeysWithValues: baseline.map { ($0.id, $0) })
        let changed = existing.filter { baselineByID[$0.id] != $0 }
        setMessages(deduplicated(changed + tail + older).sorted { $0.id < $1.id }, roomKey: room.identifier)
      } else {
        let baselineIDs = Set(baseline.map(\.id))
        setMessages(existing.filter { !baselineIDs.contains($0.id) }, roomKey: room.identifier)
      }
      // A long disconnect may leave a gap between our cache and the live tail.
      var cursor = existing.last?.id
      let end = tail.last?.id ?? 0
      while let after = cursor, after < end {
        let page = try await api.messages(scope: room.scope, id: room.roomID, after: after)
        guard generation == sessionGeneration, !Task.isCancelled,
        revision == roomRevisions[room.identifier, default: 0] else { return }
        guard let next = page.map(\.id).max(), next > after else { break }
        let merged = page + (roomMessages[room.identifier] ?? [])
        setMessages(deduplicated(merged).sorted { $0.id < $1.id }, roomKey: room.identifier)
        cursor = next
        if page.count < 50 { break }
      }
    } catch {
      if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }
    }
  }

  func readConversation(_ conversation: PWConversation) async {
    let generation = sessionGeneration
    do { try await api.markConversationRead(conversation.id); scheduleSync() }
    catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription } }
  }

  func markRead(room: Room?) async {
    guard let room, room.scope == "direct", applicationActive,
      selectedRoom?.identifier == room.identifier, selectedSection == .messages,
      readingRoomID == room.identifier, !contextRooms.contains(room.identifier),
      let conversation = conversations.first(where: { $0.id == room.roomID }),
      !readingConversations.contains(room.roomID) else { return }
    let latest = roomMessages[room.identifier]?.last?.id ?? 0
    let acknowledged = max(lastAcknowledgedMessageIDs[room.roomID] ?? 0, conversation.lastReadMessageId)
    guard latest > acknowledged || conversation.unread > 0 else { return }
    let generation = sessionGeneration
    readingConversations.insert(room.roomID)
    do {
      try await api.markConversationRead(room.roomID)
      guard generation == sessionGeneration else { return }
      lastAcknowledgedMessageIDs[room.roomID] = latest
      readingConversations.remove(room.roomID)
      scheduleSync()
      // Handle a message that arrived during the acknowledgement request.
      if roomMessages[room.identifier]?.last?.id ?? 0 > latest { await markRead(room: room) }
    } catch { if generation == sessionGeneration { readingConversations.remove(room.roomID) } }
  }

  func loadOlderMessages() async {
    guard let room = selectedRoom, loadedRooms.contains(room.identifier),
      !loadingOlder.contains(room.identifier), !reachedBeginning.contains(room.identifier),
      let first = roomMessages[room.identifier]?.first
    else { return }
    let generation = sessionGeneration
    let revision = roomRevisions[room.identifier, default: 0]
    loadingOlder.insert(room.identifier)
    defer { if generation == sessionGeneration { loadingOlder.remove(room.identifier) } }
    do {
      let older = try await api.messages(scope: room.scope, id: room.roomID, before: first.id)
      guard generation == sessionGeneration, !Task.isCancelled,
        revision == roomRevisions[room.identifier, default: 0] else { return }
      if older.isEmpty || older.count < 50 { reachedBeginning.insert(room.identifier) }
      let combined = older.sorted { $0.id < $1.id } + (roomMessages[room.identifier] ?? [])
      setMessages(deduplicated(combined), roomKey: room.identifier)
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription } }
  }

  func sendMessage(_ text: String, in room: Room, replyTo: PlainwireID? = nil) async -> Bool {
    let generation = sessionGeneration
    let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !body.isEmpty else { return false }
    guard body.utf16.count <= 5000 else {
      errorMessage = "Messages can contain up to 5,000 characters."
      return false
    }
    do {
      let sent = try await api.sendMessage(
        scope: room.scope, id: room.roomID, body: body, replyTo: replyTo)
      guard generation == sessionGeneration else { return false }
      upsert(sent, in: room.identifier)
      await realtime.sendTyping(scope: room.scope, id: room.roomID, active: false)
      scheduleSync()
      return true
    } catch {
      if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }
      return false
    }
  }

  func editMessage(_ message: PWMessage, body: String) async -> Bool {
    let generation = sessionGeneration
    let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !body.isEmpty, body.utf16.count <= 5000 else {
      errorMessage = "Messages must contain between 1 and 5,000 characters."
      return false
    }
    do {
      let edited = try await api.editMessage(id: message.id, body: body)
      guard generation == sessionGeneration else { return false }
      upsert(edited, in: "\(message.scope):\(message.scopeId)")
      return true
    } catch { if generation == sessionGeneration { errorMessage = error.localizedDescription }; return false }
  }

  func deleteMessage(_ message: PWMessage) async {
    let generation = sessionGeneration
    do {
      try await api.deleteMessage(id: message.id)
      guard generation == sessionGeneration else { return }
      removeMessage(message.id, roomKey: "\(message.scope):\(message.scopeId)")
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription } }
  }

  func toggleReaction(_ emoji: String, on message: PWMessage) async {
    let generation = sessionGeneration
    let key = "reaction:\(message.id):\(emoji)"
    guard messageOperations.insert(key).inserted else { return }
    defer { if generation == sessionGeneration { messageOperations.remove(key) } }
    do {
      let change = try await api.toggleReaction(messageID: message.id, emoji: emoji)
      guard generation == sessionGeneration else { return }
      applyReactionChange(
        messageID: change.messageId, emoji: change.emoji, count: change.count,
        added: change.added, userID: change.userId,
        preferredRoomKey: "\(message.scope):\(message.scopeId)")
    } catch { if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription } }
  }

  func noteTyping() {
    guard let room = selectedRoom else { return }
    typingStopTask?.cancel()
    if Date().timeIntervalSince(lastTypingSent[room.identifier] ?? .distantPast) >= 2 {
      lastTypingSent[room.identifier] = Date()
      Task { await realtime.sendTyping(scope: room.scope, id: room.roomID, active: true) }
    }
    typingStopTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(2.5))
      guard !Task.isCancelled, let self else { return }
      await self.realtime.sendTyping(scope: room.scope, id: room.roomID, active: false)
    }
  }

  func upload(_ url: URL) async -> PWUpload? {
    let generation = sessionGeneration
    do {
      let didAccess = url.startAccessingSecurityScopedResource()
      defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
      let result = try await api.upload(fileURL: url, contentType: Self.mimeType(for: url.pathExtension))
      guard generation == sessionGeneration, !Task.isCancelled else { return nil }
      return result
    } catch {
      if generation == sessionGeneration, !Task.isCancelled { errorMessage = error.localizedDescription }
      return nil
    }
  }

  func previewAttachment(url: URL, name: String) async {
    guard !downloadingAttachment else { return }
    downloadingAttachment = true
    let generation = sessionGeneration
    defer { if generation == sessionGeneration { downloadingAttachment = false } }
    do {
      let temporary = try await api.download(url.absoluteString)
      defer { try? FileManager.default.removeItem(at: temporary) }
      guard generation == sessionGeneration, !Task.isCancelled else { return }
      if downloadFolder == nil {
        downloadFolder = FileManager.default.temporaryDirectory.appendingPathComponent("plainwire-" + UUID().uuidString, isDirectory: true)
      }
      guard let root = downloadFolder else { return }
      let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let destination = folder.appendingPathComponent(PWAttachment.safeFilename(name.isEmpty ? url.lastPathComponent : name))
      try FileManager.default.moveItem(at: temporary, to: destination)
      previewFileURL = destination
    } catch { if generation == sessionGeneration { errorMessage = error.localizedDescription } }
  }

  func attachmentMarkdown(for upload: PWUpload) -> String {
    let safeName = ["\\", "[", "]", "(", ")", "\n", "\r", "|"].reduce(upload.name) { $0.replacingOccurrences(of: $1, with: "_") }
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
    livePresenceStatus(for: user) ?? "unknown"
  }

  func livePresenceStatus(for user: PWUser) -> String? {
    guard realtimeState == .connected else { return nil }
    return presence.status(for: user.id)
  }

  func isUsingMacApp(_ user: PWUser) -> Bool {
    guard livePresenceStatus(for: user) == "online" else { return false }
    #if os(macOS)
      if user.id == session?.user.id { return true }
    #endif
    return ["macos", "mac", "plainwire-apple-mac"].contains(
      presence.platform(for: user.id)?.lowercased() ?? "")
  }

  func handleDeepLink(_ url: URL) async {
    guard sessionState == .ready else { pendingDeepLink = url; return }
    let path = url.fragment ?? url.path
    let components = path.split(separator: "/").map(String.init)
    let host = url.host?.lowercased()
    if url.scheme == "plainwire" {
      let all = [host].compactMap { $0 } + components
      await routeDeepLink(parts: all)
    } else if url.host == config.baseURL.host {
      await routeDeepLink(parts: components)
    }
  }

  private func routeDeepLink(parts: [String]) async {
    let generation = sessionGeneration
    guard !parts.isEmpty else { return }
    if parts.first == "settings" {
      #if os(macOS)
        showSettings = true
      #else
        selectedSection = .settings
      #endif
      return
    }
    if parts.first == "voice", parts.count > 1, let id = Int64(parts[1]) {
      for server in servers {
        await ensureServerDetails(server.id)
        guard generation == sessionGeneration, !Task.isCancelled else { return }
        if let channel = serverDetails[server.id]?.channels.first(where: { $0.id == id && $0.kind == "voice" }) {
          joinVoice(channel)
          return
        }
      }
      errorMessage = "This voice channel is unavailable."
      return
    }
    if let first = parts.first, ["wire", "invite", "forums", "f", "t", "thread", "source", "profile"].contains(first) {
      openWorkspace(fragment: parts.joined(separator: "/"))
      return
    }
    if let dmIndex = parts.firstIndex(where: { $0 == "dm" || $0 == "conversation" }),
      parts.count > dmIndex + 1, let id = Int64(parts[dmIndex + 1]),
      let conversation = conversations.first(where: { $0.id == id })
    {
      await openConversation(conversation)
      navigationRoom = selectedRoom
      return
    }
    if let channelIndex = parts.firstIndex(of: "channel"), parts.count > channelIndex + 1,
      let id = Int64(parts[channelIndex + 1])
    {
      for server in servers {
        if serverDetails[server.id] == nil { await ensureServerDetails(server.id) }
        guard generation == sessionGeneration, !Task.isCancelled else { return }
        if let channel = serverDetails[server.id]?.channels.first(where: { $0.id == id }) {
          await openChannel(channel, server: server)
          navigationRoom = selectedRoom
          return
        }
      }
    }
  }

  func sectionDidChange(_ section: Section) async {
    guard selectedSection == section, sessionState == .ready else { return }
    if section == .messages, selectedRoom?.scope != "direct" {
      selectedRoom = nil
      if let id = lastDirectRoomID, let conversation = conversations.first(where: { $0.id == id }) {
        await openConversation(conversation)
      }
    } else if section == .servers, selectedRoom?.scope != "channel" {
      selectedRoom = nil
      if let server = servers.first(where: { $0.id == selectedServerID }) ?? servers.first {
        await openServer(server)
      }
    }
    await updateRealtimeSubscriptions()
  }

  private func updatePresenceWatch() async {
    var ids = Set<PlainwireID>()
    for friend in friends where friend.status == "accepted" { ids.insert(friend.user.id) }
    for conversation in conversations {
      if let peerID = conversation.peerId { ids.insert(peerID) }
    }
    for detail in conversationDetails.values {
      for member in detail.members { ids.insert(member.user.id) }
    }
    for detail in serverDetails.values {
      for member in detail.members { ids.insert(member.user.id) }
    }
    let watched = Set(ids.sorted().prefix(2_000))
    presence.retainUsers(watched)
    await realtime.watchPresence(Array(watched))
  }

  private func updateRealtimeSubscriptions() async {
    var subscriptions = Set<String>()
    if let room = selectedRoom,
      (selectedSection == .messages && room.scope == "direct") || (selectedSection == .servers && room.scope == "channel") {
      subscriptions.insert("\(room.scope):\(room.roomID)")
    }
    if let serverID = selectedServerID, selectedSection == .servers {
      subscriptions.insert("server:\(serverID)")
    }
    await realtime.setSubscriptions(subscriptions)
  }

  private func bootstrap(incremental: Bool = false) async throws {
    let generation = sessionGeneration
    let snapshot = try await api.sync(since: incremental ? lastSyncCursor : nil)
    guard generation == sessionGeneration, !Task.isCancelled else { throw CancellationError() }
    // A degraded sync uses empty arrays for failed panels; preserve those panels.
    let warnings = snapshot.syncWarnings.joined(separator: " ")
    if !snapshot.syncDegraded || !warnings.contains("conversations") { conversations = snapshot.conversations }
    if !snapshot.syncDegraded || !warnings.contains("servers") { servers = snapshot.servers }
    if !snapshot.syncDegraded || !warnings.contains("friends") { friends = snapshot.friends }
    if !snapshot.syncDegraded || !warnings.contains("notifications") {
      if !incremental {
        notifications = snapshot.notifications
      } else {
        let incoming = Set(snapshot.notifications.map(\.id))
        notifications = (snapshot.notifications + notifications.filter { !incoming.contains($0.id) })
          .sorted { $0.id > $1.id }.prefix(120).map { $0 }
      }
    }
    let conversationIDs = Set(conversations.map(\.id))
    conversationDetails = conversationDetails.filter { conversationIDs.contains($0.key) }
    for key in Array(roomMessages.keys) where key.hasPrefix("direct:") {
      if let id = Int64(key.dropFirst(7)), !conversationIDs.contains(id) {
        revokeRoom(key)
        roomMessages[key] = nil
        roomPresentations[key] = nil
        loadedRooms.remove(key)
      }
    }
    let serverIDs = Set(servers.map(\.id))
    for id in Array(serverDetails.keys) where !serverIDs.contains(id) {
      for channel in serverDetails[id]?.channels ?? [] {
        revokeRoom("channel:\(channel.id)")
        roomMessages["channel:\(channel.id)"] = nil
        roomPresentations["channel:\(channel.id)"] = nil
        loadedRooms.remove("channel:\(channel.id)")
      }
      serverDetails[id] = nil
    }
    if let id = selectedServerID, !serverIDs.contains(id) {
      selectedServerID = nil
      selectedChannelID = nil
      if selectedRoom?.scope == "channel" { selectedRoom = nil; navigationRoom = nil }
    }
    if let room = selectedRoom, room.scope == "direct",
      let conversation = conversations.first(where: { $0.id == room.roomID }) {
      selectedRoom = Room(scope: "direct", roomID: conversation.id, title: conversationDisplayName(conversation),
        subtitle: conversation.memberCount > 2 ? "\(conversation.memberCount) members" : "@\(conversation.peerUsername)",
        avatarURL: conversationDisplayAvatar(conversation))
    }
    syncWarning = snapshot.syncDegraded ? snapshot.syncWarnings.joined(separator: " · ") : nil
    lastSyncCursor = snapshot.now
    lastSyncAt = Date()
    NotificationCoordinator.shared.updateBadgeCount(
      unreadMessageCount)
    await updatePresenceWatch()
    if let selected = selectedRoom, selected.scope == "direct",
      !conversations.contains(where: { $0.id == selected.roomID })
    {
      selectedRoom = nil
      navigationRoom = nil
    }
  }

  private func startRealtimeTasks() {
    eventTask?.cancel()
    let generation = sessionGeneration
    eventTask = Task { [weak self] in
      guard let self else { return }
      let updates = await self.realtime.updates()
      // Register the consumer before starting the socket so the hello and
      // initial presence snapshot cannot be missed.
      await self.realtime.start()
      for await update in updates {
        guard !Task.isCancelled, generation == self.sessionGeneration else { break }
        switch update {
        case .state(let state):
          self.realtimeState = state
          self.calls.connectionChanged(state)
          if state != .connected {
            self.presence.reset()
            self.typingExpiryTasks.values.forEach { $0.cancel() }
            self.typingExpiryTasks.removeAll()
            self.typingByRoom.removeAll()
          }
        case .event(let event): await self.handle(event)
        }
      }
    }
  }

  private func handle(_ event: PlainwireRealtimeEvent) async {
    guard sessionState == .ready, !signingOut else { return }
    calls.userID = session?.user.id ?? 0
    let callTitle = event.conversationID.flatMap { id in
      conversations.first(where: { $0.id == id }).map(conversationDisplayName)
    }
    calls.receive(event, title: callTitle)
    switch event.type {
    case "hello":
      if let refreshed = event.session { session = refreshed }
      scheduleSync(delay: .milliseconds(100))
    case "message_created":
      if let message = event.message {
        upsert(message, in: "\(message.scope):\(message.scopeId)")
        notifyIncomingMessage(message)
      }
      scheduleSync()
    case "direct_message", "channel_message", "mention":
      if let message = event.message {
        upsert(message, in: "\(message.scope):\(message.scopeId)")
        notifyIncomingMessage(message, isMention: event.type == "mention")
      }
      scheduleSync()
    case "message_updated":
      if let message = event.message { upsert(message, in: "\(message.scope):\(message.scopeId)") }
    case "message_pin_changed":
      if let id = event.messageID, let pinned = event.payload["pinned"]?.boolValue {
        for key in Array(roomMessages.keys) {
          if var list = roomMessages[key], let index = list.firstIndex(where: { $0.id == id }) {
            list[index].pinned = pinned
            setMessages(list, roomKey: key)
          }
        }
      }
    case "notification", "friend_request", "friend_accepted", "friend_removed": scheduleSync()
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
        scheduleRealtimeWork(key: "message:\(messageID)") { model in
          await model.refreshMessage(messageID, room: room)
        }
      }
    case "conversation_updated", "conversation_created", "conversation_members_changed",
      "conversation_members_added", "conversation_member_removed", "realtime_resync",
      "access_revoked":
      if let id = event.conversationID, conversationDetails[id] != nil,
        event.type != "access_revoked" {
        scheduleRealtimeWork(key: "conversation:\(id)") { model in
          await model.loadConversationDetails(id)
        }
      }
      if event.type == "access_revoked" {
        if let id = event.conversationID {
          revokeRoom("direct:\(id)")
          realtimeWork.removeValue(forKey: "conversation:\(id)")?.cancel()
          conversationDetails[id] = nil
          roomMessages["direct:\(id)"] = nil
          roomPresentations["direct:\(id)"] = nil
          loadedRooms.remove("direct:\(id)")
          if selectedRoom?.identifier == "direct:\(id)" { selectedRoom = nil; navigationRoom = nil }
        }
        if let id = event.channelID {
          revokeRoom("channel:\(id)")
          roomMessages["channel:\(id)"] = nil
          roomPresentations["channel:\(id)"] = nil
          loadedRooms.remove("channel:\(id)")
          if selectedRoom?.identifier == "channel:\(id)" { selectedRoom = nil; navigationRoom = nil }
        }
      }
      scheduleSync(delay: .milliseconds(250))
    case "server_updated", "server_deleted", "channel_created", "channel_updated", "channel_deleted", "channel_moved",
      "category_created", "category_updated", "category_deleted", "categories_reordered",
      "member_joined", "server_member_removed", "server_member_banned",
      "server_member_profile_updated", "server_member_roles_updated", "server_roles_updated":
      if let serverID = event.payload["server_id"]?.intValue, selectedServerID == serverID {
        scheduleRealtimeWork(key: "server:\(serverID)") { model in
          let generation = model.sessionGeneration
          guard let updated = try? await model.api.server(id: serverID),
            generation == model.sessionGeneration, !Task.isCancelled else { return }
          model.serverDetails[serverID] = updated
          if model.selectedServerID == serverID, let room = model.selectedRoom, room.scope == "channel" {
            if let channel = updated.channels.first(where: { $0.id == room.roomID }) {
              model.selectedRoom = Room(scope: "channel", roomID: channel.id, title: "# \(channel.name)",
                subtitle: channel.topic.isEmpty ? updated.server.name : channel.topic)
            } else { model.selectedRoom = nil; model.selectedChannelID = nil; model.navigationRoom = nil }
          }
          await model.updatePresenceWatch()
        }
      }
      scheduleSync(delay: .milliseconds(250))
    case "presence_state", "presence_online", "presence_status", "presence_offline":
      presence.apply(event)
    case "typing":
      handleTyping(event)
    case "account_deleted": await logout()
    default: break
    }
  }

  // Detail fetches must not stall the event consumer and delay offline/typing events.
  private func scheduleRealtimeWork(key: String, operation: @escaping @MainActor (AppModel) async -> Void) {
    realtimeWork[key]?.cancel()
    let generation = sessionGeneration
    realtimeWork[key] = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(250))
      guard let self, generation == self.sessionGeneration, !Task.isCancelled else { return }
      defer { if !Task.isCancelled, generation == self.sessionGeneration { self.realtimeWork[key] = nil } }
      await operation(self)
    }
  }

  private func notifyIncomingMessage(_ message: PWMessage, isMention: Bool = false) {
    guard message.userId != session?.user.id else { return }
    if message.scope == "channel" && !isMention { return }
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
      message, roomTitle: title, selectedRoom: [.messages, .servers].contains(selectedSection) ? selectedRoom?.identifier : nil,
      isMention: isMention)
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
    guard let before = roomMessages[room.identifier]?.first(where: { $0.id == id }) else { return }
    let generation = sessionGeneration
    let revision = roomRevisions[room.identifier, default: 0]
    do {
      let fresh = try await api.messages(scope: room.scope, id: room.roomID, after: max(0, id - 1))
      guard generation == sessionGeneration, revision == roomRevisions[room.identifier, default: 0],
        roomMessages[room.identifier]?.first(where: { $0.id == id }) == before else { return }
      if let replacement = fresh.first(where: { $0.id == id }) { upsert(replacement, in: room.identifier) }
    } catch {}
  }

  private func upsert(_ message: PWMessage, in roomKey: String) {
    guard deletedMessages[message.id] == nil, !revokedRooms.contains(roomKey) else { return }
    var list = roomMessages[roomKey] ?? []
    if contextRooms.contains(roomKey), !list.contains(where: { $0.id == message.id }) { return }
    if let index = list.firstIndex(where: { $0.id == message.id }) {
      list[index] = message
    } else {
      list.append(message)
      list.sort { $0.id < $1.id }
    }
    setMessages(list, roomKey: roomKey)
  }

  private func removeMessage(_ id: PlainwireID, roomKey: String) {
    deletedMessages[id] = Date()
    if deletedMessages.count > 1024, let oldest = deletedMessages.min(by: { $0.value < $1.value })?.key { deletedMessages[oldest] = nil }
    guard var list = roomMessages[roomKey] else { return }
    list.removeAll { $0.id == id }
    setMessages(list, roomKey: roomKey)
  }

  private func revokeRoom(_ roomKey: String) {
    revokedRooms.insert(roomKey)
    roomRevisions[roomKey, default: 0] += 1
  }

  private func setMessages(_ messages: [PWMessage], roomKey: String) {
    guard !revokedRooms.contains(roomKey) else { return }
    var messages = deduplicated(messages).filter { deletedMessages[$0.id] == nil && $0.deletedAt == nil }
    // Keep history while it is being read; bound live tails and inactive rooms.
    if messages.count > 1000, selectedRoom?.identifier != roomKey || readingRoomID == roomKey {
      messages = Array(messages.suffix(1000))
      reachedBeginning.remove(roomKey)
    }
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
          || Double(message.createdAt) - Double(previous.createdAt) > 5 * 60 * 1000
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
      let attachments: [MessageAttachment]
      let timestampText: String

      if let reusable {
        displayBody = reusable.displayBody
        attachments = reusable.attachments
        timestampText = reusable.timestampText
      } else {
        let parsed = PWMessageText.parseBody(message.body)
        displayBody = parsed.text
        attachments = parsed.attachments
        timestampText = Self.messageTimestamp(message.createdAt)
      }

      let textBlocks = reusable?.textBlocks ?? Self.presentTextBlocks(displayBody)
      let redactedBlocks = reusable?.redactedTextBlocks ?? (displayBody.contains("||")
        ? Self.presentTextBlocks(PWMessageText.redactingSpoilers(displayBody)) : textBlocks)
      previous = message
      return MessagePresentation(
        message: message,
        startsGroup: startsGroup,
        dateHeader: dateHeader,
        displayBody: displayBody,
        textBlocks: textBlocks,
        redactedTextBlocks: redactedBlocks,
        attachments: attachments,
        timestampText: timestampText)
    }
  }

  private static func presentTextBlocks(_ body: String) -> [MessageTextBlock] {
    PWMessageText.blocks(body).enumerated().map { index, block in
      let markdown = (try? AttributedString(markdown: block.text,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(block.text)
      return MessageTextBlock(id: index, block: block, markdown: markdown)
    }
  }

  private static func messageTimestamp(_ milliseconds: Int64) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    return date.formatted(
      date: Calendar.current.isDateInToday(date) ? .omitted : .abbreviated,
      time: .shortened)
  }

  private func deduplicated(_ input: [PWMessage]) -> [PWMessage] {
    var seen = Set<PlainwireID>()
    return input.filter { seen.insert($0.id).inserted }
  }
  private func channelSort(_ lhs: PWChannel, _ rhs: PWChannel) -> Bool {
    lhs.position == rhs.position ? lhs.id < rhs.id : lhs.position < rhs.position
  }

  private func scheduleSync(delay: Duration = .milliseconds(450)) {
    guard refreshTask == nil, sessionState == .ready else { return }
    refreshTask = Task { [weak self] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      self?.refreshTask = nil
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
