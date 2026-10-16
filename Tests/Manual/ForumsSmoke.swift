import AppKit
import SwiftUI

@MainActor enum ForumsSmoke {
  enum Failure: Error { case check(String) }
  static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw Failure.check(message) }
  }

  static func run(model: AppModel) async throws {
    let store = model.forums
    model.selectedSection = .forums
    await store.loadForums()
    guard let forum = store.forums.first(where: { $0.id == 5 }) else { throw Failure.check("Missing forum fixture") }
    try check(!forum.joined, "Fixture membership was not isolated")
    let denied = await store.createThread(forumID: 5, title: "Permission test", body: "Must join first")
    try check(denied == nil && store.errors["create-thread:5"] != nil, "Membership denial became a successful discussion")
    let joined = await store.setMembership(forum, joined: true)
    try check(joined && store.forums.first(where: { $0.id == 5 })?.joined == true, "Joining did not refresh native membership")

    let oldSearch = Task { await store.loadThreads(forumID: 5, query: "slow") }
    try await Task.sleep(for: .milliseconds(50))
    await store.loadThreads(forumID: 5, query: "workspace")
    await oldSearch.value
    try check(store.queries[5] == "workspace" && store.threads[5]?.map(\.id) == [701], "A slow search replaced the latest results")
    await store.loadThreads(forumID: 5, query: "")

    guard let id = await store.createThread(forumID: 5, title: "Native discussion", body: "**Hello** from the Apple client 🎉") else {
      throw Failure.check("Native thread creation failed")
    }
    store.path = [.forum(5), .thread(id)]
    await store.loadThread(id)
    guard let thread = store.details[id]?.thread else { throw Failure.check("Created discussion was not readable") }
    try check(thread.canEdit && !thread.canModerate, "Author and forum-owner permissions were conflated")

    // A second API client stands in for the website. Both clients must read and
    // write the same server data rather than maintaining a separate forum copy.
    let browser = PlainwireAPIClient(configuration: try PlainwireConfiguration(serverAddress: model.serverAddress))
    _ = try await browser.restoreSession()
    _ = try await browser.replyToForumThread(id: id, body: "A reply from the website")
    model.receiveForumEvent(.init(type: "thread_reply", payload: ["thread_id": .int(id)]))
    try await waitUntil { store.details[id]?.replies.first?.rawBody == "A reply from the website" }
    try await browser.editForumThread(id: id, title: "Edited on the website", body: "Still the same discussion")
    model.receiveForumEvent(.init(type: "thread_updated", payload: ["thread_id": .int(id), "forum_id": .int(5)]))
    try await waitUntil { store.details[id]?.thread.title == "Edited on the website" }
    let voted = await store.vote(thread, value: 1)
    let browserDetail = try await browser.forumThread(id: id)
    try check(voted && browserDetail.thread.userVote == 1 && browserDetail.thread.score == 1, "Native votes did not sync to the website")
    if let reply = store.details[id]?.replies.first {
      let edited = await store.editReply(reply, body: "Edited natively")
      let reread = try await browser.forumThread(id: id)
      try check(edited && reread.replies.first?.rawBody == "Edited natively", "Reply edits did not sync")
      let deleted = await store.deleteReply(reply)
      try check(deleted && store.details[id]?.replies.isEmpty == true, "Deleted reply stayed visible")
    }
    let deleted = await store.deleteThread(thread)
    try check(deleted && store.details[id] == nil && !store.path.contains(.thread(id)), "Deleted discussion remained in navigation")

    guard let ownedForum = await store.createForum(name: "Ownership fixture", slug: "ownership-fixture", description: "Native moderation"),
      let ownedThread = await store.createThread(forumID: ownedForum, title: "Moderation fixture", body: "A body") else {
      throw Failure.check("Could not create an owned forum")
    }
    await store.loadThread(ownedThread)
    guard let owned = store.details[ownedThread]?.thread else { throw Failure.check("Missing owned discussion") }
    try check(owned.canModerate, "Forum owner was not given the server's moderation permission")
    let locked = await store.moderate(owned, action: "lock", value: true)
    let lockedReply = await store.reply(threadID: ownedThread, body: "Must be rejected")
    try check(locked && !lockedReply && store.details[ownedThread]?.thread.locked == true, "A locked thread accepted a reply")
    let removed = await store.deleteForum(store.forums.first { $0.id == ownedForum }!)
    try check(removed && store.details[ownedThread] == nil, "Removing a forum retained its discussion cache")

    let staleReply = Task { await store.loadThread(999) }
    try await Task.sleep(for: .milliseconds(50))
    store.receive(.init(type: "thread_reply_deleted", payload: ["thread_id": .int(999), "reply_id": .int(900)]))
    await staleReply.value
    try check(store.details[999]?.replies.contains(where: { $0.id == 900 }) == false,
      "An older response restored a deleted reply")

    let stale = Task { await store.loadThread(999) }
    try await Task.sleep(for: .milliseconds(50))
    store.receive(.init(type: "thread_deleted", payload: ["thread_id": .int(999), "forum_id": .int(5)]))
    await stale.value
    try check(store.details[999] == nil, "An older response restored a deleted discussion")

    _ = await store.setMembership(store.forums.first { $0.id == 5 }!, joined: false)
    await model.handleDeepLink(model.appURL(fragment: "t/700"))
    try check(model.selectedSection == .forums && store.path.last == .thread(700), "Discussion links opened a web tool instead of native navigation")
    await model.handleDeepLink(URL(string: "plainwire://f/design-studio")!)
    try check(store.path == [.forum(5)], "Forum slug links did not resolve")
    try await verifyViews(model: model)
    store.path = []
    model.selectedSection = .messages
    print("Forums smoke passed: shared website/native data, membership, latest search, creation, replies, votes, edits, moderation, deletion tombstones, deep links, and native layouts.")
  }

  private static func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<200 {
      if condition() { return }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw Failure.check("Native forum state did not refresh after a server event")
  }

  private static func verifyViews(model: AppModel) async throws {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 800),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.alphaValue = 0
    window.appearance = NSAppearance(named: .aqua)
    let host = NSHostingView(rootView: ForumsView().environment(model))
    window.contentView = host
    window.orderBack(nil)
    defer { window.orderOut(nil) }
    model.forums.path = []
    try await Task.sleep(for: .milliseconds(250))
    host.layoutSubtreeIfNeeded()
    try capture(host, path: "/tmp/plainwire-forums-light.png")
    model.forums.path = [.forum(5)]
    try await Task.sleep(for: .milliseconds(250))
    host.layoutSubtreeIfNeeded()
    try capture(host, path: "/tmp/plainwire-forum-board.png")
    model.forums.path = [.forum(5), .thread(700)]
    try await Task.sleep(for: .milliseconds(250))
    host.layoutSubtreeIfNeeded()
    try capture(host, path: "/tmp/plainwire-forum-discussion.png")
    window.setContentSize(NSSize(width: 390, height: 560))
    try await Task.sleep(for: .milliseconds(250))
    host.layoutSubtreeIfNeeded()
    try check(host.bounds.width <= 400, "A forum layout imposed a desktop width on a narrow window")
    try capture(host, path: "/tmp/plainwire-forum-narrow.png")
    model.forums.path = [.forum(6), .thread(702)]
    try await Task.sleep(for: .milliseconds(250))
    host.layoutSubtreeIfNeeded()
    try capture(host, path: "/tmp/plainwire-forum-composer-narrow.png")
    model.forums.path = [.forum(5)]
    try await Task.sleep(for: .milliseconds(250))
    host.layoutSubtreeIfNeeded()
    try capture(host, path: "/tmp/plainwire-forum-board-narrow.png")
    model.forums.path = []
    try await Task.sleep(for: .milliseconds(250))
    host.layoutSubtreeIfNeeded()
    try capture(host, path: "/tmp/plainwire-forums-narrow.png")
    window.setContentSize(NSSize(width: 1120, height: 800))
    window.appearance = NSAppearance(named: .darkAqua)
    try await Task.sleep(for: .milliseconds(200))
    host.layoutSubtreeIfNeeded()
    try capture(host, path: "/tmp/plainwire-forums-dark.png")
    window.appearance = NSAppearance(named: .aqua)
    for section in [AppModel.Section.messages, .servers, .friends, .activity] {
      model.selectedSection = section
      let page = NSHostingView(rootView: AppRootView().environment(model))
      window.contentView = page
      try await Task.sleep(for: .milliseconds(250))
      page.layoutSubtreeIfNeeded()
      try capture(page, path: "/tmp/plainwire-page-\(section.rawValue).png")
    }
  }

  private static func capture(_ view: NSView, path: String) throws {
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw Failure.check("Could not capture forum UI") }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
  }
}
