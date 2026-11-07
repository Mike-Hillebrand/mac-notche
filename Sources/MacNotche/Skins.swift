import SwiftUI

// MARK: - Farbiges Leuchten um die Notch (wie Siri)

struct Leuchten: View {
    let form: AnyShape
    static let rand: CGFloat = 30  // Platz für den Weichzeichner rund um die Form
    private let farben: [Color] = [.orange, .pink, .purple, .blue, .cyan, .yellow, .orange]
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            // Waagerechter Verlauf über die Breite, der langsam durch den Farbkreis dreht.
            let verlauf = LinearGradient(colors: farben, startPoint: .leading, endPoint: .trailing)
            ZStack {
                form.stroke(verlauf, lineWidth: 12).blur(radius: 12).opacity(0.9)
                form.stroke(verlauf, lineWidth: 5).blur(radius: 5)
                form.stroke(verlauf, lineWidth: 1.5).opacity(0.9)
            }
            .hueRotation(.degrees(tl.date.timeIntervalSinceReferenceDate * 20))
        }
        .allowsHitTesting(false)
    }
    /// Nur ohne Tier-Skin: um Katze und Hunde herum würde der Saum stören.
    static var an: Bool { UserDefaults.standard.bool(forKey: E.leuchten) && !Skin.gewaehlt.tier }
}

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
    case angedockt = "Angedockt", katze = "Katze", dackel = "Dackel", bulldogge = "Bulldogge", frenchy = "Frenchy", tropfend = "Tropfend"
    var id: String { rawValue }
    static var gewaehlt: Skin { Skin(rawValue: UserDefaults.standard.string(forKey: E.skin) ?? "") ?? .angedockt }
    /// Schwebt mit Abstand zur Bildschirmkante (Kopf links, Schwanz rechts).
    /// Tier-Skin (Kopf links, Schwanz rechts).
    var tier: Bool { self == .katze || self == .dackel || self == .bulldogge || self == .frenchy }
    /// Komplette Hundefigur aus der Vorlage: Höhe in Leistenhöhen, Anteil der Figurhöhe auf der Leistenmitte, linker Rand in Leistenhöhen, Kopfanteil der Breite.
    var figur: (h: CGFloat, fy: CGFloat, fx: CGFloat, kopf: CGFloat)? {
        switch self {
        case .dackel: (1.9, 0.5, 0, 1)
        case .bulldogge: (1.9, 0.5, 0, 1)
        case .frenchy: (1.9, 0.5, 0, 1)
        default: nil
        }
    }
    static func box(_ art: Skin) -> CGRect { HundFigur.box(art) }
    /// Kopfmaße in pt: Mittelpunkt liegt auf der linken Körperkante, der Körper beginnt hinter der Kopfmitte.
    func kopfMasse(leiste: CGFloat) -> (breite: CGFloat, hoehe: CGFloat) {
        if self == .katze { let h = (leiste + 10) * 1.7; return (h, h) }
        guard let f = figur else { return (0, 0) }
        let H = leiste * f.h
        return (H * Skin.box(self).width / Skin.box(self).height, H)
    }
    /// Senkrechte Mitte des Kopfs: schwebend auf Leistenmitte, angedockt mit der Oberkante bündig.
    func kopfMitteY(leiste: CGFloat) -> CGFloat { Skin.dockt ? kopfMasse(leiste: leiste).hoehe / 2 : leiste / 2 - 2 }
    /// Wo rechts vom Kopf der Inhalt beginnt (relativ zur linken Körperkante).
    func innenLinks(leiste: CGFloat) -> CGFloat { kopfMasse(leiste: leiste).breite / 2 + 6 }
    /// Tiere schweben mit Abstand zur Kante, außer der Nutzer dockt sie oben an.
    var schwebend: Bool { tier && !Skin.dockt }
    static var dockt: Bool { UserDefaults.standard.bool(forKey: E.skinDock) }
    /// Zusätzlicher Platz ums Fenster für Ohren, Schwanz, Beine, Tropfen.
    func rand(leiste: CGFloat) -> (oben: CGFloat, unten: CGFloat, links: CGFloat, rechts: CGFloat) {
        switch self {
        case .angedockt: return (0, 0, 0, 0)
        case .tropfend: return (0, 56, 0, 0)
        default:
            let k = kopfMasse(leiste: leiste), cy = kopfMitteY(leiste: leiste)
            let oben = max(0, k.hoehe / 2 - cy)                 // so weit ragt der Kopf über die Oberkante
            let unten = max(0, cy + k.hoehe / 2 - leiste) + 4   // so weit hängt er unter der Leiste
            return (oben, unten, k.breite / 2 + 2, self == .frenchy ? 12 : self == .katze ? 38 : 46)
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
                        ZStack(alignment: .topLeading) {
                    // Kopf: Katze aus Mikes SVG-Vorlage, Hunde gezeichnet
                    if art == .katze {
                        let k = art.kopfMasse(leiste: hoehe)
                        KatzenKopf(fuellung: fuellung, blick: b, zu: blinzelt)
                            .frame(width: k.breite, height: k.hoehe)
                            .position(x: 0, y: art.kopfMitteY(leiste: hoehe))
                    } else if art.figur != nil {
                        let k = art.kopfMasse(leiste: hoehe)
                        HundFigur(art: art, fuellung: fuellung)
                            .frame(width: k.breite, height: k.hoehe)
                            .scaleEffect(x: 1, y: 1 + 0.012 * sin(t * 1.6), anchor: .bottom)  // atmet
                            .position(x: 0, y: art.kopfMitteY(leiste: hoehe))
                    }

                    // Schwanz am rechten Ende
                    Group {
                        // Alle Schwänze setzen am Körperende an und hängen nach unten; sie pendeln um den Ansatz.
                        if art == .katze {
                            Katzenschwanz().stroke(fuellung, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                                .frame(width: 34, height: 26)
                                .rotationEffect(.degrees(wedel * 0.5), anchor: .topLeading)
                                .position(x: g.size.width + 15, y: hoehe / 2 + 9)
                        } else if art == .dackel {
                            Dackelrute().stroke(fuellung, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .frame(width: 42, height: 30)
                                .rotationEffect(.degrees(wedel * 0.7), anchor: .topLeading)
                                .position(x: g.size.width + 18, y: hoehe / 2 + 12)
                        } else if art == .bulldogge {
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
    /// Aus dem Körperende nach rechts, dann nach unten und unter dem Ende wieder nach links eingerollt.
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + 4))
        p.addCurve(to: CGPoint(x: r.maxX - 3, y: r.midY + 2), control1: CGPoint(x: r.midX + 6, y: r.minY), control2: CGPoint(x: r.maxX - 2, y: r.minY + 4))
        p.addCurve(to: CGPoint(x: r.minX + 8, y: r.maxY - 3), control1: CGPoint(x: r.maxX - 4, y: r.maxY + 2), control2: CGPoint(x: r.midX - 2, y: r.maxY + 2))
        return p
    }
}

/// Liest SVG-Pfaddaten (M L H V C S Q Z, absolut und relativ) in einen Path.
enum SVGPfad {
    static func lesen(_ d: String) -> Path {
        let muster = try! NSRegularExpression(pattern: "[MmLlHhVvCcSsQqZz]|-?\\d*\\.?\\d+(?:e-?\\d+)?")
        let tokens = muster.matches(in: d, range: NSRange(d.startIndex..., in: d)).map { String(d[Range($0.range, in: d)!]) }
        var p = Path(); var i = 0; var cmd: Character = "M"
        var cur = CGPoint.zero, start = CGPoint.zero, letzteKontrolle: CGPoint? = nil
        func zahl() -> CGFloat { let v = CGFloat(Double(tokens[i]) ?? 0); i += 1; return v }
        while i < tokens.count {
            if let c = tokens[i].first, c.isLetter { cmd = c; i += 1; if cmd == "Z" || cmd == "z" { p.closeSubpath(); cur = start; continue } }
            let rel = cmd.isLowercase
            switch cmd.uppercased() {
            case "M":
                let x = zahl(), y = zahl(); cur = rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y)
                p.move(to: cur); start = cur; cmd = rel ? "l" : "L"; letzteKontrolle = nil
            case "L":
                let x = zahl(), y = zahl(); cur = rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y); p.addLine(to: cur); letzteKontrolle = nil
            case "H": let x = zahl(); cur.x = rel ? cur.x + x : x; p.addLine(to: cur); letzteKontrolle = nil
            case "V": let y = zahl(); cur.y = rel ? cur.y + y : y; p.addLine(to: cur); letzteKontrolle = nil
            case "C":
                let x1 = zahl(), y1 = zahl(), x2 = zahl(), y2 = zahl(), x = zahl(), y = zahl()
                let o = rel ? cur : .zero
                let c1 = CGPoint(x: o.x + x1, y: o.y + y1), c2 = CGPoint(x: o.x + x2, y: o.y + y2), z = CGPoint(x: o.x + x, y: o.y + y)
                p.addCurve(to: z, control1: c1, control2: c2); cur = z; letzteKontrolle = c2
            case "S":
                let x2 = zahl(), y2 = zahl(), x = zahl(), y = zahl()
                let o = rel ? cur : .zero
                let c1 = letzteKontrolle.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                let c2 = CGPoint(x: o.x + x2, y: o.y + y2), z = CGPoint(x: o.x + x, y: o.y + y)
                p.addCurve(to: z, control1: c1, control2: c2); cur = z; letzteKontrolle = c2
            case "Q":
                let x1 = zahl(), y1 = zahl(), x = zahl(), y = zahl()
                let o = rel ? cur : .zero
                let c1 = CGPoint(x: o.x + x1, y: o.y + y1), z = CGPoint(x: o.x + x, y: o.y + y)
                p.addQuadCurve(to: z, control: c1); cur = z; letzteKontrolle = c1
            default: i += 1
            }
        }
        return p
    }
}

/// Tropfsaum aus Mikes Vorlage (SVG), auf die Breite der Notch gezogen; oben überlappt er den Körper.
struct Tropfsaum: Shape {
    static let basis: CGFloat = 4  // so weit überlappt der Saum den Körper, der Rest wird beschnitten
    static let vorlage = SVGPfad.lesen(TropfenVorlage.balken)
    func path(in r: CGRect) -> Path {
        let b = Self.vorlage.boundingRect
        let sx = r.width / b.width, sy = (r.height - Self.basis) / (b.height - 68)  // 68 = Balkenhöhe über der Tropfkante in der Vorlage
        var t = CGAffineTransform(translationX: r.minX, y: r.minY + Self.basis - 68 * sy)
        t = t.scaledBy(x: sx, y: sy).translatedBy(x: -b.minX, y: -b.minY)
        return Self.vorlage.applying(t)
    }
}

enum TropfenVorlage {
    static let balken = "M97.029,79.835v68.355c38.092,0,28.72,32.688,23.308,56.378c-4.331,18.959,0.832,26.75,10.052,26.75c9.221,0,13.384-10.321,10.188-26.836c-3.196-16.514-8.124-56.868,21.175-56.868c29.3,0,24.372,73.515,12.785,122.659c-8.302,35.212-1.598,49.143,15.182,49.143c15.582,0,19.256-24.96,14.783-53.139c-7.991-50.342-3.197-103.88,14.383-106.544c17.58-2.663,3.63,30.633,8.523,43.683c3.995,10.654,18.645,8.79,18.112-4.262c-0.348-8.533-13.868-33.828,3.729-33.828c22.093,0,11.494,32.177,8.523,52.739c-2.842,19.671-1.97,28.579,10.544,29.01c9.585,0.331,15.652-7.372,10.329-29.874c-4.544-19.208-6.49-69.013,10.025-69.013c16.514,0,11.72,21.133,23.972,21.133c12.253,0,7.175-25.533,19.96-25.533c11.72,0,15.465,25.001,6.409,49.772c-7.033,19.238,19.766,19.437,17.58,2.131c-3.197-25.304-3.729-42.618,6.925-43.15c10.654-0.533,10.801,6.931,9.146,16.087c-1.954,10.816,10.564,8.419,9.765,2.026c-0.799-6.393-3.196-22.465,3.996-22.465c7.192,0,4.794,13.142,11.72,14.207c6.925,1.066,8.523-14.207,14.65-14.207c6.126,0,7.933,33.854,3.463,55.759c-5.327,26.103-3.291,34.36,6.126,34.36c10.654,0,10.706-10.286,6.71-29.997c-4.688-23.129-3.047-60.699,8.739-60.699c10.122,0,8.79,9.189,6.659,29.166c-1.591,14.917,16.248,10.654,12.253-1.865c-2.623-8.219-0.622-26.726,7.737-26.726c12.56,0,10.046,6.423,17.683,6.341c7.767-0.082,8.94-6.341,18.796-6.341s6.502,25.395,1.253,47.769c-5.249,22.374,21.92,22.374,21.121,1.598c-0.799-20.776-8.986-46.194,10.388-47.945c22.108-1.998,15.982,66.59,9.589,118.53c-3.983,32.361,0.932,45.281,13.318,46.08c14.8,0.955,20.436-10.233,18.112-33.561c-6.393-64.193-22.59-137.863,0.464-138.855c21.745-0.935,7.701,20.771,25.285,21.153c15.204,0.331,2.809-14.77,27.523-14.77V79.835H97.029z"
    static let tropfen = ["M318.572,224.051c-4.755,0.896-8.935,12.783-8.936,20.547c-0.001,10.246,15.369,13.221,17.022,2.314C327.6,240.693,323.553,223.112,318.572,224.051z", "M422.092,263.641c-6.543,0.783-15.953,38.099-1.037,38.329C437.735,302.227,427.264,263.022,422.092,263.641z", "M132.844,247.647c-6.326,0-19.002,31.885,0,31.974C148.692,279.694,138.903,247.647,132.844,247.647z"]
}

struct Tropfen: View {
    let fuellung: AnyShapeStyle
    static let kleine = TropfenVorlage.tropfen.map { SVGPfad.lesen($0) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1 / 15)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            GeometryReader { g in
                ZStack(alignment: .topLeading) {
                    Tropfsaum().fill(fuellung)
                        .frame(width: g.size.width, height: g.size.height)
                        .scaleEffect(x: 1, y: 1 + 0.02 * sin(t * 0.8), anchor: .top)
                        .clipped()
                    // ein Tropfen löst sich alle 6 Sekunden
                    let phase = t.truncatingRemainder(dividingBy: 6) / 6
                    if phase > 0.7 {
                        let f = (phase - 0.7) / 0.3
                        Circle().fill(fuellung).frame(width: 7, height: 9)
                            .position(x: g.size.width * 0.45, y: g.size.height * 0.9 + f * f * 60)
                            .opacity(1 - f)
                    }
                }
            }
        }
    }
}




