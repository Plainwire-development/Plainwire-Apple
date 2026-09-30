import SwiftUI
import Observation
@preconcurrency import AVFoundation

@MainActor @Observable
private final class VoiceNoteRecorder: NSObject, AVAudioRecorderDelegate {
  private var recorder: AVAudioRecorder?
  private var preparationGeneration = 0
  private(set) var fileURL: URL?
  private(set) var recording = false
  private(set) var preparing = false
  private(set) var duration: TimeInterval = 0
  var error: String?
  var elapsed: TimeInterval { recording ? recorder?.currentTime ?? 0 : duration }

  func start() async {
    guard !preparing, !recording else { return }
    preparing = true
    let generation = preparationGeneration
    error = nil
    defer { preparing = false }
    let permitted = await AVCaptureDevice.requestAccess(for: .audio)
    guard generation == preparationGeneration, !Task.isCancelled else { return }
    guard permitted, !Task.isCancelled else {
      error = "Microphone access is needed to record a voice note. Enable it in system settings."
      return
    }
    do {
      #if os(iOS)
        try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try AVAudioSession.sharedInstance().setActive(true)
      #endif
      discardFile()
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("plainwire-voice-\(UUID().uuidString).m4a")
      let next = try AVAudioRecorder(url: url, settings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ])
      next.delegate = self
      fileURL = url
      recorder = next
      duration = 0
      guard next.record(forDuration: 120) else { throw PlainwireAPIError.invalidFile }
      recording = true
    } catch {
      self.error = "Unable to start recording: \(error.localizedDescription)"
      discard()
    }
  }

  func stop() {
    guard recording else { return }
    duration = recorder?.currentTime ?? 0
    recording = false
    recorder?.stop()
    #if os(iOS)
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    #endif
  }

  func discard() {
    preparationGeneration += 1
    stop()
    recorder?.delegate = nil
    recorder = nil
    discardFile()
    duration = 0
  }
  private func discardFile() {
    if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    fileURL = nil
  }

  nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
    let url = recorder.url
    Task { @MainActor [weak self] in
      guard let self, self.fileURL == url else { return }
      if self.recording {
        let elapsed = self.recorder?.currentTime ?? 0
        self.duration = elapsed > 0 ? min(120, elapsed) : (flag ? 120 : 0)
        self.recording = false
      }
      #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      #endif
      if !flag { self.error = "Recording was interrupted. Please record again." }
    }
  }
  nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
    let url = recorder.url
    Task { @MainActor [weak self] in
      guard let self, self.fileURL == url else { return }
      self.error = "This voice note could not be recorded. Please try again."
      self.stop()
    }
  }
}

struct VoiceNoteSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  let room: AppModel.Room
  @State private var recorder = VoiceNoteRecorder()
  @State private var uploading = false
  var body: some View {
    NavigationStack {
      VStack(spacing: 22) {
        Image(systemName: recorder.recording ? "waveform" : "mic.fill")
          .font(.system(size: 42, weight: .medium))
          .foregroundStyle(recorder.recording ? Color.red : Color.accentColor)
          .frame(width: 100, height: 100)
          .background(.primary.opacity(0.045), in: Circle())
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
          Text(timerText).font(.system(.title, design: .monospaced).weight(.medium))
        }
        Text(recorder.recording ? "Recording · up to 2 minutes" : "Voice note for \(room.title)")
          .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        if let error = recorder.error { Text(error).font(.callout).foregroundStyle(.red).multilineTextAlignment(.center) }
        HStack(spacing: 12) {
          if recorder.recording {
            Button("Stop Recording", systemImage: "stop.fill") { recorder.stop() }
              .buttonStyle(.borderedProminent).tint(.red)
          } else {
            Button(recorder.fileURL == nil ? "Record" : "Record Again", systemImage: "mic.fill") {
              Task { await recorder.start() }
            }.buttonStyle(.bordered).disabled(recorder.preparing || uploading)
            if recorder.fileURL != nil && recorder.duration > 0 && recorder.error == nil {
              Button(uploading ? "Uploading…" : "Attach Voice Note", systemImage: "paperclip") {
                Task { await attach() }
              }.buttonStyle(.borderedProminent).disabled(uploading)
            }
          }
        }
      }
      .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
      .navigationTitle("Voice Note")
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { recorder.discard(); dismiss() }.disabled(uploading) } }
    }
    .adaptiveSheetSize(minWidth: 380, idealWidth: 460, minHeight: 360)
    .sheetErrorNotice()
    .interactiveDismissDisabled(recorder.recording || recorder.preparing || uploading)
    .onChange(of: scenePhase) { _, phase in if phase != .active { recorder.stop() } }
    .onDisappear { recorder.discard() }
  }
  private var timerText: String {
    let seconds = Int(max(0, recorder.elapsed))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
  }
  private func attach() async {
    guard let file = recorder.fileURL else { return }
    uploading = true
    defer { uploading = false }
    guard let upload = await model.upload(file), model.sessionState == .ready else { return }
    var draft = model.drafts[room.identifier] ?? ""
    if !draft.isEmpty { draft += " " }
    let name = "Voice note.m4a"
    draft += "[\(name)](\(upload.url)#plainwire-voice-note)"
    model.drafts[room.identifier] = draft
    dismiss()
  }
}
