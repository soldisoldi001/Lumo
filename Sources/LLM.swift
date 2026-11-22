import Foundation

struct ChatMessage {
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
            if code == 401 || code == 403 { return "Chiave API non valida o non autorizzata (\(code))." }
            if code == 429 { return "Limite gratuito raggiunto: riprova tra poco o cambia servizio o modello." }
            if code == 404 { return "Modello non trovato: controlla il nome del modello nelle impostazioni." }
            return "Errore del servizio (\(code)). \(body.prefix(120))"
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
                        "temperature": 0.5,
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
            extra = "MODALITÀ CHEAT SHEET: solo definizioni, formule e regole essenziali, molti blocchi list e formula, say di una sola frase."
        }
        return #"""
        Sei Lumo, un tutor italiano che spiega alla lavagna, come un bravo insegnante.
        Livello dello studente: \#(level).

        FORMATO (obbligatorio): rispondi SOLO con oggetti JSON, uno per riga, senza markdown e senza alcun testo fuori dai JSON. Ogni oggetto è un blocco della lavagna:
        {"t":"TIPO","text":"...","items":["..."],"say":"...","color":"COLORE"}

        TIPI: "title" (titolo dell'argomento), "box" (concetto chiave in un riquadro), "list" (elenco puntato, 2-5 voci in items), "arrow" (freccia di collegamento, text = la relazione, ad esempio "porta a" o "perché"), "formula" (formula o esempio numerico), "note" (trucco da ricordare o attenzione).
        COLORI: violet, amber, green, blue, pink.

        REGOLE:
        - "text" sulla lavagna: parole chiave, massimo 8 parole. Le voci di items: massimo 7 parole. Niente frasi lunghe.
        - "say": ciò che dici ad alta voce per quel blocco, 1-2 frasi naturali e discorsive in italiano, tono amichevole, senza simboli, senza elenchi. Spiega il perché, non limitarti a ripetere il testo scritto.
        - Domanda nuova: 8-14 blocchi, dallo schema generale ai dettagli. Parti con un title, poi box e arrow che costruiscono i collegamenti tra i concetti, list per i dettagli, un esempio e una note finale col trucco da ricordare.
        - Dubbio, approfondimento o richiesta di semplificare su ciò che hai già scritto: CONTINUA lo schema esistente. Non ripetere i blocchi già scritti e non rifare il title. Parti da un blocco che si collega a quello che c'è già (arrow o box), poi 4-8 blocchi. Se chiede di semplificare, usa un'analogia quotidiana e parole semplici.
        - Inizia subito con il primo blocco, senza preamboli. Non andare a capo dentro i valori.
        - Se non sei sicuro di un dato, dillo in una note invece di inventare.
        \#(extra)
        """#
    }
}
