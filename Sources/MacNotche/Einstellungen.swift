import SwiftUI
import ServiceManagement

/// Schlüssel für UserDefaults.
enum E {
    static let look = "look", breite = "breite", schatten = "schatten"
    static let verzoegerung = "verzoegerung", klickSchliesst = "klickSchliesst"
    static let updatesAuto = "updates.auto"
    static let zeigeMusik = "zeige.musik", zeigeClaude = "zeige.claude", zeigeWetter = "zeige.wetter"
    static let fahrenheit = "wetter.fahrenheit", claudeIntervall = "claude.intervall"
    static let iphoneAuto = "iphone.auto"
    static let entsperrenAktiv = "entsperren.aktiv", entsperrenSchwelle = "entsperren.schwelle"
    static let fensterAktiv = "fenster.aktiv", augenMinuten = "augen.minuten", trinkenMinuten = "trinken.minuten", bausteine = "bausteine"
    static let emojiKuerzel = "emoji.kuerzel", aktien = "aktien", notizen = "notizen"
    static let leisteAktiv = "leiste.aktiv", leisteSekunden = "leiste.sekunden", fragenModell = "fragen.modell"
    static let sportLiga = "sport.liga", sportVereine = "sport.vereine"
    static let fensterZiehen = "fenster.ziehen", kurzbefehle = "kurzbefehle"
    static func meldung(_ art: String) -> String { "meldung.\(art)" }
}

enum Einstellungen {
    static func registrieren() {
        UserDefaults.standard.register(defaults: [
            E.look: "schwarz", E.breite: 300.0, E.schatten: true,
            E.verzoegerung: 0.0, E.klickSchliesst: true,
            E.zeigeMusik: true, E.zeigeClaude: true, E.zeigeWetter: true,
            E.fahrenheit: false, E.claudeIntervall: 5,
            E.meldung("bluetooth"): true, E.meldung("akku"): true, E.meldung("fokus"): true,
            E.iphoneAuto: false, E.meldung("iphone"): true, E.meldung("mitteilungen"): true,
            E.entsperrenAktiv: false, E.entsperrenSchwelle: 0.72,
            E.fensterAktiv: true, E.augenMinuten: 20.0, E.trinkenMinuten: 15.0, E.emojiKuerzel: true, E.aktien: "",
            E.bausteine: [";mfg": "Mit freundlichen Grüßen", ";vg": "Viele Grüße"],
            E.meldung("lautstaerke"): true, E.meldung("feststell"): true, E.meldung("timer"): true,
            E.meldung("augen"): false, E.meldung("trinken"): true, E.meldung("update"): true, E.updatesAuto: true, E.meldung("ablage"): true,
            E.leisteAktiv: true, E.leisteSekunden: 10.0, E.fragenModell: "sonnet",
            E.sportLiga: "bl1", E.sportVereine: "", E.meldung("sport"): true,
            E.fensterZiehen: true, E.kurzbefehle: "", E.meldung("termin"): true,
            "ecke.ol": "Nichts", "ecke.or": "Nichts", "ecke.ul": "Nichts", "ecke.ur": "Nichts",
        ])
    }
}

enum Seite: String, CaseIterable, Identifiable {
    case allgemein = "Allgemein", aussehen = "Aussehen", live = "Live-Aktivitäten", mitteilungen = "Mitteilungen"
    case wetter = "Wetter", iphone = "iPhone", werkzeuge = "Werkzeuge", entsperren = "Gesicht entsperren", claude = "Verbindungen", info = "Über Mac Notche"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .allgemein: "gearshape"
        case .aussehen: "paintbrush"
        case .live: "bell.badge"
        case .mitteilungen: "message"
        case .wetter: "cloud.sun"
        case .iphone: "iphone"
        case .werkzeuge: "wrench.and.screwdriver"
        case .entsperren: "faceid"
        case .claude: "link"
        case .info: "info.circle"
        }
    }
}

