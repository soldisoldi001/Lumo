import SwiftUI
import AVFoundation
import CryptoKit

// MARK: - Voce naturale (Gemini TTS, stessa chiave gratuita di Gemini)

enum TTSError: LocalizedError {
    case rateLimited
    case http(Int)
    case empty

    var errorDescription: String? {
        switch self {
        case .rateLimited: return "Limite gratuito della voce raggiunto (429): riprova tra poco."
        case .http(let c): return "Errore del servizio vocale (\(c)): controlla il nome del modello voce nelle impostazioni."
        case .empty: return "Il servizio non ha restituito audio."
        }
    }
}

enum GeminiTTS {
    static let voices = ["Kore", "Puck", "Aoede", "Zephyr", "Leda", "Charon", "Fenrir", "Orus", "Sulafat", "Achernar"]
    static let fallbackModels = ["gemini-3.1-flash-tts-preview", "gemini-2.5-flash-preview-tts"]

    // Cache su disco: riascoltare o riprendere uno studio dopo giorni non richiede nuove richieste.
    private static var cacheDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("lumo-voce", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func cacheURL(_ voice: String, _ text: String) -> URL {
        let digest = SHA256.hash(data: Data((voice + "|" + text).utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return cacheDir.appendingPathComponent(name + ".wav")
    }

    static func pruneCache(maxBytes: Int = 250_000_000) {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: keys) else { return }
        var items: [(URL, Date, Int)] = files.compactMap { u in
            guard let v = try? u.resourceValues(forKeys: Set(keys)) else { return nil }
            return (u, v.contentModificationDate ?? Date.distantPast, v.fileSize ?? 0)
        }
        var total = items.reduce(0) { $0 + $1.2 }
        items.sort { $0.1 < $1.1 }
        for it in items where total > maxBytes {
            try? fm.removeItem(at: it.0)
            total -= it.2
        }
    }

    private static func clean(_ s: String) -> String {
        var t = s
        for ch in ["*", "#", "_", "`", "→", "->", "=>"] {
            t = t.replacingOccurrences(of: ch, with: " ")
        }
        return t
    }

    /// Ritorna un WAV pronto da riprodurre.
    static func audio(text: String, voice: String, model: String, apiKey: String) async throws -> Data {
        let url = cacheURL(voice, text)
        if let cached = try? Data(contentsOf: url), cached.count > 100 { return cached }

        var models: [String] = []
        let first = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !first.isEmpty { models.append(first) }
        for m in fallbackModels where !models.contains(m) { models.append(m) }

        var last: Error = TTSError.empty
        for m in models {
            do {
                let wav = try await request(text: text, voice: voice, model: m, apiKey: apiKey)
                try? wav.write(to: url, options: .atomic)
                return wav
            } catch TTSError.http(let code) where code == 404 || code == 400 {
                last = TTSError.http(code)
                continue
            } catch {
                throw error
            }
        }
        throw last
    }

    private static func request(text: String, voice: String, model: String, apiKey: String) async throws -> Data {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw TTSError.empty
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 45
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        let prompt = "Say in a natural, warm, lively Italian voice, like a good teacher explaining to a student: " + clean(text)
        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": [
                "responseModalities": ["AUDIO"],
                "speechConfig": ["voiceConfig": ["prebuiltVoiceConfig": ["voiceName": voice]]]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw TTSError.empty }
        if http.statusCode == 429 { throw TTSError.rateLimited }
        if http.statusCode != 200 { throw TTSError.http(http.statusCode) }

        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let cands = obj["candidates"] as? [[String: Any]],
              let content = cands.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else { throw TTSError.empty }

        for part in parts {
            let inline = (part["inlineData"] as? [String: Any]) ?? (part["inline_data"] as? [String: Any])
            guard let inline = inline,
                  let b64 = inline["data"] as? String,
                  let pcm = Data(base64Encoded: b64), pcm.count > 200 else { continue }
            let mime = (inline["mimeType"] as? String) ?? (inline["mime_type"] as? String) ?? ""
            var rate = 24000
            if let r = mime.range(of: "rate=") {
                let digits = mime[r.upperBound...].prefix { $0.isNumber }
                if let v = Int(digits) { rate = v }
            }
            return wav(pcm: pcm, rate: rate)
        }
        throw TTSError.empty
    }

    private static func wav(pcm: Data, rate: Int) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + pcm.count))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1)
        u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(pcm.count))
        d.append(pcm)
        return d
    }
}

// MARK: - Riproduzione

@MainActor
final class NaturalVoice: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var cont: CheckedContinuation<Void, Never>?

    static func duration(of wav: Data) -> Double {
        (try? AVAudioPlayer(data: wav))?.duration ?? 0
    }

    /// Riproduce e ritorna quando l'audio è finito (o è stato fermato).
    func play(_ wav: Data, speed: Double) async {
        finish()
        guard let p = try? AVAudioPlayer(data: wav) else { return }
        p.enableRate = true
        p.rate = Float(max(0.5, min(2.0, speed)))
        p.delegate = self
        p.prepareToPlay()
        try? AVAudioSession.sharedInstance().setActive(true)
        player = p
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            self.cont = c
            if !p.play() {
                self.cont = nil
                self.player = nil
                c.resume()
            }
        }
    }

    func pause() { player?.pause() }
    func resume() { player?.play() }

    func stop() {
        player?.stop()
        finish()
    }

    private func finish() {
        player = nil
        let c = cont
        cont = nil
        c?.resume()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if self.player === p { self.finish() }
        }
    }
}
