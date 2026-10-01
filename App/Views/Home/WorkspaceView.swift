import SwiftUI
import Observation
@preconcurrency import WebKit

// Keep the web workspace alive while browsing native tabs, including active calls.
@MainActor @Observable
final class WorkspaceController: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver, WKDownloadDelegate {
  @ObservationIgnored private(set) var webView: WKWebView?
  @ObservationIgnored private var preparation: Task<Void, Never>?
  @ObservationIgnored private var onSessionEnded: (() -> Void)?
  @ObservationIgnored private var desiredFragment: String?
  @ObservationIgnored private var cookieStore: WKHTTPCookieStore?
  @ObservationIgnored private var downloads: [ObjectIdentifier: WKDownload] = [:]
  @ObservationIgnored private var downloadPaths: [ObjectIdentifier: URL] = [:]
  @ObservationIgnored private var temporaryDownloadFolder: URL?
  @ObservationIgnored private var promptCompletion: (@MainActor @Sendable (String?) -> Void)?
  var dialogIsPrompt = false
  var dialogInput = ""
  @ObservationIgnored private var dialogCompletion: (@MainActor @Sendable (Bool) -> Void)?
  var loading = true
  var error: String?
  var dialogMessage: String?
  var dialogIsConfirmation = false
  var downloadedFile: URL?
  private var prepared = false
  private let baseURL = PlainwireConfiguration().baseURL

  func view(onSessionEnded: @escaping () -> Void) -> WKWebView {
    self.onSessionEnded = onSessionEnded
    if let webView { return webView }
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    configuration.mediaTypesRequiringUserActionForPlayback = []
    #if os(iOS)
      configuration.allowsInlineMediaPlayback = true
    #endif
    let view = WKWebView(frame: .zero, configuration: configuration)
    view.navigationDelegate = self
    view.uiDelegate = self
    view.allowsBackForwardNavigationGestures = true
    webView = view
    let store = configuration.websiteDataStore.httpCookieStore
    cookieStore = store
    store.add(self)
    let sessionURL = baseURL
    preparation = Task { @MainActor [weak self, weak view] in
      for cookie in HTTPCookieStorage.shared.cookies(for: sessionURL) ?? [] {
        await withCheckedContinuation { continuation in
          store.setCookie(cookie) { continuation.resume() }
        }
      }
      guard !Task.isCancelled, let self, let view else { return }
      self.prepared = true
      view.load(URLRequest(url: self.routeURL))
    }
    return view
  }

  private var routeURL: URL {
    var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
    components.fragment = desiredFragment
    return components.url ?? baseURL
  }