struct EinstellungenAnsicht: View {
    @State private var seite: Seite? = {
        // --seite <Name> öffnet eine bestimmte Seite (zum Prüfen per Screenshot).
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--seite"), i + 1 < a.count else { return a.contains("--entsperren-seite") ? .entsperren : .allgemein }
        return Seite.allCases.first { $0.rawValue.lowercased().hasPrefix(a[i + 1].lowercased()) } ?? .allgemein
    }()
    var body: some View {
        NavigationSplitView {
            List(selection: $seite) {
                ForEach(Seite.allCases) { s in Label(LocalizedStringKey(s.rawValue), systemImage: s.symbol).tag(s) }
            }
            .navigationSplitViewColumnWidth(200)
        } detail: {
            Form {
                switch seite ?? .allgemein {
                case .allgemein: AllgemeinSeite()
                case .aussehen: AussehenSeite()
                case .live: LiveSeite()
                case .mitteilungen: MitteilungenSeite()
                case .wetter: WetterSeite()
                case .iphone: IPhoneSeite()
                case .werkzeuge: WerkzeugeSeite()
                case .entsperren: EntsperrenSeite()
                case .claude: VerbindungenSeite()
                case .info: InfoSeite()
                }
            }
            .formStyle(.grouped)
            .navigationTitle(L(seite?.rawValue ?? ""))
        }
        .frame(minWidth: 700, minHeight: 460)
    }
}

/// Slider mit Wertanzeige rechts.
struct Regler: View {
    let titel: String
    @Binding var wert: Double
    let bereich: ClosedRange<Double>
    let schritt: Double
    let anzeige: (Double) -> String
    var body: some View {
        LabeledContent(titel) {
            HStack {
                Slider(value: $wert, in: bereich, step: schritt)
                Text(anzeige(wert)).monospacedDigit().frame(width: 56, alignment: .trailing)
            }
        }
    }
}

