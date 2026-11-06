import SwiftUI
import EventKit
import UniformTypeIdentifiers

private let deutsch = Locale(identifier: "de_DE")

func farbe(_ anteil: Double) -> Color { anteil < 0.6 ? .green : anteil < 0.85 ? .orange : .red }

func kurz(_ n: Int) -> String {
    let f = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1)).locale(deutsch)
    if n >= 1_000_000 { return (Double(n) / 1e6).formatted(f) + " Mio." }
    if n >= 1_000 { return (Double(n) / 1e3).formatted(f) + " Tsd." }
    return "\(n)"
}

func zeit(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }

extension Text {
    func kopf() -> some View { font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.5)) }
}

// MARK: - Island-Form

/// Dynamic-Island-Profil: oben weiche „Ohren“, die in die Bildschirmkante auslaufen, unten große Rundungen.
struct Island: Shape {
    var unten: CGFloat
    static let ohr: CGFloat = 12
    var animatableData: CGFloat { get { unten } set { unten = newValue } }

    func path(in r: CGRect) -> Path {
        let o = Self.ohr, u = min(unten, (r.height - o) / 2, (r.width - 2 * o) / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        // rechtes Ohr: konkav von der Kante in den Körper
        p.addRelativeArc(center: CGPoint(x: r.maxX, y: r.minY + o), radius: o, startAngle: .degrees(270), delta: .degrees(-90))
        p.addLine(to: CGPoint(x: r.maxX - o, y: r.maxY - u))
        p.addRelativeArc(center: CGPoint(x: r.maxX - o - u, y: r.maxY - u), radius: u, startAngle: .degrees(0), delta: .degrees(90))
        p.addLine(to: CGPoint(x: r.minX + o + u, y: r.maxY))
        p.addRelativeArc(center: CGPoint(x: r.minX + o + u, y: r.maxY - u), radius: u, startAngle: .degrees(90), delta: .degrees(90))
        p.addLine(to: CGPoint(x: r.minX + o, y: r.minY + o))
        p.addRelativeArc(center: CGPoint(x: r.minX, y: r.minY + o), radius: o, startAngle: .degrees(0), delta: .degrees(-90))
        p.closeSubpath()
        return p
    }
}

// MARK: - Wurzel

struct NotchAnsicht: View {
    @EnvironmentObject var m: NotchModell
    @State private var ziel = false
    @AppStorage(E.look) private var look = "schwarz"
    @Environment(\.colorScheme) private var system

