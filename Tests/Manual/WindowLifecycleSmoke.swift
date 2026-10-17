import AppKit
import SwiftUI

// NSHostingController alone does not install SwiftUI's window toolbar bridge.
// Exercise a real App scene so native toolbar changes run just as they do in
// the installed app, including when a workspace sheet is dismissed.
@main struct WindowLifecycleSmoke: App {
  @State private var model: AppModel
  @State private var started = false

  init() {
    AppPreferences.registerDefaults()
    let address = ProcessInfo.processInfo.environment["PLAINWIRE_FIXTURE_HOST_A"]!
    _model = State(initialValue: AppModel(configuration: try! PlainwireConfiguration(serverAddress: address)))
    NSSetUncaughtExceptionHandler { exception in
      FileHandle.standardError.write(Data("Window lifecycle exception: \(exception.name.rawValue): \(exception.reason ?? "unknown")\n\(exception.callStackSymbols.joined(separator: "\n"))\n".utf8))
    }
  }

  var body: some Scene {
    Window("Plainwire", id: "main") {
      AppRootView()
        .environment(model)
        .frame(minWidth: 920, minHeight: 620)
        .task {
          guard !started else { return }
          started = true
          do {
            try await run()
            await model.logout()
            progress("Passed: real SwiftUI window, section changes, forum navigation, and workspace dismissal")
            exit(0)
          } catch {
            progress("Failed: \(error)")
            exit(1)
          }
        }
    }
    .defaultSize(width: 1180, height: 760)
    .windowResizability(.contentMinSize)
    .windowToolbarStyle(.unified)
  }

  private func run() async throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    try check(await model.login(username: "fixture", password: "fixture"), "Fixture login failed")
    try await Task.sleep(for: .milliseconds(400))
    guard let window = NSApp.windows.first(where: { $0.sheetParent == nil && $0.toolbar != nil }) else {
      throw Failure.check("SwiftUI did not create its native window toolbar")
    }
    window.alphaValue = 0
    window.orderBack(nil)
    model.selectedRoom = .init(scope: "direct", roomID: 42, title: "Layout fixture")
    await model.loadSelectedRoom()

    progress("Rapid page changes between searchable pages")
    for index in 0..<30 {
      model.selectedSection = index.isMultiple(of: 2) ? .friends : .forums
      try await Task.sleep(for: .milliseconds(30))
      window.layoutIfNeeded()
    }

    for section in [AppModel.Section.messages, .servers, .friends, .activity, .forums, .messages] {
      progress("Section \(section.rawValue)")
      model.selectedSection = section
      try await settle(window)
      try verifyToolbar(window)
      if section == .forums { try await verifySearch(window, prompt: "Find a forum") }
      if section == .friends { try await verifySearch(window, prompt: "Find people") }
      progress("Workspace over \(section.rawValue)")
      model.openWorkspace(fragment: "source")
      try await waitForSheet(window, presented: true)
      window.attachedSheet?.alphaValue = 0
      model.showWorkspace = false
      try await waitForSheet(window, presented: false)
      try verifyToolbar(window)
    }

    progress("Workspace dismissal and forum navigation in the same update")
    model.openWorkspace(fragment: "source")
    try await waitForSheet(window, presented: true)
    model.showWorkspace = false
    model.openForums()
    try await waitForSheet(window, presented: false)
    try verifyToolbar(window)
    for path: [ForumRoute] in [[.forum(5)], [.forum(5), .thread(700)], [.forum(5)], []] {
      progress("Forum path \(path)")
      model.forums.path = path
      try await settle(window)
      try verifyToolbar(window)
    }

    progress("Restoring a forum destination across section changes")
    model.forums.path = [.forum(5), .thread(700)]
    try await settle(window)
    for section in [AppModel.Section.messages, .friends, .forums, .servers, .forums, .activity, .forums] {
      model.selectedSection = section
      try await settle(window)
      try verifyToolbar(window)
    }
  }

  private func waitForSheet(_ window: NSWindow, presented: Bool) async throws {
    for _ in 0..<50 {
      if (window.attachedSheet != nil) == presented {
        try await settle(window)
        return
      }
      try await Task.sleep(for: .milliseconds(50))
    }
    throw Failure.check("Workspace sheet did not \(presented ? "appear" : "close")")
  }

  private func settle(_ window: NSWindow) async throws {
    try await Task.sleep(for: .milliseconds(400))
    window.contentView?.layoutSubtreeIfNeeded()
    window.layoutIfNeeded()
  }

  private func verifyToolbar(_ window: NSWindow) throws {
    guard let toolbar = window.toolbar else { throw Failure.check("The window lost its toolbar") }
    let identifiers = toolbar.items.map(\.itemIdentifier.rawValue)
    let uniqueItems = identifiers.filter { !["NSToolbarFlexibleSpaceItem", "NSToolbarSpaceItem"].contains($0) }
    try check(Set(uniqueItems).count == uniqueItems.count, "The toolbar contains duplicate items")
  }

  private func verifySearch(_ window: NSWindow, prompt: String) async throws {
    func findField(_ view: NSView) -> NSTextField? {
      if let field = view as? NSTextField, field.isEditable, field.placeholderString == prompt,
        !field.isHiddenOrHasHiddenAncestor { return field }
      return view.subviews.lazy.compactMap(findField).first
    }
    guard let root = window.contentView, let field = findField(root) else {
      throw Failure.check("The search field is missing: \(prompt)")
    }
    let rect = field.convert(field.bounds, to: root)
    if let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
      root.cacheDisplay(in: root.bounds, to: bitmap)
      let name = prompt == "Find people" ? "friends" : "forums"
      try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/plainwire-window-search-\(name).png"))
    }
    try check(rect.minY >= 0 && rect.maxY <= root.bounds.height, "Search lies outside the visible page")
    let point = field.convert(NSPoint(x: field.bounds.midX, y: field.bounds.midY), to: root.superview)
    guard let hit = root.hitTest(point) else {
      throw Failure.check("The search field cannot receive pointer input")
    }
    try check(hit === field || hit.isDescendant(of: field),
      "Page content covers search: \(prompt), field \(rect), root \(root.frame), hit \(type(of: hit))")
    window.makeKey()
    let find = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
      context: nil, characters: "f", charactersIgnoringModifiers: "f", isARepeat: false, keyCode: 3)!
    try check(window.performKeyEquivalent(with: find), "Command-F did not reach page search")
    try await Task.sleep(for: .milliseconds(100))
    guard let editor = field.currentEditor() as? NSTextView else {
      throw Failure.check("Command-F did not focus the search field")
    }
    editor.insertText("design", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
    try await settle(window)
    try check(field.stringValue == "design", "Search did not accept keyboard input")
    editor.selectAll(nil)
    editor.insertText("", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
    window.makeFirstResponder(nil)
  }

  private func check(_ condition: Bool, _ message: String) throws {
    if !condition { throw Failure.check(message) }
  }

  private func progress(_ message: String) {
    FileHandle.standardError.write(Data("Window lifecycle: \(message)\n".utf8))
  }

  private enum Failure: Error { case check(String) }
}
