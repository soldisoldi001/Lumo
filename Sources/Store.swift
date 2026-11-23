import SwiftUI

// MARK: - Sessione di studio salvata

struct StudySession: Identifiable, Codable {
    var id = UUID()
    var title: String
    var created: Date
    var updated: Date
    var mode: StudyMode
    var blocks: [BoardBlock]
    var pending: [BoardBlock]      // blocchi già generati ma non ancora mostrati
    var history: [ChatMessage]
    var interrupted: Bool          // c'è ancora qualcosa da riprendere
    var needsContinuation: Bool    // la spiegazione era stata interrotta a metà
    var lastQuestion: String
    var replay: BoardBlock?        // blocco che si stava spiegando quando ti sei fermato
}

// MARK: - Archivio su disco (resta anche dopo giorni)

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [StudySession] = []
    private let url: URL
    private var saveTask: Task<Void, Never>?

    init() {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        url = base.appendingPathComponent("lumo-sessioni.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let list = try? dec.decode([StudySession].self, from: data) {
            sessions = list.sorted { $0.updated > $1.updated }
        }
    }

    func upsert(_ s: StudySession, immediately: Bool = false) {
        if let i = sessions.firstIndex(where: { $0.id == s.id }) {
            sessions[i] = s
        } else {
            sessions.append(s)
        }
        sessions.sort { $0.updated > $1.updated }
        if immediately { flush() } else { scheduleSave() }
    }

    func delete(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        flush()
    }

    func rename(_ id: UUID, to title: String) {
        let t = title.trimmed
        guard !t.isEmpty, let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[i].title = t
        flush()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            if Task.isCancelled { return }
            self?.flush()
        }
    }

    func flush() {
        saveTask?.cancel()
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(sessions) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
