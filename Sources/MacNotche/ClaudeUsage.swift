import Foundation

struct Limit: Identifiable {
    let id: String
    let name: String
    let prozent: Double
    let reset: Date?
}

struct TokenSumme {
    var eingabe = 0, ausgabe = 0, cacheSchreiben = 0, cacheLesen = 0
    var kosten = 0.0
    var gesamt: Int { eingabe + ausgabe + cacheSchreiben + cacheLesen }

    mutating func add(_ o: TokenSumme) {
        eingabe += o.eingabe; ausgabe += o.ausgabe
        cacheSchreiben += o.cacheSchreiben; cacheLesen += o.cacheLesen
        kosten += o.kosten
    }
}

/// Zwei Quellen: Plan-Limits vom Anthropic-Endpunkt (wie /usage) und lokale Token aus ~/.claude/projects.
final class ClaudeUsage: ObservableObject {
    @Published var limits: [Limit] = []
    @Published var limitHinweis: String?
    /// Anthropic liefert den Schlüssel, aber leer: dieser Plan hat kein 5-Stunden-Fenster (z. B. Max 20×).
    @Published var ohneFuenfStunden = false
    @Published var stand: Date?
    @Published var heute = TokenSumme()
    @Published var fuenfStunden = TokenSumme()

    var fuenfStundenProzent: Double? { limits.first { $0.id == "five_hour" }?.prozent }

    private var letzterAbruf = Date.distantPast
    private var dienst: String?