struct AllgemeinSeite: View {
    @AppStorage(E.verzoegerung) var verzoegerung = 0.0
    @AppStorage(E.klickSchliesst) var klick = true
    @State private var login = SMAppService.mainApp.status == .enabled
    @State private var sprache = (UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first).flatMap { ["de", "en"].first(where: $0.hasPrefix) } ?? ""
    @State private var neustart = false
    var body: some View {
        Section("Sprache") {
            Picker("Sprache", selection: $sprache) {
                Text("System").tag("")
                Text("Deutsch").tag("de")
                Text("English").tag("en")
            }
            .onChange(of: sprache) { _, s in
                // Standard-Trick: AppleLanguages nur für diese App setzen, gilt ab dem nächsten Start.
                if s.isEmpty { UserDefaults.standard.removeObject(forKey: "AppleLanguages") } else { UserDefaults.standard.set([s], forKey: "AppleLanguages") }
                neustart = true
            }
            if neustart {
                HStack {
                    Text("Neustart nötig, damit die Sprache wechselt.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Jetzt neu starten") {
                        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/zsh")
                        p.arguments = ["-c", "sleep 1; open -a \"\(Bundle.main.bundlePath)\""]
                        try? p.run(); NSApp.terminate(nil)
                    }
                }
            }
        }
        Section("Start") {
            Toggle("Beim Anmelden starten", isOn: $login)
                .onChange(of: login) { _, an in
                    do { if an { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch {}
                    login = SMAppService.mainApp.status == .enabled
                }
        }
        Section("Verhalten") {
            Regler(titel: L("Öffnen nach"), wert: $verzoegerung, bereich: 0...1, schritt: 0.1) {
                $0 == 0 ? L("sofort") : String(format: "%.1f s", $0).replacingOccurrences(of: ".", with: ",")
            }
            Toggle("Klick außerhalb schließt die Notch", isOn: $klick)
        }
    }
}

struct AussehenSeite: View {
    @AppStorage(E.look) var look = "schwarz"
    @AppStorage(E.breite) var breite = 300.0
    @AppStorage(E.schatten) var schatten = true
    var body: some View {
        Section("Look") {
            Picker("Stil", selection: $look) {
                Text("Schwarz – wie eine echte Notch").tag("schwarz")
                Text("Glas – transparent").tag("glas")
                Text("System – folgt Hell/Dunkel").tag("system")
                Text("Hell").tag("hell")
                Text("Dunkel").tag("dunkel")
            }
            .pickerStyle(.radioGroup)
        }
        Section("Form") {
            Regler(titel: "Breite zugeklappt", wert: $breite, bereich: 220...420, schritt: 10) { "\(Int($0)) pt" }
            Toggle("Schatten", isOn: $schatten)
        }
    }
}

struct LiveSeite: View {
    @AppStorage(E.zeigeMusik) var musik = true
    @AppStorage(E.zeigeClaude) var claude = true
    @AppStorage(E.zeigeWetter) var wetter = true
    @AppStorage("meldung.bluetooth") var bluetooth = true
    @AppStorage("meldung.akku") var akku = true
    @AppStorage("meldung.fokus") var fokus = true
    @AppStorage("meldung.lautstaerke") var lautstaerke = true
    @AppStorage("meldung.feststell") var feststell = true
    @AppStorage("meldung.timer") var timer = true
    @AppStorage("meldung.ablage") var ablage = true
    @AppStorage("meldung.termin") var termin = true
    @AppStorage("meldung.sport") var sport = true
    var body: some View {
        Section("In der zugeklappten Notch") {
            Toggle("Laufende Musik (Cover und Equalizer)", isOn: $musik)
            Toggle("Claude-Auslastung", isOn: $claude)
            Toggle("Temperatur, wenn keine Musik läuft", isOn: $wetter)
        }
        Section {
            Toggle("Bluetooth-Gerät verbunden oder getrennt", isOn: $bluetooth)
            Toggle("Akku lädt oder ist schwach", isOn: $akku)
            Toggle("Fokus-Wechsel", isOn: $fokus)
            Toggle("Lautstärke mit Pegel", isOn: $lautstaerke)
            Toggle("Feststelltaste an/aus", isOn: $feststell)
            Toggle("Timer und Fokus-Sitzung abgelaufen", isOn: $timer)
            Toggle("Ablage: Umwandeln und Installieren", isOn: $ablage)
            Toggle("Termin beginnt (5 Min. vorher und zum Start)", isOn: $termin)
            Toggle("Tor bei deinen Vereinen", isOn: $sport)
        } header: {
            Text("Meldungen")
        } footer: {
            Text("Fokus-Meldungen brauchen Festplattenvollzugriff (Systemeinstellungen › Datenschutz & Sicherheit).")
        }
    }
}

struct WetterSeite: View {
    @AppStorage(E.fahrenheit) var fahrenheit = false
    var body: some View {
        Section {
            Picker("Einheit", selection: $fahrenheit) {
                Text("Celsius").tag(false)
                Text("Fahrenheit").tag(true)
            }
            .pickerStyle(.segmented)
        } footer: {
            Text("Daten von Open-Meteo, kostenlos und ohne Konto. Ohne Standortfreigabe gilt Chemnitz.")
        }
    }
}

struct VerbindungenSeite: View {
    @AppStorage(E.claudeIntervall) var intervall = 5
    @State private var liste: [Verbindung] = []
    @State private var diagnose = ""
    var body: some View {
        Section {
            ForEach(liste) { v in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: v.angemeldet ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(v.angemeldet ? .green : .secondary).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(v.name).fontWeight(.medium)
                            if let k = v.konto, !k.isEmpty { Text(k).foregroundStyle(.secondary) }
                        }
                        Text(v.hinweis).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let b = v.befehl {
                        Button(v.angemeldet ? "Neu anmelden" : b.contains("install") || b.contains("brew") ? "Installieren" : "Anmelden") { Verbindungen.anmelden(b) }
                    }
                }
            }
        } header: {
            HStack {
                Text("Anmeldungen auf diesem Mac")
                Spacer()
                Button("Prüfen") { laden() }.font(.caption)
            }
        } footer: {
            VStack(alignment: .trailing, spacing: 6) {
                Text("Jede Anmeldung läuft über das Werkzeug selbst (Claude Code, Codex, Antigravity CLI) im Terminal und Browser. Mac Notche speichert keine Passwörter und liest nur, was die Werkzeuge ablegen. Ohne Claude-Code-Login zeigt die Notch kein Claude-Kontingent.")
                Text(diagnose).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
            }
        }
        Section {
            Picker("Plan-Limits abrufen alle", selection: $intervall) {
                ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) Min.").tag($0) }
            }
        } footer: {
            Text("Token und Kosten werden lokal aus ~/.claude, ~/.codex und ~/.gemini gezählt.")
        }
        .onAppear(perform: laden)
    }
    private func laden() {
        DispatchQueue.global(qos: .userInitiated).async {
            let l = Verbindungen.alle(), d = Verbindungen.diagnose()
            DispatchQueue.main.async { liste = l; diagnose = d }
        }
    }
}

