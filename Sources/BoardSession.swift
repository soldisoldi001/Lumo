import SwiftUI

@MainActor
final class BoardSession: ObservableObject {
    enum Status: Equatable {
        case idle, thinking, explaining
        case error(String)
    }

    @Published private(set) var blocks: [BoardBlock] = []
    @Published private(set) var status: Status = .idle
    @Published private(set) var caption = ""
    @Published var paused = false
    @Published var mode: StudyMode = .lavagna

    let speech = SpeechEngine()

    private weak var settings: AppSettings?
    private var history: [ChatMessage] = []
    private var pending: [BoardBlock] = []
    private var streamFinished = true
    private var receivedBlocks = 0
    private var pendingError: String?
    private var streamTask: Task<Void, Never>?
    private var playerTask: Task<Void, Never>?

    // MARK: - Domande

    func ask(_ question: String, settings: AppSettings) {
        let q = question.trimmed
        guard !q.isEmpty else { return }
        self.settings = settings
        cancelCurrent()
        settings.registerStudy()

        blocks.append(BoardBlock(kind: .question, text: q))
        caption = ""
        pendingError = nil
        paused = false

        guard !settings.apiKey.trimmed.isEmpty else {
            status = .error("Inserisci la chiave API gratuita nelle impostazioni (icona ingranaggio nella home).")
            return
        }

        status = .thinking
        pending = []
        streamFinished = false
        receivedBlocks = 0

        var messages = [ChatMessage(role: "system",
                                    content: Prompts.system(level: settings.level, mode: mode))]
        messages += history.suffix(8)
        messages.append(ChatMessage(role: "user", content: q))

        let endpoint = settings.endpoint
        let key = settings.apiKey.trimmed
        let model = settings.effectiveModel

        streamTask = Task { [weak self] in
            var extractor = JSONObjectExtractor()
            var raw = ""
            do {
                for try await chunk in LLMClient.stream(endpoint: endpoint, apiKey: key,
                                                        model: model, messages: messages) {
                    raw += chunk
                    for obj in extractor.feed(chunk) {
                        if let b = BoardBlock.parse(obj) { self?.enqueue(b) }
                    }
                }
                if Task.isCancelled { return }
                self?.streamDone(question: q, raw: raw)
            } catch {
                if Task.isCancelled { return }
                self?.streamFailed(error)
            }
        }
        startPlayer()
    }

    private func enqueue(_ b: BoardBlock) {
        receivedBlocks += 1
        pending.append(b)
    }

    private func streamDone(question: String, raw: String) {
        if receivedBlocks == 0 {
            // Il modello ha risposto in testo semplice: lo mostro comunque.
            let text = raw.trimmed
            if text.isEmpty {
                pendingError = "Nessuna risposta dal servizio. Riprova."
            } else {
                pending.append(BoardBlock(kind: .note, text: String(text.prefix(280)),
                                          say: String(text.prefix(400)), color: "amber"))
            }
        }
        history.append(ChatMessage(role: "user", content: question))
        history.append(ChatMessage(role: "assistant", content: raw))
        streamFinished = true
    }

    private func streamFailed(_ error: Error) {
        pendingError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        streamFinished = true
    }

    // MARK: - Regia: mostra un blocco alla volta, in sincrono con la voce

    private func startPlayer() {
        playerTask?.cancel()
        playerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                if self.paused {
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    continue
                }
                if !self.pending.isEmpty {
                    let b = self.pending.removeFirst()
                    await self.present(b)
                } else if self.streamFinished {
                    self.finishPlayback()
                    return
                } else {
                    try? await Task.sleep(nanoseconds: 40_000_000)
                }
            }
        }
    }

    private func present(_ b: BoardBlock) async {
        status = .explaining
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            blocks.append(b)
        }
        caption = b.say
        guard let s = settings else { return }
        if s.voiceOn && !b.say.isEmpty {
            await speech.speak(b.say, voiceID: s.voiceID, rate: s.speechRate)
        } else {
            let ms = min(2600, 450 + b.displayLength * 22)
            try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
        }
    }

    private func finishPlayback() {
        caption = ""
        if let e = pendingError {
            status = .error(e)
        } else {
            status = .idle
        }
    }

    // MARK: - Controlli

    func togglePause() {
        paused.toggle()
        if paused { speech.pause() } else { speech.resume() }
    }

    private func cancelCurrent() {
        streamTask?.cancel()
        playerTask?.cancel()
        speech.stop()
        pending = []
        streamFinished = true
    }

    func stopAll() {
        cancelCurrent()
        paused = false
        caption = ""
        if case .error = status { return }
        status = .idle
    }

    func reset() {
        cancelCurrent()
        blocks = []
        history = []
        caption = ""
        paused = false
        status = .idle
    }
}
