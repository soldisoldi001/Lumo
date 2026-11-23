import SwiftUI

// MARK: - Provider

enum Provider: String, CaseIterable, Identifiable {
    case gemini, groq, custom
    var id: String { rawValue }

    var label: String {
        switch self {
        case .gemini: return "Google Gemini (gratis)"
        case .groq: return "Groq (gratis)"
        case .custom: return "Altro (compatibile OpenAI)"
        }
    }

    var endpoint: String {
        switch self {
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        case .groq: return "https://api.groq.com/openai/v1/chat/completions"
        case .custom: return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .gemini: return "gemini-3.5-flash-lite"
        case .groq: return "llama-3.3-70b-versatile"
        case .custom: return ""
        }
    }

    var keyURL: URL? {
        switch self {
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")
        case .groq: return URL(string: "https://console.groq.com/keys")
        case .custom: return nil
        }
    }
}

// MARK: - Study mode

enum StudyMode: String, CaseIterable, Identifiable, Codable {
    case lavagna, riassumi, cheat
    var id: String { rawValue }

    var label: String {
        switch self {
        case .lavagna: return "Lavagna"
        case .riassumi: return "Riassumi"
        case .cheat: return "Cheat sheet"
        }
    }

    var icon: String {
        switch self {
        case .lavagna: return "pencil.and.outline"
        case .riassumi: return "doc.text"
        case .cheat: return "list.bullet.rectangle"
        }
    }
}

// MARK: - Settings

final class AppSettings: ObservableObject {
    private let d = UserDefaults.standard

    @Published var provider: Provider { didSet { d.set(provider.rawValue, forKey: "provider") } }
    @Published var apiKey: String { didSet { d.set(apiKey, forKey: "apiKey") } }
    @Published var model: String { didSet { d.set(model, forKey: "model") } }
    @Published var customURL: String { didSet { d.set(customURL, forKey: "customURL") } }
    @Published var voiceID: String { didSet { d.set(voiceID, forKey: "voiceID") } }
    @Published var speechRate: Double { didSet { d.set(speechRate, forKey: "rate") } }
    @Published var voiceOn: Bool { didSet { d.set(voiceOn, forKey: "voiceOn") } }
    @Published var level: String { didSet { d.set(level, forKey: "level") } }
    @Published var streak: Int { didSet { d.set(streak, forKey: "streak") } }
    @Published var naturalVoice: Bool { didSet { d.set(naturalVoice, forKey: "naturalVoice") } }
    @Published var geminiVoice: String { didSet { d.set(geminiVoice, forKey: "geminiVoice") } }
    @Published var ttsModel: String { didSet { d.set(ttsModel, forKey: "ttsModel") } }
    @Published var playSpeed: Double { didSet { d.set(playSpeed, forKey: "playSpeed") } }

    static let levels = ["Medie", "Superiori", "Università"]

    init() {
        provider = Provider(rawValue: d.string(forKey: "provider") ?? "") ?? .gemini
        apiKey = d.string(forKey: "apiKey") ?? ""
        var savedModel = d.string(forKey: "model") ?? Provider.gemini.defaultModel
        // i modelli 2.5 non sono più disponibili ai nuovi utenti: passo al modello consigliato
        if savedModel.lowercased().hasPrefix("gemini-2.") {
            savedModel = Provider.gemini.defaultModel
            d.set(savedModel, forKey: "model")
        }
        model = savedModel
        customURL = d.string(forKey: "customURL") ?? ""
        voiceID = d.string(forKey: "voiceID") ?? ""
        speechRate = d.object(forKey: "rate") as? Double ?? 0.5
        voiceOn = d.object(forKey: "voiceOn") as? Bool ?? true
        level = d.string(forKey: "level") ?? "Università"
        streak = d.integer(forKey: "streak")
        naturalVoice = d.object(forKey: "naturalVoice") as? Bool ?? true
        geminiVoice = d.string(forKey: "geminiVoice") ?? "Kore"
        ttsModel = d.string(forKey: "ttsModel") ?? "gemini-3.1-flash-tts-preview"
        playSpeed = d.object(forKey: "playSpeed") as? Double ?? 1.1
    }

    var endpoint: String {
        provider == .custom ? customURL.trimmed : provider.endpoint
    }

    /// Chiave ripulita da spazi, a capo, virgolette e dal prefisso "Bearer".
    var cleanKey: String {
        var k = apiKey.trimmed
        for junk in ["\"", "'", "\u{201C}", "\u{201D}"] {
            k = k.replacingOccurrences(of: junk, with: "")
        }
        if k.lowercased().hasPrefix("bearer ") { k = String(k.dropFirst(7)) }
        return k.filter { !$0.isWhitespace }
    }

    var effectiveModel: String {
        let m = model.trimmed
        return m.isEmpty ? provider.defaultModel : m
    }

    func registerStudy() {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        let today = f.string(from: Date())
        let last = d.string(forKey: "lastDay") ?? ""
        if last == today { return }
        let yesterdayDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let yesterday = f.string(from: yesterdayDate)
        streak = (last == yesterday) ? streak + 1 : 1
        d.set(today, forKey: "lastDay")
    }
}

// MARK: - Whiteboard blocks

enum BlockKind: String {
    case title, box, flow, merge, table, icon, list, arrow, formula, note, tip, question
}

struct BoardBlock: Identifiable, Codable {
    var id = UUID()
    var kind: BlockKind
    var text: String
    var items: [String] = []
    var sub: String = ""
    var subs: [String] = []
    var say: String = ""
    var color: String = "violet"
    var dur: Double = 0   // secondi di voce: la scrittura a mano segue il ritmo della voce

    var displayLength: Int {
        text.count + sub.count
            + items.reduce(0) { $0 + $1.count }
            + subs.reduce(0) { $0 + $1.count }
    }

    static func parse(_ json: String) -> BoardBlock? {
        guard let data = json.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let t = ((o["t"] as? String) ?? (o["type"] as? String) ?? "box").lowercased()
        let kind = BlockKind(rawValue: t) ?? .box
        let text = ((o["text"] as? String) ?? "").trimmed
        let items = ((o["items"] as? [Any]) ?? []).compactMap { $0 as? String }
        let subs = ((o["subs"] as? [Any]) ?? []).compactMap { $0 as? String }
        let sub = ((o["sub"] as? String) ?? "").trimmed
        let say = ((o["say"] as? String) ?? "").trimmed
        let color = ((o["color"] as? String) ?? "violet").lowercased()
        if text.isEmpty && items.isEmpty { return nil }
        return BoardBlock(kind: kind, text: text, items: items, sub: sub, subs: subs, say: say, color: color)
    }
}