struct InfoSeite: View {
    @EnvironmentObject var u: Updates
    @AppStorage(E.updatesAuto) var auto = true
    var body: some View {
        Section {
            Toggle("Automatisch nach Updates suchen", isOn: $auto)
            HStack {
                if let n = u.neu {
                    Text("Version \(n.version) ist da").fontWeight(.medium)
                    Spacer()
                    Button("Laden") { NSWorkspace.shared.open(n.url) }
                } else {
                    Text(u.hinweis ?? L("Updates kommen von GitHub (Mike-Hillebrand/mac-notche).")).foregroundStyle(.secondary)
                    Spacer()
                    Button(u.laeuft ? "Prüfe …" : "Jetzt prüfen") { u.pruefen() }.disabled(u.laeuft)
                }
            }
        }
        Section {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mac Notche").font(.title2.weight(.semibold))
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                        .foregroundStyle(.secondary)
                    Text("Alle Funktionen frei – kein Abo, keine Sperren.")
                }
            }
        }
        Section {
            HStack(spacing: 4) {
                Text("made with")
                Text("♥").foregroundStyle(Color(red: 0.83, green: 0.02, blue: 0.03))
                Text("by")
                Link("Mike Hillebrand Media", destination: URL(string: "https://mikehillebrand.com")!)
            }
            .font(.system(size: 12)).foregroundStyle(.secondary)
            Text("© \(String(Calendar.current.component(.year, from: Date()))) Mike Hillebrand · Chemnitz")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
        }
    }
}

struct IPhoneSeite: View {
    @AppStorage(E.iphoneAuto) var auto = false
    @AppStorage("meldung.iphone") var meldung = true
    var body: some View {
        Section {
            Toggle("Neue Fotos beim Anschließen automatisch in Fotos übernehmen", isOn: $auto)
            Toggle("Meldung beim Verbinden und Trennen", isOn: $meldung)
        } footer: {
            Text("Nur per Kabel. Das iPhone muss entsperrt sein und dem Mac vertrauen. Live-Fotos werden als Foto und Video getrennt übernommen.")
        }
    }
}

struct MitteilungenSeite: View {
    @AppStorage("meldung.mitteilungen") var zeigen = true
    var body: some View {
        Section {
            Toggle("Neue Mitteilungen kurz in der Notch zeigen", isOn: $zeigen)
            Button("Festplattenvollzugriff öffnen …") { Mitteilungen.festplattenzugriffOeffnen() }
        } footer: {
            Text("Mac Notche liest die Mitteilungen und Nachrichten nur lokal. Dafür in Systemeinstellungen › Datenschutz & Sicherheit › Festplattenvollzugriff „Mac Notche“ einschalten. Antworten geht für iMessage/SMS direkt, für Mail über das Antwortfenster; andere Apps (z. B. WhatsApp) erlauben das nicht – ein Klick öffnet die App.")
        }
    }
}

struct EntsperrenSeite: View {
    @EnvironmentObject var ent: Entsperren
    @AppStorage(E.entsperrenAktiv) var aktiv = false
    @AppStorage(E.entsperrenSchwelle) var schwelle = 0.72
    @State private var passwort = ""
    @State private var takt = 0  // aktualisiert den Bedienungshilfen-Status

