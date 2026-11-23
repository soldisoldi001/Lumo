import SwiftUI
import AVFoundation

@main
struct LumoApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var session = BoardSession()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(settings)
                .environmentObject(session)
                .environmentObject(session.store)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { phase in
                    // uscendo dall'app lo studio viene salvato e potrai riprenderlo
                    if phase == .background { session.suspendAndSave() }
                }
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var session: BoardSession
    @EnvironmentObject var store: SessionStore
    @State private var text = ""
    @State private var showBoard = false
    @State private var showSettings = false
    @State private var showHistory = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Spacer()
                VStack(spacing: 16) {
                    MascotView(size: 130)
                    Text("Cosa studiamo oggi?")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Theme.card))
                    if settings.cleanKey.isEmpty {
                        Button { showSettings = true } label: {
                            Text("Aggiungi la chiave API gratuita")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.ink)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 11)
                                .background(Capsule().fill(Color(red: 0.95, green: 0.94, blue: 1.0)))
                        }
                    }
                }
                Spacer()
                resumeCard
                modeChips
                InputBar(text: $text) { send() }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
        }
        .sheet(isPresented: $showHistory) {
            HistoryView { id in openSession(id, afterSheet: true) }
                .environmentObject(store)
        }
        .fullScreenCover(isPresented: $showBoard) {
            BoardView()
                .environmentObject(settings)
                .environmentObject(session)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.card))
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "flame.fill").foregroundColor(Theme.flame)
                Text("\(settings.streak)")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.flame)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(Capsule().fill(Theme.card))
            Spacer()
            HStack(spacing: 8) {
                Button { showHistory = true } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Theme.card))
                }
                Button {
                    if session.blocks.isEmpty { return }
                    showBoard = true
                } label: {
                    Image(systemName: "rectangle.and.pencil.and.ellipsis")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(session.blocks.isEmpty ? Color.white.opacity(0.3) : .white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Theme.card))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private var modeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(StudyMode.allCases) { m in
                    Button { session.mode = m } label: {
                        HStack(spacing: 8) {
                            Image(systemName: m.icon)
                            Text(m.label)
                        }
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(session.mode == m ? Theme.ink : .white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(session.mode == m ? Theme.violet : Theme.card))
                    }
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var resumeCard: some View {
        if let s = store.sessions.first(where: { $0.interrupted }) {
            Button { openSession(s.id, afterSheet: false) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(Theme.violet)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Riprendi lo studio")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text(s.title)
                            .font(.system(size: 13))
                            .foregroundColor(Color.white.opacity(0.65))
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
        }
    }

    private func openSession(_ id: UUID, afterSheet: Bool) {
        session.load(id, settings: settings)
        if afterSheet {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showBoard = true }
        } else {
            showBoard = true
        }
    }

    private func send() {
        let q = text.trimmed
        guard !q.isEmpty else { return }
        text = ""
        session.newSession()      // ogni nuovo argomento dalla home è una sessione a sé
        session.ask(q, settings: settings)
        showBoard = true
    }
}

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @StateObject private var tester = SpeechEngine()
    @StateObject private var natTester = NaturalVoice()
    @State private var voiceTest = ""
    @State private var showKey = false
    @State private var verifyText = ""
    @State private var verifying = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Servizio", selection: $settings.provider) {
                        ForEach(Provider.allCases) { p in
                            Text(p.label).tag(p)
                        }
                    }
                    HStack {
                        Group {
                            if showKey {
                                TextField("Incolla qui la chiave API", text: $settings.apiKey)
                            } else {
                                SecureField("Incolla qui la chiave API", text: $settings.apiKey)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        Button { showKey.toggle() } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                    Button("Incolla dagli appunti") {
                        if let clip = UIPasteboard.general.string {
                            settings.apiKey = clip
                        }
                    }
                    HStack {
                        Text("Chiave salvata")
                        Spacer()
                        Text(settings.cleanKey.isEmpty ? "nessuna" : "\(settings.cleanKey.count) caratteri")
                            .foregroundColor(settings.cleanKey.isEmpty ? Theme.flame : .green)
                    }
                    TextField("Modello", text: $settings.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if settings.provider == .custom {
                        TextField("URL (…/chat/completions)", text: $settings.customURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Button {
                        Task { await verify() }
                    } label: {
                        HStack {
                            Text(verifying ? "Controllo in corso\u{2026}" : "Verifica chiave e modello")
                            if verifying { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(verifying)
                    if !verifyText.isEmpty {
                        Text(verifyText)
                            .font(.system(size: 14))
                            .foregroundColor(verifyText.hasPrefix("\u{2705}") ? .green : Theme.flame)
                    }
                    if let url = settings.provider.keyURL {
                        Link("Ottieni una chiave gratuita", destination: url)
                    }
                } header: {
                    Text("Intelligenza artificiale")
                } footer: {
                    Text("La chiave resta solo su questo iPhone. I nomi dei modelli e i limiti gratuiti cambiano nel tempo: se vedi un errore, controlla l'elenco dei modelli sul sito del servizio.")
                }

                Section {
                    Toggle("Voce attiva", isOn: $settings.voiceOn)
                    Toggle("Voce naturale (Gemini)", isOn: $settings.naturalVoice)
                    if settings.naturalVoice {
                        Picker("Timbro", selection: $settings.geminiVoice) {
                            ForEach(GeminiTTS.voices, id: \.self) { Text($0).tag($0) }
                        }
                        TextField("Modello voce", text: $settings.ttsModel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        VStack(alignment: .leading) {
                            Text("Velocità voce naturale")
                            Slider(value: $settings.playSpeed, in: 0.85...1.5, step: 0.05)
                        }
                    }
                    Picker("Voce di riserva", selection: $settings.voiceID) {
                        Text("Automatica (la migliore)").tag("")
                        ForEach(SpeechEngine.italianVoices(), id: \.identifier) { v in
                            Text("\(v.name) · \(SpeechEngine.qualityLabel(v))").tag(v.identifier)
                        }
                    }
                    VStack(alignment: .leading) {
                        Text("Velocità voce di riserva")
                        Slider(value: $settings.speechRate, in: 0.40...0.62, step: 0.01)
                    }
                    Button("Prova la voce") {
                        Task { await testVoice() }
                    }
                    if !voiceTest.isEmpty {
                        Text(voiceTest)
                            .font(.system(size: 14))
                            .foregroundColor(voiceTest.hasPrefix("\u{2705}") ? .green : Theme.flame)
                    }
                } header: {
                    Text("Voce")
                } footer: {
                    Text("La voce naturale usa la stessa chiave Gemini e ha un limite gratuito: se finisce, Lumo passa da solo alla voce di sistema. Per una voce di sistema migliore scarica una voce italiana Avanzata o Premium: Impostazioni › Accessibilità › Contenuto letto › Voci › Italiano.")
                }

                Section("Studio") {
                    Picker("Livello", selection: $settings.level) {
                        ForEach(AppSettings.levels, id: \.self) { Text($0).tag($0) }
                    }
                    Toggle("Continua da solo", isOn: $settings.autoContinue)
                    if settings.autoContinue {
                        Picker("Pausa automatica dopo", selection: $settings.autoMinutes) {
                            ForEach([3, 5, 10, 15], id: \.self) { Text("\($0) minuti").tag($0) }
                        }
                    }
                    HStack {
                        Text("Serie di giorni")
                        Spacer()
                        Text("\(settings.streak)").foregroundColor(Theme.flame).bold()
                    }
                }
            }
            .navigationTitle("Impostazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
        .onChange(of: settings.provider) { p in
            if p != .custom { settings.model = p.defaultModel }
        }
    }

    private func testVoice() async {
        let phrase = "Ciao, sono Lumo. Ti spiego tutto alla lavagna, passo dopo passo."
        voiceTest = ""
        if settings.naturalVoice && settings.provider == .gemini && !settings.cleanKey.isEmpty {
            do {
                let wav = try await GeminiTTS.audio(text: phrase, voice: settings.geminiVoice,
                                                    model: settings.ttsModel, apiKey: settings.cleanKey)
                voiceTest = "\u{2705} Voce naturale attiva."
                await natTester.play(wav, speed: settings.playSpeed)
                return
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                voiceTest = "\u{274C} " + msg + " Uso la voce di sistema."
            }
        } else if settings.naturalVoice {
            voiceTest = "La voce naturale richiede il servizio Gemini e la chiave API."
        }
        await tester.speak(phrase, voiceID: settings.voiceID, rate: settings.speechRate)
    }

    private func verify() async {
        verifying = true
        verifyText = ""
        let key = settings.cleanKey
        guard !key.isEmpty else {
            verifyText = "Incolla prima la chiave API."
            verifying = false
            return
        }

        // 1) elenco dei modelli: controlla che la chiave sia valida
        var ids: [String] = []
        if settings.provider != .custom {
            do {
                ids = try await LLMClient.listModels(endpoint: settings.endpoint, apiKey: key)
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                verifyText = "\u{274C} " + msg
                verifying = false
                return
            }
        }

        // 2) prova reale con il modello attuale; se non è più disponibile provo gli altri
        let original = settings.effectiveModel
        let queue = LLMClient.candidates(current: original, ids: ids, provider: settings.provider)
        var lastError = "Nessun modello ha risposto."
        for m in queue {
            do {
                var got = ""
                let test = [ChatMessage(role: "user", content: "Rispondi con una sola parola: ok")]
                for try await chunk in LLMClient.stream(endpoint: settings.endpoint, apiKey: key,
                                                        model: m, messages: test) {
                    got += chunk
                    if !got.isEmpty { break }
                }
                if got.isEmpty {
                    lastError = "Nessuna risposta da \(m)."
                    continue
                }
                var note = ""
                if m != original {
                    settings.model = m
                    note = "Il modello precedente non era pi\u{00F9} disponibile: ora uso \(m). "
                }
                verifyText = "\u{2705} " + note + "Tutto funziona con \(m)."
                verifying = false
                return
            } catch let e as LLMError {
                lastError = e.errorDescription ?? "Errore del servizio."
                if case .http(let code, let body) = e {
                    let modelProblem = code == 404 || (code == 400 && body.lowercased().contains("model"))
                    if !modelProblem { break }
                } else {
                    break
                }
            } catch {
                lastError = error.localizedDescription
                break
            }
        }
        verifyText = "\u{274C} " + lastError
        verifying = false
    }
}
