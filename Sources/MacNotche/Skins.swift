import SwiftUI

// MARK: - Gerät: echte Notch (MacBook) oder freier Bildschirmrand (iMac, Studio, Monitor)

enum Geraet {
    /// „auto“ erkennt die Notch über den sicheren Bereich; „macbook“/„imac“ erzwingen.
    static var echteNotch: Bool {
        switch UserDefaults.standard.string(forKey: E.geraet) ?? "auto" {
        case "macbook": return true
        case "imac": return false
        default: return (NSScreen.screens.first?.safeAreaInsets.top ?? 0) > 0
        }
    }
    /// Breite der Kamera-Notch plus Rand; unter ihr darf zugeklappt nichts stehen.
    static var luecke: CGFloat {
        guard echteNotch else { return 0 }
        if let s = NSScreen.screens.first, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea, s.frame.width - l.width - r.width > 50 {
            return s.frame.width - l.width - r.width + 16
        }
        return 200  // erzwungen oder unbekannt: typische MacBook-Notch
    }
}

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
    /// Tier-Skin (Kopf links, Schwanz rechts).
    var tier: Bool { self == .katze || self == .dackel || self == .bulldogge }
    /// Tiere schweben mit Abstand zur Kante, außer der Nutzer dockt sie oben an.
    var schwebend: Bool { tier && !Skin.dockt }
    static var dockt: Bool { UserDefaults.standard.bool(forKey: E.skinDock) }
    /// Zusätzlicher Platz ums Fenster für Ohren, Schwanz, Beine, Tropfen.
    var rand: (oben: CGFloat, unten: CGFloat, links: CGFloat, rechts: CGFloat) {
        switch self {
        case .angedockt: (0, 0, 0, 0)
        case .katze: (Skin.dockt ? 0 : 20, Skin.dockt ? 24 : 12, 6, 34)
        case .dackel: (Skin.dockt ? 0 : 20, Skin.dockt ? 26 : 16, 36, 46)
        case .bulldogge: (Skin.dockt ? 0 : 20, Skin.dockt ? 26 : 12, 10, 22)
        case .tropfend: (0, 46, 0, 0)
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
                // Angedockt: Kopf so weit nach unten, dass Ohren und Stirn unter der Bildschirmkante bleiben.
                let dock: CGFloat = Skin.dockt ? (art == .dackel ? 12 : 20) : 0
                ZStack(alignment: .topLeading) {
                    // Kopf: Dogge und Katze von vorn mit hellem Gesicht, Dackel im Profil als Silhouette mit hellen Linien.
                    KopfZeichnung(art: art, fuellung: fuellung, blick: b, zu: blinzelt, t: t)
                        .frame(width: art == .dackel ? kopf * 1.6 : kopf * 1.45, height: art == .dackel ? kopf * 1.4 : kopf * 1.45)
                        .position(x: art == .dackel ? kopf * 0.74 : kopf * 0.66, y: hoehe / 2 - 2 + dock)

                    // Schwanz am rechten Ende
                    Group {
                        // Alle Schwänze setzen am Körperende an und hängen nach unten; sie pendeln um den Ansatz.
                        if art == .katze {
                            Katzenschwanz().stroke(fuellung, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                .frame(width: 30, height: 30)
                                .rotationEffect(.degrees(wedel * 0.7), anchor: .topLeading)
                                .position(x: g.size.width + 12, y: hoehe / 2 + 12)
                        } else if art == .dackel {
                            Dackelrute().stroke(fuellung, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .frame(width: 42, height: 30)
                                .rotationEffect(.degrees(wedel * 0.7), anchor: .topLeading)
                                .position(x: g.size.width + 18, y: hoehe / 2 + 12)
                        } else {
                            Kringel().stroke(fuellung, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .frame(width: 16, height: 16)
                                .rotationEffect(.degrees(wedel * 0.5), anchor: .leading)
                                .position(x: g.size.width + 5, y: hoehe / 2 + 4)
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
func punkt(_ r: CGRect, _ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + r.width * x / 100, y: r.minY + r.height * y / 100) }

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
        p.addQuadCurve(to: punkt(r, 100, 62), control: punkt(r, 88, 78))    // Nacken läuft in den Körper
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
        p.addLine(to: punkt(r, 80, 70))
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

/// Kleiner Schwanzkringel: Dreiviertelkreis, der nach innen einrollt.
struct Kringel: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addArc(center: CGPoint(x: r.midX + 1, y: r.midY), radius: r.width * 0.36, startAngle: .degrees(180), endAngle: .degrees(480), clockwise: false)
        return p
    }
}

struct Dackelrute: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + 3))
        p.addQuadCurve(to: CGPoint(x: r.maxX - 2, y: r.maxY - 3), control: CGPoint(x: r.midX + 8, y: r.minY + 2))
        return p
    }
}

struct Katzenschwanz: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + 3))
        p.addQuadCurve(to: CGPoint(x: r.midX - 2, y: r.maxY - 4), control: CGPoint(x: r.minX + 2, y: r.maxY - 2))
        p.addQuadCurve(to: CGPoint(x: r.maxX - 3, y: r.midY + 2), control: CGPoint(x: r.maxX, y: r.maxY + 2))
        return p
    }
}

