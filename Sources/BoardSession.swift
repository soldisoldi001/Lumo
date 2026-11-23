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
    @Published private(set) var interrupted = false
    @Published private(set) var voiceNote = ""
    @Published private(set) var title = ""
    @Published private(set) var restoredIDs: Set<UUID> = []
    @Published private(set) var autoPaused = false
    @Published var paused = false
    @Published var mode: StudyMode = .lavagna

    let speech = SpeechEngine()
    let natural = NaturalVoice()
    let store = SessionStore()

    var isActive: Bool { status == .thinking || status == .explaining }
    var canResume: Bool { interrupted && !isActive }

    private var currentID: UUID?
    private var createdAt = Date()
    private var autoTitle = true
    private weak var settings: AppSettings?
    private var history: [ChatMessage] = []
    private var pending: [BoardBlock] = []
    private var inFlight: BoardBlock?
    private var replay: BoardBlock?
    private var speakingID: UUID?
    private var streamFinished = true
    private var needsContinuation = false
    private var lastQuestion = ""
    private var receivedBlocks = 0
    private var pendingError: String?
    private var streamTask: Task<Void, Never>?
    private var playerTask: Task<Void, Never>?
    private var audioTasks: [UUID: Task<Data?, Never>] = [:]
    private var ttsCooldownUntil = Date.distantPast
    private var autoStart = Date()
    private var autoRounds = 0
    private var topicComplete = false
    private var streamRetries = 0

    init() {
        Task.detached(priority: .background) { GeminiTTS.pruneCache() }
    }

    // MARK: - Domande

    func ask(_ question: String, settings: AppSettings) {
        let q = question.trimmed
        guard !q.isEmpty else { return }
        self.settings = settings
        cancelCurrent()
        settings.registerStudy()

        if currentID == nil {
            currentID = UUID()
            createdAt = Date()
            title = String(q.prefix(40))
            autoTitle = true
        }
        // contesto: cosa c'è già sulla lavagna (serve per "continua", "non ho capito", ecc.)
        let board = blocksSummary()
        let prompt = board.isEmpty ? q : q + "\n\n(Sulla lavagna c'è già: \(board))"

        interrupted = false
        autoPaused = false
        needsContinuation = false
        topicComplete = false
        autoStart = Date()
        autoRounds = 0
        streamRetries = 0
        replay = nil
        speakingID = nil
        pending = []

        blocks.append(BoardBlock(kind: .question, text: q))
        caption = ""
        pendingError = nil
        voiceNote = ""
        paused = false

        guard !settings.cleanKey.isEmpty else {
            status = .error("Manca la chiave API: aprila dall'ingranaggio nella home e tocca Verifica chiave e modello.")
            persist(immediately: true)
            return
        }
        startStream(prompt: prompt, remember: q, continuation: false, restartPlayer: true)
    }

    private func startStream(prompt: String, remember: String, continuation: Bool, restartPlayer: Bool) {
        guard let settings = settings else { return }
        if restartPlayer { status = .thinking }
        streamFinished = false
        receivedBlocks = 0
        lastQuestion = remember

        var messages = [ChatMessage(role: "system",
                                    content: Prompts.system(level: settings.level, mode: mode))]
        messages += history.suffix(8)
        messages.append(ChatMessage(role: "user", content: prompt))

        let endpoint = settings.endpoint
        let key = settings.cleanKey
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
                self?.streamDone(question: remember, raw: raw, continuation: continuation,
                                 incomplete: extractor.isIncomplete)
            } catch LLMError.truncated {
                if Task.isCancelled { return }
                self?.recoverCutOff(question: remember, continuation: continuation)
            } catch {
                if Task.isCancelled { return }
                self?.streamFailed(error)
            }
        }
        if restartPlayer { startPlayer() }
        persist()
    }

    private func enqueue(_ b: BoardBlock) {
        receivedBlocks += 1
        pending.append(b)
        prefetchNext()
    }

    private func streamDone(question: String, raw: String, continuation: Bool, incomplete: Bool) {
        let text = raw.trimmed
        let looksLikeJSON = text.hasPrefix("{") || text.hasPrefix("```") || text.contains("{\"t\"")

        // risposta tagliata a metà, oppure JSON che non riesco a leggere: riprovo da solo
        if incomplete || (receivedBlocks == 0 && looksLikeJSON && !continuation) {
            recoverCutOff(question: question, continuation: continuation)
            return
        }

        if continuation {
            // nessun blocco nuovo = non c'è più nulla da aggiungere
            if receivedBlocks == 0 { topicComplete = true }
        } else {
            if receivedBlocks == 0 {
                // risposta in testo semplice (non JSON): la mostro comunque
                if text.isEmpty {
                    pendingError = "Nessuna risposta dal servizio. Riprova."
                } else {
                    pending.append(BoardBlock(kind: .note, text: String(text.prefix(280)),
                                              say: String(text.prefix(400)), color: "amber"))
                }
            }
            history.append(ChatMessage(role: "user", content: question))
            history.append(ChatMessage(role: "assistant", content: raw))
        }
        streamFinished = true
        needsContinuation = false
    }

    /// La risposta si è interrotta: provo a farla proseguire (fino a 2 volte), poi lascio il pulsante Riprendi.
    private func recoverCutOff(question: String, continuation: Bool) {
        if streamRetries < 2 {
            streamRetries += 1
            startStream(prompt: continuePrompt(), remember: question,
                        continuation: true, restartPlayer: false)
            return
        }
        pendingError = "La risposta si è interrotta. Tocca Riprendi per continuare."
        needsContinuation = true
        streamFinished = true
    }

    private func streamFailed(_ error: Error) {
        pendingError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        needsContinuation = true     // potrai ritentare con "Riprendi"
        streamFinished = true
    }

    private func blocksSummary() -> String {
        (blocks + pending).suffix(40)
            .filter { $0.kind != .question }
            .map { b in
                let extra = b.items.isEmpty ? "" : " (" + b.items.joined(separator: ", ") + ")"
                return "\(b.kind.rawValue): \(b.text)\(extra)"
            }
            .joined(separator: "; ")
    }

    private func continuePrompt() -> String {
        "Vai avanti con lo schema sull'argomento: \(lastQuestion). Sulla lavagna c'è già: \(blocksSummary()). "
            + "Scrivi 4-8 blocchi nuovi che completano l'ultimo punto lasciato a metà oppure, se era completo, passano al prossimo aspetto importante non ancora trattato. "
            + "Non ripetere nulla, non rifare il title, collegati all'ultimo blocco. "
            + "Se l'argomento è già stato spiegato per intero, scrivi solo una note di ripasso con \"done\":true."
    }

    // MARK: - Regia: un blocco alla volta, comparsa e voce partono insieme

    private func startPlayer() {
        playerTask?.cancel()
        playerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                if self.paused {
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    continue
                }
                if let r = self.replay {
                    self.replay = nil
                    self.speakingID = r.id
                    if let s = self.settings {
                        await self.speakBlock(r, audio: await self.audioFor(r, s), s)
                    }
                    if Task.isCancelled { return }
                    self.speakingID = nil
                } else if !self.pending.isEmpty {
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

    private func present(_ original: BoardBlock) async {
        var b = original
        inFlight = b
        guard let s = settings else { return }

        // 1) preparo la voce PRIMA di mostrare il blocco, così scrittura e parlato partono insieme
        var audio: Data?
        if s.voiceOn && !b.say.isEmpty {
            audio = await audioFor(b, s)
            if Task.isCancelled { return }   // il blocco resta in inFlight e verrà salvato
        }
        if let a = audio {
            b.dur = NaturalVoice.duration(of: a) / max(0.5, s.playSpeed)
        }

        // 2) mostro il blocco
        inFlight = nil
        speakingID = b.id
        status = .explaining
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            blocks.append(b)
        }
        if b.kind == .title && autoTitle {
            title = String(b.text.prefix(60))
            autoTitle = false
        }
        caption = b.say
        if b.done == true { topicComplete = true }
        prefetchNext()
        persist()

        // 3) parlo
        await speakBlock(b, audio: audio, s)
        if Task.isCancelled { return }
        speakingID = nil
    }

    private func speakBlock(_ b: BoardBlock, audio: Data?, _ s: AppSettings) async {
        guard s.voiceOn, !b.say.isEmpty else {
            let ms = min(2600, 450 + b.displayLength * 22)
            try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
            return
        }
        if let a = audio {
            await natural.play(a, speed: s.playSpeed)
        } else {
            await speech.speak(b.say, voiceID: s.voiceID, rate: s.speechRate)
        }
    }

    // MARK: - Voce naturale (con scorta del prossimo blocco)

    private func useNatural(_ s: AppSettings) -> Bool {
        s.naturalVoice && s.provider == .gemini && !s.cleanKey.isEmpty
    }

    private func audioFor(_ b: BoardBlock, _ s: AppSettings) async -> Data? {
        guard useNatural(s) else { return nil }
        if let t = audioTasks[b.id] {
            audioTasks[b.id] = nil
            return await t.value
        }
        return await fetchAudio(b.say, s)
    }

    private func prefetchNext() {
        guard let s = settings, s.voiceOn, useNatural(s),
              audioTasks.isEmpty, let n = pending.first, !n.say.isEmpty else { return }
        let text = n.say
        audioTasks[n.id] = Task { [weak self] in
            await self?.fetchAudio(text, s)
        }
    }

    private func fetchAudio(_ text: String, _ s: AppSettings) async -> Data? {
        if Date() < ttsCooldownUntil { return nil }
        do {
            return try await GeminiTTS.audio(text: text, voice: s.geminiVoice,
                                             model: s.ttsModel, apiKey: s.cleanKey)
        } catch {
            if Task.isCancelled { return nil }
            if case TTSError.rateLimited = error {
                ttsCooldownUntil = Date().addingTimeInterval(25)
                voiceNote = "Limite gratuito della voce naturale: per un momento uso la voce di sistema."
            } else {
                ttsCooldownUntil = Date().addingTimeInterval(120)
                voiceNote = "Voce naturale non disponibile: uso la voce di sistema."
            }
            return nil
        }
    }

    private func finishPlayback() {
        caption = ""
        if let e = pendingError {
            interrupted = needsContinuation
            status = .error(e)
            persist(immediately: true)
            return
        }
        interrupted = false

        // continua da solo finché non fai una domanda o non scade il tempo
        if let s = settings, s.autoContinue, !topicComplete, currentID != nil {
            let limit = autoStart.addingTimeInterval(Double(max(1, s.autoMinutes)) * 60)
            if Date() < limit && autoRounds < 15 {
                autoRounds += 1
                streamRetries = 0
                startStream(prompt: continuePrompt(), remember: lastQuestion,
                            continuation: true, restartPlayer: true)
                return
            } else {
                needsContinuation = true
                interrupted = true
                autoPaused = true
            }
        }
        status = .idle
        persist(immediately: true)
    }

    // MARK: - Pausa, stop e ripresa (anche dopo giorni)

    func togglePause() {
        paused.toggle()
        if paused {
            speech.pause()
            natural.pause()
        } else {
            speech.resume()
            natural.resume()
        }
    }

    private func stopEngines() {
        streamTask?.cancel()
        playerTask?.cancel()
        audioTasks.values.forEach { $0.cancel() }
        audioTasks = [:]
        speech.stop()
        natural.stop()
    }

    private func cancelCurrent() {
        stopEngines()
        pending = []
        inFlight = nil
        speakingID = nil
        streamFinished = true
    }

    /// Ferma tutto e salva dove sei arrivato: potrai riprendere anche dopo giorni.
    func suspendAndSave() {
        guard currentID != nil else { return }
        if let f = inFlight { pending.insert(f, at: 0) }
        if let id = speakingID, let b = blocks.first(where: { $0.id == id }) { replay = b }
        if !streamFinished { needsContinuation = true }
        stopEngines()
        inFlight = nil
        speakingID = nil
        streamFinished = true
        interrupted = !pending.isEmpty || replay != nil || needsContinuation
        paused = false
        caption = ""
        if case .error = status {} else { status = .idle }
        persist(immediately: true)
    }

    func resume(settings: AppSettings) {
        guard interrupted else { return }
        self.settings = settings
        settings.registerStudy()
        interrupted = false
        autoPaused = false
        paused = false
        pendingError = nil
        voiceNote = ""
        autoStart = Date()
        autoRounds = 0
        streamRetries = 0
        if needsContinuation {
            needsContinuation = false
            startStream(prompt: continuePrompt(), remember: lastQuestion,
                        continuation: true, restartPlayer: true)
        } else {
            streamFinished = true
            status = .thinking
            startPlayer()
        }
        persist()
    }

    func load(_ id: UUID, settings: AppSettings) {
        suspendAndSave()
        guard let s = store.sessions.first(where: { $0.id == id }) else { return }
        self.settings = settings
        currentID = s.id
        createdAt = s.created
        title = s.title
        autoTitle = false
        mode = s.mode
        blocks = s.blocks
        restoredIDs = Set(s.blocks.map { $0.id })
        pending = s.pending
        history = s.history
        replay = s.replay
        needsContinuation = s.needsContinuation
        lastQuestion = s.lastQuestion
        interrupted = s.interrupted
        autoPaused = false
        topicComplete = false
        inFlight = nil
        speakingID = nil
        streamFinished = true
        pendingError = nil
        voiceNote = ""
        caption = ""
        paused = false
        status = .idle
    }

    func newSession() {
        suspendAndSave()
        currentID = nil
        title = ""
        blocks = []
        restoredIDs = []
        pending = []
        history = []
        replay = nil
        needsContinuation = false
        interrupted = false
        autoPaused = false
        topicComplete = false
        lastQuestion = ""
        caption = ""
        voiceNote = ""
        paused = false
        status = .idle
    }

    // MARK: - Salvataggio

    private func persist(immediately: Bool = false) {
        guard let id = currentID else { return }
        // Se l'app venisse chiusa a sorpresa durante la spiegazione, la sessione risulta comunque "in pausa".
        let active = isActive
        var savedReplay = replay
        if active, let sid = speakingID, let b = blocks.first(where: { $0.id == sid }) { savedReplay = b }
        var savedPending = pending
        if active, let f = inFlight { savedPending.insert(f, at: 0) }
        let cont = needsContinuation || (active && !streamFinished)
        let intr = interrupted || (active && (!savedPending.isEmpty || savedReplay != nil || cont))
        let s = StudySession(id: id,
                             title: title.isEmpty ? "Senza titolo" : title,
                             created: createdAt, updated: Date(), mode: mode,
                             blocks: blocks, pending: savedPending, history: history,
                             interrupted: intr, needsContinuation: cont,
                             lastQuestion: lastQuestion, replay: savedReplay)
        store.upsert(s, immediately: immediately)
    }
}
