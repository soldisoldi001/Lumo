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
                InputBar(text: $input) { send() }
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
                VStack(spacing: 12) {
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

// MARK: - Blocchi della lavagna

struct BlockView: View {
    let block: BoardBlock
    @State private var shown = false

    private var tint: Color { Theme.color(block.color) }

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 16)
            .scaleEffect(shown ? 1 : 0.96)
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { shown = true }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch block.kind {
        case .title: titleView
        case .box: boxView
        case .list: listView
        case .arrow: arrowView
        case .formula: formulaView
        case .note: noteView
        case .question: questionView
        }
    }

    private var titleView: some View {
        VStack(spacing: 4) {
            Text(block.text)
                .font(Theme.hand(30, bold: true))
                .foregroundColor(Theme.ink)
                .multilineTextAlignment(.center)
            ScribbleUnderline(color: tint)
                .padding(.horizontal, 44)
        }
        .padding(.top, 8)
    }

    private var boxView: some View {
        Text(block.text)
            .font(Theme.hand(23, bold: true))
            .foregroundColor(Theme.ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 18).fill(tint.opacity(0.16)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(tint, lineWidth: 3))
    }

    private var listView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !block.text.isEmpty {
                Text(block.text)
                    .font(Theme.hand(21, bold: true))
                    .foregroundColor(Theme.ink)
            }
            ForEach(Array(block.items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(tint).frame(width: 9, height: 9).padding(.top, 9)
                    Text(item)
                        .font(Theme.hand(20))
                        .foregroundColor(Theme.ink)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.75)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(tint.opacity(0.55), lineWidth: 2))
    }

    private var arrowView: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down")
                .font(.system(size: 26, weight: .heavy))
                .foregroundColor(tint)
            if !block.text.isEmpty {
                Text(block.text)
                    .font(Theme.hand(18))
                    .foregroundColor(Theme.ink.opacity(0.8))
            }
        }
        .padding(.vertical, 2)
    }

    private var formulaView: some View {
        Text(block.text)
            .font(.system(size: 21, weight: .semibold, design: .monospaced))
            .foregroundColor(Theme.ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.8)))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            )
    }

    private var noteView: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .foregroundColor(Theme.amber)
                .font(.system(size: 20))
            Text(block.text)
                .font(Theme.hand(19, bold: true))
                .foregroundColor(Theme.ink)
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
