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
        case .katze: (Skin.dockt ? 0 : 26, Skin.dockt ? 30 : 16, 12, 34)
        case .dackel: (Skin.dockt ? 0 : 18, Skin.dockt ? 26 : 14, 34, 46)
        case .bulldogge: (Skin.dockt ? 0 : 22, Skin.dockt ? 26 : 12, 12, 22)
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
                let dock: CGFloat = Skin.dockt ? (art == .katze ? 26 : art == .dackel ? 20 : 22) : 0
                ZStack(alignment: .topLeading) {
                    // Kopf: Katze aus Mikes SVG-Vorlage, Hunde gezeichnet
                    if art == .katze {
                        KatzenKopf(fuellung: fuellung, blick: b, zu: blinzelt)
                            .frame(width: kopf * 1.7, height: kopf * 1.7)
                            .position(x: kopf * 0.78, y: hoehe / 2 - 2 + dock)
                    } else if art == .bulldogge {
                        MopsKopf(fuellung: fuellung, blick: b, zu: blinzelt)
                            .frame(width: kopf * 1.5, height: kopf * 1.5)
                            .position(x: kopf * 0.7, y: hoehe / 2 - 2 + dock)
                    } else {
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
                    }

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

    var body: some View {
        GeometryReader { g in
            let r = CGRect(origin: .zero, size: g.size)
            let s = min(r.width / Self.box.width, r.height / Self.box.height)
            ZStack {
                // helles Gesicht hinter der Silhouette (die Vorlage lässt das Gesicht frei)
                Ellipse().fill(Color(white: 0.96)).frame(width: Self.box.width * s * 0.6, height: Self.box.height * s * 0.64).offset(y: -Self.box.height * s * 0.02)
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


// MARK: - Mopskopf aus Mikes Vorlage (Freepik „Flat Pug Collection“, erster Kopf)

enum MopsVorlage {
    /// (Rolle, SVG-Pfad) in Zeichenreihenfolge; Augen sind die Teile 3–6.
    static let teile: [(rolle: String, pfad: String)] = [
        ("fell", "M142.813,200.935c0,20.081-16.43,36.513-36.513,36.513H80.375c-20.082,0-36.512-16.432-36.512-36.513v-17.162c0-20.082,16.43-36.514,36.512-36.514H106.3c20.083,0,36.513,16.432,36.513,36.514V200.935z"),
        ("koerper", "M71.05,148.681c0,0-5.605-4.179-11.22-3.828c-5.615,0.352-23.512,7.019-23.512,35.093c0,0,0.701,10.177,12.282,0C60.181,169.769,69.636,158.475,71.05,148.681z"),
        ("koerper", "M115.626,148.681c0,0,5.604-4.179,11.221-3.828c5.615,0.352,23.512,7.019,23.512,35.093c0,0-0.701,10.177-12.282,0C126.495,169.769,117.039,158.475,115.626,148.681z"),
        ("koerper", "M78.103,191.858c0,4.855-3.936,8.792-8.793,8.792c-4.854,0-8.792-3.937-8.792-8.792c0-4.857,3.938-8.794,8.792-8.794C74.166,183.065,78.103,187.001,78.103,191.858z"),
        ("weiss", "M70.342,188.738c0,1.723-1.396,3.12-3.12,3.12c-1.723,0-3.12-1.397-3.12-3.12c0-1.723,1.397-3.12,3.12-3.12C68.946,185.618,70.342,187.015,70.342,188.738z"),
        ("koerper", "M126.159,191.858c0,4.855-3.936,8.792-8.793,8.792c-4.854,0-8.792-3.937-8.792-8.792c0-4.857,3.938-8.794,8.792-8.794C122.223,183.065,126.159,187.001,126.159,191.858z"),
        ("weiss", "M118.399,188.738c0,1.723-1.397,3.12-3.12,3.12c-1.722,0-3.12-1.397-3.12-3.12c0-1.723,1.397-3.12,3.12-3.12C117.002,185.618,118.399,187.015,118.399,188.738z"),
        ("fellDunkel", "M81.674,167.224c2.961,3.93,2.601,9.024,0,13.018c-0.62,0.951,0.9,1.829,1.515,0.885c2.903-4.459,3.327-10.374,0-14.789C82.518,165.446,80.993,166.319,81.674,167.224L81.674,167.224z"),
        ("fellDunkel", "M107.414,167.224c-2.961,3.93-2.603,9.024,0,13.018c0.619,0.951-0.901,1.829-1.517,0.885c-2.903-4.459-3.326-10.374,0-14.789C106.57,165.446,108.095,166.319,107.414,167.224L107.414,167.224z"),
        ("koerperHell", "M120.884,213.284c-10.294-12.4-27.546-12.399-27.546-12.399s-17.252-0.001-27.546,12.399c-10.295,12.4-6.784,27.606,1.404,29.712c8.188,2.105,16.96-2.106,26.143-2.106c9.183,0,17.956,4.211,26.143,2.106C127.668,240.89,131.18,225.684,120.884,213.284z"),
        ("koerper", "M107.459,234.257c-4.387-2.352-8.774-4.703-13.161-7.055c0-4.594,0-9.188,0-13.782c4.012-1.759,5.837-6.948,5.837-6.948c-2.202-1.652-6.714-1.542-6.714-1.542s-4.513-0.11-6.715,1.542c0,0,1.825,5.188,5.837,6.947c0,4.565,0,9.13,0,13.695c-4.442,2.381-8.883,4.762-13.325,7.143c-0.999,0.535-0.111,2.05,0.886,1.515c4.412-2.365,8.822-4.73,13.234-7.095c4.412,2.365,8.823,4.729,13.234,7.095C107.57,236.307,108.456,234.792,107.459,234.257z"),
    ]
    static let augen = [3, 4, 5, 6]
}

/// Farben folgen der Leiste: dunkle Teile = Körperfarbe, Schnauze heller, Fell hell, Glanzpunkte weiß.
struct MopsKopf: View {
    let fuellung: AnyShapeStyle
    let blick: CGPoint
    let zu: Bool
    static let pfade = MopsVorlage.teile.map { SVGPfad.lesen($0.pfad) }
    static let box = pfade.map(\.boundingRect).reduce(CGRect.null) { $0.union($1) }

    @ViewBuilder private func teil(_ i: Int, _ s: CGFloat, _ r: CGRect) -> some View {
        let form = VorlagenPfad(pfad: Self.pfade[i], box: Self.box)
        switch MopsVorlage.teile[i].rolle {
        case "fell": form.fill(Color(white: 0.96))
        case "fellDunkel": form.fill(Color(white: 0.78))
        case "weiss": form.fill(.white)
        case "koerperHell": ZStack { form.fill(fuellung); form.fill(Color.white.opacity(0.32)) }
        default: form.fill(fuellung)
        }
    }

    var body: some View {
        GeometryReader { g in
            let r = CGRect(origin: .zero, size: g.size)
            let s = min(r.width / Self.box.width, r.height / Self.box.height)
            ZStack {
                ForEach(0..<MopsVorlage.teile.count, id: \.self) { i in
                    if MopsVorlage.augen.contains(i) {
                        let b = Self.pfade[i].boundingRect
                        let mitte = CGPoint(x: r.midX + (b.midX - Self.box.midX) * s, y: r.midY + (b.midY - Self.box.midY) * s)
                        teil(i, s, r)
                            .scaleEffect(y: zu ? 0.1 : 1, anchor: UnitPoint(x: mitte.x / r.width, y: mitte.y / r.height))
                            .offset(x: blick.x * 1.6 * s, y: blick.y * 1.4 * s)
                            .animation(.easeInOut(duration: 0.08), value: zu)
                    } else {
                        teil(i, s, r)
                    }
                }
            }
            .frame(width: g.size.width, height: g.size.height)
        }
    }
}
