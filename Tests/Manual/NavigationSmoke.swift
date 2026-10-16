import AppKit
import SwiftUI

@MainActor enum NavigationSmoke {
  enum Failure: Error { case check(String) }

  static func run(model: AppModel) async throws {
    let savedConversations = model.conversations
    let savedServers = model.servers
    let savedDetails = model.serverDetails
    let savedSection = model.selectedSection
    let savedRoom = model.selectedRoom
    let savedServerID = model.selectedServerID
    let savedChannelID = model.selectedChannelID
    let savedMessages = model.roomMessages
    let savedError = model.errorMessage
    let savedDownloading = model.downloadingAttachment
    defer {
      model.conversations = savedConversations
      model.servers = savedServers
      model.serverDetails = savedDetails
      model.selectedSection = savedSection
      model.selectedRoom = savedRoom
      model.selectedServerID = savedServerID
      model.selectedChannelID = savedChannelID
      model.roomMessages = savedMessages
      model.errorMessage = savedError
      model.downloadingAttachment = savedDownloading
    }
    let names = ["Morgan Ellis", "Design team", "Alex Chen", "Weekend plans", "Sam Rivera", "Building together"]
    let conversations: [[String: Any]] = (0..<75).map { index in
      ["id": 420 + index, "owner_id": 7, "name": index == 0 ? "First conversation" : names[index % names.count],
       "member_count": 3, "updated_at": Int64(Date().timeIntervalSince1970 * 1000) - Int64(index) * 86_400_000,
       "last_body": "A readable preview with enough room for the conversation.", "unread": index % 7 == 0 ? 3 : 0]
    }
    let servers: [[String: Any]] = (0..<12).map { index in
      ["id": 501 + index, "owner_id": 7, "name": "Community \(index + 1)", "member_count": 42]
    }
    model.conversations = try decode(conversations)
    model.servers = try decode(servers)
    let channels: [[String: Any]] = (0..<65).map { index in
      ["id": 801 + index, "server_id": 501, "name": index == 0 ? "first-channel" : "channel-\(index + 1)", "position": index]
    }
    let members: [[String: Any]] = (0..<40).map { index in
      ["user": ["id": 20 + index, "username": "member_\(index)", "display_name": names[index % names.count]],
       "role": index == 0 ? "owner" : "member"]
    }
    model.serverDetails[501] = try decode(["server": servers[0], "channels": channels, "members": members])
    model.selectedSection = .messages
    model.selectedServerID = 501
    // Load fixture data before mounting the UI. A fixed layout delay is not a
    // network completion signal, and clearing a loaded room bypasses its cache.
    model.selectedRoom = .init(scope: "channel", roomID: 801, title: "First channel")
    await model.loadSelectedRoom()
    try check(!(model.roomMessages["channel:801"] ?? []).isEmpty,
      "The channel fixture failed to load: \(model.errorMessage ?? "empty response")")
    model.selectedRoom = nil

    let controller = NSHostingController(rootView: AppRootView().environment(model).frame(minWidth: 920, minHeight: 620))
    let window = NSWindow(contentViewController: controller)
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
    window.toolbar = NSToolbar(identifier: "PlainwireNavigationSmoke")
    window.toolbarStyle = .unified
    window.alphaValue = 0
    window.orderBack(nil)
    defer { window.orderOut(nil) }

    for size in [NSSize(width: 1180, height: 760), NSSize(width: 980, height: 640), NSSize(width: 1720, height: 900)] {
      window.setContentSize(size)
      try await settle(controller.view)
      try verifyBounds(controller.view)
      try capture(controller.view, path: "/tmp/plainwire-navigation-\(Int(size.width)).png")
      try check(controller.view.frame.height <= window.frame.height + 1, "The navigation root grew taller than its window")
      let overflowing = scrollViews(controller.view).filter {
        ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height + 10
      }
      try check(overflowing.count >= (size.height <= 760 ? 2 : 1), "Populated navigation did not provide independent scrolling")
      for scroll in overflowing { try await roundTrip(scroll, root: controller.view) }
    }
    window.setContentSize(NSSize(width: 1180, height: 760))
    for section in [AppModel.Section.servers, .friends, .activity, .forums, .messages] {
      model.selectedRoom = section == .servers ? .init(scope: "channel", roomID: 801, title: "First channel") : nil
      model.selectedChannelID = 801
      model.selectedSection = section
      try await settle(controller.view)
      try verifyBounds(controller.view)
      try capture(controller.view, path: "/tmp/plainwire-navigation-\(section.rawValue).png")
    }
    model.selectedSection = .servers
    model.selectedRoom = .init(scope: "channel", roomID: 801, title: "First channel", subtitle: "A welcoming place for everyone")
    try await settle(controller.view)
    try check(model.errorMessage == nil, "The populated chat fixture failed to load")
    try check(!(model.roomMessages["channel:801"] ?? []).isEmpty, "The chat layout was checked without messages")
    for size in [NSSize(width: 980, height: 640), NSSize(width: 1720, height: 900)] {
      window.setContentSize(size)
      try await settle(controller.view)
      try verifyBounds(controller.view)
      if size.width > 1600 {
        try check(scrollViews(controller.view).count >= 4, "The wide chat did not show its scrolling member pane")
      }
      try capture(controller.view, path: "/tmp/plainwire-navigation-chat-\(Int(size.width)).png")
    }
    window.setContentSize(NSSize(width: 1180, height: 760))
    for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
      window.appearance = NSAppearance(named: appearance)
      try await settle(controller.view)
      try verifyBounds(controller.view)
      try capture(controller.view, path: "/tmp/plainwire-navigation-\(name).png")
    }
    model.errorMessage = "A connection notice should leave every page header and control visible."
    model.downloadingAttachment = true
    try await settle(controller.view)
    try verifyBounds(controller.view)
    try capture(controller.view, path: "/tmp/plainwire-navigation-notice.png")
    model.downloadingAttachment = false
    model.errorMessage = nil
    print("Navigation smoke passed: title-bar backgrounds, populated chat, notices, window bounds, independent wheel scrolling, return to the first row, resizing, and section changes.")
  }

  private static func decode<T: Decodable>(_ object: Any) throws -> T {
    try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
  }

  private static func settle(_ view: NSView) async throws {
    try await Task.sleep(for: .milliseconds(200))
    view.layoutSubtreeIfNeeded()
  }

  private static func scrollViews(_ view: NSView) -> [NSScrollView] {
    (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
  }

  private static func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(descendants)
  }

  private static func verifyTitlebarBackgrounds(_ root: NSView) throws {
    // Inspect native drawing bounds without calling private AppKit APIs. A
    // nested split view previously drew a second title bar over page headers.
    for view in descendants(root) where String(describing: type(of: view)).contains("TitlebarBackground") {
      guard !view.isHiddenOrHasHiddenAncestor else { continue }
      let rect = view.convert(view.bounds, to: root)
      try check(rect.maxY <= root.safeAreaInsets.top + 1,
        "A native title-bar background covered page content: \(rect)")
    }
  }

  private static func verifyBounds(_ root: NSView) throws {
    try verifyTitlebarBackgrounds(root)
    for scroll in scrollViews(root) {
      let rect = scroll.convert(scroll.bounds, to: root)
      try check(rect.minY >= -1 && rect.maxY <= root.bounds.height + 1,
        "A native list extended beyond the visible window")
    }
  }

  private static func roundTrip(_ scroll: NSScrollView, root: NSView) async throws {
    guard let document = scroll.documentView else { throw Failure.check("Missing scroll document") }
    let clip = scroll.contentView
    let topPoint = NSPoint(x: -scroll.contentInsets.left, y: -scroll.contentInsets.top)
    clip.scroll(to: topPoint)
    scroll.reflectScrolledClipView(clip)
    let top = clip.bounds.origin.y
    let point = scroll.convert(NSPoint(x: scroll.bounds.midX, y: scroll.bounds.midY), to: root)
    if let hit = root.hitTest(point) {
      try check(hit === scroll || hit.isDescendant(of: scroll), "An overlay intercepted list input")
    } else { throw Failure.check("The visible list could not receive input") }
    guard let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: -18, wheel2: 0, wheel3: 0),
      let event = NSEvent(cgEvent: wheel) else { throw Failure.check("Could not create a scroll-wheel event") }
    scroll.scrollWheel(with: event)
    try await settle(root)
    try check(clip.bounds.origin.y > top + 10, "The list ignored downward wheel input")
    clip.scroll(to: NSPoint(x: topPoint.x, y: document.frame.height - clip.bounds.height))
    scroll.reflectScrolledClipView(clip)
    guard let upward = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1000, wheel2: 0, wheel3: 0),
      let upwardEvent = NSEvent(cgEvent: upward) else { throw Failure.check("Could not create upward wheel input") }
    scroll.scrollWheel(with: upwardEvent)
    try await settle(root)
    try check(abs(clip.bounds.origin.y - top) < 2, "The list could not scroll back to its first row")
  }

  private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw Failure.check(message) }
  }

  private static func capture(_ view: NSView, path: String) throws {
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
  }
}

#if NAVIGATION_DIAGNOSTIC
@main struct NavigationDiagnostic {
  @MainActor static func main() async throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let address = ProcessInfo.processInfo.environment["PLAINWIRE_FIXTURE_HOST_A"]!
    let model = AppModel(configuration: try PlainwireConfiguration(serverAddress: address))
    _ = await model.login(username: "fixture", password: "fixture")
    do { try await NavigationSmoke.run(model: model) }
    catch { print("Navigation check failed: \(error)"); exit(1) }
    await model.logout()
  }
}
#endif