    private var schema: ColorScheme {
        switch look { case "hell": .light; case "schwarz", "dunkel": .dark; default: system }
    }
    private var hintergrund: AnyShapeStyle {
        switch look {
        case "schwarz": AnyShapeStyle(Color.black)
        case "glas": AnyShapeStyle(.ultraThinMaterial)
        default: AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var unten: CGFloat { switch m.zustand { case .offen: 28; case .meldung: 20; case .zu: 14 } }

    var body: some View {
        ZStack(alignment: .top) {
            Island(unten: unten).fill(hintergrund)
            Group {
                switch m.zustand {
                case .zu: Kompakt()
                case .meldung: MeldungAnsicht()
                case .offen: Offen()
                }
            }
            .padding(.horizontal, Island.ohr)  // Inhalt bleibt neben den Ohren
        }
        // Inhalt nie über die Form hinaus zeichnen (sonst wirken die Ecken abgeschnitten).
        .clipShape(Island(unten: unten))
        .environmentObject(m.musik)
        .environmentObject(m.kalender)
        .environmentObject(m.claude)
        .environmentObject(m.andereKIs)
        .environmentObject(m.ablage)
        .environmentObject(m.wetter)
        .environmentObject(m.iphone)
        .environmentObject(m.mitteilungen)
        .environmentObject(m.wach)
        .environmentObject(m.zwischenablage)
        .environmentObject(m.spiegel)
        .environmentObject(m.geraete)
        .environmentObject(m.fokus)
        .environmentObject(m.audio)
        .environmentObject(m.kurse)
        .environmentObject(m.fragen)
        .environmentObject(m.sport)
        .environmentObject(m.appTon)
        .environmentObject(m.systemAnzeige)
        .environmentObject(m.zuhause)
        .environmentObject(m.diktat)
        .environmentObject(m.agent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover { m.hover($0) }
        .onDrop(of: [.fileURL], isTargeted: $ziel) { m.ablage.hinzu($0) }
        .onChange(of: ziel) { _, an in if an { m.reiter = .ablage; m.zustand = .offen } }
        .animation(.spring(duration: 0.3), value: m.zustand)
        .environment(\.colorScheme, schema)
    }
}

// MARK: - Zugeklappt

struct Kompakt: View {
    @EnvironmentObject var m: NotchModell
    @EnvironmentObject var musik: Musik
    @EnvironmentObject var claude: ClaudeUsage
    @EnvironmentObject var wetter: Wetter
    @EnvironmentObject var wach: WachHalten
    @EnvironmentObject var fokus: FokusTimer
    @AppStorage(E.zeigeMusik) private var zeigeMusik = true
    @AppStorage(E.zeigeClaude) private var zeigeClaude = true
    @AppStorage(E.zeigeWetter) private var zeigeWetter = true
    @AppStorage(E.zeigeTermin) private var zeigeTermin = true
    @EnvironmentObject var kalender: Kalender
    @AppStorage(E.zuKI) private var zuKI = "auto"
    @AppStorage(E.zuAus) private var zuAus = ""  // KIs, die der Nutzer hier nicht sehen will (z. B. ohne Konto)
    @EnvironmentObject var k: AndereKIs

    /// Kontingent-Paare (Kurzname, Prozent) für die gewählte KI; „auto“ nimmt die erste mit Daten.
    private func paare(_ ki: KI) -> [(String, Double)] {
        if zuAus.split(separator: ",").contains(Substring(ki.rawValue)) { return [] }
        switch ki {
        case .claude:
            // 5-Std.-Fenster nur, wenn Anthropic es für den Plan mitschickt (Max 20× hat keins); Woche immer.
            return [("5h", claude.fuenfStundenProzent), ("Wo", claude.limits.first { $0.id == "seven_day" }?.prozent)].compactMap { n, p in p.map { (n, $0) } }
        case .chatgpt:
            return [("5h", k.codexLimits.first { $0.id == "codex-primary" }?.prozent), ("Wo", k.codexLimits.first { $0.id == "codex-secondary" }?.prozent)].compactMap { n, p in p.map { (n, $0) } }
        case .gemini:
            return k.agyLimits.prefix(2).map { (String($0.name.prefix(6)), $0.prozent) }
        case .grok, .perplexity, .mistral:
            return []  // kein Abo-Kontingent auslesbar
        }
    }
    private var auslastung: (KI, [(String, Double)])? {
        guard zuKI != "alle" else { return nil }
        let reihe: [KI] = KI(rawValue: zuKI).map { [$0] } ?? [.claude, .chatgpt, .gemini]
        for ki in reihe { let p = paare(ki); if !p.isEmpty { return (ki, p) } }
        return nil
    }
    /// „Alle“: je KI ein Ring mit dem Wochenwert (sonst dem ersten Wert), kompakt.
    private var alle: [(KI, Double)] {
        guard zuKI == "alle" else { return [] }
        return KI.allCases.compactMap { ki in
            let p = paare(ki)
            guard let w = p.first(where: { $0.0 == "Wo" }) ?? p.first else { return nil }
            return (ki, w.1)
        }
    }

    private func breite(_ termin: Bool) { m.zuExtraBreite = CGFloat(max(0, alle.count - 1)) * 70 + (termin ? 80 : 0) + (fokus.name.isEmpty ? 0 : CGFloat(min(fokus.name.count, 12)) * 7) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { tl in
            inhalt(termin: zeigeTermin ? TerminCountdown.naechster(kalender.termine, jetzt: tl.date) : nil, jetzt: tl.date)
        }
    }

    private func inhalt(termin: EKEvent?, jetzt: Date) -> some View {
        HStack(spacing: 8) {
            if zeigeMusik, let t = musik.titel, t.spielt {
                CoverBild(groesse: 18)
                Equalizer()
            } else if zeigeWetter, let j = wetter.jetzt {
                Image(systemName: Wetter.beschreibung(j.code, tag: j.tag).symbol).symbolRenderingMode(.multicolor)
                Text("\(Int(j.temp.rounded()))°")
            } else {
                Image(systemName: "sparkle").foregroundStyle(Color.primary.opacity(0.5))
            }
            if wach.bis != nil { Image(systemName: "cup.and.saucer.fill").foregroundStyle(.orange) }
            Spacer()
            if let termin {
                // Ab 10 Minuten vorher orange; Klick öffnet den Videocall (sonst den Kalender).
                let bald = termin.startDate.timeIntervalSince(jetzt) <= 600
                HStack(spacing: 4) {
                    Image(systemName: TerminCountdown.anrufLink(termin) != nil ? "video.fill" : "calendar")
                    if termin.startDate > jetzt { Restzeit(ende: termin.startDate) } else { Text("jetzt") }
                }
                .foregroundStyle(bald ? Color.orange : Color.primary)
                .fixedSize()
                .contentShape(Rectangle())
                .onTapGesture { TerminCountdown.oeffnen(termin) }
                .help(termin.title ?? "")
            }
            if let ende = fokus.ende {
                Image(systemName: fokus.art == .fokus ? "brain.head.profile" : fokus.art == .pause ? "cup.and.saucer" : "timer")
                    .foregroundStyle(.orange)
                Restzeit(ende: ende)
                if !fokus.name.isEmpty { Text(fokus.name).lineLimit(1).fixedSize().foregroundStyle(Color.primary.opacity(0.7)) }
            }
            if zeigeClaude, !alle.isEmpty {
                ForEach(alle, id: \.0) { ki, p in
                    Image(systemName: ki.symbol).foregroundStyle(Color.primary.opacity(0.5))
                    Ring(anteil: p / 100).frame(width: 13, height: 13)
                    Text("\(Int(p.rounded()))%").fixedSize()
                }
            } else if zeigeClaude, let (ki, paare) = auslastung {
                // Platz ist knapp: Symbol der KI nur, wenn ein Paar gezeigt wird; nie umbrechen.
                if ki != .claude, paare.count < 2 { Image(systemName: ki.symbol).foregroundStyle(Color.primary.opacity(0.5)) }
                ForEach(paare, id: \.0) { name, p in
                    Text(name).foregroundStyle(Color.primary.opacity(0.5)).fixedSize()
                    Ring(anteil: p / 100).frame(width: 13, height: 13)
                    Text("\(Int(p.rounded()))%").fixedSize()
                }
            } else if zeigeClaude, claude.fuenfStunden.gesamt > 0 {
                Text(kurz(claude.fuenfStunden.gesamt))
            }
        }
        .font(.system(size: 11, weight: .semibold).monospacedDigit())
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 14)
        .frame(height: m.leistenHoehe)
        // Ab dem zweiten Ring je 70 pt mehr, Countdown 80 pt, damit nichts abgeschnitten wird.
        .onAppear { breite(termin != nil) }
        .onChange(of: alle.count) { _, _ in breite(termin != nil) }
        .onChange(of: termin?.eventIdentifier) { _, _ in breite(termin != nil) }
        .onChange(of: fokus.name) { _, _ in breite(termin != nil) }
    }
}

struct Ring: View {
    let anteil: Double
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.15), lineWidth: 2.5)
            Circle().trim(from: 0, to: min(max(anteil, 0), 1))
                .stroke(farbe(anteil), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct Equalizer: View {
    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<3) { i in
                    Capsule().fill(Color.primary.opacity(0.8))
                        .frame(width: 2.5, height: 4 + 8 * abs(sin(t * 4 + Double(i) * 1.3)))
                }
            }.frame(height: 12)
        }
    }
}

struct MeldungAnsicht: View {
    @EnvironmentObject var m: NotchModell
    /// Akzentfarbe wie bei der Dynamic Island: Laden grün, Akku schwach rot, Timer/Termin orange, Download blau.
    private var farbe: Color? {
        let s = m.meldung?.symbol ?? ""
        switch m.meldungArt {
        case "akku": return s.contains("bolt") || s.contains("100") ? .green : s.contains("25") ? .red : nil
        case "timer", "termin", "ausschnitt", "lautstaerke": return .orange
        case "download", "ablage": return .blue
        case "bluetooth": return s.contains("slash") ? nil : .green
        default: return nil
        }
    }
    /// „Akku schwach – 14 %“ → Titel „Akku schwach“, Wert „14 %“ in der Akzentfarbe.
    private var teile: (String, String?) {
        let t = m.meldung?.text ?? ""
        if let r = t.range(of: " – ") { return (String(t[..<r.lowerBound]), String(t[r.upperBound...])) }
        if let r = t.range(of: ": ") { return (String(t[..<r.lowerBound]), String(t[r.upperBound...])) }
        return (t, nil)
    }
    var body: some View {
        VStack {
            Spacer(minLength: m.leistenHoehe)
            HStack(spacing: 12) {
                Image(systemName: m.meldung?.symbol ?? "info.circle").font(.system(size: 20))
                    .symbolRenderingMode(.hierarchical).foregroundStyle(farbe ?? Color.primary)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(teile.0).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        if let w = teile.1, w.count <= 6 { Text(w).font(.system(size: 13, weight: .semibold)).foregroundStyle(farbe ?? Color.primary) }
                    }
                    if let w = teile.1, w.count > 6 { Text(w).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.6)).lineLimit(1) }
                }
                .minimumScaleFactor(0.8)
                Spacer()
                if let w = m.meldungWert {
                    Capsule().fill(Color.primary.opacity(0.2)).frame(width: 120, height: 6)
                        .overlay(alignment: .leading) { Capsule().fill(farbe ?? Color.primary).frame(width: 120 * min(max(w, 0), 1), height: 6) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .foregroundStyle(Color.primary)
        .background { if farbe == .red { Color.red.opacity(0.18) } }
    }
}

// MARK: - Aufgeklappt

