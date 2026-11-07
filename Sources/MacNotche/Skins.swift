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
        case .katze: (Skin.dockt ? 0 : 12, Skin.dockt ? 16 : 4, 0, 34)
        case .dackel: (Skin.dockt ? 0 : 18, Skin.dockt ? 26 : 14, 34, 46)
        case .bulldogge: (Skin.dockt ? 0 : 14, Skin.dockt ? 20 : 8, 6, 22)
        case .tropfend: (0, 56, 0, 0)
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
                let dock: CGFloat = Skin.dockt ? (art == .katze ? 16 : art == .dackel ? 20 : 12) : 0
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
                            // Bulldogge von vorn: breiter Kopf, Faltohren mit rosa Innenseite, helle Lefzen und Blesse, schwarze Nase
                            let b = kopf * 1.3, rosa = Color(red: 0.93, green: 0.70, blue: 0.78)
                            Capsule().fill(fell).frame(width: kopf * 0.5, height: 8).offset(x: -kopf * 0.15, y: kopf * 0.58)
                            Capsule().fill(fell).frame(width: kopf * 0.5, height: 8).offset(x: kopf * 0.3, y: kopf * 0.58)
                            ForEach([-1.0, 1.0], id: \.self) { s in
                                ZStack {
                                    RoundedRectangle(cornerRadius: 5).fill(fuellung).frame(width: kopf * 0.3, height: kopf * 0.38)
                                    RoundedRectangle(cornerRadius: 3).fill(rosa).frame(width: kopf * 0.16, height: kopf * 0.24).offset(y: 2)
                                }
                                .rotationEffect(.degrees(s * 28))
                                .offset(x: s * b * 0.42, y: -kopf * 0.36)
                            }
                            RoundedRectangle(cornerRadius: kopf * 0.36).fill(fuellung).frame(width: b, height: kopf)
                            // Lefzen: helle breite Fläche unten, Blesse hoch bis zur Stirn
                            Ellipse().fill(fell).frame(width: b * 0.92, height: kopf * 0.62).offset(y: kopf * 0.22)
                            Capsule().fill(fell).frame(width: kopf * 0.16, height: kopf * 0.55).offset(y: -kopf * 0.12)
                            // Stirnfalte
                            Capsule().fill(Color.black.opacity(0.35)).frame(width: kopf * 0.34, height: 2).offset(y: -kopf * 0.3)
                            // Nase und Maul
                            RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.12)).frame(width: kopf * 0.3, height: kopf * 0.2).offset(y: kopf * 0.06)
                            Capsule().fill(Color.black.opacity(0.45)).frame(width: 2, height: kopf * 0.14).offset(y: kopf * 0.22)
                        }
                        if art == .katze { RoundedRectangle(cornerRadius: kopf * 0.34).fill(fuellung).frame(width: kopf, height: kopf) }
                        if art != .dackel {
                            HStack(spacing: art == .bulldogge ? kopf * 0.3 : kopf * 0.14) {
                                Auge(blick: b, zu: blinzelt)
                                Auge(blick: b, zu: blinzelt)
                            }
                            .offset(y: art == .bulldogge ? -kopf * 0.12 : -kopf * 0.06)
                        }
                    }
                    .frame(width: kopf, height: kopf)
                    .position(x: kopf / 2 + 2, y: hoehe / 2 - 3 + dock)

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
                            Capsule().fill(fell).frame(width: 18, height: 8).position(x: g.size.width - 8, y: hoehe + 1)
                        } else {
                            Kringel().stroke(fuellung, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .frame(width: 16, height: 16)
                                .rotationEffect(.degrees(wedel * 0.5), anchor: .leading)
                                .position(x: g.size.width + 5, y: hoehe / 2 + 4)
                            Capsule().fill(fell).frame(width: 16, height: 7).position(x: g.size.width - 6, y: hoehe + 1)
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
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + 3))
        p.addQuadCurve(to: CGPoint(x: r.midX - 2, y: r.maxY - 4), control: CGPoint(x: r.minX + 2, y: r.maxY - 2))
        p.addQuadCurve(to: CGPoint(x: r.maxX - 3, y: r.midY + 2), control: CGPoint(x: r.maxX, y: r.maxY + 2))
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


