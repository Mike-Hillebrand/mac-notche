import SwiftUI

// MARK: - Farben für den Körper (Stil „Schwarz“ und Tiere)

enum Farbe {
    static let liste: [(name: String, hex: String)] = [
        ("Schwarz", "000000"), ("Anthrazit", "2B2B2E"), ("Nachtblau", "0F1F3D"), ("Tannengrün", "0F2E22"),
        ("Weinrot", "3B0F1C"), ("Schokolade", "3A2518"), ("Lila", "32175A"), ("Signalorange", "F04A00"), ("Pink", "C2185B")]
    static func color(_ hex: String) -> Color {
        var h = hex; if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return .black }
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
    static var gewaehlt: Color { color(UserDefaults.standard.string(forKey: E.farbe) ?? "000000") }
}

// MARK: - Skins: Angedockt (Island), schwebende Tiere (Katze, Dackel, Bulldogge), Tropfend

enum Skin: String, CaseIterable, Identifiable {
    case angedockt = "Angedockt", katze = "Katze", dackel = "Dackel", bulldogge = "Bulldogge", tropfend = "Tropfend"
    var id: String { rawValue }
    static var gewaehlt: Skin { Skin(rawValue: UserDefaults.standard.string(forKey: E.skin) ?? "") ?? .angedockt }
    /// Schwebt mit Abstand zur Bildschirmkante (Kopf links, Schwanz rechts).
    var schwebend: Bool { self == .katze || self == .dackel || self == .bulldogge }
    /// Zusätzlicher Platz ums Fenster für Ohren, Schwanz, Beine, Tropfen.
    var rand: (oben: CGFloat, unten: CGFloat, links: CGFloat, rechts: CGFloat) {
        switch self {
        case .angedockt: (0, 0, 0, 0)
        case .katze: (12, 4, 0, 34)
        case .dackel: (18, 14, 34, 46)
        case .bulldogge: (12, 8, 0, 30)
        case .tropfend: (0, 30, 0, 0)
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
            let blinzelt = art == .bulldogge ? t.truncatingRemainder(dividingBy: 5) > 1.2 : t.truncatingRemainder(dividingBy: 4.3) > 4.12
            let wedel = sin(t * 3.2) * (art == .katze ? 10 : art == .dackel ? 9 : 8)
            let fell = Color(red: 0.90, green: 0.76, blue: 0.58)  // helles Fell an Pfoten, Brauen und Rute
            let b = blick(), b2 = b
            GeometryReader { g in
                let kopf = hoehe + 10
                ZStack(alignment: .topLeading) {
                    // Kopf
                    ZStack {
                        if art == .katze {
                            Ohr().fill(fuellung).frame(width: 13, height: 13).offset(x: -kopf * 0.3, y: -kopf * 0.5 - 2)
                            Ohr().fill(fuellung).frame(width: 13, height: 13).offset(x: kopf * 0.3, y: -kopf * 0.5 - 2)
                        } else if art == .dackel {
                            // Dackel im Profil: Schädel und lange spitze Schnauze als eine Silhouette, helle Unterseite, Schlappohr, kleines Auge
                            let b = kopf * 1.5, h = kopf * 1.25
                            ZStack {
                                DackelKopf().fill(fuellung).frame(width: b, height: h)
                                DackelMaul().fill(fell).frame(width: b, height: h)
                                Circle().fill(fell).frame(width: 5, height: 5).offset(x: -b * 0.17, y: -h * 0.2)
                                ZStack {
                                    Circle().fill(.white).frame(width: 7, height: 7)
                                    Circle().fill(.black).frame(width: 3.5, height: 3.5).offset(x: b2.x * 1.4, y: b2.y * 1.4)
                                }
                                .scaleEffect(y: blinzelt ? 0.15 : 1).animation(.easeInOut(duration: 0.08), value: blinzelt)
                                .offset(x: -b * 0.16, y: -h * 0.1)
                                Circle().fill(Color(white: 0.2)).frame(width: 6, height: 6).offset(x: -b * 0.49, y: -h * 0.02)
                                DackelOhr().fill(fuellung).frame(width: b * 0.3, height: h * 0.8)
                                    .rotationEffect(.degrees(sin(t * 2.5) * 3), anchor: .top)
                                    .offset(x: b * 0.17, y: h * 0.2)
                            }
                            .offset(x: -b * 0.12, y: h * 0.06)
                        } else {
                            // Liegende Bulldogge: kleine Ohren, helle Schnauze unten, Pfoten unter dem Kopf
                            Ohr().fill(fuellung).frame(width: 10, height: 9).offset(x: -kopf * 0.32, y: -kopf * 0.5)
                            Ohr().fill(fuellung).frame(width: 10, height: 9).offset(x: kopf * 0.32, y: -kopf * 0.5)
                            Capsule().fill(fell).frame(width: kopf * 0.5, height: 8).offset(x: -kopf * 0.1, y: kopf * 0.56)
                            Capsule().fill(fell).frame(width: kopf * 0.5, height: 8).offset(x: kopf * 0.35, y: kopf * 0.56)
                        }
                        if art != .dackel { RoundedRectangle(cornerRadius: kopf * 0.34).fill(fuellung).frame(width: kopf, height: kopf) }
                        if art == .bulldogge {
                            Capsule().fill(fell).frame(width: kopf * 0.42, height: kopf * 0.28).offset(x: -kopf * 0.1, y: kopf * 0.22)
                            Circle().fill(Color(white: 0.25)).frame(width: 6, height: 6).offset(x: -kopf * 0.28, y: kopf * 0.2)
                            HStack(spacing: kopf * 0.2) { Circle().fill(fell).frame(width: 5, height: 5); Circle().fill(fell).frame(width: 5, height: 5) }.offset(y: -kopf * 0.28)
                        }
                        if art != .dackel {
                            HStack(spacing: kopf * 0.14) {
                                Auge(blick: b, zu: blinzelt)
                                Auge(blick: b, zu: blinzelt)
                            }
                            .offset(y: -kopf * 0.06)
                        }
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
                        } else if art == .dackel {
                            // Lange dünne Rute, schwingt nach oben; helle Hinterpfote
                            Dackelrute().stroke(fuellung, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .frame(width: 42, height: 30)
                                .rotationEffect(.degrees(wedel), anchor: .bottomLeading)
                                .position(x: g.size.width + 18, y: hoehe / 2 - 4)
                            Capsule().fill(fell).frame(width: 18, height: 8).position(x: g.size.width - 6, y: hoehe + 1)
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

/// Dackelkopf im Profil, Schnauze nach links (Einheitsbox 100×100, y nach unten).
private func punkt(_ r: CGRect, _ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + r.width * x / 100, y: r.minY + r.height * y / 100) }

struct DackelKopf: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: punkt(r, 58, 6))
        p.addQuadCurve(to: punkt(r, 30, 24), control: punkt(r, 40, 6))      // Stirn
        p.addQuadCurve(to: punkt(r, 1, 40), control: punkt(r, 14, 30))      // Nasenrücken
        p.addQuadCurve(to: punkt(r, 4, 49), control: punkt(r, 0, 46))       // Nasenspitze
        p.addQuadCurve(to: punkt(r, 24, 51), control: punkt(r, 12, 52))     // Lefze
        p.addQuadCurve(to: punkt(r, 44, 66), control: punkt(r, 34, 54))     // Kinn
        p.addQuadCurve(to: punkt(r, 70, 76), control: punkt(r, 56, 76))     // Kehle
        p.addLine(to: punkt(r, 82, 100))                                    // Hals
        p.addLine(to: punkt(r, 100, 100))
        p.addLine(to: punkt(r, 100, 40))
        p.addQuadCurve(to: punkt(r, 58, 6), control: punkt(r, 98, 6))       // Hinterkopf
        p.closeSubpath()
        return p
    }
}

/// Helle Unterseite der Schnauze und Kehle.
struct DackelMaul: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: punkt(r, 3, 47))
        p.addQuadCurve(to: punkt(r, 24, 51), control: punkt(r, 12, 52))
        p.addQuadCurve(to: punkt(r, 44, 66), control: punkt(r, 34, 54))
        p.addQuadCurve(to: punkt(r, 70, 76), control: punkt(r, 56, 76))
        p.addLine(to: punkt(r, 76, 88))
        p.addQuadCurve(to: punkt(r, 48, 58), control: punkt(r, 66, 66))
        p.addQuadCurve(to: punkt(r, 20, 44), control: punkt(r, 36, 46))
        p.closeSubpath()
        return p
    }
}

/// Schlappohr: oben schmal, unten rund.
struct DackelOhr: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: punkt(r, 30, 0))
        p.addLine(to: punkt(r, 80, 0))
        p.addQuadCurve(to: punkt(r, 100, 70), control: punkt(r, 100, 20))
        p.addQuadCurve(to: punkt(r, 50, 100), control: punkt(r, 100, 100))
        p.addQuadCurve(to: punkt(r, 0, 70), control: punkt(r, 0, 100))
        p.addQuadCurve(to: punkt(r, 30, 0), control: punkt(r, 0, 20))
        p.closeSubpath()
        return p
    }
}

struct Dackelrute: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY - 2))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + 2), control: CGPoint(x: r.midX + 6, y: r.maxY - 6))
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