struct Offen: View {
    @EnvironmentObject var m: NotchModell
    @AppStorage(E.reiterAus) private var reiterAus = ""
    // Ausgeblendete Reiter zeigen wir nur, solange sie gerade offen sind (Tastenkürzel, Ablegen).
    private var reiter: [Reiter] { Reiter.sichtbar + (Reiter.sichtbar.contains(m.reiter) ? [] : [m.reiter]) }
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(reiter, id: \.self) { r in
                    Button(LocalizedStringKey(r.rawValue)) { m.reiter = r }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, reiter.count > 9 ? 7 : 10).padding(.vertical, 5)
                        .background(Capsule().fill(m.reiter == r ? Color.primary.opacity(0.18) : .clear))
                        .foregroundStyle(m.reiter == r ? Color.primary : Color.primary.opacity(0.55))
                }
                Menu {
                    Button("Einstellungen …") { m.einstellungenOeffnen?() }
                    Divider()
                    Button("Mac Notche beenden") { NSApp.terminate(nil) }
                } label: { Image(systemName: "gearshape") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .foregroundStyle(Color.primary.opacity(0.55)).padding(.leading, 6)
                .help("Einstellungen und Beenden")
            }
            .padding(.top, 10 + m.echteNotch)
            Group {
                switch m.reiter {
                case .uebersicht: Uebersicht()
                case .mitteilungen: MitteilungenAnsicht()
                case .wetter: WetterAnsicht()
                case .claude: ClaudeAnsicht()
                case .fragen: FragenAnsicht()
                case .ablage: AblageAnsicht()
                case .iphone: IPhoneAnsicht()
                case .fokus: FokusAnsicht()
                case .notiz: NotizAnsicht()
                case .zuhause: ZuhauseAnsicht()
                case .werkzeuge: WerkzeugeAnsicht()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 16)
        .foregroundStyle(Color.primary)
    }
}

struct Leer: View {
    let symbol, text, unter: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(Color.primary.opacity(0.4))
            Text(text).font(.system(size: 13, weight: .medium))
            Text(unter).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

func knopf(_ symbol: String, _ tun: @escaping () -> Void) -> some View {
    Button(action: tun) { Image(systemName: symbol).font(.system(size: 16)) }.buttonStyle(.plain)
}

// MARK: Übersicht

struct Uebersicht: View {
    @EnvironmentObject var geraete: Geraete
    @EnvironmentObject var iphone: IPhone
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    MusikKarte()
                    LautstaerkeLeiste()
                }
                .frame(width: 300)
                Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1)
                TermineKarte()
            }
            AkkuLeiste(liste: geraete.liste + (iphone.akku.map { [GeraetAkku(name: iphone.name ?? "iPhone", prozent: $0)] } ?? []))
            KurseLeiste()
            SportLeiste()
            KurzbefehlLeiste()
        }
        .onAppear { geraete.laden() }
    }
}

struct AkkuLeiste: View {
    let liste: [GeraetAkku]
    var body: some View {
        if !liste.isEmpty {
            HStack(spacing: 14) {
                ForEach(liste) { g in
                    HStack(spacing: 5) {
                        Image(systemName: g.name.lowercased().contains("iphone") ? "iphone" : g.symbol)
                        Text(g.name).lineLimit(1).foregroundStyle(Color.primary.opacity(0.7))
                        Image(systemName: g.prozent > 60 ? "battery.75" : g.prozent > 20 ? "battery.50" : "battery.25")
                            .foregroundStyle(g.prozent > 20 ? Color.primary : Color.red)
                        Text("\(g.prozent) %").monospacedDigit()
                        AkkuTrend(name: g.name)
                    }
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 11))
        }
    }
}

struct CoverBild: View {
    @EnvironmentObject var musik: Musik
    let groesse: CGFloat
    var body: some View {
        Group {
            if let c = musik.cover {
                Image(nsImage: c).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.primary.opacity(0.1)
                    Image(systemName: "music.note").foregroundStyle(Color.primary.opacity(0.5))
                }
            }
        }
        .frame(width: groesse, height: groesse)
        .clipShape(RoundedRectangle(cornerRadius: groesse * 0.2))
    }
}

struct MusikKarte: View {
    @EnvironmentObject var musik: Musik
    var body: some View {
        if let t = musik.titel {
            HStack(spacing: 14) {
                CoverBild(groesse: 92)
                VStack(alignment: .leading, spacing: 4) {
                    Text(t.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(t.kuenstler).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.6)).lineLimit(1)
                    ProgressView(value: t.dauer > 0 ? min(t.position / t.dauer, 1) : 0).tint(Color.primary).padding(.top, 6)
                    HStack { Text(zeit(t.position)); Spacer(); Text(zeit(t.dauer)) }
                        .font(.system(size: 10).monospacedDigit()).foregroundStyle(Color.primary.opacity(0.5))
                    HStack(spacing: 26) {
                        knopf("backward.fill") { musik.befehl("previous track") }
                        knopf(t.spielt ? "pause.fill" : "play.fill") { musik.befehl("playpause") }
                        knopf("forward.fill") { musik.befehl("next track") }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }
            }
        } else {
            Leer(symbol: "music.note", text: "Keine Musik aktiv", unter: "Apple Music oder Spotify starten")
        }
    }
}

struct TermineKarte: View {
    @EnvironmentObject var k: Kalender

    func wann(_ e: EKEvent) -> String {
        let f = DateFormatter()
        f.locale = deutsch
        f.timeStyle = .short
        let kal = Calendar.current
        let tag = e.startDate < Date() ? "Läuft" : kal.isDateInToday(e.startDate) ? "Heute" : kal.isDateInTomorrow(e.startDate) ? L("Morgen") : L("Übermorgen")
        return e.isAllDay ? "\(tag), ganztägig" : "\(tag), \(f.string(from: e.startDate))–\(f.string(from: e.endDate)) Uhr"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Termine").kopf()
            if k.termine.isEmpty {
                Text(k.zugriff ? L("Nichts in den nächsten 48 Std.") : L("Kein Kalender-Zugriff – Systemeinstellungen › Datenschutz"))
                    .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.6))
            }
            ForEach(Array(k.termine.enumerated()), id: \.offset) { _, e in
                HStack(spacing: 8) {
                    Capsule().fill(Color(cgColor: e.calendar.cgColor)).frame(width: 3, height: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(e.title ?? "Ohne Titel").font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text(wann(e)).font(.system(size: 10)).foregroundStyle(Color.primary.opacity(0.55))
                    }
                    if let u = TerminCountdown.anrufLink(e) {
                        Spacer()
                        Button { NSWorkspace.shared.open(u) } label: { Image(systemName: "video.fill") }
                            .buttonStyle(.plain).foregroundStyle(.orange).help("Call beitreten")
                    }
                }
            }
            Text("Erinnerungen").kopf().padding(.top, 6)
            if k.erinnerungen.isEmpty {
                Text("Alles erledigt").font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.6))
            }
            ForEach(Array(k.erinnerungen.enumerated()), id: \.offset) { _, r in
                Button { k.erledigt(r) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "circle").foregroundStyle(Color.primary.opacity(0.6))
                        Text(r.title ?? "").lineLimit(1)
                    }
                    .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Abhaken")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Claude

