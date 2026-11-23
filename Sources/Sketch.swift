import SwiftUI

// MARK: - Disegno statico (PDF e sessioni riaperte: niente animazioni di scrittura)

struct StaticDrawKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var staticDraw: Bool {
        get { self[StaticDrawKey.self] }
        set { self[StaticDrawKey.self] = newValue }
    }
}

// MARK: - Numeri casuali ripetibili (così ogni disegno ha sempre lo stesso tratto)

struct SeededRNG: RandomNumberGenerator {
    var state: UInt64

    init(seed: Int) {
        state = UInt64(truncatingIfNeeded: seed) &+ 0x9E3779B97F4A7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - Forme disegnate a mano

struct RoughRect: Shape {
    var seed: Int = 1

    func path(in r: CGRect) -> Path {
        var g = SeededRNG(seed: seed)
        func j(_ m: CGFloat) -> CGFloat { CGFloat.random(in: -m...m, using: &g) }
        let rad = min(14, min(r.width, r.height) / 3)
        let x0 = r.minX + 1, x1 = r.maxX - 1, y0 = r.minY + 1, y1 = r.maxY - 1
        var p = Path()
        p.move(to: CGPoint(x: x0 + rad - 3, y: y0 + j(1.5)))
        p.addLine(to: CGPoint(x: x1 - rad, y: y0 + j(1.5)))
        p.addQuadCurve(to: CGPoint(x: x1 + j(1.5), y: y0 + rad),
                       control: CGPoint(x: x1 + j(1), y: y0 + j(1)))
        p.addLine(to: CGPoint(x: x1 + j(1.5), y: y1 - rad))
        p.addQuadCurve(to: CGPoint(x: x1 - rad, y: y1 + j(1.5)),
                       control: CGPoint(x: x1 + j(1), y: y1 + j(1)))
        p.addLine(to: CGPoint(x: x0 + rad, y: y1 + j(1.5)))
        p.addQuadCurve(to: CGPoint(x: x0 + j(1.5), y: y1 - rad),
                       control: CGPoint(x: x0 + j(1), y: y1 + j(1)))
        p.addLine(to: CGPoint(x: x0 + j(1.5), y: y0 + rad))
        p.addQuadCurve(to: CGPoint(x: x0 + rad + 3, y: y0 + j(1.5)),
                       control: CGPoint(x: x0 + j(1), y: y0 + j(1)))
        return p
    }
}

struct RoughEllipse: Shape {
    var seed: Int = 1

    func path(in r: CGRect) -> Path {
        var g = SeededRNG(seed: seed)
        let ph = Double.random(in: 0...6, using: &g)
        let cx = r.midX, cy = r.midY
        let rx = r.width / 2 - 1, ry = r.height / 2 - 1
        var p = Path()
        let steps = 72
        for i in 0...steps {
            let t = Double(i) / Double(steps) * 2 * Double.pi * 1.04 + 0.4
            let wob = 1 + 0.02 * sin(3 * t + ph)
            let pt = CGPoint(x: cx + CGFloat(cos(t) * wob) * rx,
                             y: cy + CGFloat(sin(t) * wob) * ry)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}

struct ArrowShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY + 1))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.move(to: CGPoint(x: r.maxX - 7, y: r.midY - 6))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX - 7, y: r.midY + 6))
        return p
    }
}

struct MergeCurves: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.width * 0.25, y: 0))
        p.addQuadCurve(to: CGPoint(x: r.width * 0.45, y: r.height),
                       control: CGPoint(x: r.width * 0.27, y: r.height * 0.85))
        p.move(to: CGPoint(x: r.width * 0.75, y: 0))
        p.addQuadCurve(to: CGPoint(x: r.width * 0.55, y: r.height),
                       control: CGPoint(x: r.width * 0.73, y: r.height * 0.85))
        return p
    }
}

// MARK: - Testo che si "scrive" da sinistra a destra

struct WriteOn<Content: View>: View {
    var duration: Double
    let content: Content
    @State private var p: CGFloat = 0
    @Environment(\.staticDraw) private var staticDraw

    init(duration: Double, @ViewBuilder content: () -> Content) {
        self.duration = duration
        self.content = content()
    }

    var body: some View {
        content
            .mask(
                GeometryReader { geo in
                    Rectangle()
                        .frame(width: max(1, geo.size.width * (staticDraw ? 1 : p)), height: geo.size.height)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                }
            )
            .onAppear {
                withAnimation(.easeInOut(duration: duration)) { p = 1 }
            }
    }
}

private let inkStroke = StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)

// MARK: - Elementi della lavagna

struct SketchBox: View {
    var text: String
    var sub: String = ""
    var tint: Color
    var seed: Int
    var size: CGFloat = 22
    var fill: Bool = false
    var expand: Bool = false
    var time: Double = 0.9
    @State private var d: CGFloat = 0
    @Environment(\.staticDraw) private var staticDraw