  func route(_ fragment: String?) {
    guard let fragment else { return }
    desiredFragment = fragment
    guard prepared, let webView else { return }
    // A fragment change navigates the Elm router without restarting live media.
    let encoded = (try? JSONEncoder().encode(fragment)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    webView.evaluateJavaScript("window.location.hash = \(encoded)")
  }

  func reload() {
    error = nil
    loading = true
    if let view = webView { view.load(URLRequest(url: routeURL)) }
  }

  func reset() {
    preparation?.cancel()
    preparation = nil
    prepared = false
    cookieStore?.remove(self)
    cookieStore = nil
    downloads.values.forEach { $0.cancel { _ in } }
    downloads = [:]
    downloadPaths = [:]
    if let folder = temporaryDownloadFolder { try? FileManager.default.removeItem(at: folder) }
    temporaryDownloadFolder = nil
    finishDialog(false)
    webView?.stopLoading()
    webView?.navigationDelegate = nil
    webView?.uiDelegate = nil
    webView?.loadHTMLString("", baseURL: nil)
    webView = nil
    onSessionEnded = nil
    desiredFragment = nil
    downloadedFile = nil
    error = nil
    loading = true
  }

  func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
    guard prepared else { return }
    Task { @MainActor [weak self] in
      let cookies = await withCheckedContinuation { continuation in
        cookieStore.getAllCookies { continuation.resume(returning: $0) }
      }
      guard let self, self.prepared, self.cookieStore === cookieStore else { return }
      if let cookie = cookies.first(where: { $0.name == "pw_session" && $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")) == self.baseURL.host }) {
        // Keep native requests authenticated when the web client rotates its session.
        HTTPCookieStorage.shared.setCookie(cookie)
        return
      }
      self.onSessionEnded?()
    }
  }

  private func trusted(_ url: URL?) -> Bool {
    guard let url else { return false }
    return PlainwireConfiguration(baseURL: baseURL).isSameOrigin(url)
  }

  private func trustedBlob(_ url: URL) -> Bool {
    url.scheme == "blob" && trusted(URL(string: String(url.absoluteString.dropFirst(5))))
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
               decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
    guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
    if trusted(url) || url.absoluteString == "about:blank" || trustedBlob(url) {
      decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
    } else {
      decisionHandler(.cancel)
      guard navigationAction.navigationType == .linkActivated,
        navigationAction.targetFrame?.isMainFrame != false else { return }
      guard ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return }
      #if os(macOS)
        NSWorkspace.shared.open(url)
      #else
        UIApplication.shared.open(url)
      #endif
    }
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
               decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
    if navigationResponse.isForMainFrame, let url = navigationResponse.response.url,
      !trusted(url), url.absoluteString != "about:blank", !trustedBlob(url) {
      decisionHandler(.cancel)
      return
    }
    let disposition = (navigationResponse.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
    decisionHandler(!navigationResponse.canShowMIMEType || disposition.lowercased().hasPrefix("attachment") ? .download : .allow)
  }

  func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
               for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
    if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
    return nil
  }

  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    loading = true
    error = nil
  }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loading = false }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    loading = false
    error = "The workspace stopped responding. Reload to reconnect."
  }
  private func failed(_ error: Error) {
    guard (error as NSError).code != NSURLErrorCancelled else { return }
    loading = false
    self.error = error.localizedDescription
  }

  func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
               initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
               decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void) {
    let expectedPort = baseURL.port ?? (baseURL.scheme == "https" ? 443 : 80)
    let matchesPort = origin.port == expectedPort || (origin.port == 0 && baseURL.port == nil)
    decisionHandler(origin.host == baseURL.host && origin.protocol == baseURL.scheme && matchesPort ? .prompt : .deny)
  }

  func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
               initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable () -> Void) {
    finishDialog(false)
    dialogIsConfirmation = false
    dialogIsPrompt = false
    dialogMessage = message
    dialogCompletion = { _ in completionHandler() }
  }
  func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
               initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (Bool) -> Void) {
    finishDialog(false)
    dialogIsConfirmation = true
    dialogIsPrompt = false
    dialogMessage = message
    dialogCompletion = completionHandler
  }
  func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
               defaultText: String?, initiatedByFrame frame: WKFrameInfo,
               completionHandler: @escaping @MainActor @Sendable (String?) -> Void) {
    finishDialog(false)
    dialogIsPrompt = true
    dialogIsConfirmation = false
    dialogInput = defaultText ?? ""
    dialogMessage = prompt
    promptCompletion = completionHandler
  }

  func finishDialog(_ accepted: Bool) {
    let completion = dialogCompletion
    let prompt = promptCompletion
    promptCompletion = nil
    dialogCompletion = nil
    dialogMessage = nil
    completion?(accepted)
    prompt?(accepted ? dialogInput : nil)
  }

  #if os(macOS)
  func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
               initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void) {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = parameters.allowsMultipleSelection
    panel.canChooseDirectories = parameters.allowsDirectories
    panel.begin { result in completionHandler(result == .OK ? panel.urls : nil) }
  }
  #endif

  func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { track(download) }
  func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { track(download) }
  private func track(_ download: WKDownload) {
    downloads[ObjectIdentifier(download)] = download
    download.delegate = self
    loading = false
  }
  func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                suggestedFilename: String, completionHandler: @escaping @MainActor @Sendable (URL?) -> Void) {
    let name = PWAttachment.safeFilename(suggestedFilename)
    #if os(macOS)
      let panel = NSSavePanel()
      panel.nameFieldStringValue = name
      panel.begin { [weak self] result in
        let url = result == .OK ? panel.url : nil
        self?.downloadPaths[ObjectIdentifier(download)] = url
        completionHandler(url)
      }
    #else
      if temporaryDownloadFolder == nil {
        temporaryDownloadFolder = FileManager.default.temporaryDirectory.appendingPathComponent("plainwire-web-" + UUID().uuidString, isDirectory: true)
      }
      guard let root = temporaryDownloadFolder else { completionHandler(nil); return }
      let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
      do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        downloadPaths[ObjectIdentifier(download)] = url
        completionHandler(url)
      } catch { completionHandler(nil) }
    #endif
  }
  func downloadDidFinish(_ download: WKDownload) {
    downloadedFile = downloadPaths.removeValue(forKey: ObjectIdentifier(download))
    downloads[ObjectIdentifier(download)] = nil
  }
  func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
    downloads[ObjectIdentifier(download)] = nil
    downloadPaths[ObjectIdentifier(download)] = nil
    if (error as NSError).code != NSURLErrorCancelled { self.error = error.localizedDescription }
  }
}

