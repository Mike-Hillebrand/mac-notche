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

    var body: some View {
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: m.zustand == .offen ? 24 : 12,
                                   bottomTrailingRadius: m.zustand == .offen ? 24 : 12)
                .fill(hintergrund)
            switch m.zustand {
            case .zu: Kompakt()
            case .meldung: MeldungAnsicht()
            case .offen: Offen()
            }
        }
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

    var body: some View {
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
            if let ende = fokus.ende {
                Image(systemName: fokus.art == .fokus ? "brain.head.profile" : fokus.art == .pause ? "cup.and.saucer" : "timer")
                    .foregroundStyle(.orange)
                Restzeit(ende: ende)
            }
            if zeigeClaude, !claude.limits.isEmpty {
                // 5-Std.-Fenster nur, wenn Anthropic es für den Plan mitschickt; Woche immer.
                ForEach([("5h", claude.fuenfStundenProzent), ("Wo", claude.limits.first { $0.id == "seven_day" }?.prozent)], id: \.0) { name, p in
                    // Ultra hat kein 5-Stunden-Fenster mehr; dann nur die Woche zeigen.
                    if let p {
                        Text(name).foregroundStyle(Color.primary.opacity(0.5))
                        Ring(anteil: p / 100).frame(width: 13, height: 13)
                        Text("\(Int(p.rounded())) %")
                    }
                }
            } else if zeigeClaude, claude.fuenfStunden.gesamt > 0 {
                Text(kurz(claude.fuenfStunden.gesamt))
            }
        }
        .font(.system(size: 11, weight: .semibold).monospacedDigit())
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 14)
        .frame(height: m.leistenHoehe)
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
    var body: some View {
        VStack {
            Spacer(minLength: m.leistenHoehe)
            HStack(spacing: 10) {
                Image(systemName: m.meldung?.symbol ?? "info.circle").font(.system(size: 16))
                Text(m.meldung?.text ?? "").font(.system(size: 13, weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.75)
                Spacer()
                if let w = m.meldungWert {
                    Capsule().fill(Color.primary.opacity(0.2)).frame(width: 120, height: 6)
                        .overlay(alignment: .leading) { Capsule().fill(Color.primary).frame(width: 120 * min(max(w, 0), 1), height: 6) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .foregroundStyle(Color.primary)
    }
}

// MARK: - Aufgeklappt

struct Offen: View {
    @EnvironmentObject var m: NotchModell
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(Reiter.allCases, id: \.self) { r in
                    Button(LocalizedStringKey(r.rawValue)) { m.reiter = r }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
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
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Claude · Plan-Limits").kopf()
                    Spacer()
                    Button { c.aktualisieren(erzwingen: true) } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).font(.system(size: 11)).help("Jetzt abrufen")
                }
                ForEach(c.limits) { LimitBalken(l: $0) }
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
            if k.codexDa || k.geminiDa {
                Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1)
                VStack(alignment: .leading, spacing: 10) {
                    if k.codexDa {
                        Text("Codex" + (k.codexPlan.map { " · ChatGPT \($0.capitalized)" } ?? "")).kopf()
                        ForEach(k.codexLimits) { LimitBalken(l: $0) }
                        TokenZeile(titel: "Heute", s: k.codexHeute)
                    }
                    if k.geminiDa {
                        Text("Gemini CLI").kopf().padding(.top, k.codexDa ? 4 : 0)
                        TokenZeile(titel: "Heute", s: k.geminiHeute)
                    }
                }
                .frame(width: 200, alignment: .leading)
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
    var body: some View {
        if a.dateien.isEmpty {
            Leer(symbol: "tray.and.arrow.down", text: "Ablage ist leer", unter: "Dateien auf die Notch ziehen")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) { ForEach(a.dateien, id: \.self) { DateiKachel(url: $0) } }
                }
                HStack {
                    Text("\(a.dateien.count == 1 ? "1 Datei" : "\(a.dateien.count) Dateien") – rausziehen zum Ablegen, Doppelklick öffnet, Rechtsklick wandelt um").kopf()
                    Spacer()
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
                    Text("Frage").tag(0); Text("Bildschirm").tag(1); Text("Aufgabe").tag(2)
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small).frame(width: 230)
                .onChange(of: art) { _, n in f.mitBildschirm = n == 1; fokus = true }
                if art == 2 {
                    TextField("Was soll Claude auf dem Mac erledigen?", text: $agent.aufgabe)
                        .textFieldStyle(.plain).font(.system(size: 13)).focused($fokus).onSubmit { agent.planen() }
                    if agent.plant { ProgressView().controlSize(.small); Button("Stopp") { agent.abbrechen() }.buttonStyle(.plain).font(.system(size: 11)) }
                    else { Button("Planen") { agent.planen() }.controlSize(.small).disabled(agent.aufgabe.isEmpty || agent.laeuft) }
                } else {
                    TextField(art == 1 ? L("Frag Claude zu deinem Bildschirm …") : L("Frag Claude …"), text: $f.frage)
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
            if art == 2 { AgentListe() } else { antwortBereich }
        }
        .onAppear { fokus = true; f.mitBildschirm = art == 1 }
    }

    @ViewBuilder private var antwortBereich: some View {
        if f.antwort.isEmpty {
            Text(f.laeuft ? (art == 1 ? L("Bildschirm wird fotografiert und an Claude geschickt …") : L("Claude denkt nach …"))
                 : art == 1 ? "Claude bekommt ein Foto deines Bildschirms und beantwortet deine Frage dazu."
                 : "Enter schickt die Frage ab. ⌥⌘K öffnet diesen Reiter von überall.")
                .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.45))
            Spacer(minLength: 0)
        } else {
            ScrollView {
                Text((try? AttributedString(markdown: f.antwort, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(f.antwort))
                    .font(.system(size: 12)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
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
