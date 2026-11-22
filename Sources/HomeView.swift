import SwiftUI
import AVFoundation

@main
struct LumoApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var session = BoardSession()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(settings)
                .environmentObject(session)
                .preferredColorScheme(.dark)
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var session: BoardSession
    @State private var text = ""
    @State private var showBoard = false
    @State private var showSettings = false

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
                modeChips
                InputBar(text: $text) { send() }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
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

    private func send() {
        let q = text.trimmed
        guard !q.isEmpty else { return }
        text = ""
        session.ask(q, settings: settings)
        showBoard = true
    }
}

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @StateObject private var tester = SpeechEngine()
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
                    Picker("Voce", selection: $settings.voiceID) {
                        Text("Automatica (la migliore)").tag("")
                        ForEach(SpeechEngine.italianVoices(), id: \.identifier) { v in
                            Text("\(v.name) · \(SpeechEngine.qualityLabel(v))").tag(v.identifier)
                        }
                    }
                    VStack(alignment: .leading) {
                        Text("Velocità")
                        Slider(value: $settings.speechRate, in: 0.40...0.62, step: 0.01)
                    }
                    Button("Prova la voce") {
                        Task {
                            await tester.speak("Ciao, sono Lumo. Ti spiego tutto alla lavagna, passo dopo passo.",
                                               voiceID: settings.voiceID, rate: settings.speechRate)
                        }
                    }
                } header: {
                    Text("Voce")
                } footer: {
                    Text("Per una voce molto più naturale scarica una voce italiana Avanzata o Premium: Impostazioni › Accessibilità › Contenuto letto › Voci › Italiano.")
                }

                Section("Studio") {
                    Picker("Livello", selection: $settings.level) {
                        ForEach(AppSettings.levels, id: \.self) { Text($0).tag($0) }
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

    private func verify() async {
        verifying = true
        verifyText = ""
        let key = settings.cleanKey
        guard !key.isEmpty else {
            verifyText = "Incolla prima la chiave API."
            verifying = false
            return
        }
        var note = ""

        // 1) elenco dei modelli: controlla che la chiave sia valida e che il modello esista ancora
        if settings.provider != .custom {
            do {
                let ids = try await LLMClient.listModels(endpoint: settings.endpoint, apiKey: key)
                if !ids.isEmpty {
                    let cur = settings.effectiveModel
                    let exists = ids.contains(where: { $0 == cur || $0 == "models/" + cur })
                    if !exists, let best = LLMClient.pickModel(ids: ids, provider: settings.provider) {
                        settings.model = best
                        note = "Il modello precedente non c\u{2019}era pi\u{00F9}: ho scelto \(best). "
                    }
                }
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                verifyText = "\u{274C} " + msg
                verifying = false
                return
            }
        }

        // 2) prova reale: una domanda minuscola in streaming
        do {
            var got = ""
            let test = [ChatMessage(role: "user", content: "Rispondi con una sola parola: ok")]
            for try await chunk in LLMClient.stream(endpoint: settings.endpoint, apiKey: key,
                                                    model: settings.effectiveModel, messages: test) {
                got += chunk
                if !got.isEmpty { break }
            }
            if got.isEmpty {
                verifyText = "\u{26A0}\u{FE0F} Il servizio non ha risposto. Riprova tra poco."
            } else {
                verifyText = "\u{2705} " + note + "Tutto funziona con \(settings.effectiveModel)."
            }
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            verifyText = "\u{274C} " + msg
        }
        verifying = false
    }
}
