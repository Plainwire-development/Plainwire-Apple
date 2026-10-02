import SwiftUI

enum CallPanelDragPhase { case began, changed, ended, cancelled }

/// Native pointer handlers avoid the SwiftUI GestureState executor crash and
/// measure in window coordinates, even while the handle itself is moving.
struct CallPanelDragSurface {
  var resizing = false
  let onDrag: @MainActor (CGSize, CallPanelDragPhase) -> Void
}

#if os(macOS)
extension CallPanelDragSurface: NSViewRepresentable {
  func makeNSView(context: Context) -> CallPanelPointerView { CallPanelPointerView() }
  func updateNSView(_ view: CallPanelPointerView, context: Context) {
    view.resizing = resizing
    view.onDrag = onDrag
  }
}

@MainActor final class CallPanelPointerView: NSView {
  var resizing = false
  var onDrag: (@MainActor (CGSize, CallPanelDragPhase) -> Void)?
  private var start: CGPoint?
  override var acceptsFirstResponder: Bool { true }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func resetCursorRects() { addCursorRect(bounds, cursor: resizing ? .crosshair : .openHand) }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    start = event.locationInWindow
    onDrag?(.zero, .began)
  }
  override func mouseDragged(with event: NSEvent) {
    guard let start else { return }
    onDrag?(CGSize(width: event.locationInWindow.x - start.x,
      height: start.y - event.locationInWindow.y), .changed)
  }
  override func mouseUp(with event: NSEvent) {
    guard let start else { return }
    self.start = nil
    onDrag?(CGSize(width: event.locationInWindow.x - start.x,
      height: start.y - event.locationInWindow.y), .ended)
  }
  override func cancelOperation(_ sender: Any?) {
    guard start != nil else { return }
    start = nil
    onDrag?(.zero, .cancelled)
  }
}
#else
extension CallPanelDragSurface: UIViewRepresentable {
  func makeUIView(context: Context) -> CallPanelPointerView { CallPanelPointerView() }
  func updateUIView(_ view: CallPanelPointerView, context: Context) { view.onDrag = onDrag }
}

@MainActor final class CallPanelPointerView: UIView {
  var onDrag: (@MainActor (CGSize, CallPanelDragPhase) -> Void)?
  override init(frame: CGRect) {
    super.init(frame: frame)
    addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan(_:))))
    isAccessibilityElement = false
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  @objc private func pan(_ gesture: UIPanGestureRecognizer) {
    let translation = gesture.translation(in: window)
    let delta = CGSize(width: translation.x, height: translation.y)
    switch gesture.state {
    case .began: onDrag?(.zero, .began)
    case .changed: onDrag?(delta, .changed)
    case .ended: onDrag?(delta, .ended)
    case .cancelled, .failed: onDrag?(.zero, .cancelled)
    default: break
    }
  }
}
#endif
