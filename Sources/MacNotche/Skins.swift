import SwiftUI

// MARK: - Skins: Angedockt (Island), schwebende Tiere (Katze, Dackel), Tropfend

enum Skin: String, CaseIterable, Identifiable {
    case angedockt = "Angedockt", katze = "Katze", dackel = "Hund", tropfend = "Tropfend"
    var id: String { rawValue }
    static var gewaehlt: Skin { Skin(rawValue: UserDefaults.standard.string(forKey: E.skin) ?? "") ?? .angedockt }
    /// Schwebt mit Abstand zur Bildschirmkante (Kopf links, Schwanz rechts).
    var schwebend: Bool { self == .katze || self == .dackel }
    /// Zusätzlicher Platz ums Fenster für Ohren, Schwanz, Beine, Tropfen.
    var rand: (oben: CGFloat, unten: CGFloat, rechts: CGFloat) {
        switch self {
        case .angedockt: (0, 0, 0)
        case .katze: (12, 4, 34)
        case .dackel: (12, 8, 30)
        case .tropfend: (0, 30, 0)
        }
    }
}

/// Blickrichtung der Pupillen: Maus relativ zur Bildschirmmitte oben, auf ±1 begrenzt.
private func blick() -> CGPoint {
    guard let s = NSScreen.screens.first else { return .zero }
    let m = NSEvent.mouseLocation
    let dx = (m.x - s.frame.midX) / (s.frame.width / 2)
    let dy = (s.frame.maxY - m.y) / s.frame.height * 2 - 0.3
    return CGPoint(x: max(-1, min(1, dx)), y: max(-1, min(1, dy)))
}

/// Tier-Overlay um den schwebenden Körper: Kopf links (ragt oben hinaus), Schwanz rechts, Dackel mit Beinen.
struct Tier: View {
    let art: Skin
    let fuellung: AnyShapeStyle
    let hoehe: CGFloat  // Höhe der Leiste = Körperhöhe im zugeklappten Zustand

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1 / 20)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            // Katze blinzelt kurz; der Hund döst und macht alle 5 Sekunden die Augen auf.
            let blinzelt = art == .katze ? t.truncatingRemainder(dividingBy: 4.3) > 4.12 : t.truncatingRemainder(dividingBy: 5) > 1.2
            let wedel = sin(t * 3.2) * (art == .katze ? 10 : 8)
            let fell = Color(red: 0.90, green: 0.76, blue: 0.58)  // helles Fell an Pfoten, Brauen und Rute
            let b = blick()
            GeometryReader { g in
                let kopf = hoehe + 10
                ZStack(alignment: .topLeading) {
                    // Kopf
                    ZStack {
                        if art == .katze {
                            Ohr().fill(fuellung).frame(width: 13, height: 13).offset(x: -kopf * 0.3, y: -kopf * 0.5 - 2)
                            Ohr().fill(fuellung).frame(width: 13, height: 13).offset(x: kopf * 0.3, y: -kopf * 0.5 - 2)
                        } else {
                            // Liegender Hund: kleine Ohren, helle Schnauze unten, Pfoten unter dem Kopf
                            Ohr().fill(fuellung).frame(width: 10, height: 9).offset(x: -kopf * 0.32, y: -kopf * 0.5)
                            Ohr().fill(fuellung).frame(width: 10, height: 9).offset(x: kopf * 0.32, y: -kopf * 0.5)
                            Capsule().fill(fell).frame(width: kopf * 0.5, height: 8).offset(x: -kopf * 0.1, y: kopf * 0.56)
                            Capsule().fill(fell).frame(width: kopf * 0.5, height: 8).offset(x: kopf * 0.35, y: kopf * 0.56)
                        }
                        RoundedRectangle(cornerRadius: kopf * 0.34).fill(fuellung).frame(width: kopf, height: kopf)
                        if art == .dackel {
                            Capsule().fill(fell).frame(width: kopf * 0.42, height: kopf * 0.28).offset(x: -kopf * 0.1, y: kopf * 0.22)
                            Circle().fill(Color(white: 0.25)).frame(width: 6, height: 6).offset(x: -kopf * 0.28, y: kopf * 0.2)
                            HStack(spacing: kopf * 0.2) { Circle().fill(fell).frame(width: 5, height: 5); Circle().fill(fell).frame(width: 5, height: 5) }.offset(y: -kopf * 0.28)
                        }
                        HStack(spacing: kopf * 0.14) {
                            Auge(blick: b, zu: blinzelt)
                            Auge(blick: b, zu: blinzelt)
                        }
                        .offset(y: -kopf * 0.06)
                    }
                    .frame(width: kopf, height: kopf)
                    .position(x: kopf / 2 + 2, y: hoehe / 2 - 3)

                    // Schwanz am rechten Ende
                    Group {
                        if art == .katze {
                            Katzenschwanz().stroke(fuellung, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                .frame(width: 30, height: 26)
                                .rotationEffect(.degrees(wedel), anchor: .bottomLeading)
                                .position(x: g.size.width + 12, y: hoehe / 2 - 6)
                        } else {
                            // Ringelrute mit heller Spitze, wippt
                            ZStack {
                                Circle().stroke(fuellung, lineWidth: 7).frame(width: 18, height: 18)
                                Circle().fill(fell).frame(width: 7, height: 7).offset(x: 6, y: -6)
                            }
                            .rotationEffect(.degrees(wedel), anchor: .bottomLeading)
                            .position(x: g.size.width + 8, y: hoehe / 2 - 8)
                            // Hinterpfote
                            Capsule().fill(fell).frame(width: 16, height: 7).position(x: g.size.width - 2, y: hoehe + 1)
                        }
                    }
                }
            }
        }
    }
}

