import Foundation
import Observation

enum ForumRoute: Hashable {
  case forum(PlainwireID)
  case thread(PlainwireID)
}

@MainActor @Observable
final class ForumStore {
  @ObservationIgnored private let api: PlainwireAPIClient
  @ObservationIgnored private var generation = 0
  @ObservationIgnored private var active = false
  @ObservationIgnored private var revisions: [String: UUID] = [:]
  @ObservationIgnored private var deletedThreads = Set<PlainwireID>()
  @ObservationIgnored private var deletedForums = Set<PlainwireID>()
  @ObservationIgnored private var deletedReplies: [PlainwireID: Set<PlainwireID>] = [:]
  @ObservationIgnored private var detailOrder: [PlainwireID] = []
  var path: [ForumRoute] = []
  private(set) var forums: [PWForum] = []
  private(set) var threads: [PlainwireID: [PWForumThread]] = [:]
  private(set) var details: [PlainwireID: PWForumThreadDetail] = [:]
  private(set) var queries: [PlainwireID: String] = [:]
  private(set) var errors: [String: String] = [:]
  private(set) var loading = Set<String>()
  private(set) var busy = Set<String>()
  private(set) var hasLoaded = false

  init(api: PlainwireAPIClient) { self.api = api }
  func activate() { active = true }

  func reset() {
    active = false
    generation += 1
    revisions = [:]
    path = []
    forums = []
    threads = [:]
    details = [:]
    queries = [:]
    errors = [:]
    loading = []
    busy = []
    deletedThreads = []
    deletedForums = []
    deletedReplies = [:]
    detailOrder = []
    hasLoaded = false
  }

  var activeThreadID: PlainwireID? {
    if case .thread(let id) = path.last { return id }
    return nil
  }

  var activeForumID: PlainwireID? {
    if let id = activeThreadID, let thread = details[id]?.thread { return thread.forumId }
    for route in path.reversed() {
      if case .forum(let id) = route { return id }
    }
    return nil
  }

  var subscriptions: Set<String> {
    var keys = Set(forums.filter(\.joined).prefix(120).map { "forum:\($0.id)" })
    if let id = activeForumID { keys.insert("forum:\(id)") }
    if let id = activeThreadID { keys.insert("thread:\(id)") }
    return keys
  }

  func loadForums(force: Bool = false) async {
    let key = "forums"
    guard active, force || !loading.contains(key) else { return }
    let epoch = generation
    let revision = UUID()
    revisions[key] = revision
    loading.insert(key)
    defer { if epoch == generation, revisions[key] == revision { loading.remove(key) } }
    do {
      let result = try await api.forums()
      guard epoch == generation, revisions[key] == revision, !Task.isCancelled else { return }
      forums = result.filter { !deletedForums.contains($0.id) }
      hasLoaded = true
      errors[key] = nil
    } catch { if revisions[key] == revision { record(error, key: key, epoch: epoch) } }
  }

