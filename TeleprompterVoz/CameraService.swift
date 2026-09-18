@preconcurrency import AVFoundation
import Speech
import NaturalLanguage
import SwiftUI
import Photos

private final class SpeechInput: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var count = 0

    func start(_ request: SFSpeechAudioBufferRecognitionRequest) {
        lock.lock()
        self.request = request
        count = 0
        lock.unlock()
    }

    func append(_ buffer: CMSampleBuffer) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard let request else { return 0 }
        request.appendAudioSampleBuffer(buffer)
        count += 1
        return count
    }

    func end() {
        lock.lock()
        request?.endAudio()
        request = nil
        lock.unlock()
    }
}

@MainActor
final class CameraService: NSObject, ObservableObject {
    @Published var status = "Preparing camera…"
    @Published var isRecording = false
    @Published var currentWord = 0
    @Published var lastVideo: URL?
    @Published var speechAvailable = false
    @Published var cameraReady = false
    @Published var isStarting = false
    @Published var isSaving = false
    @Published var microphoneActive = false
    @Published var voiceDetected = false

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "teleprompter.capture")
    private let audioQueue = DispatchQueue(label: "teleprompter.audio")
    private let movieOutput = AVCaptureMovieFileOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var recognizer: SFSpeechRecognizer?
    nonisolated private let speechInput = SpeechInput()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var follower = ScriptFollower()
    private var configured = false

    override init() {
        super.init()
        if let path = UserDefaults.standard.string(forKey: "lastVideoPath"),
           FileManager.default.fileExists(atPath: path) {
            lastVideo = URL(fileURLWithPath: path)
        }
    }

    func prepare() async {
        let cameraOK = await AVCaptureDevice.requestAccess(for: .video)
        let micOK = await AVCaptureDevice.requestAccess(for: .audio)
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard cameraOK && micOK else {
            status = "Enable camera and microphone in Settings."
            return
        }
        speechAvailable = speechStatus == .authorized
        configureSession()
    }

    private func configureSession() {
        guard !configured else { return }
        configured = true
        let session = self.session
        let movieOutput = self.movieOutput
        let audioOutput = self.audioOutput
        let audioQueue = self.audioQueue
        sessionQueue.async { [weak self] in
            session.beginConfiguration()
            session.sessionPreset = .high
            do {
                guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                      let mic = AVCaptureDevice.default(for: .audio) else { throw CameraError.missingDevice }
                let cameraInput = try AVCaptureDeviceInput(device: camera)
                let micInput = try AVCaptureDeviceInput(device: mic)
                guard session.canAddInput(cameraInput), session.canAddInput(micInput),
                      session.canAddOutput(movieOutput), session.canAddOutput(audioOutput) else {
                    throw CameraError.cannotConfigure
                }
                session.addInput(cameraInput)
                session.addInput(micInput)
                session.addOutput(movieOutput)
                session.addOutput(audioOutput)
                if let self { audioOutput.setSampleBufferDelegate(self, queue: audioQueue) }
                if let connection = movieOutput.connection(with: .video), connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = true
                }
                session.commitConfiguration()
                session.startRunning()
                Task { @MainActor in
                    self?.cameraReady = true
                    self?.status = self?.speechAvailable == true ? "Ready to record" : "Enable Speech Recognition in Settings."
                }
                return
            } catch {
                session.commitConfiguration()
                Task { @MainActor in self?.status = "Camera error: \(error.localizedDescription)" }
            }
        }
    }

    func start(script: String) {
        guard cameraReady else {
            status = "Camera is not ready. Check camera and microphone access."
            return
        }
        guard !isStarting && !isRecording && !isSaving else {
            status = isSaving ? "Please wait while the video is saved." : "Recording is already starting."
            return
        }
        guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "Write a script first."
            return
        }
        guard speechAvailable else {
            status = "Voice follow needs Speech Recognition permission."
            return
        }
        recognizer = SpeechLocaleSelector.recognizer(for: script)
        guard recognizer != nil else {
            status = "Voice follow supports English and Spanish scripts."
            return
        }
        guard recognizer?.isAvailable == true else {
            status = "Speech Recognition is unavailable right now."
            return
        }
        follower.load(script)
        currentWord = 0
        microphoneActive = false
        voiceDetected = false
        isStarting = true
        status = "Starting recording…"
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch {
            isStarting = false
            status = "Could not create the recordings folder."
            return
        }
        let url = folder.appendingPathComponent(UUID().uuidString + ".mov")
        startRecognition()
        let output = movieOutput
        let session = self.session
        sessionQueue.async { [weak self] in
            if !session.isRunning { session.startRunning() }
            if let self { output.startRecording(to: url, recordingDelegate: self) }
        }
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        isSaving = true
        let output = movieOutput
        sessionQueue.async { output.stopRecording() }
        speechInput.end()
        recognitionTask?.cancel()
        recognitionTask = nil
        status = "Saving video…"
        currentWord = 0
        follower.seek(to: 0)
    }

    func shutdown() {
        speechInput.end()
        recognitionTask?.cancel()
        recognitionTask = nil
        let session = self.session
        sessionQueue.async { session.stopRunning() }
    }

    func seek(to word: Int) {
        follower.seek(to: word)
        currentWord = follower.position
    }

    private func startRecognition() {
        recognitionTask?.cancel()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        speechInput.start(request)
        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    if self.isStarting || self.isRecording {
                        if !result.bestTranscription.formattedString.isEmpty { self.voiceDetected = true }
                        self.currentWord = self.follower.follow(result.bestTranscription.formattedString)
                    }
                }
            }
            if let error {
                Task { @MainActor in
                    if self.isRecording { self.status = "Speech: \(error.localizedDescription)" }
                }
            }
        }
    }

    private func saveToPhotos(_ url: URL) async {
        let permission = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { continuation.resume(returning: $0) }
        }
        guard permission == .authorized else {
            status = "Video saved in app · Photos access denied"
            return
        }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHPhotoLibrary.shared().performChanges {
                    _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                } completionHandler: { success, error in
                    if success { continuation.resume() }
                    else { continuation.resume(throwing: error ?? NSError(domain: "VoiceTeleprompter", code: 1)) }
                }
            }
            status = "Saved to Photos · ready to share"
        } catch {
            status = "Video saved in app · Photos save failed"
        }
    }

    private enum CameraError: LocalizedError {
        case missingDevice, cannotConfigure
        var errorDescription: String? { "Could not configure the camera or microphone." }
    }
}