struct ClaudeAnsicht: View {
    @EnvironmentObject var c: ClaudeUsage
    @EnvironmentObject var k: AndereKIs
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            // Ohne Claude-Login (z. B. nur Gemini/ChatGPT) die beiden Claude-Spalten weglassen.
            if c.keinLogin && c.heute.gesamt == 0 && (k.codexDa || k.agyUsage != nil) {
                EmptyView()
            } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Claude · Plan-Limits").kopf()
                    Spacer()
                    Button { c.aktualisieren(erzwingen: true) } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).font(.system(size: 11)).help("Jetzt abrufen")
                }
                ForEach(c.limits) { LimitBalken(l: $0) }
                if c.ohneFuenfStunden, !c.limits.isEmpty {
                    Text("Kein 5-Stunden-Fenster in diesem Plan – nur das Wochenlimit zählt.")
                        .font(.system(size: 10)).foregroundStyle(Color.primary.opacity(0.5))
                }
                if let h = c.limitHinweis {
                    Text(h).font(.system(size: 11)).foregroundStyle(c.limits.isEmpty ? Color.primary.opacity(0.6) : .orange)
                }
                if let s = c.stand {
                    Text("Stand \(s.formatted(date: .omitted, time: .shortened)) Uhr")
                        .font(.system(size: 10)).foregroundStyle(Color.primary.opacity(0.4))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1)
            VStack(alignment: .leading, spacing: 12) {
                Text("Claude Code auf diesem Mac").kopf()
                TokenBlock(titel: "Letzte 5 Std.", s: c.fuenfStunden)
                TokenBlock(titel: "Heute", s: c.heute)
                Text("Kosten = API-Gegenwert, im Abo nicht berechnet")
                    .font(.system(size: 9)).foregroundStyle(Color.primary.opacity(0.4))
            }
            .frame(width: 220, alignment: .leading)
            }
            if k.codexDa || k.geminiDa || k.agyUsage != nil {
                if !(c.keinLogin && c.heute.gesamt == 0) { Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1) }
                ScrollView(.vertical, showsIndicators: false) { VStack(alignment: .leading, spacing: 10) {
                    if k.codexDa {
                        Text("Codex" + (k.codexPlan.map { " · ChatGPT \($0.capitalized)" } ?? "")).kopf()
                        ForEach(k.codexLimits) { LimitBalken(l: $0) }
                        TokenZeile(titel: "Heute", s: k.codexHeute)
                    }
                    if let z = k.agyUsage {
                        Text("Gemini · Antigravity").kopf().padding(.top, k.codexDa ? 4 : 0)
                        ForEach(k.agyLimits) { LimitBalken(l: $0) }
                        if k.agyLimits.isEmpty {
                            ForEach(z, id: \.self) { Text($0).font(.system(size: 10)).foregroundStyle(Color.primary.opacity(0.7)).lineLimit(1) }
                        }
                    } else if k.geminiDa {
                        Text("Gemini CLI").kopf().padding(.top, k.codexDa ? 4 : 0)
                        TokenZeile(titel: "Heute", s: k.geminiHeute)
                    }
                } }
                .frame(width: c.keinLogin && c.heute.gesamt == 0 ? 320 : 200, alignment: .leading)
            }
        }
    }
}

/// Nur Token, ohne Kosten: Codex und Gemini laufen im Abo bzw. kostenlos.
struct TokenZeile: View {
    let titel: String
    let s: TokenSumme
    var body: some View {
        HStack {
            Text(titel).font(.system(size: 11, weight: .medium))
            Spacer()
            Text(s.gesamt == 0 ? "nicht benutzt" : "\(kurz(s.gesamt)) Token")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(s.gesamt == 0 ? Color.primary.opacity(0.45) : .primary)
        }
        .help("\(kurz(s.eingabe)) rein · \(kurz(s.ausgabe)) raus · \(kurz(s.cacheLesen)) aus dem Cache")
    }
}

struct LimitBalken: View {
    let l: Limit
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(l.name).font(.system(size: 11, weight: .medium))
                Spacer()
                Text("\(Int(l.prozent.rounded())) %").font(.system(size: 11, weight: .semibold).monospacedDigit())
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule().fill(farbe(l.prozent / 100)).frame(width: g.size.width * min(max(l.prozent / 100, 0), 1))
                }
            }
            .frame(height: 5)
            if let r = l.reset {
                Text("Setzt zurück: \(r.formatted(.relative(presentation: .named).locale(deutsch)))")
                    .font(.system(size: 9)).foregroundStyle(Color.primary.opacity(0.45))
            }
        }
    }
}

struct TokenBlock: View {
    let titel: String
    let s: TokenSumme
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(titel).font(.system(size: 11, weight: .medium))
                Spacer()
                Text(s.kosten, format: .currency(code: "USD").locale(deutsch))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
            }
            Text("\(kurz(s.eingabe)) rein · \(kurz(s.ausgabe)) raus · \(kurz(s.cacheLesen)) Cache gelesen · \(kurz(s.cacheSchreiben)) geschrieben")
                .font(.system(size: 10)).foregroundStyle(Color.primary.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: Ablage

struct AblageAnsicht: View {
    @EnvironmentObject var a: Ablage
    @EnvironmentObject var m: NotchModell
    private var freistellen: some View {
        Button { m.zustand = .zu; m.ausschnitt.starten() } label: { Label("Freistellen ⌥⌘4", systemImage: "rectangle.dashed") }
            .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.7))
            .help("Bereich aufziehen: Text wird erkannt und kopiert, das Bild landet hier")
    }
    var body: some View {
        if a.dateien.isEmpty {
            VStack(spacing: 8) {
                Leer(symbol: "tray.and.arrow.down", text: "Ablage ist leer", unter: "Dateien auf die Notch ziehen")
                freistellen
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) { ForEach(a.dateien, id: \.self) { DateiKachel(url: $0) } }
                }
                HStack {
                    Text("\(a.dateien.count == 1 ? "1 Datei" : "\(a.dateien.count) Dateien") – rausziehen zum Ablegen, Doppelklick öffnet, Rechtsklick wandelt um").kopf()
                    Spacer()
                    freistellen
                    Button("Alle entfernen") { a.dateien.removeAll() }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.7))
                }
            }
        }
    }
}

struct DateiKachel: View {
    @EnvironmentObject var a: Ablage
    let url: URL
    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 56, height: 56)
            Text(url.lastPathComponent).font(.system(size: 10)).lineLimit(2).multilineTextAlignment(.center).frame(width: 84)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
        .overlay(alignment: .topTrailing) {
            Button { a.dateien.removeAll { $0 == url } } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(Color.primary.opacity(0.6)).padding(2)
        }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .contextMenu {
            let endung = url.pathExtension.lowercased()
            if Ablage.bildEndungen.contains(endung) {
                Button("In PNG umwandeln") { a.umwandeln(url, in: "png") }
                Button("In JPEG umwandeln") { a.umwandeln(url, in: "jpeg") }
                Button("In HEIC umwandeln") { a.umwandeln(url, in: "heic") }
            }
            if endung == "dmg" { Button("Programm installieren") { a.installieren(url) } }
            Button("Per AirDrop senden") { NSSharingService(named: .sendViaAirDrop)?.perform(withItems: [url]) }
            Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }
}

