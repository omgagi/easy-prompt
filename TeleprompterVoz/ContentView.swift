import AVFoundation
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var camera = CameraService()
    @AppStorage("savedScript") private var script = SampleScript.longSpanish
    @State private var scriptWords: [String] = []
    @State private var fontSize = 27.0
    @State private var showEditor = false
    @State private var displayedLine = -1
    @FocusState private var textFocused: Bool

    private var words: [String] { scriptWords }
    #if DEBUG
    private var screenshotMode: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "--easy-prompt-screenshot"),
              arguments.indices.contains(flag + 1) else { return nil }
        return arguments[flag + 1]
    }
    #endif

    var body: some View {
        prompterScreen
            .task {
                #if DEBUG
                if let screenshotMode {
                    script = SampleScript.longEnglish
                    scriptWords = ScriptFollower.displayWords(in: script)
                    camera.cameraReady = true
                    camera.speechAvailable = true
                    camera.status = screenshotMode == "recording" ? "Recording" : "Ready to record"
                    if screenshotMode == "recording" {
                        camera.currentWord = 12
                        camera.isRecording = true
                        camera.recordedDuration = 68
                        camera.microphoneActive = true
                        camera.voiceDetected = true
                    } else if screenshotMode == "paused" {
                        camera.currentWord = 12
                        camera.isPaused = true
                        camera.segmentCount = 2
                        camera.segmentDurations = [72, 93]
                        camera.canRedo = true
                        camera.recordedDuration = 165
                        camera.status = "Paused · tap Resume to continue"
                    }
                    if screenshotMode == "editor" { showEditor = true }
                    return
                }
                #endif
                if script == SampleScript.previousShortSpanish { script = SampleScript.longSpanish }
                scriptWords = ScriptFollower.displayWords(in: script)
                await camera.prepare()
            }
            .onChange(of: script) { _, updated in
                scriptWords = ScriptFollower.displayWords(in: updated)
                displayedLine = -1
            }
            .sheet(isPresented: $showEditor, onDismiss: {
                textFocused = false
            }) {
                editorSheet
            }
    }

    private var editorSheet: some View {
        NavigationStack {
            TextEditor(text: $script)
                .focused($textFocused)
                .task {
                    try? await Task.sleep(for: .milliseconds(300))
                    textFocused = true
                }
                .font(.system(size: 19))
                .foregroundStyle(.black)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .background(Color.white)
            .navigationTitle("Script")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        textFocused = false
                        showEditor = false
                    }
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private var prompterScreen: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            #if DEBUG
            if screenshotMode != nil,
               let demo = UIImage(contentsOfFile: NSHomeDirectory() + "/Documents/presenter-sample.png") {
                GeometryReader { geometry in
                    Image(uiImage: demo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
                .ignoresSafeArea()
            } else {
                CameraPreview(session: camera.session).ignoresSafeArea()
            }
            #else
            CameraPreview(session: camera.session).ignoresSafeArea()
            #endif
            VStack(spacing: 6) {
                if camera.recordedDuration > 0 || camera.isRecording {
                    RecordingProgressBar(duration: camera.recordedDuration,
                                         segmentDurations: camera.segmentDurations,
                                         isRecording: camera.isRecording)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        FlowingScript(words: words, currentWord: camera.currentWord, fontSize: fontSize)
                    }
                    .frame(height: 145)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !camera.isRecording && !camera.isStarting && !camera.isSaving && !camera.isPaused && !camera.isFinalizingSegment {
                            showEditor = true
                        }
                    }
                    .onChange(of: camera.currentWord) { _, newValue in
                        let line = min(newValue, max(words.count - 1, 0)) / 3
                        guard line != displayedLine else { return }
                        displayedLine = line
                        proxy.scrollTo(line, anchor: .top)
                    }
                }
                Spacer()
                HStack(alignment: .center) {
                    if camera.isPaused {
                        HStack(spacing: 0) {
                            Button(action: camera.undoLastSegment) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.title2.weight(.semibold))
                                    .frame(width: 46, height: 64)
                            }
                            .accessibilityLabel("Undo last take")
                            .disabled(camera.segmentCount == 0)
                            Button(action: camera.redoLastSegment) {
                                Image(systemName: "arrow.uturn.forward")
                                    .font(.title2.weight(.semibold))
                                    .frame(width: 46, height: 64)
                            }
                            .accessibilityLabel("Redo last take")
                            .disabled(!camera.canRedo)
                        }
                    } else {
                        Color.clear.frame(width: 92, height: 64)
                    }
                    Spacer()
                    Button {
                        if camera.isRecording { camera.pause() }
                        else if camera.isPaused { camera.resume() }
                        else { camera.start(script: script) }
                    } label: {
                        VStack(spacing: 7) {
                            ZStack {
                                Circle().stroke(.white, lineWidth: 4).frame(width: 76, height: 76)
                                RoundedRectangle(cornerRadius: camera.isRecording ? 5 : 30)
                                    .fill(.red)
                                    .frame(width: camera.isRecording ? 30 : 58, height: camera.isRecording ? 30 : 58)
                            }
                            Text(camera.isRecording ? "Pause" : camera.isPaused ? "Resume" : "Record")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .accessibilityLabel(camera.isRecording ? "Pause recording" : camera.isPaused ? "Resume recording" : "Record video")
                    .disabled(camera.isStarting || camera.isSaving || camera.isFinalizingSegment)
                    Spacer()
                    if camera.isPaused || camera.isRecording {
                        Button(action: camera.finish) {
                            Image(systemName: "checkmark")
                                .font(.title2.weight(.semibold))
                                .frame(width: 64, height: 64)
                        }
                        .accessibilityLabel("Finish video")
                        .disabled(camera.isStarting || camera.isFinalizingSegment || camera.isSaving || camera.segmentCount == 0 && !camera.isRecording)
                    } else {
                        Color.clear.frame(width: 92, height: 64)
                    }
                }
                .padding(.bottom, 8)
                Text(camera.status)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.65), in: Capsule())
                    .frame(maxWidth: .infinity)
                if camera.isRecording || camera.isStarting {
                    HStack(spacing: 14) {
                        Label(camera.microphoneActive ? "Mic OK" : "Waiting for mic", systemImage: "mic")
                        Label(camera.voiceDetected ? "Voice OK" : "Listening", systemImage: "waveform")
                    }
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.55), in: Capsule())
                }
                if !camera.isRecording && !camera.isPaused {
                    Text("Tap the script to edit or paste")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                }
                if let video = camera.lastVideo, !camera.isRecording && !camera.isPaused && !camera.isSaving {
                    ShareLink(item: video) { Label("Share last video", systemImage: "square.and.arrow.up") }
                        .font(.caption)
                        .buttonStyle(.bordered)
                }
            }
            .foregroundStyle(.white)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

}

