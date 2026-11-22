import SwiftUI

struct BoardView: View {
    @EnvironmentObject var session: BoardSession
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""

    private let followUps: [(String, String)] = [
        ("Più semplice", "Non l'ho capito bene: rispiegamelo in modo più semplice, con un'analogia quotidiana, continuando lo schema."),
        ("Fammi un esempio", "Fammi un esempio pratico, passo passo, collegandolo allo schema."),
        ("Approfondisci", "Approfondisci l'ultimo punto aggiungendo dettagli allo schema."),
        ("Ripasso veloce", "Fammi un riepilogo velocissimo dello schema con i 5 punti da ricordare.")
    ]

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            DotGrid().ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                scroller
                captionBar
                if case .error(let msg) = session.status {
                    Text(msg)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.flame))
                        .padding(.horizontal, 14)
                        .padding(.bottom, 6)
                }
                if session.status == .idle && !session.blocks.isEmpty {
                    chips
                }
                InputBar(text: $input,
                         placeholder: session.blocks.isEmpty ? "Chiedi a Lumo\u{2026}" : "Fai un'altra domanda\u{2026}") { send() }
                    .background(Theme.paper.opacity(0.01))
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            CircleButton(icon: "xmark") {
                session.stopAll()
                dismiss()
            }
            Spacer()
            CircleButton(icon: "plus") { session.reset() }
            CircleButton(icon: session.paused ? "play.fill" : "pause.fill") { session.togglePause() }
            CircleButton(icon: settings.voiceOn ? "speaker.wave.2.fill" : "speaker.slash.fill") {
                settings.voiceOn.toggle()
                if !settings.voiceOn { session.speech.stop() }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var scroller: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    if session.blocks.isEmpty && session.status == .idle {
                        Text("Chiedimi qualcosa e lo spiego sulla lavagna.")
                            .font(Theme.hand(28, bold: true))
                            .foregroundColor(Theme.ink.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .padding(.top, 120)
                    }
                    ForEach(session.blocks) { b in
                        BlockView(block: b).id(b.id)
                    }
                    if session.status == .thinking { ThinkingDots() }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: session.blocks.count) { _ in
                withAnimation(.easeOut(duration: 0.45)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private var captionBar: some View {
        if session.status == .explaining && !session.caption.isEmpty {
            Text(session.caption)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.78)))
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(followUps, id: \.0) { item in
                    Button {
                        session.ask(item.1, settings: settings)
                    } label: {
                        Text(item.0)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(Theme.violet.opacity(0.18)))
                            .overlay(Capsule().stroke(Theme.violet, lineWidth: 1.5))
                    }
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.bottom, 8)
    }

    private func send() {
        let q = input.trimmed
        guard !q.isEmpty else { return }
        input = ""
        session.ask(q, settings: settings)
    }
}

// MARK: - Blocchi della lavagna (scritti e disegnati a mano)

struct BlockView: View {
    let block: BoardBlock

    private var tint: Color { Theme.color(block.color) }
    private var seed: Int { Int(UInt(bitPattern: block.id.hashValue) % 9973) + 1 }
    private var writeTime: Double {
        min(2.4, max(0.6, 0.35 + Double(block.displayLength) * 0.035))
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch block.kind {
        case .title: titleView
        case .box:
            SketchBox(text: block.text, sub: block.sub, tint: tint, seed: seed,
                      size: 24, fill: true)
                .frame(maxWidth: 330)
        case .flow: flowView
        case .merge:
            if block.items.count >= 2 {
                SketchMerge(block: block, tint: tint, seed: seed)
            } else {
                SketchBox(text: block.text.isEmpty ? (block.items.first ?? "") : block.text,
                          tint: tint, seed: seed, size: 24, fill: true)
                    .frame(maxWidth: 330)
            }
        case .table: SketchTable(items: block.items, tint: tint, seed: seed)
        case .icon: iconView
        case .list: listView
        case .arrow: arrowView
        case .formula:
            SketchBox(text: block.text, tint: tint, seed: seed, size: 24, fill: true)
                .frame(maxWidth: 340)
        case .note: noteView
        case .tip: tipView
        case .question: questionView
        }
    }

    private var titleView: some View {
        VStack(alignment: .leading, spacing: 4) {
            WriteOn(duration: writeTime) {
                Text(block.text)
                    .font(Theme.hand(38))
                    .foregroundColor(Theme.ink)
                    .multilineTextAlignment(.leading)
            }
            ScribbleUnderline(color: tint)
                .padding(.trailing, 60)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var flowView: some View {
        let items = block.items
        let maxLen = items.map { $0.count }.max() ?? 0
        let per = (items.count <= 3) ? 3 : (maxLen > 9 ? 3 : 4)
        let rows: [[String]] = stride(from: 0, to: items.count, by: per).map {
            Array(items[$0..<min($0 + per, items.count)])
        }
        return VStack(spacing: 10) {
            ForEach(0..<rows.count, id: \.self) { r in
                HStack(spacing: 4) {
                    ForEach(0..<rows[r].count, id: \.self) { i in
                        SketchBox(text: rows[r][i], tint: tint, seed: seed + r * 10 + i,
                                  size: 16, expand: true)
                        if i < rows[r].count - 1 { SketchArrow() }
                    }
                }
            }
        }
    }

    private var iconView: some View {
        let palette: [Color] = [Theme.blue, Theme.pink, Theme.green, Theme.amber, Theme.violet]
        return VStack(spacing: 6) {
            HStack(spacing: 26) {
                ForEach(0..<block.items.count, id: \.self) { i in
                    IconPop(symbol: Theme.symbol(block.items[i]),
                            color: palette[(i + seed) % palette.count],
                            delay: Double(i) * 0.25)
                }
            }
            if !block.text.isEmpty {
                WriteOn(duration: 0.8) {
                    Text(block.text)
                        .font(Theme.hand(20))
                        .foregroundColor(Theme.ink.opacity(0.85))
                }
            }
        }
    }

    private var listView: some View {
        WriteOn(duration: writeTime) {
            VStack(alignment: .leading, spacing: 6) {
                if !block.text.isEmpty {
                    Text(block.text)
                        .font(Theme.hand(24))
                        .foregroundColor(Theme.ink)
                }
                ForEach(0..<block.items.count, id: \.self) { i in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(tint).frame(width: 9, height: 9).padding(.top, 10)
                        Text(block.items[i])
                            .font(Theme.hand(22))
                            .foregroundColor(Theme.ink)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var arrowView: some View {
        HStack(spacing: 8) {
            SketchArrow(vertical: true)
            if !block.text.isEmpty {
                WriteOn(duration: 0.7) {
                    Text(block.text)
                        .font(Theme.hand(20))
                        .foregroundColor(Theme.ink.opacity(0.8))
                }
            }
        }
    }

    private var noteView: some View {
        WriteOn(duration: writeTime) {
            Text(block.text)
                .font(Theme.hand(26))
                .foregroundColor(tint)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var tipView: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .foregroundColor(Theme.amber)
                .font(.system(size: 22))
            WriteOn(duration: writeTime) {
                Text(block.text)
                    .font(Theme.hand(22))
                    .foregroundColor(Theme.ink)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.amber.opacity(0.24)))
        .rotationEffect(.degrees(-1))
    }

    private var questionView: some View {
        HStack {
            Spacer(minLength: 40)
            Text(block.text)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(6)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.ink))
        }
        .padding(.top, 10)
    }
}
