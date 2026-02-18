// MARK: - Core/RayVoiceEngine.swift
// Always-on ambient voice engine for the Ray voice pet

import Foundation
import Combine
import Speech
import AVFoundation
import SwiftUI

/// Ray state for UI binding
enum RayState: Equatable {
    case idle
    case listening
    case thinking
    case responding(String)
}

/// Always-on voice engine for Ray. Separate from VoiceAssistantService (keyboard panel mic).
/// Uses SFSpeechRecognizer + AVAudioEngine for continuous listening, wake-word activation,
/// and command routing with 1.5s silence timeout.
@MainActor
final class RayVoiceEngine: NSObject, ObservableObject {

    @Published var state: RayState = .idle {
        didSet { onStateChanged?(state) }
    }
    @Published private(set) var liveTranscript: String = ""

    var onCommand: ((String) -> Void)?
    var onStateChanged: ((RayState) -> Void)?

    func dismissResponse() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        state = .idle
    }

    private var recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var restartTask: Task<Void, Never>?
    private var wakeWordDetected = false
    private var pendingCommand = ""
    private let synthesizer = AVSpeechSynthesizer()
    private let silenceTimeout: TimeInterval = 1.5

    private var wakeWords: [String] {
        SynapseSettings.rayWakeWords
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    override init() {
        super.init()
    }

    func start() {
        guard SynapseSettings.rayEnabled else { return }
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
        state = .idle
        liveTranscript = ""
    }

    func speak(_ text: String) {
        guard SynapseSettings.rayAutoSpeak else { return }
        let content = cleanedSpeechText(text)
        guard !content.isEmpty else { return }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        state = .responding(content)
        let utterance = AVSpeechUtterance(string: content)
        utterance.rate = 0.47
        utterance.voice = AVSpeechSynthesisVoice(language: SynapseSettings.voiceLocale)
        synthesizer.delegate = self
        synthesizer.speak(utterance)
    }

    private func startIfPermitted() async {
        let speech = await ensureSpeechPermission()
        let mic = await ensureMicrophonePermission()
        guard speech && mic else {
            state = .idle
            return
        }
        startRecognitionSession()
    }

    private func startRecognitionSession() {
        stop()

        guard SynapseSettings.rayEnabled else { return }

        let locale = Locale(identifier: SynapseSettings.voiceLocale)
        recognizer = SFSpeechRecognizer(locale: locale)
        guard let recognizer, recognizer.isAvailable else {
            state = .idle
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

            state = .idle
            liveTranscript = ""

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
        } catch {
            state = .idle
            scheduleRestartIfNeeded()
        }
    }

    private func handleTranscript(_ text: String, isFinal: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        liveTranscript = trimmed

        let lower = trimmed.lowercased()

        if !wakeWordDetected {
            // Check for any configured wake word
            for wakeWord in wakeWords {
                guard !wakeWord.isEmpty else { continue }
                if lower.contains(wakeWord) {
                    wakeWordDetected = true
                    state = .listening
                    if let range = lower.range(of: wakeWord) {
                        let afterWake = String(trimmed[range.upperBound...])
                        let command = afterWake.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !command.isEmpty {
                            pendingCommand = command
                            scheduleCommandCommit(delay: isFinal ? 0.15 : silenceTimeout)
                        }
                    }
                    return
                }
            }
            return
        }

        // In active listening: accumulate command
        pendingCommand = cleanedCommand(trimmed)
        scheduleCommandCommit(delay: isFinal ? 0.2 : silenceTimeout)
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
            state = .idle
            liveTranscript = ""
            scheduleRestartIfNeeded()
            return
        }

        state = .thinking
        liveTranscript = ""
        pendingCommand = ""
        wakeWordDetected = false

        onCommand?(command)
        scheduleRestartIfNeeded()
    }

    private func scheduleRestartIfNeeded() {
        guard SynapseSettings.rayEnabled else { return }
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            await MainActor.run {
                guard let self else { return }
                guard SynapseSettings.rayEnabled else { return }
                self.startRecognitionSession()
            }
        }
    }

    private func cleanedCommand(_ text: String) -> String {
        var result = text
        for wakeWord in wakeWords {
            let lower = result.lowercased()
            if let range = lower.range(of: wakeWord) {
                result = String(result[range.upperBound...])
            }
        }
        return result
            .trimmingCharacters(in: CharacterSet(charactersIn: " ，。,:：\t\n"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

// MARK: - AVSpeechSynthesizerDelegate
extension RayVoiceEngine: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if state == .responding(utterance.speechString) {
                state = .idle
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if state == .responding(utterance.speechString) {
                state = .idle
            }
        }
    }
}
