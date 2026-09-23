import SwiftUI

struct SignInView: View {
  @Environment(AppModel.self) private var model
  @State private var mode: Mode = .signIn
  @State private var username = ""
  @State private var displayName = ""
  @State private var password = ""
  @FocusState private var focus: Field?

  enum Mode: String, CaseIterable, Identifiable {
    case signIn = "Sign In"
    case create = "Create Account"
    var id: String { rawValue }
  }
  enum Field { case username, displayName, password }

  var body: some View {
    ZStack {
      AppBackdrop()
      ScrollView {
        VStack(spacing: 28) {
          VStack(spacing: 14) {
            PlainwireMark(size: 76)
            Text("Plainwire").font(.largeTitle.bold())
            Text("Messages, friends, and servers in one place.").font(.subheadline)
              .foregroundStyle(.secondary).multilineTextAlignment(.center)
          }
          VStack(spacing: 16) {
            Picker("Mode", selection: $mode) {
              ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            TextField("Username", text: $username).textContentType(.username).modifier(
              UsernameInputModifier()
            ).focused($focus, equals: .username)
              .textFieldStyle(.plain).padding(13).background(
                .primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            if mode == .create {
              TextField("Display name", text: $displayName).textContentType(.name).focused(
                $focus, equals: .displayName
              )
              .textFieldStyle(.plain).padding(13).background(
                .primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            SecureField("Password", text: $password).textContentType(
              mode == .signIn ? .password : .newPassword
            ).focused($focus, equals: .password)
              .textFieldStyle(.plain).padding(13).background(
                .primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 13, style: .continuous)
              )
              .onSubmit { submit() }
            Button(action: submit) {
              HStack {
                if model.isBusy { ProgressView().controlSize(.small) }
                Text(mode == .signIn ? "Sign In" : "Create Account").frame(maxWidth: .infinity)
              }
              .padding(.vertical, 5)
            }
            .adaptiveGlassButton(prominent: true).controlSize(.large).disabled(
              model.isBusy || username.isEmpty || password.isEmpty)
          }
          .padding(24)
          .adaptiveGlass(cornerRadius: 28)
          .frame(maxWidth: 440)
        }
        .padding(.horizontal, 24).padding(.vertical, 54)
        .frame(maxWidth: .infinity)
      }
    }
    .onAppear { focus = .username }
  }

  private func submit() {
    guard !model.isBusy else { return }
    Task {
      if mode == .signIn {
        _ = await model.login(username: username, password: password)
      } else {
        _ = await model.register(
          username: username, displayName: displayName.isEmpty ? username : displayName,
          password: password)
      }
    }
  }
}

private struct UsernameInputModifier: ViewModifier {
  @ViewBuilder func body(content: Content) -> some View {
    #if os(iOS)
      content.textInputAutocapitalization(.never).autocorrectionDisabled()
    #else
      content
    #endif
  }
}