/// Zähflüssige Tropfen unter der Island, die langsam laufen; ab und zu fällt einer.
/// Tropfsaum wie bei laufender Farbe: eine zusammenhängende Form. Zwischen den Tropfen schwingt die Kante
/// nach oben, jeder Tropfen läuft als Hals nach unten und endet in einer runden Perle.
struct Tropfsaum: Shape {
    var tropfen: [(x: CGFloat, breite: CGFloat, laenge: CGFloat)]  // x relativ 0…1, Längen in pt
    static let basis: CGFloat = 8  // so weit überlappt der Saum den Körper

    func path(in r: CGRect) -> Path {
        let y0 = r.minY + Self.basis
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX, y: y0))
        var letztesRechts = r.minX
        for d in tropfen.sorted(by: { $0.x < $1.x }) {
            let x = r.minX + r.width * d.x, w = d.breite, l = max(d.laenge, w)
            let perle = w * 0.62
            let links = x - w / 2, rechts = x + w / 2
            // Kante zwischen zwei Tropfen: flacher Bogen nach oben
            p.addQuadCurve(to: CGPoint(x: links, y: y0), control: CGPoint(x: (letztesRechts + links) / 2, y: y0 - min(6, (links - letztesRechts) / 4)))
            // linke Flanke mit Einschnürung zum Hals, dann Perle, dann rechte Flanke
            p.addCurve(to: CGPoint(x: x - perle, y: y0 + l - perle),
                       control1: CGPoint(x: links + w * 0.05, y: y0 + l * 0.35),
                       control2: CGPoint(x: x - w * 0.32, y: y0 + l * 0.55))
            p.addArc(center: CGPoint(x: x, y: y0 + l - perle), radius: perle, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: true)
            p.addCurve(to: CGPoint(x: rechts, y: y0),
                       control1: CGPoint(x: x + w * 0.32, y: y0 + l * 0.55),
                       control2: CGPoint(x: rechts - w * 0.05, y: y0 + l * 0.35))
            letztesRechts = rechts
        }
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: y0), control: CGPoint(x: (letztesRechts + r.maxX) / 2, y: y0 - min(6, (r.maxX - letztesRechts) / 4)))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

/// Zähflüssige Tropfen unter der Island, die langsam laufen; ab und zu fällt einer.
struct Tropfen: View {
    let fuellung: AnyShapeStyle
    private static let stellen: [(x: CGFloat, breite: CGFloat, laenge: CGFloat)] = [
        (0.06, 9, 14), (0.15, 12, 30), (0.24, 7, 10), (0.33, 10, 22), (0.42, 8, 12), (0.52, 13, 38), (0.62, 8, 16),
        (0.71, 10, 26), (0.8, 7, 9), (0.88, 11, 32), (0.96, 8, 14)]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1 / 15)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let aktuell = Self.stellen.enumerated().map { i, s in (x: s.x, breite: s.breite, laenge: s.laenge + CGFloat(3 * sin(t * 0.5 + Double(i) * 1.3))) }
            GeometryReader { g in
                ZStack(alignment: .topLeading) {
                    Tropfsaum(tropfen: aktuell).fill(fuellung).frame(width: g.size.width, height: g.size.height).offset(y: -Tropfsaum.basis)
                    // fallender Tropfen unter dem längsten, alle 6 Sekunden
                    let phase = t.truncatingRemainder(dividingBy: 6) / 6
                    if phase > 0.7 {
                        let f = (phase - 0.7) / 0.3
                        Circle().fill(fuellung).frame(width: 7, height: 7)
                            .position(x: g.size.width * 0.52, y: 40 + f * f * 60)
                            .opacity(1 - f)
                    }
                }
            }
        }
    }
}


// MARK: - Köpfe nach Vorlage (Einheitsbox 100×100, y nach unten)

