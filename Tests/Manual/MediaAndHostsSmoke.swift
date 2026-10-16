import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import Observation

enum MediaAndHostsSmoke {
  enum Failure: Error { case check(String) }
  static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw Failure.check(message) }
  }

  @MainActor static func run() async throws {
    try await verifyAnimatedImages()
    guard let firstAddress = ProcessInfo.processInfo.environment["PLAINWIRE_FIXTURE_HOST_A"],
      let secondAddress = ProcessInfo.processInfo.environment["PLAINWIRE_FIXTURE_HOST_B"] else {
      throw Failure.check("Run this smoke executable through HostFixture.py")
    }
    let first = try PlainwireConfiguration(serverAddress: firstAddress)
    let second = try PlainwireConfiguration(serverAddress: secondAddress)
    let keys = [AppPreferenceKeys.serverAddress, AppPreferenceKeys.recentServers]
      + [AppPreferenceKeys.enterSendsMessage]
      + [first, second].flatMap { config in
        ["plainwire.apple.drafts.\(config.storageIdentifier).7",
         "plainwire.apple.mutedConversations.\(config.storageIdentifier).7"]
      }
    let saved = keys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
    defer {
      for (key, value) in saved {
        if let value { UserDefaults.standard.set(value, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
      }
      RemoteImageStore.shared.configure(PlainwireConfiguration())
    }
    for key in keys { UserDefaults.standard.removeObject(forKey: key) }
    let model = AppModel(configuration: first)
    await model.start()
    try check(model.sessionState == .signedOut, "Fresh host should require sign in")
    let firstLogin = await model.login(username: "fixture", password: "fixture")
    try check(firstLogin && model.session?.user.displayName == "Host A", "Host A login failed")
    let gifPage = try await model.searchGIFs("hello & 🎉")
    guard let gif = gifPage.results.first else { throw Failure.check("GIF search did not use the host API") }
    let room = AppModel.Room(scope: "direct", roomID: 42, title: "GIF fixture")
    try check(model.insertGIF(gif, query: "hello & 🎉", room: room), "GIF insertion failed")
    let parsed = PWMessageText.parseBody(model.drafts[room.identifier] ?? "")
    try check(parsed.attachments.count == 1 && parsed.attachments[0].url == gif.url
      && !parsed.attachments[0].isSpoiler, "GIF metadata broke attachment/spoiler parsing")
    model.clearDrafts()
    model.drafts["direct:42"] = "Draft on the first database"
    guard let conversation = model.conversations.first else { throw Failure.check("Missing fixture conversation") }
    model.setConversationMuted(conversation, muted: true)
    model.selectedRoom = .init(scope: "direct", roomID: 42, title: "Old host")
    model.roomMessages["direct:42"] = []
    let firstImage = await RemoteImageStore.shared.image(for: first.appURL().appendingPathComponent("image"), pixelSize: 64)
    let cachedImage = await RemoteImageStore.shared.image(for: first.appURL().appendingPathComponent("image"), pixelSize: 64)
    try check(firstImage != nil && firstImage === cachedImage, "Repeated avatars did not share the cache")
    let staleImage = Task { await RemoteImageStore.shared.image(for: first.appURL().appendingPathComponent("slow-image"), pixelSize: 64) }
    try await Task.sleep(for: .milliseconds(50))
    let generation = RemoteImageStore.shared.generation
    let switched = await model.switchServer(to: secondAddress)
    try check(switched && model.serverURL == second.baseURL && model.sessionState == .signedOut, "Host switch failed")
    try check(model.session == nil && model.conversations.isEmpty && model.roomMessages.isEmpty
      && model.selectedRoom == nil && model.drafts.isEmpty, "Old database state survived a host switch")
    try check(RemoteImageStore.shared.generation > generation, "Private image cache survived switching")
    let oldResult = await staleImage.value
    try check(oldResult == nil, "An old host's image completed after switching")
    let secondLogin = await model.login(username: "fixture", password: "fixture")
    try check(secondLogin && model.session?.user.displayName == "Host B", "Host B login failed")
    try check(model.drafts.isEmpty, "Identical user IDs leaked drafts across database ports")
    try check(!model.isConversationMuted(model.conversations[0]), "Mute preferences leaked between hosts")
    try check(model.mediaURL("/api/media/banner.gif")?.port == second.baseURL.port, "Media still used the old host")
    model.drafts["direct:42"] = "Draft on the second database"
    let returned = await model.switchServer(to: firstAddress)
    try check(returned, "Could not return to original host")
    let returnedLogin = await model.login(username: "fixture", password: "fixture")
    try check(returnedLogin && model.drafts["direct:42"] == "Draft on the first database", "Original host draft was not restored")
    try check(model.isConversationMuted(model.conversations[0]), "Host preference did not persist")
    try await verifyViews(model: model)
    try await verifyComposer(model: model)
    model.clearDrafts()
    try check(model.drafts.isEmpty, "Clear drafts failed")
    await model.logout()
    // A slow initial /me response must not sign the user back in after logout.
    model.sessionState = .booting
    let restore = Task { await model.start() }
    try await Task.sleep(for: .milliseconds(30))
    await model.logout()
    await restore.value
    try check(model.sessionState == .signedOut && model.session == nil, "A stale session restore undid logout")
    print("Media and hosts smoke passed: GIF frames/timing/playback, GIF search/insertion, downsampling, cache invalidation, two-host draft/session isolation, native preferences, and Return/Command-Return keyboard events.")
  }

  @MainActor private static func verifyAnimatedImages() async throws {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 2, nil) else {
      throw Failure.check("Could not create GIF fixture")
    }
    CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for (color, delay) in [(CGColor(red: 1, green: 0, blue: 0, alpha: 1), 0.04),
                           (CGColor(red: 0, green: 0, blue: 1, alpha: 1), 0.07)] {
      let context = CGContext(data: nil, width: 1024, height: 512, bitsPerComponent: 8, bytesPerRow: 4096,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      context.setFillColor(color)
      context.fill(CGRect(x: 0, y: 0, width: 1024, height: 512))
      CGImageDestinationAddImage(destination, context.makeImage()!,
        [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
    }
    try check(CGImageDestinationFinalize(destination), "GIF encoding failed")
    let bytes = data as Data
    guard let asset = await Task.detached(priority: .utility, operation: { RemoteImageAsset(data: bytes, pixelSize: 64) }).value else {
      throw Failure.check("GIF decoding failed")
    }
    try check(asset.isAnimated && asset.durations.count == 2, "GIF was flattened to a poster")
    try check(abs(asset.durations[0] - 0.04) < 0.001 && abs(asset.durations[1] - 0.07) < 0.001, "GIF timing changed")
    try check(asset.poster.width == 64 && asset.poster.height == 32, "Avatar/banner frames were not downsampled")
    let second = await Task.detached { asset.frame(at: 1) }.value
    try check(second != nil && second?.dataProvider?.data != asset.poster.dataProvider?.data, "GIF frames have identical pixels")
    try check(asset.frame(at: -1) == nil && asset.frame(at: 2) == nil, "Invalid GIF frame indices were accepted")
    try check(RemoteImageAsset(data: Data("invalid image".utf8), pixelSize: 64) == nil, "Malformed media was decoded")
    let layer = CALayer()
    let driver = AnimatedImageDriver()
    driver.update(asset: asset, layer: layer, playing: true)
    var advanced = false
    for _ in 0..<100 {
      try await Task.sleep(for: .milliseconds(5))
      if let displayed = layer.contents as AnyObject?, displayed !== asset.poster { advanced = true; break }
    }
    try check(advanced, "Native GIF layer never advanced beyond the first frame")
    driver.update(asset: asset, layer: layer, playing: false)
    try await Task.sleep(for: .milliseconds(150))
    try check((layer.contents as AnyObject?) === asset.poster, "Reduced-motion/paused media continued animating")
    driver.stop()
  }

  @MainActor private static func verifyViews(model: AppModel) async throws {
    let root = SettingsView(showNavigationTitle: false, detailPresentation: true).environment(model)
    let host = NSHostingView(rootView: root)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.alphaValue = 0
    window.contentView = host
    window.orderBack(nil)
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(150))
    if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/plainwire-2.2-settings.png"))
    }
    let sidebar = NSHostingView(rootView: SidebarView().environment(model))
    window.contentView = sidebar
    sidebar.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(50))
    let picker = NSHostingView(rootView: ServerHostSheet().environment(model))
    window.contentView = picker
    picker.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(50))
    let gifs = NSHostingView(rootView: GIFPickerSheet(room: .init(scope: "direct", roomID: 42, title: "GIF fixture")).environment(model))
    window.contentView = gifs
    gifs.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(50))
  }

  @MainActor private static func verifyComposer(model: AppModel) async throws {
    let state = ComposerState()
    model.selectedRoom = .init(scope: "direct", roomID: 42, title: "Keyboard fixture")
    UserDefaults.standard.set(true, forKey: AppPreferenceKeys.enterSendsMessage)
    let host = NSHostingView(rootView: ComposerFixture(state: state).environment(model))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 200),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.alphaValue = 0
    window.contentView = host
    window.orderBack(nil)
    defer { window.orderOut(nil); model.selectedRoom = nil }
    try await Task.sleep(for: .milliseconds(100))
    host.layoutSubtreeIfNeeded()
    func findEditor(_ view: NSView) -> NSTextView? {
      if let editor = view as? NSTextView, editor.isEditable { return editor }
      for child in view.subviews { if let result = findEditor(child) { return result } }
      return nil
    }
    func findField(_ view: NSView) -> NSTextField? {
      if let field = view as? NSTextField, field.isEditable { return field }
      for child in view.subviews { if let result = findField(child) { return result } }
      return nil
    }
    // AppKit creates a shared field editor only after the text field is focused.
    let field = findField(host)
    if let field { window.makeKey(); window.makeFirstResponder(field) }
    try await Task.sleep(for: .milliseconds(50))
    guard let editor = findEditor(host) ?? field?.currentEditor() as? NSTextView else {
      throw Failure.check("Native composer editor was not mounted")
    }
    window.makeFirstResponder(editor)
    func pressReturn(_ modifiers: NSEvent.ModifierFlags = []) async throws {
      if let field { window.makeFirstResponder(field) }
      (field?.currentEditor() as? NSTextView ?? editor).setSelectedRange(NSRange(location: state.text.utf16.count, length: 0))
      try await Task.sleep(for: .milliseconds(20))
      let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
      window.sendEvent(event)
      try await Task.sleep(for: .milliseconds(50))
    }
    try await pressReturn()
    try check(state.sent == 1, "Return did not send exactly once with Enter-to-send enabled")
    UserDefaults.standard.set(false, forKey: AppPreferenceKeys.enterSendsMessage)
    try await Task.sleep(for: .milliseconds(50))
    state.text = "Line one"
    try await Task.sleep(for: .milliseconds(50))
    try await pressReturn()
    try check(state.sent == 1 && state.text == "Line one\n", "Return did not insert a line with Enter-to-send disabled")
    try await pressReturn(.command)
    try check(state.sent == 2, "Command-Return did not send with Enter-to-send disabled")
  }

  @MainActor @Observable final class ComposerState {
    var text = "Hello"
    var sent = 0
  }

  private struct ComposerFixture: View {
    @Bindable var state: ComposerState
    var body: some View {
      ComposerBar(text: $state.text, uploading: false, sending: false, replyingTo: nil,
        onCancelReply: {}, onAttach: {}, onRecordVoiceNote: {}, onChooseGIF: {},
        onAttachSpoiler: {}, onSend: { state.sent += 1 })
    }
  }
}
