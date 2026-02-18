import Foundation
import Combine
import Speech
import AVFoundation

@MainActor
final class VoiceAssistantService: NSObject, ObservableObject {
    static let shared = VoiceAssistantService()

    @Published private(set) var isListening: Bool = false
    @Published private(set) var statusText: String = "语音待机"
    @Published private(set) var liveTranscript: String = ""

    var onCommand: ((String) -> Void)?

    private var recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var restartTask: Task<Void, Never>?
    private var wakeWordDetected = false
    private var pendingCommand = ""
    private let synthesizer = AVSpeechSynthesizer()

    private override init() {
        super.init()
    }

    func start() {
        Task { [weak self] in
            await self?.startIfPermitted()
        }
    }

    func stop() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        restartTask?.cancel()
        restartTask = nil

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)

        wakeWordDetected = false
        pendingCommand = ""
        isListening = false
        if SynapseSettings.voiceEnabled {
            statusText = "语音暂停"
        } else {
            statusText = "语音关闭"
        }
    }

    func toggleListening() {
        if isListening {
            stop()
        } else {
            start()
        }
    }

    func speak(_ text: String) {
        guard SynapseSettings.voiceSpeakResponse else { return }
        let content = cleanedSpeechText(text)
        guard !content.isEmpty else { return }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: content)
        utterance.rate = 0.47
        utterance.voice = AVSpeechSynthesisVoice(language: SynapseSettings.voiceLocale)
        synthesizer.speak(utterance)
    }

    private func startIfPermitted() async {
        let speech = await ensureSpeechPermission()
        let mic = await ensureMicrophonePermission()
        guard speech && mic else {
            isListening = false
            statusText = "缺少语音权限"
            return
        }
        startRecognitionSession()
    }

    private func startRecognitionSession() {
        stop()

        let locale = Locale(identifier: SynapseSettings.voiceLocale)
        recognizer = SFSpeechRecognizer(locale: locale)
        guard let recognizer, recognizer.isAvailable else {
            statusText = "语音识别暂不可用"
            return
        }

        do {
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                Task { @MainActor in
                    if let result {
                        self.handleTranscript(result.bestTranscription.formattedString, isFinal: result.isFinal)
                    }

                    if error != nil || (result?.isFinal ?? false) {
                        self.scheduleRestartIfNeeded()
                    }
                }
            }

            isListening = true
            statusText = "语音监听中（唤醒词：\(SynapseSettings.voiceWakeWord)）"
        } catch {
            statusText = "语音启动失败：\(error.localizedDescription)"
            stop()
        }
    }

    private func handleTranscript(_ text: String, isFinal: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        liveTranscript = trimmed

        let wakeWord = SynapseSettings.voiceWakeWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let wakeWordLower = wakeWord.lowercased()
        let lower = trimmed.lowercased()

        if !wakeWordDetected {
            guard let wakeRange = lower.range(of: wakeWordLower) else { return }
            wakeWordDetected = true
            statusText = "已唤醒，正在听取命令..."
            let command = String(trimmed[wakeRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !command.isEmpty {
                pendingCommand = command
                scheduleCommandCommit(delay: isFinal ? 0.15 : 0.8)
            }
            return
        }

        pendingCommand = cleanedCommand(trimmed, wakeWord: wakeWord)
        scheduleCommandCommit(delay: isFinal ? 0.2 : 0.8)
    }

    private func scheduleCommandCommit(delay: TimeInterval) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.commitVoiceCommand()
            }
        }
    }

    private func commitVoiceCommand() {
        let command = pendingCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            wakeWordDetected = false
            return
        }

        statusText = "已识别语音命令：\(command)"
        onCommand?(command)
        if SynapseSettings.voiceAutoExecute {
            speak("正在执行")
        }

        pendingCommand = ""
        wakeWordDetected = false
    }

    private func scheduleRestartIfNeeded() {
        guard SynapseSettings.voiceEnabled else { return }
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            await MainActor.run {
                guard let self else { return }
                guard SynapseSettings.voiceEnabled else { return }
                self.startRecognitionSession()
            }
        }
    }

    private func cleanedCommand(_ text: String, wakeWord: String) -> String {
        let lower = text.lowercased()
        let lowerWake = wakeWord.lowercased()
        if let range = lower.range(of: lowerWake) {
            let suffix = String(text[range.upperBound...])
            return suffix
                .trimmingCharacters(in: CharacterSet(charactersIn: " ，。,:：\t\n"))
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanedSpeechText(_ text: String) -> String {
        let compact = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if compact.count > 180 {
            return String(compact.prefix(180))
        }
        return compact
    }

    private func ensureSpeechPermission() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .authorized { return true }
        if status == .denied || status == .restricted { return false }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { authStatus in
                continuation.resume(returning: authStatus == .authorized)
            }
        }
    }

    private func ensureMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }
}