// MARK: Wetter

struct WetterAnsicht: View {
    @EnvironmentObject var w: Wetter
    var body: some View {
        if let j = w.jetzt {
            let b = Wetter.beschreibung(j.code, tag: j.tag)
            HStack(spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(w.ort).kopf()
                    HStack(spacing: 10) {
                        Image(systemName: b.symbol).symbolRenderingMode(.multicolor).font(.system(size: 34))
                        Text("\(Int(j.temp.rounded()))°").font(.system(size: 44, weight: .light))
                    }
                    Text(b.text).font(.system(size: 13))
                    if let h = w.tage.first {
                        Text("↑ \(Int(h.max.rounded()))°  ↓ \(Int(h.min.rounded()))°  ·  Regen \(h.regen) %")
                            .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.55))
                    }
                }
                .frame(width: 230, alignment: .leading)
                Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1)
                HStack(spacing: 10) { ForEach(w.tage.dropFirst()) { TagKachel(t: $0) } }
                    .frame(maxWidth: .infinity)
            }
        } else {
            Leer(symbol: "cloud.sun", text: "Wetter wird geladen", unter: "Daten von Open-Meteo")
        }
    }
}

struct TagKachel: View {
    let t: WetterTag
    var body: some View {
        VStack(spacing: 6) {
            Text(t.datum.formatted(.dateTime.weekday(.wide).locale(deutsch))).font(.system(size: 11, weight: .semibold))
            Image(systemName: Wetter.beschreibung(t.code).symbol).symbolRenderingMode(.multicolor)
                .font(.system(size: 24)).frame(height: 28)
            Text("\(Int(t.max.rounded()))° / \(Int(t.min.rounded()))°").font(.system(size: 12).monospacedDigit())
            Label("\(t.regen) %", systemImage: "drop.fill").font(.system(size: 10))
                .foregroundStyle(Color.primary.opacity(t.regen > 20 ? 0.8 : 0.4))
        }
        .frame(width: 96)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)))
    }
}

// MARK: iPhone

struct IPhoneAnsicht: View {
    @EnvironmentObject var i: IPhone
    var body: some View {
        if let name = i.name {
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Verbunden per Kabel").kopf()
                    HStack(spacing: 12) {
                        Image(systemName: "iphone").font(.system(size: 34))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(name).font(.system(size: 15, weight: .semibold))
                            if let a = i.akku {
                                Label("Akku \(a) %", systemImage: a > 20 ? "battery.75" : "battery.25")
                                    .font(.system(size: 12)).foregroundStyle(a > 20 ? Color.primary : .red)
                            }
                        }
                    }
                    Text("\(i.medien) Fotos und Videos auf dem Gerät")
                        .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.55))
                }
                .frame(width: 260, alignment: .leading)
                Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1)
                VStack(alignment: .leading, spacing: 10) {
                    Text("In die Fotos-App übernehmen").kopf()
                    if let f = i.fortschritt {
                        ProgressView(value: Double(f.fertig), total: Double(max(f.gesamt, 1)))
                        Text("\(f.fertig) von \(f.gesamt) …").font(.system(size: 12).monospacedDigit())
                    } else if i.neue.isEmpty {
                        Text("Keine neuen Fotos.").font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.6))
                    } else {
                        Text("\(i.neue.count) neue Fotos und Videos").font(.system(size: 13, weight: .medium))
                        HStack {
                            Button("Jetzt übernehmen") { i.importieren() }
                            Button("Vorhandene ignorieren") { i.alleBekannt() }
                        }
                        .controlSize(.small)
                    }
                    if let h = i.hinweis { Text(h).font(.system(size: 11)).foregroundStyle(.orange) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Leer(symbol: "iphone", text: "Kein iPhone verbunden", unter: "Per Kabel anschließen, entsperren und „Vertrauen“ tippen")
        }
    }
}

// MARK: Mitteilungen

struct MitteilungenAnsicht: View {
    @EnvironmentObject var mt: Mitteilungen
    @State private var auswahl: String?
    @State private var antwort = ""

    func senden() {
        guard let g = mt.gespraeche.first(where: { $0.id == auswahl }), !antwort.isEmpty else { return }
        mt.senden(antwort, an: g)
        antwort = ""
    }

    var body: some View {
        if !mt.zugriff {
            VStack(spacing: 8) {
                Image(systemName: "lock.shield").font(.system(size: 24)).foregroundStyle(Color.primary.opacity(0.4))
                Text("Mac Notche braucht Festplattenvollzugriff").font(.system(size: 13, weight: .medium))
                Text("Dort Mac Notche einschalten, dann erscheinen Mitteilungen und Nachrichten hier.")
                    .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.55))
                Button("Systemeinstellungen öffnen") { Mitteilungen.festplattenzugriffOeffnen() }.controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mitteilungen").kopf()
                    if mt.liste.isEmpty { Text("Keine Mitteilungen").font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.6)) }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) { ForEach(mt.liste) { MitteilungZeile(n: $0) } }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Nachrichten").kopf()
                    ForEach(mt.gespraeche) { g in
                        Button { auswahl = g.id } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(g.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                Text((g.vonMir ? "Du: " : "") + g.text).font(.system(size: 11)).lineLimit(1)
                                    .foregroundStyle(Color.primary.opacity(0.6))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6).fill(auswahl == g.id ? Color.primary.opacity(0.14) : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if let g = mt.gespraeche.first(where: { $0.id == auswahl }) {
                        HStack(spacing: 6) {
                            TextField("Antwort an \(g.name)", text: $antwort).textFieldStyle(.roundedBorder).onSubmit(senden)
                            Button(action: senden) { Image(systemName: "paperplane.fill") }.disabled(antwort.isEmpty)
                        }
                        .controlSize(.small)
                    }
                    if !mt.mails.isEmpty {
                        Text("Ungelesene Mails").kopf().padding(.top, 4)
                        ForEach(mt.mails) { mail in
                            Button { mt.mailAntworten(mail) } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrowshape.turn.up.left").font(.system(size: 10))
                                    Text(mail.betreff.isEmpty ? mail.absender : mail.betreff).font(.system(size: 11)).lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                            .help("In Mail antworten: \(mail.absender)")
                        }
                    }
                    if let s = mt.status { Text(s).font(.system(size: 10)).foregroundStyle(Color.primary.opacity(0.6)) }
                }
                .frame(width: 300, alignment: .leading)
            }
            .onAppear { mt.mailsLaden() }
        }
    }
}