struct WebWorkspaceView: View {
  @Environment(AppModel.self) private var model
  private var workspace: WorkspaceController { model.workspace }
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Image(systemName: "square.grid.2x2.fill").foregroundStyle(.tint)
        Text("Workspace").font(.headline)
        Spacer()
        Menu {
          Button("Home") { model.openWorkspace(fragment: "home") }
          Button("Forums") { model.openWorkspace(fragment: "forums") }
          Button("Source Hub") { model.openWorkspace(fragment: "source") }
          Button("Settings & Developer Apps") { model.openWorkspace(fragment: "settings") }
        } label: { Label("Browse", systemImage: "square.grid.2x2") }
        Button { workspace.reload() } label: { Image(systemName: "arrow.clockwise") }
          .help("Reload workspace").accessibilityLabel("Reload workspace")
      }
      .padding(12)
      .background(.bar)
      Divider()
      if workspace.loading { ProgressView().progressViewStyle(.linear).padding(.horizontal) }
      if let error = workspace.error {
        ContentUnavailableView {
          Label("Workspace unavailable", systemImage: "wifi.exclamationmark")
        } description: { Text(error) } actions: {
          Button("Try Again") { workspace.reload() }.buttonStyle(.borderedProminent)
        }
      }
      WorkspaceWebView(controller: workspace, model: model)
        .opacity(workspace.error == nil ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      if let url = workspace.downloadedFile {
        HStack {
          Label(url.lastPathComponent, systemImage: "checkmark.circle.fill").lineLimit(1)
          Spacer()
          ShareLink(item: url)
          Button("Dismiss") { workspace.downloadedFile = nil }
        }.font(.caption).padding(12).background(.bar)
      }
    }
    .navigationTitle("Workspace")
    .alert(workspace.dialogIsConfirmation ? "Confirm" : "Plainwire", isPresented: Binding(
      get: { workspace.dialogMessage != nil },
      set: { _ in }
    )) {
      if workspace.dialogIsPrompt { TextField("Value", text: Binding(get: { workspace.dialogInput }, set: { workspace.dialogInput = $0 })) }
      Button("OK") { workspace.finishDialog(true) }
      if workspace.dialogIsConfirmation || workspace.dialogIsPrompt { Button("Cancel", role: .cancel) { workspace.finishDialog(false) } }
    } message: { Text(workspace.dialogMessage ?? "") }
  }
}

#if os(macOS)
private struct WorkspaceWebView: NSViewRepresentable {
  let controller: WorkspaceController
  let model: AppModel
  func makeNSView(context: Context) -> WKWebView {
    controller.view { [weak model] in Task { await model?.logout() } }
  }
  func updateNSView(_ view: WKWebView, context: Context) {}
}
#else
private struct WorkspaceWebView: UIViewRepresentable {
  let controller: WorkspaceController
  let model: AppModel
  func makeUIView(context: Context) -> WKWebView {
    controller.view { [weak model] in Task { await model?.logout() } }
  }
  func updateUIView(_ view: WKWebView, context: Context) {}
}
#endif
