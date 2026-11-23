import SwiftUI
import AVFoundation
import Speech
import Vision

// MARK: - Voce di Lumo (sintesi vocale gratuita, a latenza zero)

@MainActor
final class SpeechEngine: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?
    private var current: AVSpeechUtterance?

    override init() {
        super.init()
        synth.delegate = self
        try? AVAudioSession.sharedInstance().setCategory(
            .playAndRecord, mode: .default,
            options: [.defaultToSpeaker, .allowBluetooth])
    }

    static func italianVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == "it-IT" }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
    }

    static func qualityLabel(_ v: AVSpeechSynthesisVoice) -> String {
        switch v.quality {
        case .premium: return "Premium"
        case .enhanced: return "Avanzata"
        default: return "Standard"
        }
    }

    private func voice(for id: String) -> AVSpeechSynthesisVoice? {
        if !id.isEmpty, let v = AVSpeechSynthesisVoice(identifier: id) { return v }
        return Self.italianVoices().first ?? AVSpeechSynthesisVoice(language: "it-IT")
    }

    private func clean(_ s: String) -> String {
        var t = s
        for ch in ["*", "#", "_", "`", "→", "->", "=>"] {
            t = t.replacingOccurrences(of: ch, with: " ")
        }
        return t
    }

    /// Parla e ritorna quando la frase è finita (o è stata interrotta).
    func speak(_ text: String, voiceID: String, rate: Double) async {
        finishPending()
        let u = AVSpeechUtterance(string: clean(text))
        u.voice = voice(for: voiceID)
        u.rate = Float(rate)
        u.preUtteranceDelay = 0
        u.postUtteranceDelay = 0.03
        try? AVAudioSession.sharedInstance().setActive(true)
        current = u
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            self.continuation = c
            self.synth.speak(u)
        }
    }

    func pause() { synth.pauseSpeaking(at: .immediate) }
    func resume() { synth.continueSpeaking() }

    func stop() {
        let c = continuation
        continuation = nil
        current = nil
        synth.stopSpeaking(at: .immediate)
        c?.resume()
    }

    private func finishPending() {
        let c = continuation
        continuation = nil
        current = nil
        c?.resume()
    }

    private func finished(_ u: AVSpeechUtterance) {
        guard u === current else { return }
        current = nil
        let c = continuation
        continuation = nil
        c?.resume()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished(utterance) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished(utterance) }
    }
}

// MARK: - Dettatura (microfono)

final class VoiceInput: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "it-IT"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else { return }
                AVAudioSession.sharedInstance().requestRecordPermission { ok in
                    DispatchQueue.main.async { if ok { self.begin() } }
                }
            }
        }
    }

    private func begin() {
        guard !isRecording, let recognizer = recognizer, recognizer.isAvailable else { return }
        transcript = ""
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch { return }
        isRecording = true

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let r = result { self.transcript = r.bestTranscription.formattedString }
                if error != nil || (result?.isFinal ?? false) { self.stop() }
            }
        }
    }

    func stop() {
        guard isRecording else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        isRecording = false
    }
}

// MARK: - OCR da foto (Vision, gratis e sul dispositivo)

enum OCR {
    static func text(from image: UIImage) async -> String {
        guard let cg = image.cgImage else { return "" }
        return await Task.detached(priority: .userInitiated) {
            let req = VNRecognizeTextRequest()
            req.recognitionLevel = .accurate
            req.recognitionLanguages = ["it-IT", "en-US"]
            req.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            try? handler.perform([req])
            let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
            return observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }.value
    }
}
