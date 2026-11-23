import SwiftUI

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// Versione "da stampare" di un blocco: niente animazioni, su fondo bianco.
struct PrintBlock: View {
    let block: BoardBlock
    var body: some View {
        Group {
            if block.kind == .question {
                Text("Domanda: " + block.text)
                    .font(.system(size: 12, weight: .semibold))
                    .italic()
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                BlockView(block: block)
            }
        }
        .environment(\.staticDraw, true)
    }
}

struct PrintHeader: View {
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.hand(30))
                .foregroundColor(Theme.ink)
            Text("Lumo · " + Date().formatted(date: .long, time: .omitted))
                .font(.system(size: 11))
                .foregroundColor(.gray)
            Rectangle().fill(Theme.ink.opacity(0.4)).frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum PDFExporter {
    /// Crea un PDF A4 con lo schema, pronto da condividere o stampare.
    @MainActor
    static func makePDF(title: String, blocks: [BoardBlock]) -> URL? {
        let pageW: CGFloat = 595, pageH: CGFloat = 842, margin: CGFloat = 40
        let contentW = pageW - 2 * margin
        let layoutW: CGFloat = 390                 // larghezza "da telefono"
        let k = contentW / layoutW                 // ingrandimento per la pagina

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var box = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }

        var y = margin
        var pageOpen = false

        func place<V: View>(_ v: V, gap: CGFloat) {
            let r = ImageRenderer(content: v.frame(width: layoutW, alignment: .leading).background(Color.white))
            r.proposedSize = ProposedViewSize(width: layoutW, height: nil)
            r.render { size, draw in
                let h = size.height * k
                if !pageOpen || y + h > pageH - margin {
                    if pageOpen { ctx.endPDFPage() }
                    ctx.beginPDFPage(nil)
                    pageOpen = true
                    y = margin
                }
                ctx.saveGState()
                ctx.translateBy(x: margin, y: pageH - y - h)
                ctx.scaleBy(x: k, y: k)
                draw(ctx)
                ctx.restoreGState()
                y += h + gap
            }
        }

        let shown = title.trimmed.isEmpty ? "Schema di studio" : title
        place(PrintHeader(title: shown), gap: 16)
        for b in blocks { place(PrintBlock(block: b), gap: 12) }

        if pageOpen { ctx.endPDFPage() }
        ctx.closePDF()

        let safe = shown.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined(separator: " ")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Lumo - " + String(safe.prefix(50)) + ".pdf")
        do {
            try (data as Data).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