// MARK: - Katzenkopf aus SVG-Vorlage

enum KatzenVorlage {
    static let silhouette = "M4000.205,2882.233c-33.772-1.635-61.285-1.454-88.401-4.643c-38.709-4.553-77.575-2.354-116.23-5.332c-16.057-1.238-22.212,3.646-23.956,20.084c-7.106,66.984-25.068,131.101-55.979,191.141c-9.524,18.499,0.255,23.353,15.28,28.126c89.623,28.475,176.306,64.252,260.226,106.654c14.767,7.461,28.818,16.339,45.442,25.845c-14.403,7.771-23.14,0.955-32.032-1.783c-97.427-29.999-195.025-59.49-291.934-91.09c-22.825-7.442-34.618-1.334-46.515,17.15c-32.009,49.729-72.64,92.195-118.139,129.498c-19.007,15.583-16.539,22.713,2.715,34.277c85.206,51.179,166.617,107.888,242.604,172.086c15.24,12.875,32.617,24.231,38.924,46.964c-41.578-24.408-83.11-48.897-124.746-73.207c-67.792-39.58-135.677-78.999-203.46-118.594c-12.446-7.27-23.879-10.211-37.563-1.123c-162.302,107.786-344.099,164.685-532.927,202.811c-66.193,13.365-127.532,38.228-185.726,72.32c-133.936,78.465-279.84,113.8-434.113,117.741c-146.9,3.753-292.174-4.872-432.69-53.632c-55.808-19.366-108.245-45.636-158.259-76.196c-79.755-48.732-169.892-64.961-258.443-85.146c-150.284-34.256-291.126-89.967-420.018-174.716c-16.679-10.966-30.126-11.39-47.013-1.436c-101.039,59.555-202.435,118.506-303.865,177.394c-8.071,4.686-14.52,13.918-28.086,11.235c7.643-18.087,23.179-27.558,36.155-38.857c77.876-67.816,163.218-125.226,252.266-177.024c23.391-13.606,21.942-22.537,3.062-38.386c-45.838-38.477-85.427-83.019-118.86-132.606c-10.868-16.119-22.622-17.253-39.148-12.127c-101.678,31.537-203.493,62.631-305.302,93.745c-9.195,2.81-17.888,8.456-30.066,6.004c3.494-12.749,15.216-15.029,23.649-19.433c89.772-46.879,183.009-85.567,279.318-116.926c34.392-11.199,34.485-11.653,19.604-44.098c-24.626-53.695-42.386-109.408-48.134-168.363c-2.127-21.811-12.464-29.477-33.669-28.243c-58.524,3.406-117.107,5.792-175.664,8.623c-5.23,0.253-10.631,3.042-16.652-2.283c4.518-10.481,15.378-10.596,23.928-13.359c56.772-18.344,114.872-31.235,173.682-40.975c12.182-2.018,22.931-3.745,23.139-20.211c0.576-45.544,9.705-89.367,28.811-132.756c-34.837,13.295-65.047,32.336-91.458,57.797c-5.488,5.291-9.283,17.063-18.13,13.28c-10.083-4.313-5.323-15.784-4.073-24.157c8.221-55.069,32.132-102.92,67.875-145.171c8.673-10.252,17.494-20.378,30.64-35.673c-31.797,8.667-55.867,19.274-79.173,32.131c-6.688,3.689-13.75,12.21-21.753,5.781c-7.014-5.636-3.554-15.089-2.463-23.058c14.75-107.779,73.189-184.076,168.596-233.594c33.247-17.256,47.078-61.488,31.391-95.125c-35.766-76.688-54.002-158.74-69.575-241.23c-68.184-361.176-50.708-718.06,56.359-1070.026c11.298-37.139,27.232-72.497,49.032-105.138c33.736-50.514,81.324-66.721,138.737-55.983c62.541,11.697,120.596,37.278,177.971,63.665c178.181,81.944,341.667,188.117,492.161,312.842c53.113,44.019,97.855,57.149,168.115,39.807c282.858-69.817,566.762-62.872,848.142,14.45c22.306,6.13,37.312,0.398,53.849-13.211c146.079-120.208,301.569-226.569,469.85-313.378c82.594-42.607,166.081-84.101,258.279-102.554c69.601-13.93,118.517,10.478,152.784,73.34c31.44,57.675,48.713,120.352,63.919,183.539c53.108,220.68,74.886,444.756,64.006,671.278c-7.941,165.335-33.303,328.381-84.654,486.511c-4.452,13.71-7.84,28.535-15.646,40.221c-14.906,22.313-14.285,43.875-8.411,69.021c4.818,20.627,13.617,32.725,32.365,42.277c89.56,45.628,148.536,115.724,167.607,216.325c1.175,6.198,2.635,12.456,2.76,18.71c0.153,7.612,6.114,17.185-2.821,22.385c-7.283,4.238-13.146-3.59-19.086-7.068c-23.275-13.626-47.312-25.092-79.414-30.733c13.532,16.633,24.038,29.578,34.577,42.495c33.865,41.505,55.343,88.499,62.815,141.701c0.988,7.036,4.528,16.077-2.41,20.151c-9.551,5.61-13.747-5.307-18.869-10.499c-28.146-28.535-61.506-49.076-102.095-68.907c27.775,46.221,36.877,92.715,39.951,140.542c1.042,16.207,11.117,18.126,23.35,20.227c57.833,9.933,115.221,21.908,171.239,39.676C3977.002,2866.965,3987.258,2867.994,4000.205,2882.233zM2935.823,2973.96c15.457-7.201,26.421-5.068,36.907-3.886c212.433,23.948,425.105,46.573,631.884,104.618c16.414,4.608,27.087,1.514,34.109-15.805c22.762-56.137,33.086-114.076,29.822-174.608c-0.784-14.541-6.657-20.709-21.353-21.488c-58.534-3.106-116.988-9.127-175.541-10.174c-165.105-2.954-330.27-5.586-495.112,8.73c-8.768,0.761-19.354,3.968-27.176-6.574c3.776-1.841,6.036-3.717,8.495-4.029c113.621-14.427,227.51-26.289,341.834-33.373c108.037-6.694,216.12-11.508,324.436-6.143c29.158,1.444,32.389-5.083,19.218-31.08c-25.582-50.496-71.062-73.006-122.933-84.181c-93.859-20.222-188.442-15.419-282.755-3.247c-86.972,11.225-171.056,36.68-256.748,54.202c-177.977,36.392-328.993-12.464-448.027-150.211c-114.865-132.921-144.325-294.085-140.703-463.018c3.193-148.921,25.017-296.427,44.217-443.958c20.93-160.821,17.749-320.257-21.737-478.274c-3.976-15.912-9.937-25.552-27.807-27.048c-91.905-7.693-183.748-9.186-275.71-0.886c-14.167,1.279-20.454,7.581-23.775,20.799c-18.944,75.413-33.171,151.537-36.198,229.424c-5.107,131.386,14.768,260.865,29.755,390.747c16.943,146.83,39.949,293.363,24.743,442.027c-15.495,151.484-72.806,282.392-190.942,382.167c-97.405,82.266-208.526,122.776-337.822,107.395c-58.556-6.966-115.156-21.791-172.026-35.896c-127.083-31.52-255.433-48.026-386.15-30.165c-65.285,8.92-125.923,28.034-156.634,95.065c-10.485,22.883-8.079,27.574,17.377,25.675c74.869-5.585,149.562-2.397,224.452,0.131c138.983,4.692,277.115,18.134,415.005,34.88c12.25,1.488,26.142,0.973,38.604,9.818c-11.692,9.518-22.678,5.854-32.947,5.183c-35.991-2.353-71.909-6.913-107.918-7.699c-184.985-4.039-369.941-5.059-554.641,9.484c-17.196,1.354-23.526,8.274-24.099,25.029c-1.622,47.428,4.453,93.647,19.331,138.643c17.461,52.81,17.67,52.882,70.159,39.485c190.306-48.571,384.882-70.058,579.554-90.512c19.053-2.002,39.598-9.43,63.771,1.993c-36.458,14.51-70.784,15.732-104.064,21.215c-179.058,29.499-356.296,67.396-531.676,113.954c-31.024,8.236-31.238,9.451-12.416,34.153c31.911,41.879,70.332,77.236,110.519,110.996c15.045,12.639,27.618,14.366,46.078,5.81c146.754-68.024,298.618-122.906,452.367-172.708c9.344-3.027,19.025-9.924,30.305-4.156c-3.394,10.89-12.916,10.999-19.857,13.865c-141.899,58.595-280.916,123.259-415.891,196.49c-6.229,3.379-15.81,4.919-16.888,12.24c-1.458,9.897,9.406,11.968,15.916,15.909c116.087,70.292,239.459,121.561,374.087,143.887c81.425,13.502,160.589,35.18,233.872,74.083c190.069,100.903,392.142,139.483,606.545,125.73c124.322-7.975,242.528-33.817,354.191-89.253c99.685-49.49,201.479-92.71,312.517-110.916c134.446-22.043,257.825-74.233,374.698-142.839c7.449-4.372,20.406-6.584,20.003-15.914c-0.458-10.603-13.772-12.712-22.265-17.147c-136.88-71.486-277.09-135.79-419.863-194.58c-7.624-3.139-17.977-3.308-21.293-14.312c10.65-5.402,19.738,0.12,28.75,2.964c159.33,50.267,316.242,106.983,467.881,177.474c14.661,6.815,25.788,7.638,39.512-2.723c42.769-32.292,81.772-68.161,113.693-111.369c19.122-25.883,18.17-28.422-12.409-36.631c-186.612-50.093-375.433-89.816-565.999-121.574C2985.858,2987.98,2961.258,2987.908,2935.823,2973.96zM1281.025,2340.478c-0.292,25.475,0.979,50.709,7.329,75.353c29.748,115.455,94.975,200.333,215.801,224.98c123.09,25.109,227.085-16.089,303.031-116.404c58.651-77.471,73.689-168.004,56.757-262.411c-42.445-236.655-277.97-320.826-451.486-195.983C1319.76,2132.707,1281.851,2228.457,1281.025,2340.478zM3219.623,2326.925c1.327-78.92-28.602-155.021-85.684-221.364c-102.487-119.115-295.077-127.185-406.104-16.866c-59.902,59.52-88.767,132.247-93.621,215.612c-7.536,129.419,36.435,233.485,150.347,301.986c119.695,71.979,267.541,51.861,355.394-48.823C3194.986,2494.399,3220.217,2419.567,3219.623,2326.925z"
    static let maul = "M2587.388,3246.151c58.767,0.835,123.892-18.08,185.831-50.113c8.86-4.582,19.811-15.973,28.871-5.046c9.748,11.757-2.496,22.134-9.981,30.165c-30.058,32.251-66.12,56.741-108.106,69.622c-130.209,39.949-251.151,18.516-362.216-59.512c-24.697-17.35-42.169-41.823-59.487-66.093c-8.877-12.44-16.634-15.687-25.848-0.059c-85.849,145.597-316.867,177.343-450.847,113.782c-30.503-14.47-57.602-33.738-79.779-59.335c-6.9-7.964-17.323-17.589-9.972-28.305c8.341-12.159,19.929-2.334,28.93,2.152c78.311,39.034,160.255,59.952,248.376,51.654c61.116-5.754,118.891-21.871,170.198-56.59c47.907-32.417,75.336-76.446,74.933-136.046c-0.11-16.208-4.094-26.942-20.422-33.594c-28.175-11.479-47.909-31.578-54.813-62.461c-3.949-17.665-15.246-24.288-33.346-24.594c-32.947-0.558-64.025-8.942-92.518-26.492c-51.202-31.536-75.201-117.002,4.719-157.099c42.672-21.409,88.585-30.33,135.158-36.568c95.849-12.837,190.73-8.345,283.924,18.876c13.764,4.02,27.358,9.549,40.007,16.298c57.641,30.759,67.595,92.308,22.047,139.45c-30.372,31.435-68.575,46.929-112.212,43.958c-17.305-1.178-25.94,4.307-29.525,19.578c-8.382,35.705-30.86,58.475-64.479,70.731c-14.37,5.239-18.269,13.749-16.768,28.916c7.217,72.916,43.477,124.155,109.916,155.318C2449.054,3232.454,2510.856,3246.078,2587.388,3246.151zM2236.664,2817.76c68.724,0.05,128.029-2.673,186.101-17.334c10.045-2.536,24.124-3.545,24.4-17.1c0.267-13.084-12.905-16.25-23.229-18.868c-113.967-28.892-228.041-28.882-342,0.006c-11.109,2.816-24.889,5.951-24.2,21.017c0.64,13.987,14.33,14.605,24.461,16.785C2136.107,2813.862,2190.656,2819.289,2236.664,2817.76z"
    static let pupilleLinks = "M1817.408,2325.627c0.004,68.846-17.5,132.697-61.108,186.525c-82.668,102.043-234.578,95.345-312.245-12.335c-84.145-116.661-51.057-302.248,68.254-382.829c96.331-65.061,213.181-35.43,269.923,68.446C1805.378,2227.808,1817.196,2275.018,1817.408,2325.627z"
    static let pupilleRechts = "M3101.302,2347.486c-0.025,57.624-16.401,110.92-51.753,158.059c-69.818,93.097-202.719,104.582-288.289,24.934c-102.735-95.627-104.741-297.965-3.771-395.186c90.591-87.226,210.728-54.664,273.647,17.352C3079.756,2208.292,3101.458,2273.29,3101.302,2347.486z"
}

