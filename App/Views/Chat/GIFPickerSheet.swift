import SwiftUI

struct GIFPickerSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let room: AppModel.Room
  @State private var query = ""
  @State private var results: [PWGIF] = []
  @State private var next = ""
  @State private var provider = ""
  @State private var loading = false
  @State private var error: String?
  @State private var requestID = UUID()

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 230), spacing: 12)], spacing: 12) {
          ForEach(results) { gif in
            Button {
              if model.insertGIF(gif, query: query, room: room) { dismiss() }
            } label: {
              VStack(alignment: .leading, spacing: 5) {
                CachedRemoteImage(url: model.mediaURL(gif.previewURL ?? gif.url), pixelSize: 400) { phase in
                  if case .success(let image) = phase { image.resizable().scaledToFill() }
                  else {
                    Rectangle().fill(.quaternary)
                      .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
                  }
                }
                .frame(height: 130).frame(maxWidth: .infinity).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(gif.title.isEmpty ? "GIF" : gif.title).font(.caption)
                  .foregroundStyle(.secondary).lineLimit(1)
              }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Insert GIF: \(gif.title)")
          }
        }.padding()
        if let error, !results.isEmpty {
          Text(error).font(.caption).foregroundStyle(.secondary).padding(.horizontal)
        }
        if loading { ProgressView("Searching…").padding() }
        if !next.isEmpty && !loading {
          Button("Load More") { Task { await search(append: true) } }.padding()
        }
        if !provider.isEmpty && !results.isEmpty {
          Text("GIFs from \(provider)").font(.caption).foregroundStyle(.secondary).padding(.bottom)
        }
      }
      .overlay {
        if results.isEmpty && !loading {
          if let error {
            ContentUnavailableView {
              Label("GIF search unavailable", systemImage: "wifi.exclamationmark")
            } description: { Text(error) } actions: {
              Button("Try Again") { Task { await search(append: false) } }
            }
          } else {
            ContentUnavailableView(query.isEmpty ? "Find a GIF" : "No matching GIFs",
              systemImage: "photo.on.rectangle.angled",
              description: Text(query.isEmpty ? "Search for a GIF to add to your message." : "Try another search."))
          }
        }
      }
      .searchable(text: $query, prompt: "Search GIFs")
      .navigationTitle("Choose a GIF")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }
      }
      .task(id: query + model.serverAddress) {
        requestID = UUID()
        results = []
        next = ""
        error = nil
        loading = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard loading else { return }
        do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
        await search(append: false)
      }
      .onDisappear { requestID = UUID() }
    }
    .adaptiveSheetSize(minWidth: 460, idealWidth: 620, minHeight: 480)
    .sheetErrorNotice()
  }

  private func search(append: Bool) async {
    let token = UUID()
    requestID = token
    let searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !searchQuery.isEmpty else { loading = false; return }
    loading = true
    error = nil
    defer { if requestID == token { loading = false } }
    do {
      let page = try await model.searchGIFs(searchQuery, position: append ? next : nil)
      guard requestID == token, !Task.isCancelled else { return }
      var seen = Set(append ? results.map(\.id) : [])
      let items = page.results.filter { !$0.id.isEmpty && model.mediaURL($0.url) != nil && seen.insert($0.id).inserted }
      results = append ? results + items : items
      next = page.next
      provider = page.provider
    } catch {
      guard requestID == token, !Task.isCancelled else { return }
      if case PlainwireAPIError.server(_, let code, _) = error, code == "gif_search_unavailable" {
        self.error = "GIF search isn’t configured on this Plainwire server. You can still attach a GIF file or paste its image URL."
      } else { self.error = error.localizedDescription }
    }
  }
}
