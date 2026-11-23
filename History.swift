import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    var onOpen: (UUID) -> Void

    @State private var renamingID: UUID?
    @State private var newName = ""
    @State private var shareItem: ShareItem?

    var body: some View {
        NavigationStack {
            Group {
                if store.sessions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text("Le tue sessioni di studio appariranno qui.")
                            .foregroundColor(.secondary)
                    }
                } else {
                    List {
                        ForEach(store.sessions) { s in
                            Button {
                                dismiss()
                                onOpen(s.id)
                            } label: {
                                row(s)
                            }
                            .swipeActions {
                                Button(role: .destructive) { store.delete(s.id) } label: {
                                    Label("Elimina", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button {
                                    newName = s.title
                                    renamingID = s.id
                                } label: { Label("Rinomina", systemImage: "pencil") }
                                Button {
                                    if let url = PDFExporter.makePDF(title: s.title, blocks: s.blocks) {
                                        shareItem = ShareItem(url: url)
                                    }
                                } label: { Label("Esporta PDF", systemImage: "square.and.arrow.up") }
                                Button(role: .destructive) { store.delete(s.id) } label: {
                                    Label("Elimina", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Cronologia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
        .alert("Rinomina sessione", isPresented: Binding(
            get: { renamingID != nil },
            set: { if !$0 { renamingID = nil } }
        )) {
            TextField("Titolo", text: $newName)
            Button("Salva") {
                if let id = renamingID { store.rename(id, to: newName) }
                renamingID = nil
            }
            Button("Annulla", role: .cancel) { renamingID = nil }
        }
        .sheet(item: $shareItem) { ShareSheet(url: $0.url) }
    }

    private func row(_ s: StudySession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: s.mode.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Theme.violet)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Theme.violet.opacity(0.18)))
            VStack(alignment: .leading, spacing: 3) {
                Text(s.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                Text(s.updated.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            Spacer()
            if s.interrupted {
                Text("In pausa")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.ink)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.amber))
            }
        }
        .padding(.vertical, 4)
    }
}