struct Auge: View {
    let blick: CGPoint
    let zu: Bool
    var body: some View {
        ZStack {
            Circle().fill(.white).frame(width: 10, height: 10)
            Circle().fill(.black).frame(width: 5, height: 5).offset(x: blick.x * 2.2, y: blick.y * 2.2)
        }
        .scaleEffect(y: zu ? 0.12 : 1)
        .animation(.easeInOut(duration: 0.08), value: zu)
    }
}

struct Ohr: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct Katzenschwanz: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY - 4))
        p.addQuadCurve(to: CGPoint(x: r.maxX - 4, y: r.midY), control: CGPoint(x: r.maxX + 2, y: r.maxY + 2))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY + 2), control: CGPoint(x: r.maxX, y: r.minY - 4))
        return p
    }
}

/// Zähflüssige Tropfen unter der Island, die langsam laufen; ab und zu fällt einer.
struct Tropfen: View {
    let fuellung: AnyShapeStyle
    private static let stellen: [(x: CGFloat, breite: CGFloat, laenge: CGFloat)] = [
        (0.06, 12, 12), (0.17, 9, 22), (0.3, 14, 8), (0.42, 10, 18), (0.55, 13, 26), (0.68, 9, 10), (0.8, 12, 16), (0.93, 10, 20)]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1 / 15)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            GeometryReader { g in
                ZStack(alignment: .topLeading) {
                    ForEach(Array(Self.stellen.enumerated()), id: \.offset) { i, s in
                        let l = s.laenge + 3 * sin(t * 0.7 + Double(i) * 1.1)
                        Capsule().fill(fuellung).frame(width: s.breite, height: l + s.breite)
                            .position(x: g.size.width * s.x, y: (l + s.breite) / 2 - s.breite / 2)
                        Circle().fill(fuellung).frame(width: s.breite + 3, height: s.breite + 3)
                            .position(x: g.size.width * s.x, y: l)
                    }
                    // fallender Tropfen an der längsten Stelle, alle 6 Sekunden
                    let phase = t.truncatingRemainder(dividingBy: 6) / 6
                    if phase > 0.7 {
                        let f = (phase - 0.7) / 0.3
                        Circle().fill(fuellung).frame(width: 8, height: 8)
                            .position(x: g.size.width * 0.55, y: 30 + f * f * 60)
                            .opacity(1 - f)
                    }
                }
            }
        }
    }
}