private enum SpeechLocaleSelector {
    static func recognizer(for script: String) -> SFSpeechRecognizer? {
        let supported = SFSpeechRecognizer.supportedLocales()
        let detected = NLLanguageRecognizer.dominantLanguage(for: script)?.rawValue
        let deviceLanguage = Locale.current.language.languageCode?.identifier
        let language: String
        if let detected, ["en", "es"].contains(detected) {
            language = detected
        } else if script.split(whereSeparator: \.isWhitespace).count < 5 {
            language = deviceLanguage.flatMap { ["en", "es"].contains($0) ? $0 : nil } ?? "en"
        } else {
            return nil
        }
        let current = Locale.current
        let preferred = [current, Locale(identifier: preferredIdentifier(for: language))]
        if let locale = preferred.first(where: {
            $0.language.languageCode?.identifier == language && supported.contains($0)
        }) {
            return SFSpeechRecognizer(locale: locale)
        }
        guard let locale = supported
            .filter({ $0.language.languageCode?.identifier == language })
            .sorted(by: { $0.identifier < $1.identifier })
            .first else { return nil }
        return SFSpeechRecognizer(locale: locale)
    }

    private static func preferredIdentifier(for language: String) -> String {
        switch language {
        case "en": return "en_US"
        case "es": return "es_ES"
        default: return language
        }
    }
}

extension CameraService: AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let count = speechInput.append(sampleBuffer)
        if count == 1 {
            Task { @MainActor [weak self] in self?.microphoneActive = true }
        }
    }
}

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        Task { @MainActor in self.isStarting = false; self.isRecording = true; self.status = "Recording" }
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        Task { @MainActor in
            self.isRecording = false
            self.isStarting = false
            self.isSaving = false
            if let error { self.status = "Recording error: \(error.localizedDescription)" }
            else {
                self.lastVideo = outputFileURL
                UserDefaults.standard.set(outputFileURL.path, forKey: "lastVideoPath")
                self.status = "Video saved in app · adding to Photos…"
                Task { await self.saveToPhotos(outputFileURL) }
            }
        }
    }
}