    var bereit: Bool { ent.modellBereit && ent.eingelernt > 0 && ent.passwortGespeichert && ent.bedienungshilfen }

    var body: some View {
        let _ = takt
        Section {
            Text("Bequemer, aber weniger sicher als Touch ID oder Apple Watch: Eine Webcam misst kein 3D-Gesicht. Mac Notche verlangt deshalb ein Blinzeln (gegen Fotos) und drei Treffer hintereinander – ein Video oder eine sehr ähnliche Person kann trotzdem durchkommen. Dein Passwort liegt nur im Schlüsselbund und wird ausschließlich getippt, wenn der Bildschirm gesperrt ist.")
                .font(.callout).foregroundStyle(.orange)
        }
        Section("1. Gesicht") {
            LabeledContent("Status", value: ent.eingelernt > 0 ? "Eingelernt (\(ent.eingelernt) Aufnahmen)" : "Noch nicht eingelernt")
            if ent.kameraLaeuft {
                KameraBild(sitzung: ent.sitzung).frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 10))
            }
            HStack {
                Button("Gesicht einlernen") { ent.einlernen() }
                Button("Erkennung testen") { ent.testen() }.disabled(ent.eingelernt == 0)
                Spacer()
                Button("Gesichtsdaten löschen", role: .destructive) { ent.gesichtLoeschen() }.disabled(ent.eingelernt == 0)
            }
            .disabled(!ent.modellBereit || ent.kameraLaeuft)
            if let a = ent.testAehnlichkeit {
                Text("Ähnlichkeit \(String(format: "%.2f", a)) – \(a >= Float(schwelle) ? L("erkannt ✓") : L("nicht erkannt")) · Blinzeln \(ent.testBlinzeln ? "✓" : "–")")
                    .monospacedDigit()
            }
            Regler(titel: "Strenge", wert: $schwelle, bereich: 0.6...0.9, schritt: 0.02) { String(format: "%.2f", $0) }
        }
        Section("2. Mac-Passwort") {
            if ent.passwortGespeichert {
                HStack {
                    Label("Geprüft und im Schlüsselbund gespeichert", systemImage: "checkmark.seal.fill")
                    Spacer()
                    Button("Entfernen") { ent.passwortLoeschen(); aktiv = false }
                }
            } else {
                HStack {
                    SecureField("Passwort deines Mac-Kontos", text: $passwort)
                    Button("Prüfen und speichern") { ent.passwortSpeichern(passwort); passwort = "" }.disabled(passwort.isEmpty)
                }
            }
        }
        Section("3. Bedienungshilfen (zum Eintippen)") {
            HStack {
                Label(ent.bedienungshilfen ? L("Erlaubt") : L("Noch nicht erlaubt"),
                      systemImage: ent.bedienungshilfen ? "checkmark.circle.fill" : "exclamationmark.circle")
                Spacer()
                Button("Erlauben …") { ent.bedienungshilfenAnfragen() }.disabled(ent.bedienungshilfen)
            }
        }
        Section {
            Toggle("Mit Gesicht entsperren", isOn: $aktiv).disabled(!bereit && !aktiv)
            if !ent.status.isEmpty { Text(ent.status).font(.caption) }
            if !ent.modellBereit { Text("Das Gesichtsmodell fehlt in dieser App-Version.").foregroundStyle(.red) }
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in takt += 1 }
    }
}

