import AppKit
import SwiftUI
import Observation

// Run optimized: the reported 2.1.1 crash happened in a Release build's
// GestureState callback. This mounts the replacement native handle in SwiftUI
// and drives its AppKit pointer entry points while the panel moves beneath it.
@main struct CallPanelSmoke {
  @MainActor static func main() async throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let fixture = Fixture()
    let host = NSHostingView(rootView: PanelFixture(fixture: fixture))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.alphaValue = 0
    window.contentView = host
    window.orderBack(nil)
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(100))
    guard let pointer = findPointer(host) else { throw SmokeError.failed("Native drag handle was not mounted") }

    func event(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat) throws -> NSEvent {
      guard let event = NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: y), modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, eventNumber: 1, clickCount: 1, pressure: 1) else {
        throw SmokeError.failed("Could not create pointer event")
      }
      return event
    }

    for _ in 0..<10 {
      fixture.layout = PWCallPanelLayout(container: fixture.container, preferredSize: CGSize(width: 480, height: 380), origin: CGPoint(x: 100, y: 100))
      fixture.resizing = false
      try await Task.sleep(for: .milliseconds(10))
      host.layoutSubtreeIfNeeded()
      pointer.mouseDown(with: try event(.leftMouseDown, x: 120, y: 680))
      for step in 1...30 {
        pointer.mouseDragged(with: try event(.leftMouseDragged, x: 120 + CGFloat(step), y: 680 - CGFloat(step)))
        try check(fixture.layout.origin.x == 100 + CGFloat(step) && fixture.layout.origin.y == 100 + CGFloat(step),
          "Panel drifted as its handle moved")
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(2))
      }
      pointer.mouseUp(with: try event(.leftMouseUp, x: 150, y: 650))
      try check(fixture.interaction == nil && fixture.layout.origin.x == 130, "Pointer release lost the final position")
    }

    fixture.resizing = true
    try await Task.sleep(for: .milliseconds(10))
    host.layoutSubtreeIfNeeded()
    let oldWidth = fixture.layout.size.width
    pointer.mouseDown(with: try event(.leftMouseDown, x: 500, y: 400))
    for step in 1...60 {
      pointer.mouseDragged(with: try event(.leftMouseDragged, x: 500 + CGFloat(step), y: 400 - CGFloat(step)))
      try check(fixture.layout.size.width == oldWidth + CGFloat(step), "Resize compounded its translation")
      host.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(2))
    }
    pointer.mouseUp(with: try event(.leftMouseUp, x: 560, y: 340))
    let beforeCancel = fixture.layout
    pointer.mouseDown(with: try event(.leftMouseDown, x: 500, y: 400))
    pointer.mouseDragged(with: try event(.leftMouseDragged, x: 530, y: 370))
    pointer.cancelOperation(nil)
    try check(fixture.layout == beforeCancel && fixture.interaction == nil, "Cancelling failed to restore the drag anchor")
    try await verifyCallDock()
    print("Call panel smoke passed: optimized SwiftUI hosting, 300 move events, 60 resize events, release, and cancellation.")
  }

  @MainActor private static func verifyCallDock() async throws {
    let model = AppModel()
    let call = model.calls
    call.userID = 8
    call.send = { _ in }
    call.loadConfiguration = { .object(["iceServers": .array([])]) }
    call.requestMicrophone = { true }
    call.toggleMute()
    call.start(kind: .direct, id: 42, title: "Panel interaction smoke", userID: 8)
    for _ in 0..<100 {
      if call.status == "Calling…" { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    try check(call.localVideo != nil, "Native call startup did not finish")
    call.receive(.init(type: "call_state", payload: ["conversation_id": .int(42),
      "users": .array([.object(["user_id": .int(8)])])]))
    let host = NSHostingView(rootView: CallDockView().environment(model))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.alphaValue = 0
    window.contentView = host
    window.orderBack(nil)
    defer { window.orderOut(nil); call.reset() }
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(100))
    let handles = findPointers(host)
    guard let move = handles.first(where: { !$0.resizing }), let resize = handles.first(where: \.resizing) else {
      throw SmokeError.failed("Actual call dock handles were not mounted")
    }
    func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
      guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, eventNumber: 1, clickCount: 1, pressure: 1) else { throw SmokeError.failed("Could not create dock event") }
      return event
    }
    let original = move.convert(CGPoint.zero, to: nil)
    let press = move.convert(CGPoint(x: 20, y: 15), to: nil)
    // Route the initial down through AppKit hit testing, then exercise the
    // native responder while SwiftUI continually replaces callback closures.
    window.sendEvent(try event(.leftMouseDown, press))
    for step in 1...60 {
      let delta = CGFloat(step)
      move.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: press.x - delta, y: press.y + delta)))
      try await Task.sleep(for: .milliseconds(5))
      host.layoutSubtreeIfNeeded()
      let actual = move.convert(CGPoint.zero, to: nil)
      try check(abs(actual.x - (original.x - delta)) < 0.5 && abs(actual.y - (original.y + delta)) < 0.5,
        "Actual call dock drifted or lost its pointer interaction")
    }
    move.mouseUp(with: try event(.leftMouseUp, CGPoint(x: press.x - 60, y: press.y + 60)))
    let resizePress = resize.convert(CGPoint(x: 15, y: 15), to: nil)
    let moveWidth = move.frame.width
    resize.mouseDown(with: try event(.leftMouseDown, resizePress))
    for step in 1...30 {
      let delta = CGFloat(step)
      resize.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: resizePress.x + delta, y: resizePress.y - delta)))
      try await Task.sleep(for: .milliseconds(5))
      host.layoutSubtreeIfNeeded()
      try check(abs(move.frame.width - (moveWidth + delta)) < 0.5, "Actual call dock resize compounded its translation")
    }
    resize.mouseUp(with: try event(.leftMouseUp, CGPoint(x: resizePress.x + 30, y: resizePress.y - 30)))
    await call.end()
    print("Actual call dock smoke passed: optimized call UI, AppKit hit testing, native move/resize, and media teardown.")
  }

  @MainActor private static func findPointers(_ view: NSView) -> [CallPanelPointerView] {
    if let pointer = view as? CallPanelPointerView { return [pointer] }
    return view.subviews.flatMap { findPointers($0) }
  }

  @MainActor private static func findPointer(_ view: NSView) -> CallPanelPointerView? {
    if let pointer = view as? CallPanelPointerView { return pointer }
    return view.subviews.lazy.compactMap { findPointer($0) }.first
  }
  private static func check(_ condition: Bool, _ message: String) throws {
    if !condition { throw SmokeError.failed(message) }
  }
  private enum SmokeError: Error { case failed(String) }

  @MainActor @Observable final class Fixture {
    let container = CGSize(width: 1000, height: 800)
    var layout = PWCallPanelLayout(container: CGSize(width: 1000, height: 800), preferredSize: CGSize(width: 480, height: 380), origin: CGPoint(x: 100, y: 100))
    var interaction: PWCallPanelInteraction?
    var resizing = false
    func handle(_ translation: CGSize, _ phase: CallPanelDragPhase) {
      if phase == .began {
        interaction = PWCallPanelInteraction(anchor: layout, kind: resizing ? .resize : .move)
        return
      }
      guard let interaction else { return }
      layout = phase == .cancelled ? interaction.anchor : interaction.layout(translation: translation, container: container)
      if phase == .ended || phase == .cancelled { self.interaction = nil }
    }
  }

  private struct PanelFixture: View {
    let fixture: Fixture
    var body: some View {
      ZStack(alignment: .topLeading) {
        Color.clear
        CallPanelDragSurface(resizing: fixture.resizing) { delta, phase in fixture.handle(delta, phase) }
          .frame(width: fixture.layout.size.width, height: 40)
          .offset(x: fixture.layout.origin.x, y: fixture.layout.origin.y)
      }.frame(width: 1000, height: 800)
    }
  }
}