/// Zeichnet einen SVG-Pfad gleichmäßig skaliert in das Rechteck; `box` ist der gemeinsame Rahmen aller Teile.
struct VorlagenPfad: Shape {
    let pfad: Path
    let box: CGRect
    func path(in r: CGRect) -> Path {
        let s = min(r.width / box.width, r.height / box.height)
        let dx = r.midX - box.midX * s, dy = r.midY - box.midY * s
        return pfad.applying(CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s))
    }
}

struct KatzenKopf: View {
    let fuellung: AnyShapeStyle
    let blick: CGPoint
    let zu: Bool
    static let silhouette = SVGPfad.lesen(KatzenVorlage.silhouette)
    static let maul = SVGPfad.lesen(KatzenVorlage.maul)
    static let pupillen = [SVGPfad.lesen(KatzenVorlage.pupilleLinks), SVGPfad.lesen(KatzenVorlage.pupilleRechts)]
    static let box = silhouette.boundingRect
    /// Größter geschlossener Teilpfad der Silhouette = Außenkontur des Kopfs; hell gefüllt, damit nichts durchscheint.
    static let gesicht: Path = {
        let teile = KatzenVorlage.silhouette.split(whereSeparator: { $0 == "z" || $0 == "Z" }).map(String.init)
        let pfade = teile.map { SVGPfad.lesen($0 + "z") }
        return pfade.max { $0.boundingRect.width * $0.boundingRect.height < $1.boundingRect.width * $1.boundingRect.height } ?? silhouette
    }()