struct WerkzeugeSeite: View {
    @AppStorage(E.fensterAktiv) var fenster = true
    @AppStorage(E.fensterZiehen) var ziehen = true
    @AppStorage(E.kurzbefehle) var kurzbefehle = ""
    @State private var alleKurzbefehle: [String] = []
    @AppStorage(E.emojiKuerzel) var emoji = true
    @AppStorage(E.augenMinuten) var augenMinuten = 20.0
    @AppStorage("meldung.augen") var augen = false
    @AppStorage(E.trinkenMinuten) var trinkenMinuten = 15.0
    @AppStorage("meldung.trinken") var trinken = true
    @AppStorage(E.aktien) var aktien = ""
    @AppStorage(E.leisteAktiv) var leiste = true
    @AppStorage(E.leisteSekunden) var leisteSekunden = 10.0
    @AppStorage(E.fragenModell) var fragenModell = "sonnet"
    @AppStorage(E.sportLiga) var sportLiga = "bl1"
    @AppStorage(E.sportVereine) var sportVereine = ""
    @AppStorage("ecke.ol") var eckeOL = "Nichts"
    @AppStorage("ecke.or") var eckeOR = "Nichts"
    @AppStorage("ecke.ul") var eckeUL = "Nichts"
    @AppStorage("ecke.ur") var eckeUR = "Nichts"
    @State private var bausteine: [(kuerzel: String, text: String)] =
        ((UserDefaults.standard.dictionary(forKey: E.bausteine) as? [String: String]) ?? [:]).sorted { $0.key < $1.key }.map { ($0.key, $0.value) }

    private func speichern() {
        var d: [String: String] = [:]
        for b in bausteine where !b.kuerzel.isEmpty { d[b.kuerzel] = b.text }
        UserDefaults.standard.set(d, forKey: E.bausteine)
    }

