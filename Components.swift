import SwiftUI

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

enum Theme {
    static let bg = Color(red: 0.04, green: 0.05, blue: 0.10)
    static let card = Color(red: 0.13, green: 0.14, blue: 0.19)
    static let paper = Color(red: 0.96, green: 0.95, blue: 1.0)
    static let ink = Color(red: 0.12, green: 0.10, blue: 0.25)
    static let violet = Color(red: 0.50, green: 0.40, blue: 0.88)
    static let amber = Color(red: 0.96, green: 0.68, blue: 0.16)
    static let green = Color(red: 0.16, green: 0.64, blue: 0.42)
    static let blue = Color(red: 0.22, green: 0.47, blue: 0.92)
    static let pink = Color(red: 0.86, green: 0.31, blue: 0.60)
    static let flame = Color(red: 0.93, green: 0.51, blue: 0.38)

    static func color(_ name: String) -> Color {
        switch name {
        case "amber": return amber
        case "green": return green
        case "blue": return blue
        case "pink": return pink
        default: return violet
        }
    }

    static func hand(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom("BradleyHandITCTT-Bold", size: size)
    }

    static func symbol(_ name: String) -> String {
        let map: [String: String] = [
            "eye": "eye", "ear": "ear", "brain": "brain.head.profile", "heart": "heart.fill",
            "lightbulb": "lightbulb.fill", "book": "book.fill", "globe": "globe.europe.africa.fill",
            "atom": "atom", "leaf": "leaf.fill", "bolt": "bolt.fill", "flame": "flame.fill",
            "drop": "drop.fill", "clock": "clock.fill", "calculator": "function",
            "chart": "chart.bar.fill", "search": "magnifyingglass", "gear": "gearshape.fill",
            "person": "person.fill", "people": "person.2.fill", "building": "building.columns.fill",
            "medical": "cross.case.fill", "pill": "pills.fill", "tool": "hammer.fill",
            "phone": "phone.fill", "mail": "envelope.fill", "lock": "lock.fill", "key": "key.fill",
            "cloud": "cloud.fill", "star": "star.fill", "flag": "flag.fill", "map": "map.fill",
            "camera": "camera.fill", "music": "music.note", "money": "eurosign.circle.fill",
            "scale": "scalemass.fill", "rocket": "paperplane.fill", "shield": "shield.fill",
            "puzzle": "puzzlepiece.fill"
        ]
        return map[name.lowercased().trimmed] ?? "sparkles"
    }
}

// MARK: - Original mascot "Lumo"

struct MascotView: View {
    var size: CGFloat = 120
    @State private var breathe = false

    var body: some View {
        ZStack {
            Capsule().fill(Theme.green)
                .frame(width: size * 0.13, height: size * 0.30)
                .rotationEffect(.degrees(-22))
                .offset(x: -size * 0.06, y: -size * 0.56)
            Capsule().fill(Theme.green.opacity(0.85))
                .frame(width: size * 0.13, height: size * 0.24)
                .rotationEffect(.degrees(26))
                .offset(x: size * 0.07, y: -size * 0.54)
            Ellipse().fill(Theme.amber)
                .frame(width: size, height: size * 0.92)
            HStack(spacing: size * 0.15) {
                MascotEye(d: size * 0.22)
                MascotEye(d: size * 0.22)
            }
            .offset(y: -size * 0.05)
            Capsule().fill(Color.black.opacity(0.75))
                .frame(width: size * 0.17, height: size * 0.05)
                .offset(y: size * 0.20)
        }
        .frame(width: size, height: size * 1.2)
        .scaleEffect(breathe ? 1.04 : 0.98, anchor: .bottom)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }
}

struct MascotEye: View {
    var d: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(Color.white).frame(width: d, height: d)
            Circle().fill(Color.black).frame(width: d * 0.5, height: d * 0.5)
                .offset(x: d * 0.08, y: d * 0.04)
        }
    }
}

// MARK: - Whiteboard helpers

struct DotGrid: View {
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 28
            var y: CGFloat = 14
            while y < size.height {
                var x: CGFloat = 14
                while x < size.width {
                    let rect = CGRect(x: x, y: y, width: 2.5, height: 2.5)
                    ctx.fill(Path(ellipseIn: rect), with: .color(Color.black.opacity(0.11)))
                    x += step
                }
                y += step
            }
        }
    }
}

struct Wave: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: r.midY))
        let n = 6
        for i in 0..<n {
            let cx = r.width * (CGFloat(i) + 0.5) / CGFloat(n)
            let ex = r.width * CGFloat(i + 1) / CGFloat(n)
            p.addQuadCurve(to: CGPoint(x: ex, y: r.midY),
                           control: CGPoint(x: cx, y: i % 2 == 0 ? r.minY : r.maxY))
        }
        return p
    }
}

struct ScribbleUnderline: View {
    var color: Color
    @State private var drawn: CGFloat = 0
    @Environment(\.staticDraw) private var staticDraw
    var body: some View {
        Wave()
            .trim(from: 0, to: staticDraw ? 1 : drawn)
            .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            .frame(height: 10)
            .onAppear {
                withAnimation(.easeOut(duration: 0.8)) { drawn = 1 }
            }
    }
}

struct ThinkingDots: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(Theme.violet)
                    .frame(width: 9, height: 9)
                    .opacity(phase % 3 == i ? 1 : 0.3)
            }
        }
        .padding(.vertical, 12)
        .onReceive(timer) { _ in phase += 1 }
    }
}

struct CircleButton: View {
    let icon: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.ink))
        }
    }
}