    var body: some View {
        GeometryReader { g in
            let r = CGRect(origin: .zero, size: g.size)
            let s = min(r.width / Self.box.width, r.height / Self.box.height)
            ZStack {
                // helles Gesicht hinter der Silhouette (die Vorlage lässt Gesicht und Augen frei)
                VorlagenPfad(pfad: Self.gesicht, box: Self.box).fill(Color(white: 0.96))
                VorlagenPfad(pfad: Self.silhouette, box: Self.box).fill(fuellung)
                VorlagenPfad(pfad: Self.maul, box: Self.box).fill(fuellung)
                ForEach(0..<2, id: \.self) { i in
                    let b = Self.pupillen[i].boundingRect
                    let mitte = CGPoint(x: r.midX + (b.midX - Self.box.midX) * s, y: r.midY + (b.midY - Self.box.midY) * s)
                    VorlagenPfad(pfad: Self.pupillen[i], box: Self.box).fill(fuellung)
                        .scaleEffect(y: zu ? 0.1 : 1, anchor: UnitPoint(x: mitte.x / r.width, y: mitte.y / r.height))
                        .offset(x: blick.x * b.width * s * 0.35, y: blick.y * b.height * s * 0.3)
                        .animation(.easeInOut(duration: 0.08), value: zu)
                }
            }
            .frame(width: g.size.width, height: g.size.height)
        }
    }
}