struct MitteilungZeile: View {
    let n: Mitteilung
    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: n.app)
        Button { if let url { NSWorkspace.shared.open(url) } } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!)
                    .resizable().frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(n.appName).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.55))
                        Spacer()
                        Text(n.zeit.formatted(date: .omitted, time: .shortened)).font(.system(size: 10)).foregroundStyle(Color.primary.opacity(0.45))
                    }
                    if !n.titel.isEmpty { Text(n.titel).font(.system(size: 12, weight: .semibold)).lineLimit(1) }
                    Text(n.text).font(.system(size: 11)).lineLimit(2).foregroundStyle(Color.primary.opacity(0.75))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(n.appName) öffnen")
    }
}

// MARK: Werkzeuge

struct WerkzeugeAnsicht: View {
    @EnvironmentObject var spiegel: Spiegel
    @EnvironmentObject var wach: WachHalten
    @EnvironmentObject var ablage: Zwischenablage

    var wachText: String {
        guard let b = wach.bis else { return "Aus" }
        return b == .distantFuture ? "An, unbegrenzt" : "An bis \(b.formatted(date: .omitted, time: .shortened)) Uhr"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Spiegel").kopf()
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.08))
                    if spiegel.laeuft {
                        KameraBild(sitzung: spiegel.sitzung).clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Button("Kamera an") { spiegel.starten() }.controlSize(.small)
                    }
                }
                .frame(width: 200, height: 150)
                if spiegel.laeuft { Button("Aus") { spiegel.stoppen() }.controlSize(.small) }
                if let h = spiegel.hinweis { Text(h).font(.system(size: 10)).foregroundStyle(.orange) }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Wach halten").kopf()
                Label(wachText, systemImage: wach.bis == nil ? "cup.and.saucer" : "cup.and.saucer.fill")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(wach.bis == nil ? Color.primary : .orange)
                Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow {
                        Button("30 Min.") { wach.an(minuten: 30) }
                        Button("1 Std.") { wach.an(minuten: 60) }
                    }
                    GridRow {
                        Button("Unbegrenzt") { wach.an(minuten: nil) }
                        Button("Aus") { wach.aus() }.disabled(wach.bis == nil)
                    }
                }
                .controlSize(.small)
            }
            .frame(width: 170, alignment: .leading)
            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1)
            VStack(alignment: .leading, spacing: 4) {
                Text("Zwischenablage").kopf()
                if ablage.eintraege.isEmpty {
                    Text("Noch nichts kopiert.").font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.6))
                }
                ForEach(ablage.eintraege, id: \.self) { s in
                    Button { ablage.kopieren(s) } label: {
                        Text(s.replacingOccurrences(of: "\n", with: " ")).font(.system(size: 11)).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Erneut kopieren")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onDisappear { spiegel.stoppen() }
    }
}

// MARK: Fokus

struct Restzeit: View {
    let ende: Date
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            Text(zeit(max(ende.timeIntervalSince(tl.date), 0))).monospacedDigit()
        }
    }
}

struct FokusAnsicht: View {
    @EnvironmentObject var fokus: FokusTimer
    @EnvironmentObject var audio: AudioAusgabe
    @EnvironmentObject var appTon: AppLautstaerke
    @AppStorage("meldung.augen") private var augen = false
    @AppStorage(E.augenMinuten) private var augenMinuten = 20.0
    @AppStorage("meldung.trinken") private var trinken = true
    @AppStorage(E.trinkenMinuten) private var trinkenMinuten = 15.0
    @AppStorage(E.notizen) private var notizen = ""

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedStringKey(fokus.art?.rawValue ?? "Timer")).kopf()
                if let ende = fokus.ende {
                    TimelineView(.periodic(from: .now, by: 1)) { tl in
                        let rest = max(ende.timeIntervalSince(tl.date), 0)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(zeit(rest)).font(.system(size: 34, weight: .semibold).monospacedDigit())
                            ProgressView(value: fokus.gesamt > 0 ? 1 - rest / fokus.gesamt : 0).tint(.orange)
                        }
                    }
                    Button("Stopp") { fokus.stopp() }.controlSize(.small)
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
                        GridRow {
                            Button("5 Min.") { fokus.start(.timer, minuten: 5) }
                            Button("15 Min.") { fokus.start(.timer, minuten: 15) }
                        }
                        GridRow {
                            Button("30 Min.") { fokus.start(.timer, minuten: 30) }
                            Button("60 Min.") { fokus.start(.timer, minuten: 60) }
                        }
                    }
                    .controlSize(.small)
                    Button { fokus.start(.fokus, minuten: 25) } label: { Label("Fokus 25 + 5 Pause", systemImage: "brain.head.profile") }
                        .controlSize(.small)
                }
            }
            .frame(width: 190, alignment: .leading)
            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1)
            VStack(alignment: .leading, spacing: 8) {
                Text("Umgebung").kopf()
                Toggle("Rauschen zum Konzentrieren", isOn: $fokus.rauschen).toggleStyle(.switch).controlSize(.mini)
                Toggle("Augenpause alle \(Int(augenMinuten)) Min.", isOn: $augen).toggleStyle(.switch).controlSize(.mini)
                Toggle("Trinkpause alle \(Int(trinkenMinuten)) Min.", isOn: $trinken).toggleStyle(.switch).controlSize(.mini)
                Text("Ton-Ausgabe").kopf().padding(.top, 4)
                Picker("", selection: Binding(get: { audio.aktuell }, set: { audio.waehlen($0) })) {
                    ForEach(audio.geraete) { Text($0.name).tag($0.id) }
                }
                .labelsHidden().controlSize(.small)
                if !appTon.apps.isEmpty {
                    Text("Lautstärke pro App").kopf().padding(.top, 2)
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 2) {
                            ForEach(appTon.apps) { a in
                                HStack(spacing: 6) {
                                    Text(a.name).font(.system(size: 10)).lineLimit(1).frame(width: 70, alignment: .leading)
                                    Slider(value: Binding(get: { Double(appTon.pegel[a.pid] ?? 1) }, set: { appTon.setzen(a.pid, Float($0)) }), in: 0...1)
                                        .controlSize(.mini)
                                    Text("\(Int((appTon.pegel[a.pid] ?? 1) * 100))").font(.system(size: 9).monospacedDigit()).frame(width: 22, alignment: .trailing)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 60)
                }
            }
            .font(.system(size: 12))
            .frame(width: 210, alignment: .leading)
            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1)
            VStack(alignment: .leading, spacing: 6) {
                Text("Notizen").kopf()
                TextEditor(text: $notizen)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            }
        }
    }
}

struct KurseLeiste: View {
    @EnvironmentObject var kurse: Kurse
    var body: some View {
        if !kurse.liste.isEmpty {
            HStack(spacing: 14) {
                ForEach(kurse.liste) { k in
                    HStack(spacing: 4) {
                        Text(k.name).lineLimit(1).foregroundStyle(Color.primary.opacity(0.7))
                        Text(k.preis.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "de_DE")))).monospacedDigit()
                        Text((k.aenderung >= 0 ? "+" : "") + k.aenderung.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "de_DE"))) + " %")
                            .monospacedDigit().foregroundStyle(k.aenderung >= 0 ? Color.green : Color.red)
                    }
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 11))
        }
    }
}

// MARK: Akku-Verlauf