private struct RecordingProgressBar: View {
    let duration: TimeInterval
    let segmentDurations: [TimeInterval]
    let isRecording: Bool
    private let interval: TimeInterval = 150

    private var blockCount: Int { max(1, Int(ceil(duration / interval))) }
    private var boundaries: [TimeInterval] {
        let completedCount = isRecording ? segmentDurations.count : max(0, segmentDurations.count - 1)
        var elapsed = 0.0
        return segmentDurations.prefix(completedCount).map { segment in
            elapsed += segment
            return elapsed
        }
    }

    var body: some View {
        GeometryReader { timeline in
            HStack(spacing: 3) {
                ForEach(0..<blockCount, id: \.self) { block in
                    GeometryReader { geometry in
                        Capsule()
                            .fill(.black.opacity(0.5))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(.red)
                                    .frame(width: geometry.size.width * min(1, max(0, (duration - Double(block) * interval) / interval)))
                            }
                            .clipShape(Capsule())
                    }
                    .frame(height: 5)
                }
            }
            .frame(height: 5)
            ForEach(Array(boundaries.enumerated()), id: \.offset) { _, boundary in
                Rectangle()
                    .fill(.white)
                    .frame(width: 2, height: 10)
                    .position(x: timeline.size.width * boundary / (Double(blockCount) * interval), y: 2.5)
            }
        }
        .frame(height: 10)
        .accessibilityLabel("Recording progress")
    }
}