// MARK: - Hundeköpfe aus Mikes SVG-Vorlage (Dackel, Dogge, Frenchy)

enum HundeVorlage {
    static let dackel: [(rolle: String, deckkraft: Double, pfad: String)] = [
        ("koerper", 1.0, "M494.12,697.5c65.66-20.98,183.67-23.68,272.05-26.04,14.63-.39,29.78-1.04,42.89-7.55,30.89-15.34,38.35-55.16,57.33-83.95,22.44-34.03,62.7-52.83,102.99-58.98,149.29-22.78,199.47,50.97,205.46,68.9,22.45,67.22,16.58,140.09,12.94,210.88-.71,13.75-1.22,28.09,4.41,40.66,7.15,15.96,22.88,26.17,38.38,34.26,77.75,40.56,167.62,49.54,255.03,56.57,263.79,21.21,530.26,31.18,792.23-6.3,3.97,52.64,25.3,94.01,16.63,146.09-3.2,19.21-63.4,88.31-94.36,104.63-247.64,130.47-1062.4,142.53-1157.31,97.14-57.8-27.64-124.71-141.38-102.42-342.77,3.21-28.98-20.03-54.05-49.16-52.81-52.31,2.22-103.79-4.5-155.8-8.87-182.32-15.33-226.02-140.08-241.29-171.83h0Z"),
        ("koerper", 1.0, "M481.05,682.98c2.77,15.67,10.45,30.07,19.54,43.13,4.55,6.53,10.08,13.22,17.84,15.02,11.68,2.71,22.45-6.59,30.55-15.43,8.08-8.83,15.99-18.2,20.25-29.38,2.27-5.96,3.04-13.63-1.73-17.85-2.29-2.03-5.39-2.8-8.38-3.43-21.55-4.59-43.87-5.57-65.74-2.9-5.78.71-13.07,3.43-12.8,9.24l.47,1.61Z"),
        ("koerper", 1.0, "M1057.02,590.45c47.46,14.08,91.07,141.91,114.25,220.53,2.16,7.33,4.34,14.89,3.51,22.49-.75,6.85-3.9,13.17-7.07,19.29-31.48,60.72-73.92,120.3-136.64,147.55-9.3,4.04-20.44,7.2-29.2,2.09-6.97-4.07-10.31-12.22-12.77-19.9-14.7-45.9-14.76-95.41-8.12-143.14s19.76-94.29,31.1-141.14c4.54-18.76,8.7-39.04,1.33-56.88-2.78-6.73-7.16-12.98-8-20.21-1.53-13.28,9.96-25.24,22.78-29,12.83-3.76,15.68-4.11,28.83-1.69h0Z"),
        ("koerper", 1.0, "M936.00,639.87C936.00,653.05,925.32,663.73,912.14,663.73C898.96,663.73,888.28,653.05,888.28,639.87C888.28,626.69,898.96,616.01,912.14,616.01C925.32,616.01,936.00,626.69,936.00,639.87Z"),
        ("koerperHell2", 1.0, "M952.02,780.54c-11.23-12.33-32.11,2.62-98.49-12.63-41.58-9.55-51.09-44.14-70.49-47.1-11.68-1.78-171.04,50.62-258.69,35.91,31.56,46.92,91.5,103.41,210.35,113.4,52.01,4.37,103.49,11.09,155.8,8.87,29.13-1.23,52.37,23.84,49.16,52.81-1.69,15.24-2.86,29.98-3.56,44.22,1.1-1.31,2.18-2.63,3.21-4,20.42-26.97,26-62.31,26.88-96.12.56-21.66-.53-43.36-3.27-64.85-1.39-10.89-3.51-22.4-10.9-30.51Z"),
        ("koerperHell2", 1.0, "M905.1,596.72c26.5,1.33,49.85,25.33,50.47,51.85,12.72-3.13,21.73-16.6,25.09-29.27,1.92-7.23.21-16.16-1.73-23.39-1.67-6.22-6.05-11.38-10.94-15.59-10.22-8.8-23.86-14.42-37.21-12.44s-24.55,15.39-25.68,28.83h0Z"),
        ("koerperHell2", 1.0, "M1008.27,1047.35c-18.62-20.67-47.23-33.43-74.6-28.8,2.73,105.66,32.83,178.54,67.74,218.99,4.33-2.66,8.27-6.12,11.75-9.82,25.15-26.78,31.56-66.73,27.08-103.19-3.44-28.08-13.04-56.15-31.97-77.17Z"),
        ("koerperHell", 1.0, "M591.31,822.11c109.55,19.84,224.37,11.44,328.72-27.35-32,25.75-147.85,64.98-271.8,51.67-21.84-2.34-40.2-10.74-56.92-24.32h0Z"),
    ]
    static let dogge: [(rolle: String, deckkraft: Double, pfad: String)] = [
        ("koerper", 1.0, "M4047.23,4520.04c-7.54.01-17.23-6.61-21.16-13.04-3.93-6.43-5.4-14.05-6.32-21.54-2.02-16.41-1.73-33.11.86-49.44.53-3.37,1.13-7.02-.45-10.04-2.81-5.4-10.59-5.55-16.31-3.48-12.14,4.39-21.23,15.12-26.1,27.07s-5.97,25.11-6,38.02c-.06,26.2,4.66,53.71,21.08,74.12.66.81,1.47,1.69,2.51,1.69.87,0,1.61-.58,2.27-1.15,16.54-14.07,33.08-28.14,49.62-42.21h0Z"),
        ("koerper", 1.0, "M4252.21,4099.51L4206.29,4069.83L4171.21,4102.73L4195.04,4151.03L4252.21,4099.51Z"),
        ("koerper", 1.0, "M4631.31,4109.78c1.82-5,20.39-49.88,20.39-49.88l113.37,68.3-35.82,63.18-97.95-81.6Z"),
        ("fell", 1.0, "M4748.42,4311.17c11.9,47.25,12.45,102.59-20.1,138.86-18.82,20.97-45.96,32.33-72.77,41.01-139.48,45.15-291.58,34.16-434.43,1.16-17.73-4.1-35.87-8.74-50.59-19.42-34.75-25.19-39.76-74.87-35.47-117.57,17.31-172,134.53-374.92,307.25-382.13,130.01-5.42,272.81,205.91,306.1,338.09Z"),
        ("fellDunkel", 1.0, "M4128.81,4362.51c12.59-125.09,78.03-266.51,179.22-337.13-73.55,76.51-120.45,191.64-130.9,295.51-4.3,42.7.72,92.38,35.47,117.57,14.73,10.68,32.87,15.33,50.6,19.42,142.84,33,294.94,43.99,434.43-1.16,11.88-3.85,23.82-8.22,35.07-13.73-3.06,5.04-6.59,9.83-10.63,14.33-18.82,20.97-45.96,32.33-72.77,41.01-139.48,45.15-291.58,34.16-434.43,1.16-17.73-4.1-35.87-8.74-50.6-19.42-34.75-25.19-39.76-74.87-35.47-117.57Z"),
        ("koerper", 1.0, "M4580.9,4325.78c-14.44-18.96-36.22-36.81-58.91-44.11-104.48-33.62-172.75,108.91-159.04,149.14,6.59,19.32,27.72,29.61,47.42,34.98,41.72,11.36,75.44,13.92,118.39,8.94,22.04-2.55,55.86-12.29,72.9-26.51,17.04-14.21,34.83-49.41-20.76-122.44Z"),
        ("koerper", 1.0, "M4643.18,4328.85c-22.01-3.83-39.23-13.63-57.94-25.86-19.83-12.96-38.18-34.06-34.81-57.51,2.5-17.38,17.18-31.46,34.01-36.47,16.83-5,35.24-2.02,51.39,4.85,15.86,6.74,30.13,17.18,41.37,30.25,11.29,13.14,19.69,29.75,19.04,47.06s-12.21,34.82-29.14,38.49c-7.85,1.7-16,.44-23.93-.82h0Z"),
        ("koerper", 1.0, "M4353.51,4340.26c21.64-5.56,38.02-16.71,55.7-30.38,18.74-14.5,35.36-36.99,30.13-60.09-3.88-17.12-19.62-30-36.8-33.65-17.17-3.65-35.28.79-50.84,8.92-15.27,7.98-28.67,19.52-38.83,33.44-10.22,14-17.26,31.22-15.24,48.42s14.94,33.74,32.1,36.06c7.96,1.07,15.98-.83,23.79-2.72h0Z"),
        ("koerper", 1.0, "M4466.04,4308.32c.51,12.84,19.81,22.49,43.11,21.56,23.3-.93,41.77-12.08,41.26-24.92-.51-12.84-19.81-22.49-43.11-21.56-23.3.93-41.77,12.08-41.26,24.92Z"),
        ("koerper", 1.0, "M4572.06,4278.38c.56,14.18,12.52,25.22,26.7,24.65s25.22-12.52,24.65-26.7c-.56-14.18-12.52-25.22-26.7-24.65-14.18.56-25.22,12.52-24.65,26.7Z"),
        ("koerper", 1.0, "M4361.77,4287.46c.56,14.18,12.52,25.22,26.7,24.65s25.22-12.52,24.65-26.7-12.52-25.22-26.7-24.65-25.22,12.52-24.65,26.7Z"),
        ("koerper", 1.0, "M4672.74,4222.84l-80.65-43.67s10.35-33.73,15.4-33.93c5.04-.2,73.88,37.16,73.88,37.16l-8.63,40.44Z"),
        ("koerper", 1.0, "M4314.35,4238.52l76.93-49.94s-13-32.8-18.04-32.6c-5.04.2-70.69,42.91-70.69,42.91l11.81,39.63Z"),
        ("fellDunkel", 1.0, "M4525.99,4110.01c-10.1,31.71-4.99,75.04,3.25,107.29-26.69-28.55-28.17-77.18-3.25-107.29h0Z"),
        ("fellDunkel", 1.0, "M4465.39,4112.42c12.59,30.81,10.93,74.41,5.28,107.21,24.34-30.58,21.95-79.17-5.28-107.21h0Z"),
        ("fellDunkel", 1.0, "M4240.49,4118.88c6.09,17.23,12.18,34.46,18.27,51.69,2.92,8.26,5.85,16.58,7.08,25.25,1.36,9.61.58,19.42-1.22,28.95-1.37,7.23-3.41,14.53-7.68,20.52-9.03,12.68-26.7,16.97-41.92,13.68s-28.32-12.85-39.76-23.41c-1.25-1.16-2.55-2.42-2.97-4.08-.39-1.56.07-3.19.53-4.73,5.99-20.12,12.02-40.36,21.47-59.1s22.59-36.1,40.24-47.46l5.95-1.32Z"),
        ("koerper", 1.0, "M4799.27,4102.53c-2.34-4.63-38.55-28.31-43.4-30.15-44.28-16.79-48.68-18.51-95.93-15.39-3,.2-6.33.6-8.25,2.92-1.53,1.85-1.73,4.44-1.8,6.84-1.19,43.71,17.86,85.12,36.5,124.67,5.37,11.4,12.76,24.32,25.28,25.76,5.47.63,10.93-1.19,15.89-3.57,19.49-9.36,33.47-27.18,45.16-45.37,16.31-25.39,16.67-37.2,26.56-65.71h0Z"),
        ("koerper", 1.0, "M4212.62,4067.81c-2.47-.77-5.02-.65-7.54-.07-2.73.63-5.42,1.8-7.95,2.99-44.49,20.91-92.39,54.16-99.11,95.31-4.81,29.45,59.34,56.33,102.29,70.98,12.38,4.22,27.35,8.04,37.46-.26,4.42-3.62,7-9.01,8.81-14.43,7.09-21.29,3.89-44.59-1.24-66.44-7.16-30.49-17.96-60.13-32.08-88.08h-.64Z"),
        ("zunge", 1.0, "M4518.64,4405.14c-15.39-2.73-31.52,13.66-39.01,27.37-7.49,13.71-9.61,29.6-13.61,44.7s-10.81,30.68-24.16,38.8c-5.41,3.29-11.58,5.14-17.79,6.38-18.63,3.71-39.41,1.62-54.2-10.29s-20.97-35.19-10.11-50.77c5.4-7.74,13.93-12.63,20.54-19.37,9.88-10.07,15.17-24.47,14.15-38.54,14.07,5.15,28.64,10.38,43.6,9.55,25.38-1.41,46.25-19.62,64.94-36.85,2.54,10.83,8.01,20.95,15.66,29.02h0Z"),
        ("zungeDunkel", 1.0, "M4467.45,4409.89c-13.35,4.49-24.92,14.08-31.81,26.36-6.18,11.02-8.61,23.83-14.88,34.8-6.1-18.8-5.84-39.61.73-58.25,7.64,4.39,16.84,6,25.52,4.46l20.44-7.37Z"),
        ("koerper", 1.0, "M4615.45,4402.38c-28.11,17.01-68.18,10.39-89.33-14.75-18.94-22.52-21.7-54.06-23.63-83.42,1.04,20.42,1.98,41.51-5.2,60.65-7.25,19.33-22.87,35.37-42.01,43.11-19.14,7.75-67.83-17.56-86.49-26.41,1.91,4.3,13.52,23.1,36.78,33.67,34.11,15.51,79.13.83,96.4-32.43,8.46,22.27,29.46,39.29,53.01,42.95,23.55,3.66,48.72-6.18,63.55-24.83l-3.08,1.45Z"),
    ]
    static let frenchy: [(rolle: String, deckkraft: Double, pfad: String)] = [
        ("koerper", 1.0, "M2333.54,2172c-35.86-15.58-67.22-42.05-89.18-75.27-30.73,38.33-61.46,76.66-92.18,114.99-20.57,25.66-41.41,51.58-67.32,71.4,8.44,6.03,19.02,7.67,29.23,8.69,13.07,1.31,26.22,1.86,39.35,1.66,15.93-.24,32.17-1.67,46.82-8.14,30.29-13.36,48.28-45.23,64.18-75.07,11.4,9.15,23.52,17.34,36.19,24.47,1.74.98,3.74,1.97,5.62,1.34,1.55-.51,2.59-1.98,3.52-3.37,10.71-15.94,21.42-31.87,32.13-47.81-3.24-5.85-8.11-10.71-13.88-13.84"),
        ("koerper", 1.0, "M2933.03,2172c35.86-15.58,67.22-42.05,89.18-75.27,30.73,38.33,61.46,76.66,92.18,114.99,20.57,25.66,41.41,51.58,67.32,71.4-8.44,6.03-19.02,7.67-29.23,8.69-13.08,1.31-26.22,1.86-39.35,1.66-15.93-.24-32.17-1.67-46.82-8.14-30.29-13.36-48.28-45.23-64.18-75.07-11.4,9.15-23.52,17.34-36.19,24.47-1.74.98-3.74,1.97-5.62,1.34-1.55-.51-2.59-1.98-3.52-3.37-10.71-15.94-21.42-31.87-32.13-47.81,3.24-5.85,8.11-10.71,13.88-13.84"),
        ("koerperHell2", 1.0, "M2936.58,2173.96c-63.8-40.49-111.81-13.77-148.87-6.81-112.35,21.08-182.82,26.07-294.46,1.26-32.09-7.13-64.12-16.18-96.94-16.82-32.82-.64-67.37,8.25-90.62,32.23-25.26,26.06-33.06,65.04-35.62,101.86-16.69,240.07,49.89,296.96,102,313.18,45.06,14.03,144.02-18.64,249.06-19.3,100.31-.63,206.51,31.63,262.45,7.74,107.79-46.04,175.66-335.49,53-413.34Z"),
        ("koerperHell", 0.46, "M2407.93,2602.09c-15.38.74-28.52-.02-38.83-3.23-52.1-16.22-118.69-73.11-102-313.18,2.56-36.82,10.35-75.8,35.62-101.86,23.25-23.98,57.81-32.88,90.62-32.23,32.82.64,64.85,9.69,96.94,16.82,111.63,24.81,182.11,19.82,294.46-1.26,5.74-1.08,11.74-2.63,18.02-4.33-13.6,17.27-32.38,31.01-52.42,39.23-39.57,16.23-83.39,15.69-125.95,15.86-53.74.21-107.75,1.94-160.56,12.27-20.75,4.06-42.21,9.95-57.8,24.69-10.1,9.54-17.01,22.17-22.53,35.11-34.18,80.13-19.29,173.33,6.07,256.9,5.64,18.57,11.77,36.99,18.36,55.22Z"),
        ("koerper", 1.0, "M2830.62,2342.42C2830.62,2360.40,2816.54,2374.98,2799.16,2374.98C2781.78,2374.98,2767.70,2360.40,2767.70,2342.42C2767.70,2324.44,2781.78,2309.86,2799.16,2309.86C2816.54,2309.86,2830.62,2324.44,2830.62,2342.42Z"),
        ("koerper", 1.0, "M2438.04,2325.89c12.28-12.72,32.2-12.72,44.48,0,12.28,12.72,12.28,33.33,0,46.05s-32.2,12.72-44.48,0-12.28-33.33,0-46.05Z"),
        ("koerper", 0.46, "M2866.87,2332.39L2774.68,2283.84L2806.14,2238.76L2883.19,2285.58L2866.87,2332.39Z"),
        ("koerper", 0.46, "M2389.25,2331.09L2481.44,2282.54L2449.98,2237.46L2372.93,2284.28L2389.25,2331.09Z"),
        ("koerper", 1.0, "M2267.95,2574.12c3.04-24.4,19.71-45.18,39.68-58.52,19.98-13.34,43.02-20.9,65.99-27.26,118.98-32.93,146.64-165.35,177.6-193.3,8.17-7.38,17.57-13.49,27.95-16.73,10.71-3.34,22.1-3.53,33.26-2.79,1.58.1,3.17.25,4.75.4,1.58-.15,3.17-.29,4.75-.4,11.16-.74,22.55-.55,33.26,2.79,10.38,3.24,19.78,9.35,27.95,16.73,30.96,27.95,58.62,160.37,177.6,193.3,22.96,6.36,46.01,13.92,65.99,27.26,19.98,13.34,36.64,34.12,39.68,58.52,4.83,38.76-26.94,74.59-63.21,85.48-36.26,10.89-75.18,2.62-111.42-8.37-41.36-12.54-105.05-57.44-174.61-67.26-69.56,9.82-133.24,54.73-174.61,67.26-36.24,10.99-75.15,19.26-111.42,8.37-36.26-10.89-68.04-46.71-63.21-85.48Z"),
        ("koerper", 1.0, "M2547.2,2316.89c0,22.85,31.33,41.36,69.99,41.36s69.99-18.52,69.99-41.36-31.33-59.66-69.99-59.66-69.99,36.82-69.99,59.66Z"),
        ("koerper", 1.0, "M2617.18,2358.25c-1.81,27.62,5.5,95.69,8.31,101.5,3.08,6.37,9.35,10.29,15.32,13.83,45.26,26.85,91.49,51.96,138.55,75.27,30.26,14.99,63.06,31.34,78.26,62.3-72.9-36.17-146.72-70.38-221.34-102.58-6.49-2.8-17.71-7.79-21.42-13.97-2.21-3.69-7.51-87.7-2.96-136.34.48-5.15,5.28,0,5.28,0"),
        ("weiss", 1.0, "M2810.63,2587.76c-.9-32.87-9.07-65.5-23.72-94.67-15.73,20.31-29.8,41.99-42.04,64.73,22.99,9.93,42.77,20,65.76,29.94"),
        ("koerper", 1.0, "M2611.9,2358.25c1.81,27.62-5.5,95.69-8.31,101.5-3.08,6.37-9.35,10.29-15.32,13.83-45.26,26.85-91.49,51.96-138.55,75.27-30.26,14.99-63.06,31.34-78.26,62.3,72.9-36.17,146.72-70.38,221.34-102.58,6.49-2.8,16.96-7.79,20.66-13.97,2.44-4.08,4.99-88.48-1.57-136.34"),
        ("weiss", 1.0, "M2438.11,2579.67c.9-32.87,9.07-65.5,23.72-94.67,15.73,20.31,29.8,41.99,42.04,64.73-22.99,9.93-42.77,20-65.76,29.94"),
        ("koerper", 1.0, "M2866.87,2321.99L2774.68,2273.44L2806.14,2228.36L2883.19,2275.18L2866.87,2321.99Z"),
        ("koerper", 1.0, "M2389.25,2320.69L2481.44,2272.14L2449.98,2227.06L2372.93,2273.87L2389.25,2320.69Z"),
    ]
    /// Schnitt in Vorlagen-Koordinaten (x, y, maxX, maxY): der Dackel wird am Hals und über den Beinen abgeschnitten.
    static func schnitt(_ art: Skin) -> CGRect? { art == .dackel ? CGRect(x: 0, y: 0, width: 1185, height: 1020) : nil }
}