  func loadThreads(forumID: PlainwireID, query: String? = nil) async {
    guard active, !deletedForums.contains(forumID) else { return }
    let key = "forum:\(forumID)"
    let revision = UUID()
    let epoch = generation
    let query = PWForumLimits.prefix((query ?? queries[forumID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines), maximumBytes: PWForumLimits.search)
    queries[forumID] = query
    revisions[key] = revision
    loading.insert(key)
    defer { if epoch == generation, revisions[key] == revision { loading.remove(key) } }
    do {
      let result = try await api.forumThreads(forumID: forumID, query: query)
      guard epoch == generation, revisions[key] == revision, !Task.isCancelled,
        !deletedForums.contains(forumID) else { return }
      threads[forumID] = result.filter { !deletedThreads.contains($0.id) }
      errors[key] = nil
    } catch {
      if epoch == generation, revisions[key] == revision {
        if accessLost(error) { threads[forumID] = nil }
        record(error, key: key, epoch: epoch)
      }
    }
  }

  func loadThread(_ id: PlainwireID) async {
    guard active, !deletedThreads.contains(id) else { return }
    let key = "thread:\(id)"
    let epoch = generation
    let revision = UUID()
    revisions[key] = revision
    loading.insert(key)
    defer { if epoch == generation, revisions[key] == revision { loading.remove(key) } }
    do {
      var result = try await api.forumThread(id: id)
      guard epoch == generation, revisions[key] == revision, !Task.isCancelled,
        !deletedThreads.contains(id), !deletedForums.contains(result.thread.forumId) else { return }
      result.replies.removeAll { deletedReplies[id]?.contains($0.id) == true }
      details[id] = result
      detailOrder.removeAll { $0 == id }
      detailOrder.append(id)
      while detailOrder.count > 6 { details[detailOrder.removeFirst()] = nil }
      errors[key] = nil
    } catch {
      if epoch == generation, revisions[key] == revision {
        if accessLost(error) { details[id] = nil }
        record(error, key: key, epoch: epoch)
      }
    }
  }

  func refreshVisible() async {
    let epoch = generation
    let forumID = activeForumID
    let threadID = activeThreadID
    await loadForums()
    guard epoch == generation, active else { return }
    if let forumID { await loadThreads(forumID: forumID) }
    guard epoch == generation, active else { return }
    if let threadID { await loadThread(threadID) }
  }

  func createForum(name: String, slug: String, description: String) async -> PlainwireID? {
    var id: PlainwireID?
    let success = await perform("create-forum") {
      id = try await self.api.createForum(name: name, slug: slug, description: description).id
      await self.loadForums(force: true)
    }
    return success ? id : nil
  }

  func setMembership(_ forum: PWForum, joined: Bool) async -> Bool {
    await perform("membership:\(forum.id)") {
      try await self.api.forumMembership(id: forum.id, joined: joined)
      await self.loadForums(force: true)
      await self.loadThreads(forumID: forum.id)
      if let id = self.activeThreadID { await self.loadThread(id) }
    }
  }

  func createThread(forumID: PlainwireID, title: String, body: String) async -> PlainwireID? {
    var id: PlainwireID?
    let success = await perform("create-thread:\(forumID)") {
      id = try await self.api.createForumThread(forumID: forumID, title: title, body: body).id
      await self.loadThreads(forumID: forumID)
      await self.loadForums(force: true)
    }
    return success ? id : nil
  }

  func reply(threadID: PlainwireID, body: String) async -> Bool {
    await perform("reply:\(threadID)") {
      _ = try await self.api.replyToForumThread(id: threadID, body: body)
      await self.loadThread(threadID)
      if let forumID = self.details[threadID]?.thread.forumId { await self.loadThreads(forumID: forumID) }
    }
  }

  func vote(_ thread: PWForumThread, value: Int) async -> Bool {
    await perform("vote:\(thread.id)") {
      let result = try await self.api.voteOnForumThread(id: thread.id, value: value)
      guard self.active else { return }
      if var detail = self.details[thread.id] {
        detail.thread.score = result.score
        detail.thread.userVote = result.userVote
        self.details[thread.id] = detail
      }
      if let index = self.threads[thread.forumId]?.firstIndex(where: { $0.id == thread.id }) {
        self.threads[thread.forumId]?[index].score = result.score
        self.threads[thread.forumId]?[index].userVote = result.userVote
      }
    }
  }

  func editThread(_ thread: PWForumThread, title: String, body: String) async -> Bool {
    await perform("edit-thread:\(thread.id)") {
      try await self.api.editForumThread(id: thread.id, title: title, body: body)
      await self.loadThread(thread.id)
      await self.loadThreads(forumID: thread.forumId)
    }
  }

  func moderate(_ thread: PWForumThread, action: String, value: Bool) async -> Bool {
    await perform("moderate:\(thread.id)") {
      try await self.api.moderateForumThread(id: thread.id, action: action, value: value)
      await self.loadThread(thread.id)
      await self.loadThreads(forumID: thread.forumId)
    }
  }

  func editReply(_ reply: PWForumReply, body: String) async -> Bool {
    await perform("edit-reply:\(reply.id)") {
      try await self.api.editForumReply(threadID: reply.threadId, replyID: reply.id, body: body)
      await self.loadThread(reply.threadId)
    }
  }

  func deleteReply(_ reply: PWForumReply) async -> Bool {
    await perform("delete-reply:\(reply.id)") {
      try await self.api.deleteForumReply(threadID: reply.threadId, replyID: reply.id)
      self.removeReply(reply.id, threadID: reply.threadId)
      await self.loadThread(reply.threadId)
      if let forumID = self.details[reply.threadId]?.thread.forumId { await self.loadThreads(forumID: forumID) }
    }
  }

  func deleteThread(_ thread: PWForumThread) async -> Bool {
    await perform("delete-thread:\(thread.id)") {
      try await self.api.deleteForumThread(id: thread.id)
      self.removeThread(thread.id)
      await self.loadForums(force: true)
    }
  }

  func deleteForum(_ forum: PWForum) async -> Bool {
    await perform("delete-forum:\(forum.id)") {
      try await self.api.deleteForum(id: forum.id)
      self.removeForum(forum.id)
    }
  }

  // Deletion is applied before any asynchronous refresh. Tombstones stop an
  // older in-flight response from restoring a removed discussion or forum.
  func receive(_ event: PlainwireRealtimeEvent) {
    if event.type == "thread_deleted", let id = event.payload["thread_id"]?.intValue { removeThread(id) }
    if event.type == "forum_deleted", let id = event.payload["forum_id"]?.intValue { removeForum(id) }
    if event.type == "thread_reply_deleted", let threadID = event.payload["thread_id"]?.intValue,
      let id = event.payload["reply_id"]?.intValue { removeReply(id, threadID: threadID) }
  }

  private func removeReply(_ id: PlainwireID, threadID: PlainwireID) {
    deletedReplies[threadID, default: []].insert(id)
    details[threadID]?.replies.removeAll { $0.id == id }
  }

  private func removeThread(_ id: PlainwireID) {
    deletedThreads.insert(id)
    deletedReplies[id] = nil
    details[id] = nil
    for forumID in Array(threads.keys) { threads[forumID]?.removeAll { $0.id == id } }
    if let index = path.firstIndex(of: .thread(id)) { path.removeSubrange(index...) }
  }

  private func removeForum(_ id: PlainwireID) {
    deletedForums.insert(id)
    let wasOpen = activeForumID == id
    forums.removeAll { $0.id == id }
    threads[id] = nil
    for threadID in Array(details.keys) where details[threadID]?.thread.forumId == id { removeThread(threadID) }
    if wasOpen { path = [] }
  }

  private func perform(_ key: String, operation: () async throws -> Void) async -> Bool {
    guard active, busy.insert(key).inserted else { return false }
    let epoch = generation
    defer { if epoch == generation { busy.remove(key) } }
    errors[key] = nil
    do {
      try await operation()
      return epoch == generation && active && !Task.isCancelled
    } catch {
      record(error, key: key, epoch: epoch)
      return false
    }
  }

  private func record(_ error: Error, key: String, epoch: Int) {
    guard epoch == generation, active, !(error is CancellationError), !Task.isCancelled else { return }
    errors[key] = error.localizedDescription
  }

  private func accessLost(_ error: Error) -> Bool {
    if case PlainwireAPIError.notAuthenticated = error { return true }
    if case PlainwireAPIError.server(let status, _, _) = error { return status == 403 || status == 404 }
    return false
  }
}