/// Mini-Verlauf der letzten 7 Tage plus geschätzte Resttage, Details im Tooltip.
struct AkkuTrend: View {
    let name: String
    var body: some View {
        let p = AkkuVerlauf.punkte(name).filter { $0.0 > Date().addingTimeInterval(-7 * 86400) }
        if p.count >= 2 {
            let rest = AkkuVerlauf.restTage(p)
            HStack(spacing: 3) {
                Linie(werte: p.map { Double($0.1) }).stroke(Color.primary.opacity(0.5), lineWidth: 1).frame(width: 26, height: 10)
                if let rest { Text(rest < 1 ? "< 1 T." : "~\(Int(rest)) T.").foregroundStyle(Color.primary.opacity(0.5)) }
            }
            .help("\(p[0].1) % am \(p[0].0.formatted(date: .abbreviated, time: .omitted)) → jetzt \(p[p.count - 1].1) %"
                  + (rest.map { ". Reicht noch etwa \(Int($0.rounded())) Tage." } ?? ""))
        }
    }
}

struct Linie: Shape {
    let werte: [Double]
    func path(in r: CGRect) -> Path {
        Path { p in
            guard werte.count > 1 else { return }
            for (i, w) in werte.enumerated() {
                let pt = CGPoint(x: r.minX + r.width * Double(i) / Double(werte.count - 1), y: r.maxY - r.height * min(max(w, 0), 100) / 100)
                i == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
        }
    }
}

// MARK: Sport

struct SportLeiste: View {
    @EnvironmentObject var sport: Sport
    var body: some View {
        if !sport.spiele.isEmpty {
            HStack(spacing: 14) {
                ForEach(sport.spiele) { s in
                    HStack(spacing: 5) {
                        Image(systemName: "soccerball")
                        Text("\(s.heim) \(s.ergebnis) \(s.gast)").monospacedDigit().lineLimit(1)
                        Text(s.fertig ? "Ende" : s.live ? "läuft" : s.anstoss.formatted(.dateTime.weekday(.abbreviated).hour().minute().locale(deutsch)))
                            .foregroundStyle(s.live ? Color.green : Color.primary.opacity(0.5))
                    }
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 11))
        }
    }
}

// MARK: Claude fragen

struct FragenAnsicht: View {
    @EnvironmentObject var f: Fragen
    @EnvironmentObject var agent: Agent
    @FocusState private var fokus: Bool
    @State private var art = 0  // 0 Frage, 1 Bildschirm, 2 Aufgabe

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("", selection: $art) {
                    Text("Frage").tag(0); Text("Bildschirm").tag(1); Text("Aufgabe").tag(2); Text("Text").tag(3)
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small).frame(width: 280)
                .onChange(of: art) { _, n in f.mitBildschirm = n == 1; fokus = n != 3; if n == 3, f.werkstattText.isEmpty { f.werkstattOeffnen() } }
                .onReceive(f.$artWunsch) { w in if let w { art = w; f.artWunsch = nil } }
                if art != 2 {
                    Menu {
                        ForEach(KI.allCases) { k in Button { f.ki = k } label: { Label(k.rawValue, systemImage: k.symbol) } }
                    } label: {
                        HStack(spacing: 3) { Image(systemName: f.ki.symbol); Text(f.ki.rawValue); Image(systemName: "chevron.down").font(.system(size: 8)) }
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Color.primary.opacity(0.8))
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help(L("Welche KI antwortet"))
                }
                if art == 3 {
                    Text(L("Zwischenablage · ") + "\(f.werkstattText.count) " + L("Zeichen")).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.6))
                    Button("Neu laden") { f.werkstattOeffnen() }.controlSize(.small)
                    Spacer()
                    if f.laeuft { ProgressView().controlSize(.small); Button("Stopp") { f.stopp() }.buttonStyle(.plain).font(.system(size: 11)) }
                } else if art == 2 {
                    TextField("Was soll Claude auf dem Mac erledigen?", text: $agent.aufgabe)
                        .textFieldStyle(.plain).font(.system(size: 13)).focused($fokus).onSubmit { agent.planen() }
                    if agent.plant { ProgressView().controlSize(.small); Button("Stopp") { agent.abbrechen() }.buttonStyle(.plain).font(.system(size: 11)) }
                    else { Button("Planen") { agent.planen() }.controlSize(.small).disabled(agent.aufgabe.isEmpty || agent.laeuft) }
                } else {
                    TextField(art == 1 ? L("Frag ") + f.ki.rawValue + L(" zu deinem Bildschirm …") : L("Frag ") + f.ki.rawValue + L(" … oder „15 min Tee“ für einen Timer"), text: $f.frage)
                        .textFieldStyle(.plain).font(.system(size: 13)).focused($fokus).onSubmit { f.senden() }
                    if f.laeuft { ProgressView().controlSize(.small); Button("Stopp") { f.stopp() }.buttonStyle(.plain).font(.system(size: 11)) }
                    else {
                        Button { f.senden() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 18)) }
                            .buttonStyle(.plain).disabled(f.frage.isEmpty)
                    }
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.08)))
            if art == 3 { werkstattBereich } else if art == 2 { AgentListe() } else { antwortBereich }
        }
        .onAppear { fokus = true; f.mitBildschirm = art == 1 }
    }

    @ViewBuilder private var werkstattBereich: some View {
        if f.werkstattText.isEmpty {
            Text("Erst Text kopieren (⌘C), dann ⌥⌘T – oder hier „Neu laden“. Das Ergebnis geht per „Einfügen“ zurück in die App.")
                .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.45))
            Spacer(minLength: 0)
        } else {
            HStack(spacing: 6) {
                ForEach(Fragen.werkstattAktionen, id: \.0) { name, anweisung in
                    Button(LocalizedStringKey(name)) { f.werkstatt(anweisung) }.controlSize(.small).disabled(f.laeuft)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                ScrollView {
                    Text(f.werkstattText).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
                Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1)
                ScrollView {
                    Text(f.antwort.isEmpty ? (f.laeuft ? f.ki.rawValue + L(" arbeitet …") : L("Ergebnis erscheint hier.")) : f.antwort)
                        .font(.system(size: 12)).foregroundStyle(f.antwort.isEmpty ? Color.primary.opacity(0.4) : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
            }
            if !f.antwort.isEmpty {
                HStack {
                    Label(L("Antwort von ") + f.antwortVon.rawValue, systemImage: f.antwortVon.symbol).foregroundStyle(Color.primary.opacity(0.45))
                    Spacer()
                    Button("Kopieren") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(f.antwort, forType: .string) }
                    Button("Einfügen") { f.einfuegen() }.disabled(f.zielApp == nil)
                    Button("Als Vorlage") { f.werkstattText = f.antwort; f.antwort = "" }
                }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.7))
            }
        }
    }

    @ViewBuilder private var antwortBereich: some View {
        if f.antwort.isEmpty {
            Text(f.laeuft ? (art == 1 ? L("Bildschirm wird fotografiert und an ") + f.ki.rawValue + L(" geschickt …") : f.ki.rawValue + L(" denkt nach …"))
                 : art == 1 ? f.ki.rawValue + L(" bekommt ein Foto deines Bildschirms und beantwortet deine Frage dazu.")
                 : L("Enter schickt die Frage ab. ⌥⌘K öffnet diesen Reiter von überall."))
                .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.45))
            Spacer(minLength: 0)
        } else {
            ScrollView {
                Text((try? AttributedString(markdown: f.antwort, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(f.antwort))
                    .font(.system(size: 12)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Label(L("Antwort von ") + f.antwortVon.rawValue, systemImage: f.antwortVon.symbol).foregroundStyle(Color.primary.opacity(0.45))
                Spacer()
                Button("Kopieren") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(f.antwort, forType: .string) }
                Button("Neue Frage") { f.frage = ""; f.antwort = ""; fokus = true }
            }
            .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.7))
        }
    }
}

