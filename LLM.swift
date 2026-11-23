import Foundation

struct ChatMessage: Codable {
    let role: String
    let content: String
}

enum LLMError: LocalizedError {
    case badURL
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "Indirizzo del servizio non valido."
        case .http(let code, let body):
            var head: String
            switch code {
            case 400: head = "Richiesta rifiutata (400): la chiave potrebbe non essere valida."
            case 401, 403: head = "Chiave API non valida o non autorizzata (\(code))."
            case 404: head = "Modello o indirizzo non trovato (404): tocca Verifica chiave e modello nelle impostazioni."
            case 429: head = "Limite gratuito raggiunto (429): riprova tra poco o cambia modello."
            default: head = "Errore del servizio (\(code))."
            }
            let detail = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !detail.isEmpty { head += " Dettaglio: \(detail.prefix(160))" }
            return head
        }
    }
}

enum LLMClient {
    /// Streaming per qualsiasi servizio compatibile con l'API chat/completions (Gemini, Groq, ecc.).
    static func stream(endpoint: String, apiKey: String, model: String,
                       messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = URL(string: endpoint) else { throw LLMError.badURL }
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.timeoutInterval = 60
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    let body: [String: Any] = [
                        "model": model,
                        "stream": true,
                        "messages": messages.map { ["role": $0.role, "content": $0.content] }
                    ]
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    guard let http = response as? HTTPURLResponse else { throw LLMError.badURL }
                    if http.statusCode != 200 {
                        var errText = ""
                        for try await line in bytes.lines {
                            errText += line
                            if errText.count > 400 { break }
                        }
                        throw LLMError.http(http.statusCode, errText)
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                              let choices = obj["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let content = delta["content"] as? String else { continue }
                        continuation.yield(content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Elenco dei modelli disponibili per quella chiave (serve anche a verificare che la chiave sia valida).
    static func listModels(endpoint: String, apiKey: String) async throws -> [String] {
        var base = endpoint
        if let r = base.range(of: "/chat/completions") { base = String(base[..<r.lowerBound]) }
        guard let url = URL(string: base + "/models") else { throw LLMError.badURL }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw LLMError.badURL }
        if http.statusCode != 200 {
            throw LLMError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let arr = obj["data"] as? [[String: Any]] else { return [] }
        return arr.compactMap { $0["id"] as? String }
    }

    /// Elenco ordinato di modelli da provare, dal più adatto al meno adatto.
    static func candidates(current: String, ids: [String], provider: Provider) -> [String] {
        let names = ids.map { $0.hasPrefix("models/") ? String($0.dropFirst(7)) : $0 }
        var out: [String] = []
        func add(_ m: String?) {
            guard let m = m, !m.isEmpty, !out.contains(m) else { return }
            out.append(m)
        }
        add(current)
        if provider == .gemini {
            let preferred = ["gemini-3.5-flash-lite", "gemini-flash-lite-latest",
                             "gemini-3.1-flash-lite", "gemini-flash-latest", "gemini-3.5-flash"]
            for m in preferred where names.isEmpty || names.contains(m) { add(m) }
        }
        add(pickModel(ids: ids, provider: provider))
        return Array(out.prefix(6))
    }

    /// Sceglie un modello veloce tra quelli disponibili.
    static func pickModel(ids: [String], provider: Provider) -> String? {
        let names = ids.map { $0.hasPrefix("models/") ? String($0.dropFirst(7)) : $0 }
        let bad = ["image", "tts", "audio", "embedding", "live", "robotics", "computer",
                   "vision", "native", "exp", "guard", "whisper", "dialog", "veo", "imagen", "gemma"]
        let ok = names.filter { n in !bad.contains(where: { n.contains($0) }) }

        func best(_ list: [String]) -> String? {
            let stable = list.filter { !$0.contains("preview") }
            return (stable.isEmpty ? list : stable).sorted(by: >).first
        }

        switch provider {
        case .gemini:
            let gem = ok.filter { $0.hasPrefix("gemini") }
            if gem.contains("gemini-flash-lite-latest") { return "gemini-flash-lite-latest" }
            if let l = best(gem.filter { $0.contains("flash-lite") }) { return l }
            if gem.contains("gemini-flash-latest") { return "gemini-flash-latest" }
            return best(gem.filter { $0.contains("flash") })
        default:
            return best(ok.filter { $0.contains("llama") }) ?? ok.first
        }
    }
}

/// Estrae oggetti JSON completi man mano che arrivano i pezzi dello stream,
/// anche se il modello li scrive su più righe o dentro blocchi ```.
struct JSONObjectExtractor {
    private var buf: [Character] = []
    private var depth = 0
    private var inString = false
    private var escape = false

    mutating func feed(_ s: String) -> [String] {
        var out: [String] = []
        for ch in s {
            if depth == 0 {
                if ch == "{" {
                    depth = 1
                    buf = ["{"]
                    inString = false
                    escape = false
                }
                continue
            }
            buf.append(ch)
            if inString {
                if escape { escape = false }
                else if ch == "\\" { escape = true }
                else if ch == "\"" { inString = false }
            } else {
                if ch == "\"" { inString = true }
                else if ch == "{" { depth += 1 }
                else if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        out.append(String(buf))
                        buf = []
                    }
                }
            }
        }
        return out
    }
}

enum Prompts {
    static func system(level: String, mode: StudyMode) -> String {
        var extra = ""
        switch mode {
        case .lavagna:
            break
        case .riassumi:
            extra = "MODALITÀ RIASSUNTO: schema compatto di 6-9 blocchi, solo i concetti essenziali, say brevi."
        case .cheat:
            extra = "MODALITÀ CHEAT SHEET: solo definizioni, formule e regole essenziali, molte table, list e formula, say di una sola frase."
        }
        return #"""
        Sei Lumo, un tutor italiano che spiega alla lavagna, scrivendo e disegnando a mano mentre parli, come un bravo insegnante.
        Livello dello studente: \#(level).

        FORMATO (obbligatorio): rispondi SOLO con oggetti JSON, uno per riga, senza markdown e senza alcun testo fuori dai JSON. Ogni oggetto è un blocco che appare sulla lavagna mentre lo racconti:
        {"t":"TIPO","text":"...","items":["..."],"sub":"...","subs":["..."],"say":"...","color":"COLORE"}

        TIPI DI BLOCCO:
        - "title": titolo dell'argomento (text).
        - "flow": catena orizzontale di riquadri collegati da frecce, per processi e sequenze. items = 2-5 passi di 1-2 parole.
        - "box": un concetto in un riquadro. text = massimo 6 parole; sub = sigla o dettaglio piccolo sotto (facoltativo).
        - "merge": due elementi che confluiscono in un risultato. items = [A, B], subs = [dettaglio A, dettaglio B] (facoltativo), text = il risultato (ellisse).
        - "table": tabella. items = prima l'intestazione, poi le righe, con le colonne separate da " | " (es. "Fase | Dove", "Luminosa | Tilacoidi"). Massimo 5 righe e 3 colonne, celle brevi.
        - "icon": piccoli disegni. items = 1-4 nomi scelti SOLO tra: eye, ear, brain, heart, lightbulb, book, globe, atom, leaf, bolt, flame, drop, clock, calculator, chart, search, gear, person, people, building, medical, pill, tool, phone, mail, lock, key, cloud, star, flag, map, camera, music, money, scale, rocket, shield, puzzle. text = didascalia breve (facoltativa).
        - "list": elenco puntato scritto a mano. items = 2-5 voci di massimo 7 parole.
        - "arrow": freccia verso il basso che collega il blocco sopra a quello sotto. text = la relazione ("porta a", "perché", "quindi").
        - "formula": formula o esempio numerico (text).
        - "note": frase di enfasi scritta a mano e colorata, breve (text).
        - "tip": trucco da ricordare, su un foglietto (text).
        COLORI: violet, amber, green, blue, pink.

        ESEMPIO DI RISPOSTA (solo come stile del formato, non copiare il contenuto):
        {"t":"title","text":"Come funziona la fotosintesi","color":"green","say":"Partiamo dal quadro generale: come fa una pianta a fabbricarsi il cibo."}
        {"t":"flow","items":["Luce","Clorofilla","Zuccheri","Ossigeno"],"color":"green","say":"La luce viene catturata dalla clorofilla e trasformata in zuccheri, e come scarto esce ossigeno."}
        {"t":"icon","items":["leaf","bolt"],"text":"energia dalla luce","color":"green","say":"Le foglie sono come piccoli pannelli solari."}
        {"t":"table","items":["Fase | Dove","Luminosa | Tilacoidi","Calvin | Stroma"],"color":"blue","say":"Le due fasi avvengono in punti diversi del cloroplasto."}
        {"t":"merge","items":["Acqua","Luce"],"subs":["dalle radici","dal sole"],"text":"Energia chimica","color":"amber","say":"Acqua e luce insieme producono l'energia che serve alla pianta."}
        {"t":"note","text":"Senza luce niente zuccheri!","color":"pink","say":"Ricordatelo: senza luce il processo si ferma."}

        REGOLE:
        - Sulla lavagna parole chiave, mai frasi lunghe.
        - "say": ciò che dici ad alta voce per quel blocco, 1-2 frasi naturali e discorsive in italiano, tono amichevole, senza simboli, senza elenchi. Spiega il perché, non limitarti a ripetere il testo scritto.
        - Domanda nuova: 8-14 blocchi, dallo schema generale ai dettagli. Parti con un title. VARIA i tipi: usa flow per i processi, table per i confronti, merge quando due cose danno un risultato, icon quando c'è un oggetto concreto (organi, strumenti), e chiudi con una note o un tip. Non fare solo box e arrow.
        - Dubbio, approfondimento o richiesta di semplificare su ciò che hai già scritto: CONTINUA lo schema esistente. Non ripetere i blocchi già scritti e non rifare il title. Parti da un blocco che si collega a quello che c'è già, poi 4-8 blocchi. Se chiede di semplificare, usa un'analogia quotidiana e parole semplici. Se manda un esercizio, risolvilo passo passo con formula e note.
        - Inizia subito con il primo blocco, senza preamboli. Non andare a capo dentro i valori.
        - Se non sei sicuro di un dato, dillo in una note invece di inventare.
        \#(extra)
        """#
    }
}
