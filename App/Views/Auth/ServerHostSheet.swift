import SwiftUI

struct ServerHostSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var address = ""
  @State private var connecting = false

  private var validated: PlainwireConfiguration? { try? PlainwireConfiguration(serverAddress: address) }
  private var recentServers: [String] {
    let saved = UserDefaults.standard.stringArray(forKey: AppPreferenceKeys.recentServers) ?? []
    return Array(Set(saved + [PlainwireConfiguration.defaultServerAddress, model.serverAddress])).sorted()
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Server address", text: $address, prompt: Text("https://chat.example.com"))
            .textContentType(.URL)
            .autocorrectionDisabled()
            .modifier(ServerURLInputModifier())
            .onSubmit { connect() }
          if !address.isEmpty && validated == nil {
            Label("Use HTTPS, or HTTP for a local server. Leave out invite links and sign-in details.",
              systemImage: "exclamationmark.circle")
              .font(.caption).foregroundStyle(.secondary)
          }
        } header: { Text("Plainwire host") } footer: {
          Text("Use the address of a Plainwire installation. A custom port or deployment path is supported.")
        }

        Section("Recent hosts") {
          ForEach(recentServers, id: \.self) { server in
            Button {
              address = server
            } label: {
              HStack {
                Label(server, systemImage: server.hasPrefix("https://") ? "lock.shield" : "network")
                  .lineLimit(2).truncationMode(.middle)
                Spacer()
                if server == model.serverAddress {
                  Image(systemName: "checkmark").accessibilityLabel("Current host")
                }
              }.contentShape(Rectangle())
            }.buttonStyle(.plain)
          }
        }
        if model.session != nil {
          Section {
            Text("Switching hosts signs out of this account and ends any active call. Your drafts stay saved for this host. Sign in with an account on the new host.")
              .font(.callout).foregroundStyle(.secondary)
          }
        }
      }
      .formStyle(.grouped)
      .disabled(connecting)
      .navigationTitle("Switch Server Host")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(connecting)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            connect()
          } label: {
            HStack(spacing: 6) {
              if connecting { ProgressView().controlSize(.small) }
              Text(connecting ? "Connecting…" : "Connect")
            }
          }
          .keyboardShortcut(.defaultAction)
          .disabled(validated == nil || connecting || model.isBusy)
        }
      }
    }
    .adaptiveSheetSize(minWidth: 480, minHeight: 430)
    .onAppear { address = model.serverAddress }
    .sheetErrorNotice()
    .interactiveDismissDisabled(connecting)
  }

  private func connect() {
    guard validated != nil, !connecting, !model.isBusy else { return }
    connecting = true
    Task {
      if await model.switchServer(to: address) { dismiss() }
      connecting = false
    }
  }
}

private struct ServerURLInputModifier: ViewModifier {
  @ViewBuilder func body(content: Content) -> some View {
    #if os(iOS)
      content.keyboardType(.URL).textInputAutocapitalization(.never)
    #else
      content
    #endif
  }
}