struct AgentListe: View {
    @EnvironmentObject var agent: Agent
    var body: some View {
        if agent.schritte.isEmpty {
            Text(agent.plant ? "Claude plant die Schritte …" : agent.hinweis.isEmpty
                 ? "Beispiel: „Wandle alle HEIC-Fotos auf dem Schreibtisch in JPEG um.“ Claude schlägt Befehle vor, nichts läuft ohne dein OK."
                 : agent.hinweis)
                .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.5))
            Spacer(minLength: 0)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach($agent.schritte) { $s in
                        HStack(alignment: .top, spacing: 6) {
                            Toggle("", isOn: $s.an).labelsHidden().controlSize(.mini).disabled(agent.laeuft || s.zustand != .offen)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.was).font(.system(size: 11, weight: .medium))
                                Text(s.befehl).font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.primary.opacity(0.55)).textSelection(.enabled)
                                if !s.ausgabe.isEmpty { Text(s.ausgabe).font(.system(size: 9)).foregroundStyle(s.zustand == .fehler ? .red : Color.primary.opacity(0.5)).lineLimit(3) }
                            }
                            Spacer()
                            switch s.zustand {
                            case .offen: EmptyView()
                            case .laeuft: ProgressView().controlSize(.mini)
                            case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            case .fehler: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
            HStack {
                Text(agent.hinweis).font(.system(size: 10)).foregroundStyle(Color.primary.opacity(0.5))
                Spacer()
                Button("Verwerfen") { agent.schritte = []; agent.hinweis = "" }.buttonStyle(.plain).font(.system(size: 11)).disabled(agent.laeuft)
                Button("Ausführen") { agent.ausfuehren() }.controlSize(.small)
                    .disabled(agent.laeuft || !agent.schritte.contains { $0.an && $0.zustand == .offen })
            }
        }
    }
}

struct NotizAnsicht: View {
    @EnvironmentObject var d: Diktat
    @EnvironmentObject var m: NotchModell
    @State private var meldung = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button { d.umschalten() } label: {
                    Label(d.laeuft ? L("Diktat stoppen") : L("Diktieren"), systemImage: d.laeuft ? "stop.circle.fill" : "mic.circle.fill")
                        .foregroundStyle(d.laeuft ? .red : .orange)
                }
                .buttonStyle(.plain).font(.system(size: 13, weight: .semibold))
                if d.laeuft { Text("… spricht").font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.5)) }
                Spacer()
                Button("In Notizen") { meldung = NotizSichern.inNotizen(d.text) ? L("In Apple Notizen gesichert.") : L("Notizen-App hat es nicht angenommen.") }
                    .controlSize(.small).disabled(d.text.isEmpty)
                Button("In Ordner") {
                    do { let u = try NotizSichern.inOrdner(d.text); meldung = L("Gesichert: ") + u.lastPathComponent }
                    catch { meldung = L("Sichern fehlgeschlagen: ") + error.localizedDescription }
                }
                .controlSize(.small).disabled(d.text.isEmpty)
                Button("Leeren") { d.text = ""; meldung = "" }.controlSize(.small).disabled(d.text.isEmpty)
            }
            TextEditor(text: $d.text)
                .font(.system(size: 13)).scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.08)))
            Text(d.hinweis ?? (meldung.isEmpty ? L("Diktat läuft über Apples Spracherkennung, wenn möglich auf dem Mac. „In Ordner“ schreibt eine Markdown-Datei (Einstellungen › Werkzeuge).") : meldung))
                .font(.system(size: 10)).foregroundStyle(d.hinweis == nil ? Color.primary.opacity(0.45) : .orange)
        }
        .onDisappear { d.stoppen() }
    }
}

struct ZuhauseAnsicht: View {
    @EnvironmentObject var z: Zuhause
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if z.kacheln.isEmpty {
                Text("Keine Zuhause-Kurzbefehle gefunden. In der Kurzbefehle-App einen Ordner „Zuhause“ anlegen oder Kurzbefehle mit Wörtern wie Licht, Heizung, Steckdose benennen – jeder Kurzbefehl kann HomeKit-Szenen und -Geräte schalten.")
                    .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.5))
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(z.kacheln, id: \.self) { n in
                            Button { z.starten(n) } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: z.zuletzt == n ? "checkmark.circle.fill" : Zuhause.symbol(n))
                                        .font(.system(size: 20)).foregroundStyle(z.zuletzt == n ? .green : .orange)
                                    Text(n).font(.system(size: 11, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity, minHeight: 64)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .onAppear(perform: z.laden)
    }
}

struct KurzbefehlLeiste: View {
    @AppStorage(E.kurzbefehle) private var text = ""
    var body: some View {
        let namen = Kurzbefehle.gewaehlt()
        if !namen.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "square.2.layers.3d").foregroundStyle(Color.primary.opacity(0.6))
                ForEach(namen, id: \.self) { n in
                    Button(n) { Kurzbefehle.starten(n) }.controlSize(.small)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 11))
        }
    }
}

// MARK: Lautstärke in der Übersicht

/// Systemlautstärke als Regler, dahinter die Apps mit eigenem Regler.
struct LautstaerkeLeiste: View {
    @EnvironmentObject var system: SystemAnzeige
    @EnvironmentObject var appTon: AppLautstaerke
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: system.lautstaerke == 0 ? "speaker.slash.fill" : system.lautstaerke < 0.34 ? "speaker.wave.1.fill" : system.lautstaerke < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")
                    .frame(width: 16)
                Slider(value: Binding(get: { system.lautstaerke }, set: { system.setzen($0) }), in: 0...1).controlSize(.mini)
                Text("\(Int((system.lautstaerke * 100).rounded())) %").monospacedDigit().frame(width: 36, alignment: .trailing)
            }
            ForEach(appTon.apps.prefix(3)) { a in
                HStack(spacing: 6) {
                    Text(a.name).lineLimit(1).foregroundStyle(Color.primary.opacity(0.7)).frame(width: 70, alignment: .leading)
                    Slider(value: Binding(get: { Double(appTon.pegel[a.pid] ?? 1) }, set: { appTon.setzen(a.pid, Float($0)) }), in: 0...1).controlSize(.mini)
                    Text("\(Int(((appTon.pegel[a.pid] ?? 1) * 100).rounded())) %").monospacedDigit().frame(width: 36, alignment: .trailing)
                }
            }
        }
        .font(.system(size: 11))
    }
}