    var body: some View {
        Section {
            Toggle("Fenster per Tastenkürzel einrasten", isOn: $fenster)
            Toggle("Fenster per Ziehen an den Rand einrasten", isOn: $ziehen)
            LabeledContent("⌃⌥ ← / →", value: "linke / rechte Hälfte")
            LabeledContent("⌃⌥ ↑ / ↓", value: "obere / untere Hälfte")
            LabeledContent("⌃⌥ D / F / G", value: "linkes / mittleres / rechtes Drittel")
            LabeledContent("⌃⌥ ↩ / C", value: "ganzer Bildschirm / mittig")
        } header: { Text("Fenster") } footer: { Text("Braucht die Bedienungshilfen-Erlaubnis (wie beim Entsperren).") }

        Section {
            LabeledContent("⌥⌘V", value: "Verlauf öffnen – Klick fügt direkt ein")
        } header: { Text("Zwischenablage") } footer: { Text("Die letzten 20 kopierten Texte, nur im Speicher. Inhalte aus Passwort-Managern werden nie gemerkt.") }

        Section {
            ForEach(bausteine.indices, id: \.self) { i in
                HStack {
                    TextField("Kürzel", text: Binding(get: { bausteine[i].kuerzel }, set: { bausteine[i].kuerzel = $0; speichern() }))
                        .frame(width: 90)
                    TextField("Text", text: Binding(get: { bausteine[i].text }, set: { bausteine[i].text = $0; speichern() }))
                    Button { bausteine.remove(at: i); speichern() } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                }
                .labelsHidden()
            }
            Button("Textbaustein hinzufügen") { bausteine.append((";", "")) }
            Toggle("Emoji-Kürzel wie :herz: oder :daumen:", isOn: $emoji)
        } header: { Text("Textbausteine") } footer: {
            Text("Tippst du das Kürzel irgendwo, ersetzt Mac Notche es durch den Text. Emoji-Kürzel: " + Textbausteine.emojis.keys.sorted().prefix(12).joined(separator: " ") + " …")
        }

        Section("Augenpause") {
            Toggle("Erinnern, in die Ferne zu schauen", isOn: $augen)
            Stepper("Alle \(Int(augenMinuten)) Minuten", value: $augenMinuten, in: 10...60, step: 5)
        }

        Section("Trinken und Aufstehen") {
            Toggle("Erinnern, etwas zu trinken und aufzustehen", isOn: $trinken)
            Stepper("Alle \(Int(trinkenMinuten)) Minuten", value: $trinkenMinuten, in: 5...120, step: 5)
        }

        Section {
            TextField("Symbole", text: $aktien, prompt: Text("AAPL, ^GDAXI, BTC-EUR"))
                .onSubmit { NotificationCenter.default.post(name: .kurseLaden, object: nil) }
        } header: { Text("Aktienkurse in der Übersicht") } footer: {
            Text("Kürzel wie bei Yahoo Finance, mit Komma getrennt. Enter lädt sofort, sonst alle 15 Minuten. Leer = aus.")
        }

        Section {
            TextField("Kurzbefehle", text: $kurzbefehle, prompt: Text("Name 1, Name 2"))
        } header: { Text("Kurzbefehle in der Übersicht") } footer: {
            Text(alleKurzbefehle.isEmpty ? "Namen aus der Kurzbefehle-App, mit Komma getrennt."
                 : "Vorhanden: " + alleKurzbefehle.prefix(12).joined(separator: ", ") + (alleKurzbefehle.count > 12 ? " …" : ""))
        }
        .onAppear { DispatchQueue.global().async { let l = Kurzbefehle.alle(); DispatchQueue.main.async { alleKurzbefehle = l } } }

        Section {
            Toggle("Menüleisten-Symbole ausblenden", isOn: $leiste)
            Stepper(leisteSekunden == 0 ? "Nicht automatisch wieder einklappen" : "Nach \(Int(leisteSekunden)) Sekunden wieder einklappen",
                    value: $leisteSekunden, in: 0...60, step: 5)
        } header: { Text("Menüleiste") } footer: {
            Text("Halte ⌘ gedrückt und ziehe Symbole links neben den Schrägstrich in der Menüleiste. Der Pfeil daneben oder ⌃⌥M blendet sie ein und aus.")
        }

        Section {
            Picker("Oben links", selection: $eckeOL) { ForEach(Ecken.Aktion.allCases, id: \.rawValue) { Text(LocalizedStringKey($0.rawValue)) } }
            Picker("Oben rechts", selection: $eckeOR) { ForEach(Ecken.Aktion.allCases, id: \.rawValue) { Text(LocalizedStringKey($0.rawValue)) } }
            Picker("Unten links", selection: $eckeUL) { ForEach(Ecken.Aktion.allCases, id: \.rawValue) { Text(LocalizedStringKey($0.rawValue)) } }
            Picker("Unten rechts", selection: $eckeUR) { ForEach(Ecken.Aktion.allCases, id: \.rawValue) { Text(LocalizedStringKey($0.rawValue)) } }
        } header: { Text("Bildschirmecken") } footer: {
            Text("Maus kurz in die Ecke schieben löst die Aktion aus. Gilt für jeden Bildschirm. Die Ecken von macOS (Systemeinstellungen › Schreibtisch & Dock) besser auf „–“ lassen.")
        }

        Section {
            Picker("Modell", selection: $fragenModell) {
                Text("Haiku – am schnellsten").tag("haiku")
                Text("Sonnet – ausgewogen").tag("sonnet")
                Text("Opus – am klügsten").tag("opus")
            }
        } header: { Text("Claude fragen") } footer: {
            Text("⌥⌘K öffnet den Reiter „Fragen“ mit drei Arten: Frage, Bildschirm (schickt ein Foto des Bildschirms mit, braucht die Erlaubnis Bildschirmaufnahme) und Aufgabe (Claude plant Schritte, du bestätigst, Mac Notche führt sie aus). Läuft über deinen Claude-Code-Login, ohne API-Schlüssel.")
        }

        Section {
            TextField("Liga", text: $sportLiga, prompt: Text("bl1"))
            TextField("Vereine", text: $sportVereine, prompt: Text("Bayern, Dortmund"))
                .onSubmit { NotificationCenter.default.post(name: .sportLaden, object: nil) }
        } header: { Text("Sport in der Übersicht") } footer: {
            Text("Daten von OpenLigaDB. Liga: bl1 = 1. Bundesliga, bl2 = 2. Bundesliga, bl3 = 3. Liga. Vereine mit Komma getrennt, ein Teil des Namens reicht. Leer = aus. Bei Toren kommt eine Meldung.")
        }
    }
}

extension Notification.Name { static let kurseLaden = Notification.Name("kurseLaden") }