/// Zeichnet eine Figur aus der Vorlage; Farben folgen der Leiste: dunkel = Körperfarbe, Zwischentöne aufgehellt, Fell hell, Zunge rot.
struct HundFigur: View {
    let art: Skin
    let fuellung: AnyShapeStyle
    static var cache: [Skin: ([Path], CGRect)] = [:]
    static func teile(_ art: Skin) -> [(rolle: String, deckkraft: Double, pfad: String)] {
        switch art { case .dackel: HundeVorlage.dackel; case .bulldogge: HundeVorlage.dogge; default: HundeVorlage.frenchy }
    }
    static func pfade(_ art: Skin) -> ([Path], CGRect) {
        if let c = cache[art] { return c }
        let p = teile(art).map { SVGPfad.lesen($0.pfad) }
        var b = p.map(\.boundingRect).reduce(CGRect.null) { $0.union($1) }
        if let s = HundeVorlage.schnitt(art) { b = b.intersection(s) }
        cache[art] = (p, b); return (p, b)
    }
    static func box(_ art: Skin) -> CGRect { pfade(art).1 }

    @ViewBuilder private func teil(_ i: Int, _ pfade: [Path], _ box: CGRect) -> some View {
        let form = VorlagenPfad(pfad: pfade[i], box: box)
        let t = Self.teile(art)[i]
        Group {
            switch t.rolle {
            case "fell": form.fill(Color(white: 0.96))
            case "fellDunkel": form.fill(Color(white: 0.82))
            case "weiss": form.fill(.white)
            case "zunge": form.fill(Color(red: 0.86, green: 0.2, blue: 0.19))
            case "zungeDunkel": form.fill(Color(red: 0.72, green: 0.15, blue: 0.15))
            case "akzent": form.fill(Color(red: 0.8, green: 0.4, blue: 0.4))
            case "koerperHell": ZStack { form.fill(fuellung); form.fill(Color.white.opacity(0.28)) }
            case "koerperHell2": ZStack { form.fill(fuellung); form.fill(Color.white.opacity(0.45)) }
            default: form.fill(fuellung)
            }
        }
        .opacity(t.deckkraft)
    }

    var body: some View {
        let (pfade, box) = Self.pfade(art)
        ZStack {
            ForEach(0..<pfade.count, id: \.self) { i in teil(i, pfade, box) }
        }
        // Schnitt mit runden Ecken, damit am Hals keine gerade Kante steht
        .clipShape(VorlagenPfad(pfad: Path(roundedRect: box, cornerRadius: box.height * 0.28), box: box))
    }
}