    var body: some View {
        VStack(spacing: 2) {
            WriteOn(duration: time) {
                Text(text)
                    .font(Theme.hand(size))
                    .foregroundColor(Theme.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            if !sub.isEmpty {
                WriteOn(duration: time) {
                    Text(sub)
                        .font(Theme.hand(size * 0.7))
                        .foregroundColor(tint)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: expand ? CGFloat.infinity : nil)
        .background(
            ZStack {
                if fill {
                    RoughRect(seed: seed).fill(tint.opacity(0.2))
                }
                RoughRect(seed: seed)
                    .trim(from: 0, to: staticDraw ? 1 : d)
                    .stroke(Theme.ink, style: inkStroke)
            }
        )
        .onAppear {
            withAnimation(.easeOut(duration: 0.55)) { d = 1 }
        }
    }
}

struct SketchArrow: View {
    var vertical = false
    @State private var d: CGFloat = 0
    @Environment(\.staticDraw) private var staticDraw

    var body: some View {
        Group {
            if vertical {
                ArrowShape()
                    .trim(from: 0, to: staticDraw ? 1 : d)
                    .stroke(Theme.ink, style: inkStroke)
                    .frame(width: 34, height: 20)
                    .rotationEffect(.degrees(90))
                    .frame(width: 20, height: 34)
            } else {
                ArrowShape()
                    .trim(from: 0, to: staticDraw ? 1 : d)
                    .stroke(Theme.ink, style: inkStroke)
                    .frame(width: 22, height: 16)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) { d = 1 }
        }
    }
}

struct SketchEllipse: View {
    var text: String
    var tint: Color
    var seed: Int
    @State private var d: CGFloat = 0
    @Environment(\.staticDraw) private var staticDraw

    var body: some View {
        WriteOn(duration: 0.9) {
            Text(text)
                .font(Theme.hand(26))
                .foregroundColor(Theme.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 20)
        .background(
            ZStack {
                RoughEllipse(seed: seed).fill(tint.opacity(0.75))
                RoughEllipse(seed: seed)
                    .trim(from: 0, to: staticDraw ? 1 : d)
                    .stroke(Theme.ink, style: inkStroke)
            }
        )
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { d = 1 }
        }
    }
}

struct SketchMerge: View {
    let block: BoardBlock
    let tint: Color
    let seed: Int
    @State private var d: CGFloat = 0
    @Environment(\.staticDraw) private var staticDraw

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                SketchBox(text: block.items[0],
                          sub: block.subs.first ?? "",
                          tint: tint, seed: seed, size: 20, expand: true)
                SketchBox(text: block.items[1],
                          sub: block.subs.count > 1 ? block.subs[1] : "",
                          tint: tint, seed: seed + 7, size: 20, expand: true)
            }
            MergeCurves()
                .trim(from: 0, to: staticDraw ? 1 : d)
                .stroke(Theme.ink, style: inkStroke)
                .frame(height: 42)
            if !block.text.isEmpty {
                SketchEllipse(text: block.text, tint: tint, seed: seed + 3)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7).delay(0.5)) { d = 1 }
        }
    }
}

struct SketchTable: View {
    let rows: [[String]]
    let tint: Color
    let seed: Int
    @State private var d: CGFloat = 0
    @Environment(\.staticDraw) private var staticDraw

    init(items: [String], tint: Color, seed: Int) {
        self.rows = items.map { line in
            line.split(separator: "|", omittingEmptySubsequences: false)
                .map { String($0).trimmed }
        }
        self.tint = tint
        self.seed = seed
    }

    var body: some View {
        let cols = max(1, rows.map { $0.count }.max() ?? 1)
        WriteOn(duration: 1.2) {
            VStack(spacing: 0) {
                ForEach(0..<rows.count, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<cols, id: \.self) { c in
                            if c > 0 { Rectangle().fill(Theme.ink).frame(width: 2) }
                            Text(c < rows[r].count ? rows[r][c] : "")
                                .font(Theme.hand(18))
                                .foregroundColor(Theme.ink)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .padding(.horizontal, 6)
                                .background(r == 0 ? tint.opacity(0.2) : Color.clear)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    if r < rows.count - 1 {
                        Rectangle().fill(Theme.ink).frame(height: 2)
                    }
                }
            }
        }
        .overlay(
            RoughRect(seed: seed)
                .trim(from: 0, to: staticDraw ? 1 : d)
                .stroke(Theme.ink, style: inkStroke)
        )
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) { d = 1 }
        }
    }
}

struct IconPop: View {
    var symbol: String
    var color: Color
    var delay: Double
    @State private var on = false
    @Environment(\.staticDraw) private var staticDraw

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 54, weight: .semibold))
            .foregroundColor(color)
            .scaleEffect(on || staticDraw ? 1 : 0.2)
            .opacity(on || staticDraw ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(delay)) { on = true }
            }
    }
}