private struct FlowingScript: View {
    let words: [String]
    let currentWord: Int
    let fontSize: Double
    private let wordsPerLine = 3

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 5) {
            ForEach(0..<Int(ceil(Double(words.count) / Double(wordsPerLine))), id: \.self) { line in
                let first = line * wordsPerLine
                let end = min(first + wordsPerLine, words.count)
                highlightedLine(first: first, end: end)
                    .font(.system(size: fontSize))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(line)
            }
            Color.clear.frame(height: 145)
        }
    }

    private func highlightedLine(first: Int, end: Int) -> Text {
        (first..<end).reduce(Text("")) { line, index in
            let word = Text(words[index] + (index < end - 1 ? " " : ""))
                .foregroundColor(index == currentWord ? .yellow : index < currentWord ? .gray : .white)
                .fontWeight(index == currentWord ? .bold : .regular)
            return line + word
        }
    }
}

private enum SampleScript {
    static let longEnglish = """
    Hello, and welcome. Today I want to show you how easy it can be to speak to the camera while keeping your thoughts on track. I can read these words at my own pace, and the teleprompter follows my voice as I go.

    I will look straight into the lens and speak naturally. If I pause to take a breath, the script waits for me. When I start talking again, the yellow highlight moves to the next word, keeping my place near the top of the screen.

    Now I can share a story with confidence. This morning I stepped outside, felt the warm sunlight, and noticed how quiet the street had become. I took a moment to enjoy the view before continuing with my day.

    A good presentation leaves room for moments like that. I can slow down, smile, and connect with the people watching. Easy Prompt helps me focus on what I want to say while I record a clean video.

    When I finish, I can save the video to Photos or share it with someone else. The script stays on my screen and does not appear in the final recording. Thanks for watching, and see you soon.
    """
    static let previousShortSpanish = "Hola. Este es mi primer vídeo con un teleprompter que sigue mi voz."
    static let longSpanish = """
    Hola, bienvenidos. Hoy quiero mostrarles una forma sencilla de hablar frente a la cámara sin perder el hilo de lo que queremos decir. Voy a leer este texto con calma, haciendo pausas naturales, para comprobar cómo el teleprompter sigue cada palabra de mi voz.

    Al principio miraré directamente al objetivo. Después bajaré un poco la velocidad y dejaré un silencio de varios segundos. Durante ese silencio, el texto debería quedarse quieto. Cuando vuelva a hablar, la palabra resaltada en amarillo tendría que avanzar conmigo, sin obligarme a correr ni a seguir un ritmo fijo.

    Ahora voy a contar una pequeña historia. Una mañana salí a caminar por mi barrio y vi que la luz del sol iluminaba las ventanas. Las calles estaban tranquilas, una cafetería acababa de abrir y alguien saludaba desde la esquina. Me detuve un momento para escuchar los sonidos de la ciudad. Pensé que una buena presentación también necesita esos momentos de calma: tiempo para respirar, mirar a la audiencia y dejar que una idea se entienda.

    En esta parte puedo probar algo más difícil. Voy a repetir una frase, voy a cambiar una palabra y quizá me salte una línea. Si el sistema pierde mi posición, puedo tocar la línea correcta en la pantalla y continuar. Lo importante es que la lectura se sienta cómoda y que yo mantenga el control de la grabación.

    Para terminar, volveré a hablar con un ritmo normal. Revisaré que el vídeo tenga imagen y sonido, que el texto no aparezca grabado sobre mi cara y que el archivo siga disponible después de cerrar la aplicación. Gracias por acompañarme en esta prueba. Hasta pronto.
    """
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