private func pfad(_ r: CGRect, _ schritte: [(String, [CGFloat])]) -> Path {
    var p = Path()
    for (art, v) in schritte {
        switch art {
        case "m": p.move(to: punkt(r, v[0], v[1]))
        case "l": p.addLine(to: punkt(r, v[0], v[1]))
        default: p.addQuadCurve(to: punkt(r, v[0], v[1]), control: punkt(r, v[2], v[3]))  // "q": Ziel, Kontrolle
        }
    }
    p.closeSubpath()
    return p
}
private func linie(_ r: CGRect, _ schritte: [(String, [CGFloat])]) -> Path {
    var p = Path()
    for (art, v) in schritte {
        switch art {
        case "m": p.move(to: punkt(r, v[0], v[1]))
        case "l": p.addLine(to: punkt(r, v[0], v[1]))
        default: p.addQuadCurve(to: punkt(r, v[0], v[1]), control: punkt(r, v[2], v[3]))
        }
    }
    return p
}

struct Umriss: Shape { let schritte: [(String, [CGFloat])]; func path(in r: CGRect) -> Path { pfad(r, schritte) } }
struct Strich: Shape { let schritte: [(String, [CGFloat])]; func path(in r: CGRect) -> Path { linie(r, schritte) } }

struct KopfZeichnung: View {
    let art: Skin
    let fuellung: AnyShapeStyle
    let blick: CGPoint
    let zu: Bool
    let t: Double
    private let hell = Color(white: 0.96)

    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height) / 100  // 1 Einheit in pt
            ZStack {
                switch art {
                case .bulldogge: dogge(s)
                case .katze: katze(s)
                default: dackel(s)
                }
            }
            .frame(width: g.size.width, height: g.size.height)
        }
    }

    /// Auge mit Pupille, die der Maus folgt; „zu“ zieht das Lid herunter.
    private func auge(_ s: CGFloat, r: CGFloat, dunkel: Bool) -> some View {
        ZStack {
            Circle().fill(dunkel ? Color.black : hell).frame(width: r * 2 * s, height: r * 2 * s)
            Circle().fill(dunkel ? hell : Color.black).frame(width: r * 0.8 * s, height: r * 0.8 * s)
                .offset(x: blick.x * r * 0.45 * s, y: blick.y * r * 0.45 * s)
        }
        .scaleEffect(y: zu ? 0.15 : 1)
        .animation(.easeInOut(duration: 0.08), value: zu)
    }

    // Dogge (Mops) von vorn: Hängeohren, helles Gesicht, dunkle Maske über Schnauze und Kinn, dunkle Augenflecken, Stirnfalten.
    private func dogge(_ s: CGFloat) -> some View {
        ZStack {
            Umriss(schritte: [("m", [50, 6]), ("q", [80, 12, 66, 4]), ("q", [96, 34, 94, 16]), ("q", [90, 76, 102, 56]), ("q", [76, 72, 80, 82]),
                              ("q", [72, 92, 80, 84]), ("q", [50, 98, 64, 100]), ("q", [28, 92, 36, 100]), ("q", [24, 72, 20, 84]), ("q", [10, 76, 20, 82]),
                              ("q", [4, 34, -2, 56]), ("q", [20, 12, 6, 16]), ("q", [50, 6, 34, 4])]).fill(fuellung)
            Umriss(schritte: [("m", [50, 13]), ("q", [78, 24, 70, 11]), ("q", [80, 56, 86, 38]), ("q", [66, 91, 82, 80]), ("q", [50, 95, 58, 97]),
                              ("q", [34, 91, 42, 97]), ("q", [20, 56, 18, 80]), ("q", [22, 24, 14, 38]), ("q", [50, 13, 30, 11])]).fill(hell)
            // dunkle Maske: Schnauze und Kinn
            Umriss(schritte: [("m", [30, 58]), ("q", [50, 52, 40, 50]), ("q", [70, 58, 60, 50]), ("q", [66, 90, 80, 74]), ("q", [50, 94, 60, 96]),
                              ("q", [34, 90, 40, 96]), ("q", [30, 58, 20, 74])]).fill(fuellung)
            // Nase und Maul als helle Linien auf der Maske
            Strich(schritte: [("m", [42, 62]), ("q", [58, 62, 50, 58]), ("q", [56, 70, 60, 66]), ("m", [42, 62]), ("q", [44, 70, 40, 66]),
                              ("m", [50, 68]), ("l", [50, 80]), ("m", [50, 80]), ("q", [38, 82, 44, 88]), ("m", [50, 80]), ("q", [62, 82, 56, 88])])
                .stroke(hell, style: StrokeStyle(lineWidth: 2 * s, lineCap: .round))
            // Augenflecken dunkel, Augen hell mit Pupille
            Ellipse().fill(fuellung).frame(width: 18 * s, height: 13 * s).rotationEffect(.degrees(-14)).position(x: 35 * s, y: 46 * s)
            Ellipse().fill(fuellung).frame(width: 18 * s, height: 13 * s).rotationEffect(.degrees(14)).position(x: 65 * s, y: 46 * s)
            auge(s, r: 4.6, dunkel: false).position(x: 36 * s, y: 46 * s)
            auge(s, r: 4.6, dunkel: false).position(x: 64 * s, y: 46 * s)
            // Brauen und Stirnfalten
            Strich(schritte: [("m", [27, 34]), ("q", [40, 36, 33, 31]), ("m", [73, 34]), ("q", [60, 36, 67, 31]),
                              ("m", [44, 24]), ("q", [46, 36, 42, 30]), ("m", [50, 22]), ("q", [50, 36, 50, 29]), ("m", [56, 24]), ("q", [54, 36, 58, 30])])
                .stroke(fuellung, style: StrokeStyle(lineWidth: 2.6 * s, lineCap: .round))
        }
    }

    // Katze von vorn: spitze Ohren, helles Gesicht, Stirnstreifen, Dreiecksnase, Schnurrhaare.
    private func katze(_ s: CGFloat) -> some View {
        ZStack {
            Umriss(schritte: [("m", [14, 42]), ("l", [8, 4]), ("l", [36, 20]), ("q", [64, 20, 50, 14]), ("l", [92, 4]), ("l", [86, 42]),
                              ("q", [94, 66, 96, 52]), ("q", [50, 96, 92, 96]), ("q", [6, 66, 8, 96]), ("q", [14, 42, 4, 52])]).fill(fuellung)
            Umriss(schritte: [("m", [22, 44]), ("l", [18, 14]), ("l", [38, 27]), ("q", [62, 27, 50, 22]), ("l", [82, 14]), ("l", [78, 44]),
                              ("q", [86, 66, 88, 54]), ("q", [50, 90, 84, 90]), ("q", [14, 66, 16, 90]), ("q", [22, 44, 12, 54])]).fill(hell)
            Strich(schritte: [("m", [50, 29]), ("l", [50, 38]), ("m", [42, 31]), ("l", [44, 39]), ("m", [58, 31]), ("l", [56, 39])])
                .stroke(fuellung, style: StrokeStyle(lineWidth: 3 * s, lineCap: .round))
            auge(s, r: 6, dunkel: true).position(x: 36 * s, y: 55 * s)
            auge(s, r: 6, dunkel: true).position(x: 64 * s, y: 55 * s)
            Umriss(schritte: [("m", [44, 66]), ("l", [56, 66]), ("l", [50, 73])]).fill(fuellung)
            Strich(schritte: [("m", [50, 73]), ("q", [42, 78, 46, 81]), ("m", [50, 73]), ("q", [58, 78, 54, 81]),
                              ("m", [30, 70]), ("l", [8, 66]), ("m", [30, 75]), ("l", [8, 78]), ("m", [70, 70]), ("l", [92, 66]), ("m", [70, 75]), ("l", [92, 78])])
                .stroke(fuellung, style: StrokeStyle(lineWidth: 2.2 * s, lineCap: .round))
        }
    }

    // Dackel im Profil, Kopf nach oben gereckt: Silhouette mit heller Ohrkontur, Maulstrich und Augenpunkt.
    private func dackel(_ s: CGFloat) -> some View {
        ZStack {
            let kontur: [(String, [CGFloat])] = [("m", [6, 30]), ("q", [26, 12, 10, 14]), ("q", [58, 6, 40, 4]), ("q", [86, 30, 82, 8]), ("q", [92, 78, 98, 50]),
                              ("q", [76, 86, 90, 92]), ("q", [66, 62, 70, 78]), ("q", [62, 80, 64, 70]), ("q", [42, 80, 52, 84]),
                              ("q", [36, 60, 36, 72]), ("q", [14, 44, 28, 52]), ("q", [6, 30, 4, 38])]
            Umriss(schritte: kontur).fill(fuellung)
            // feine helle Kontur, damit sich der Kopf vom gleichfarbigen Körper abhebt
            Umriss(schritte: kontur).stroke(hell.opacity(0.85), style: StrokeStyle(lineWidth: 1.4 * s, lineJoin: .round))
            Strich(schritte: [("m", [62, 28]), ("q", [66, 62, 56, 44]), ("q", [88, 76, 72, 88]), ("m", [10, 36]), ("q", [34, 48, 22, 48])])
                .stroke(hell, style: StrokeStyle(lineWidth: 2.4 * s, lineCap: .round))
                .rotationEffect(.degrees(sin(t * 2.5) * 1.5), anchor: UnitPoint(x: 0.62, y: 0.28))
            Circle().fill(hell).frame(width: 3.2 * s, height: 3.2 * s).position(x: 9 * s, y: 27 * s)
            auge(s, r: 4.4, dunkel: false).position(x: 34 * s, y: 22 * s)
        }
    }
}