    func starten() {
        aktualisieren(erzwingen: true)
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.aktualisieren() }
    }

    private static let tokenWarteschlange = DispatchQueue(label: "kerbe.token", qos: .utility)

    func aktualisieren(erzwingen: Bool = false) {
        Self.tokenWarteschlange.async {
            let (h, f) = Self.lokaleToken()
            DispatchQueue.main.async { self.heute = h; self.fuenfStunden = f }
        }
        // ponytail: der Endpunkt drosselt schnell (429), daher nur im eingestellten Abstand (Standard 5 Min.).
        guard erzwingen || Date().timeIntervalSince(letzterAbruf) > Double(UserDefaults.standard.integer(forKey: E.claudeIntervall) * 60) else { return }
        letzterAbruf = Date()
        Task.detached(priority: .utility) { await self.limitsHolen() }
    }

    // MARK: Plan-Limits

    private func limitsHolen() async {
        var kandidaten = dienst.map { [$0] } ?? []
        kandidaten += Self.schluesselbundDienste().filter { $0 != dienst }
        if Self.dateiToken() != nil { kandidaten.append(Self.dateiDienst) }
        var hinweis = kandidaten.isEmpty
            ? (Verbindungen.claudeStatus()?.angemeldet == true
               ? L("Claude Code ist angemeldet, aber der Schlüsselbund-Eintrag ist für Mac Notche nicht lesbar. Einstellungen › Verbindungen.")
               : L("Kein Claude-Code-Login auf diesem Mac. Einstellungen › Verbindungen."))
            : L("Claude-Code-Login abgelaufen oder ungültig. Einmal „claude“ im Terminal starten.")
        for d in kandidaten.prefix(6) {
            guard let token = (d == Self.dateiDienst ? Self.dateiToken() : Self.token(dienst: d))?.token else { continue }
            var r = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
            r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            r.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            r.timeoutInterval = 15
            guard let (daten, antwort) = try? await URLSession.shared.data(for: r),
                  let code = (antwort as? HTTPURLResponse)?.statusCode else {
                hinweis = L("Keine Verbindung zu Anthropic.")
                break
            }
            if code == 401 || code == 403 { continue }
            dienst = d
            if code == 429 { hinweis = L("Anthropic drosselt gerade – neuer Versuch in 5 Min."); break }
            guard code == 200, let l = Self.limitsLesen(daten) else { hinweis = L("Unerwartete Antwort") + " (\(code))."; break }
            let ohne = Self.ohneFuenfStunden(daten)
            await MainActor.run { self.limits = l; self.ohneFuenfStunden = ohne; self.limitHinweis = nil; self.stand = Date() }
            return
        }
        let h = hinweis
        await MainActor.run { self.limitHinweis = h }
    }

    /// Über /usr/bin/security lesen: Claude Code legt seine Einträge selbst so an, daher kein Schlüsselbund-Dialog.
    static func security(_ args: [String]) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? d : nil
    }

    /// Alle „Claude Code-credentials*“-Einträge, frischester Ablauf zuerst.
    static func schluesselbundDienste() -> [String] {
        guard let d = security(["dump-keychain"]), let text = String(data: d, encoding: .utf8) else { return [] }
        let muster = try! NSRegularExpression(pattern: "\"svce\"<blob>=\"(Claude Code-credentials[^\"]*)\"")
        var namen = Set<String>()
        for m in muster.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let r = Range(m.range(at: 1), in: text) { namen.insert(String(text[r])) }
        }
        if namen.isEmpty, token(dienst: "Claude Code-credentials") != nil { namen.insert("Claude Code-credentials") }
        return namen.map { ($0, token(dienst: $0)?.ablauf ?? 0) }.sorted { $0.1 > $1.1 }.map(\.0)
    }

    static func token(dienst: String) -> (token: String, ablauf: Double)? {
        guard let d = security(["find-generic-password", "-s", dienst, "-w"]) else { return nil }
        return tokenLesen(d)
    }

    /// Claude Code ohne Schlüsselbund (Linux-Art, auch auf manchen Macs): Datei mit demselben JSON.
    static let dateiDienst = "~/.claude/.credentials.json"
    static func dateiToken() -> (token: String, ablauf: Double)? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
        guard let d = try? Data(contentsOf: url) else { return nil }
        return tokenLesen(d)
    }

    static func tokenLesen(_ d: Data) -> (token: String, ablauf: Double)? {
        guard let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let o = j["claudeAiOauth"] as? [String: Any],
              let t = o["accessToken"] as? String else { return nil }
        let a = (o["expiresAt"] as? NSNumber)?.doubleValue ?? 0
        return (t, a < 1e11 ? a * 1000 : a)  // Sekunden oder Millisekunden
    }

    static let namen = ["five_hour": "5-Stunden-Fenster", "seven_day": "Woche – alle Modelle",
                        "seven_day_opus": "Woche – Opus", "seven_day_sonnet": "Woche – Sonnet",
                        "seven_day_oauth_apps": "Woche – Apps"]
    static let reihenfolge = ["five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet"]

    static func ohneFuenfStunden(_ d: Data) -> Bool {
        guard let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let v = j["five_hour"] else { return false }
        return v is NSNull
    }

    static func limitsLesen(_ d: Data) -> [Limit]? {
        guard let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        let isoBruch = ISO8601DateFormatter()
        isoBruch.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()
        return j.compactMap { k, v -> Limit? in
            guard let o = v as? [String: Any], let u = (o["utilization"] as? NSNumber)?.doubleValue else { return nil }
            let s = o["resets_at"] as? String
            return Limit(id: k, name: namen[k] ?? "Weiteres Limit", prozent: u,
                         reset: s.flatMap { isoBruch.date(from: $0) ?? iso.date(from: $0) })
        }.sorted {
            (reihenfolge.firstIndex(of: $0.id) ?? 9, $0.id) < (reihenfolge.firstIndex(of: $1.id) ?? 9, $1.id)
        }
    }

    // MARK: Lokale Token & API-Gegenwert

    struct Preis { let ein, aus, lesen: Double }  // $ pro Mio. Token

    // Reihenfolge wichtig: spezifischer Name zuerst.
    static let preise: [(String, Preis)] = [
        ("fable", Preis(ein: 10, aus: 50, lesen: 0.25)), ("mythos", Preis(ein: 10, aus: 50, lesen: 0.25)),
        ("opus-5-5", Preis(ein: 4, aus: 20, lesen: 0.20)), ("opus", Preis(ein: 5, aus: 25, lesen: 0.50)),
        ("sonnet-5", Preis(ein: 2, aus: 10, lesen: 0.20)), ("sonnet", Preis(ein: 3, aus: 15, lesen: 0.30)),
        ("haiku-5", Preis(ein: 0.10, aus: 0.50, lesen: 0.01)), ("haiku", Preis(ein: 1, aus: 5, lesen: 0.10)),
    ]

    static func preis(_ modell: String) -> Preis { preise.first { modell.contains($0.0) }?.1 ?? preise[2].1 }

    static func summe(modell: String, usage u: [String: Any]) -> TokenSumme {
        let n = { (k: String) in (u[k] as? NSNumber)?.intValue ?? 0 }
        let p = preis(modell)
        var s = TokenSumme(eingabe: n("input_tokens"), ausgabe: n("output_tokens"),
                           cacheSchreiben: n("cache_creation_input_tokens"), cacheLesen: n("cache_read_input_tokens"))
        let einStunde = ((u["cache_creation"] as? [String: Any])?["ephemeral_1h_input_tokens"] as? NSNumber)?.intValue ?? 0
        let fuenfMinuten = s.cacheSchreiben - einStunde
        s.kosten = (Double(s.eingabe) * p.ein + Double(s.ausgabe) * p.aus
                    + Double(fuenfMinuten) * p.ein * 1.25 + Double(einStunde) * p.ein * 2
                    + Double(s.cacheLesen) * p.lesen) / 1_000_000
        return s
    }

    typealias Eintrag = (id: String, ts: Date, s: TokenSumme)
    // Nur auf tokenWarteschlange (bzw. im Selbsttest) benutzen.
    private static var zwischenspeicher: [URL: (geaendert: Date, eintraege: [Eintrag])] = [:]

    // ponytail: geänderte Dateien werden komplett neu gelesen; bei riesigen Logs auf Datei-Offsets umstellen.
    static func lokaleToken(jetzt: Date = Date(),
                            ordner: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects"))
        -> (heute: TokenSumme, fuenfStunden: TokenSumme) {
        let tagesBeginn = Calendar.current.startOfDay(for: jetzt)
        let grenze5 = jetzt.addingTimeInterval(-5 * 3600)
        let ab = min(tagesBeginn, grenze5)
        var heute = TokenSumme(), fuenf = TokenSumme()
        var gesehen = Set<String>()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let e = FileManager.default.enumerator(at: ordner, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return (heute, fuenf)
        }
        var aktuell: [URL: (geaendert: Date, eintraege: [Eintrag])] = [:]
        for case let url as URL in e where url.pathExtension == "jsonl" {
            guard let geaendert = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  geaendert >= ab else { continue }
            if let c = zwischenspeicher[url], c.geaendert == geaendert { aktuell[url] = c; continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            var eintraege: [Eintrag] = []
            for zeile in text.split(separator: "\n") where zeile.contains("\"usage\"") {
                guard let j = try? JSONSerialization.jsonObject(with: Data(zeile.utf8)) as? [String: Any],
                      let msg = j["message"] as? [String: Any],
                      let u = msg["usage"] as? [String: Any],
                      let ts = (j["timestamp"] as? String).flatMap(iso.date(from:)), ts >= ab else { continue }
                let id = (msg["id"] as? String).map { "\($0)|\(j["requestId"] as? String ?? "")" } ?? (j["uuid"] as? String ?? UUID().uuidString)
                eintraege.append((id, ts, summe(modell: msg["model"] as? String ?? "", usage: u)))
            }
            aktuell[url] = (geaendert, eintraege)
        }
        zwischenspeicher = aktuell
        for (_, c) in aktuell {
            // Claude Code schreibt dieselbe Antwort pro Inhaltsblock erneut → nach Nachricht + Request entdoppeln.
            for e in c.eintraege where e.ts >= ab && gesehen.insert(e.id).inserted {
                if e.ts >= tagesBeginn { heute.add(e.s) }
                if e.ts >= grenze5 { fuenf.add(e.s) }
            }
        }
        return (heute, fuenf)
    }
}

// MARK: - Selbsttest (MacNotche --selbsttest)

enum Selbsttest {
    static func laufen() {
        let s = ClaudeUsage.summe(modell: "claude-opus-5-5", usage: [
            "input_tokens": 1_000_000, "output_tokens": 1_000_000,
            "cache_read_input_tokens": 1_000_000, "cache_creation_input_tokens": 1_000_000,
            "cache_creation": ["ephemeral_1h_input_tokens": 1_000_000],
        ])
        precondition(abs(s.kosten - (4 + 20 + 0.2 + 8)) < 0.0001, "Kosten falsch: \(s.kosten)")
        precondition(ClaudeUsage.preis("claude-sonnet-5-5").ein == 2 && ClaudeUsage.preis("claude-opus-5").ein == 5)

        let antwort = #"{"seven_day":{"utilization":40,"resets_at":"2026-11-05T10:00:00.123+00:00"},"five_hour":{"utilization":12.5,"resets_at":"2026-11-01T15:00:00Z"},"extra_usage":null}"#
        let l = ClaudeUsage.limitsLesen(Data(antwort.utf8))!
        precondition(l.map(\.id) == ["five_hour", "seven_day"], "Reihenfolge: \(l.map(\.id))")
        precondition(l[0].prozent == 12.5 && l[0].reset != nil && l[1].reset != nil, "Reset-Zeiten nicht gelesen")
        precondition(!ClaudeUsage.ohneFuenfStunden(Data(antwort.utf8)) && ClaudeUsage.ohneFuenfStunden(Data(#"{"five_hour":null,"seven_day":{"utilization":1}}"#.utf8)), "five_hour null")

        precondition(Updates.neuer("2.10", als: "2.9") && !Updates.neuer("2.5", als: "2.5") && !Updates.neuer("2.4.1", als: "2.5"), "Versionsvergleich")
        let rel = #"{"tag_name":"v2.6","html_url":"https://x/r","assets":[{"name":"Mac Notche 2.6.dmg","browser_download_url":"https://x/d.dmg"}]}"#
        let r = Updates.lesen(Data(rel.utf8))!
        precondition(r.0 == "2.6" && r.1.absoluteString == "https://x/d.dmg", "Release-Antwort")
        precondition(Verbindungen.jwt("a.eyJlbWFpbCI6ImFAYi5jIn0.b")?["email"] as? String == "a@b.c", "JWT")

        let ordner = FileManager.default.temporaryDirectory.appendingPathComponent("kerbe-test-\(UUID().uuidString)/p")
        try! FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let jetzt = Date()
        func zeile(_ id: String, _ t: Date) -> String {
            #"{"timestamp":"\#(iso.string(from: t))","requestId":"r\#(id)","message":{"id":"m\#(id)","model":"claude-opus-5-5","usage":{"input_tokens":1,"output_tokens":10}}}"#
        }
        let inhalt = [zeile("1", jetzt), zeile("1", jetzt), zeile("2", jetzt.addingTimeInterval(-7 * 3600)), zeile("3", jetzt.addingTimeInterval(-3 * 86400))]
        try! inhalt.joined(separator: "\n").write(to: ordner.appendingPathComponent("a.jsonl"), atomically: true, encoding: .utf8)
        let (h, f) = ClaudeUsage.lokaleToken(jetzt: jetzt, ordner: ordner.deletingLastPathComponent())
        precondition(f.ausgabe == 10, "5-Std.-Fenster: \(f.ausgabe)")
        let siebenStundenHeute = Calendar.current.isDate(jetzt.addingTimeInterval(-7 * 3600), inSameDayAs: jetzt)
        precondition(h.ausgabe == (siebenStundenHeute ? 20 : 10), "Heute: \(h.ausgabe)")
        let w = Wetter.lesen(Data(#"{"current":{"temperature_2m":7.6,"weather_code":3,"is_day":1},"daily":{"time":["2026-11-01","2026-11-02"],"weather_code":[61,3],"temperature_2m_max":[8.2,7.0],"temperature_2m_min":[4.5,2.6],"precipitation_probability_max":[25,3]}}"#.utf8))!
        precondition(w.0.temp == 7.6 && w.1.count == 2 && w.1[0].regen == 25 && w.1[1].code == 3, "Wetter falsch gelesen")
        precondition(Wetter.beschreibung(61).text == "Regen" && Wetter.beschreibung(0, tag: false).symbol == "moon.stars.fill")
        var blob = Array("streamtyped NSAttributedString NSString".utf8) + [0x01, 0x94, 0x84, 0x01, 0x2B, 5] + Array("Hallo".utf8) + [0x86]
        precondition(Mitteilungen.nachrichtText(Data(blob)) == "Hallo", "Nachrichtentext kurz")
        let lang = String(repeating: "ä", count: 100)  // 200 Byte → Länge mit 0x81-Präfix
        blob = Array("NSString".utf8) + [0x01, 0x2B, 0x81, 200, 0] + Array(lang.utf8)
        precondition(Mitteilungen.nachrichtText(Data(blob)) == lang, "Nachrichtentext lang")
        precondition(Mitteilungen.maskieren(#"a"b\c"#) == #"a\"b\\c"#)
        var auge = Blinzeln()
        precondition(!auge.neu(0.30) && !auge.neu(0.30) && !auge.neu(0.10) && auge.neu(0.29), "Blinzeln nicht erkannt")
        var foto = Blinzeln()
        precondition(!(0..<30).contains { _ in foto.neu(0.30) }, "Standbild darf nicht als Blinzeln gelten")
        let v = GesichtsErkennung.normiert([3, 4])
        precondition(abs(GesichtsErkennung.aehnlichkeit(v, v) - 1) < 1e-5 && abs(v[0] - 0.6) < 1e-5)
        if Bundle.main.bundlePath.hasSuffix(".app") { precondition(GesichtsErkennung().bereit, "Gesichtsmodell lädt nicht") }
        // Textbausteine: längstes Kürzel am Ende gewinnt, Emojis nur mit Schalter.
        let gemerkt = UserDefaults.standard.dictionary(forKey: E.bausteine)
        UserDefaults.standard.set([";m": "kurz", ";mfg": "Mit freundlichen Grüßen"], forKey: E.bausteine)
        precondition(Textbausteine.treffer("Hallo ;mfg")?.1 == "Mit freundlichen Grüßen")
        precondition(Textbausteine.treffer("Hallo ;mf") == nil)
        precondition(Textbausteine.treffer("super :herz:")?.1 == "❤️")
        UserDefaults.standard.set(gemerkt, forKey: E.bausteine)
        // Kurse: Yahoo-Antwort lesen, Änderung zum Vortag.
        let k = Kurse.lesen(#"{"chart":{"result":[{"meta":{"regularMarketPrice":110.0,"chartPreviousClose":100.0,"currency":"EUR","shortName":"Test AG"}}]}}"#.data(using: .utf8)!, symbol: "T")
        precondition(k?.name == "Test AG" && abs((k?.aenderung ?? 0) - 10) < 0.001)
        // Codex: Token ab heute, Cache aus input_tokens herausgerechnet, Limits aus dem jüngsten Ereignis.
        func cx(_ t: Date, _ prozent: Double) -> String {
            #"{"timestamp":"\#(iso.string(from: t))","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":20}},"rate_limits":{"primary":{"used_percent":\#(prozent),"window_minutes":300,"resets_at":\#(jetzt.timeIntervalSince1970 + 3600)},"secondary":{"used_percent":5.0,"window_minutes":10080,"resets_at":\#(jetzt.timeIntervalSince1970 - 60)},"plan_type":"plus"}}}"#
        }
        let cxt = AndereKIs.codexLesen([cx(jetzt, 30), cx(jetzt.addingTimeInterval(-60), 10), cx(jetzt.addingTimeInterval(-3 * 86400), 99)].joined(separator: "\n"),
                                       ab: jetzt.addingTimeInterval(-3600), jetzt: jetzt)
        precondition(cxt.summe.eingabe == 120 && cxt.summe.cacheLesen == 80 && cxt.summe.ausgabe == 40, "Codex-Token: \(cxt.summe)")
        precondition(cxt.limits.map(\.name) == ["5 Stunden", "Woche"] && cxt.limits[0].prozent == 30 && cxt.limits[1].prozent == 0 && cxt.plan == "plus", "Codex-Limits")
        // Gemini: JSON-Datei mit Nachrichtenliste, alte Nachricht zählt nicht.
        let gm = AndereKIs.geminiLesen(#"[{"timestamp":"\#(iso.string(from: jetzt))","tokens":{"input":100,"output":20,"cached":40,"thoughts":5}},{"timestamp":"2020-01-01T00:00:00.000Z","tokens":{"input":9,"output":9}}]"#,
                                       ab: jetzt.addingTimeInterval(-3600))
        precondition(gm.eingabe == 60 && gm.cacheLesen == 40 && gm.ausgabe == 25, "Gemini-Token: \(gm)")
        // Ecken: nur echte Ecken zählen.
        let eckRahmen = NSRect(x: 0, y: 0, width: 100, height: 50)
        precondition(Ecken.ecke(NSPoint(x: 0, y: 50), in: eckRahmen) == "ecke.ol" && Ecken.ecke(NSPoint(x: 99.5, y: 0), in: eckRahmen) == "ecke.ur")
        precondition(Ecken.ecke(NSPoint(x: 50, y: 50), in: eckRahmen) == nil && Ecken.ecke(NSPoint(x: 0, y: 25), in: eckRahmen) == nil)
        // Akku: 10 % in 2 Tagen bei 60 % → 12 Tage; Laden setzt die Messung zurück.
        let t0 = jetzt.addingTimeInterval(-2 * 86400)
        precondition(abs((AkkuVerlauf.restTage([(t0, 70), (jetzt, 60)]) ?? 0) - 12) < 0.01, "Akku-Prognose")
        precondition(AkkuVerlauf.restTage([(t0, 20), (t0.addingTimeInterval(3600), 100), (jetzt, 99)]) == nil, "Nach Laden zu wenig Verbrauch")
        // Sport: live zählt die Tore-Liste, beendet das Endergebnis, Zukunft ohne Ergebnis.
        let sp = Sport.lesen(Data(#"[{"matchID":1,"matchDateTimeUTC":"2026-10-31T14:30:00Z","matchIsFinished":false,"team1":{"shortName":"Bremen"},"team2":{"teamName":"TSG Hoffenheim","shortName":""},"goals":[{"scoreTeam1":1,"scoreTeam2":0},{"scoreTeam1":2,"scoreTeam2":0}],"matchResults":[{"resultOrderID":1,"pointsTeam1":0,"pointsTeam2":0}]},{"matchID":2,"matchDateTimeUTC":"2030-01-01T14:30:00Z","matchIsFinished":false,"team1":{"shortName":"A"},"team2":{"shortName":"B"}},{"matchID":3,"matchDateTimeUTC":"2026-10-30T14:30:00Z","matchIsFinished":true,"team1":{"shortName":"C"},"team2":{"shortName":"D"},"goals":[{"scoreTeam1":1,"scoreTeam2":0}],"matchResults":[{"resultOrderID":2,"pointsTeam1":3,"pointsTeam2":1},{"resultOrderID":1,"pointsTeam1":1,"pointsTeam2":0}]}]"#.utf8), jetzt: jetzt)!
        precondition(sp[0].ergebnis == "2:0" && sp[0].gast == "TSG Hoffenheim" && sp[0].live, "Sport live: \(sp[0])")
        precondition(sp[1].ergebnis == "–:–" && !sp[1].live && sp[2].ergebnis == "3:1", "Sport: \(sp.map(\.ergebnis))")
        // Fenster-Rahmen: Hälften und Drittel ohne Lücken.
        let schirm = NSRect(x: 0, y: 0, width: 900, height: 600)
        precondition(Fenster.rahmen(.links, in: schirm).maxX == Fenster.rahmen(.rechts, in: schirm).minX && Fenster.rahmen(.drittel3, in: schirm).maxX == 900)
        // Agent: JSON auch mit Text drumherum lesen.
        let (schritte, _) = Agent.lesen("Hier:\n```json\n{\"schritte\":[{\"was\":\"a\",\"befehl\":\"ls\"},{\"was\":\"leer\",\"befehl\":\"\"}]}\n```")
        precondition(schritte.count == 1 && schritte[0].befehl == "ls", "Agent-Plan")
        precondition(Agent.lesen("{\"schritte\":[],\"grund\":\"nein\"}").1 == "nein")
        print("Apps mit Ton: " + AppLautstaerke.prozesse().map(\.name).joined(separator: ", "))
        print("Selbsttest ok")
    }
}
