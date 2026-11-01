import AppKit
import Carbon.HIToolbox

// MARK: - Menüleiste aufräumen

/// Zwei eigene Symbole: Pfeil zum Umschalten und ein Trenner. Alles links vom Trenner verschwindet,
/// indem der Trenner beim Einklappen 10 000 pt breit wird und die Symbole aus dem Bild schiebt.
final class Menueleiste {
    private var pfeil: NSStatusItem?
    private var trenner: NSStatusItem?
    private var eingeklappt = false
    private var zuklappen: DispatchWorkItem?

    func starten() {
        anwenden()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.anwenden() }
        Tastenkuerzel.registrieren(kVK_ANSI_M, controlKey | optionKey) { [weak self] in self?.umschalten() }
    }

    private func anwenden() {
        let an = UserDefaults.standard.bool(forKey: E.leisteAktiv)
        if !an {
            if let p = pfeil { NSStatusBar.system.removeStatusItem(p) }
            if let t = trenner { NSStatusBar.system.removeStatusItem(t) }
            pfeil = nil; trenner = nil; eingeklappt = false
            return
        }
        guard pfeil == nil else { return }
        // Neue Symbole erscheinen links der vorhandenen: erst Pfeil, dann Trenner links daneben.
        let p = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        p.autosaveName = "kerbe.leiste.pfeil"
        p.button?.target = self
        p.button?.action = #selector(geklickt)
        let t = NSStatusBar.system.statusItem(withLength: 8)
        t.autosaveName = "kerbe.leiste.trenner"
        t.button?.image = NSImage(systemSymbolName: "line.diagonal", accessibilityDescription: "Trenner")
        t.button?.appearsDisabled = true
        pfeil = p; trenner = t
        bild()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.setzen(eingeklappt: true) }
    }

    @objc private func geklickt() { umschalten() }

    func umschalten() { setzen(eingeklappt: !eingeklappt) }

    private func setzen(eingeklappt neu: Bool) {
        guard let p = pfeil, let t = trenner else { return }
        // Liegt der Trenner rechts vom Pfeil, würde Einklappen alles verschieben – dann lieber nichts tun.
        if neu, let tx = t.button?.window?.frame.minX, let px = p.button?.window?.frame.minX, tx > px { return }
        eingeklappt = neu
        t.length = neu ? 10_000 : 8
        bild()
        zuklappen?.cancel()
        let sekunden = UserDefaults.standard.double(forKey: E.leisteSekunden)
        if !neu, sekunden > 0 {
            let w = DispatchWorkItem { [weak self] in self?.setzen(eingeklappt: true) }
            zuklappen = w
            DispatchQueue.main.asyncAfter(deadline: .now() + sekunden, execute: w)
        }
    }

    private func bild() {
        pfeil?.button?.image = NSImage(systemSymbolName: eingeklappt ? "chevron.left" : "chevron.right",
                                       accessibilityDescription: eingeklappt ? "Symbole zeigen" : "Symbole ausblenden")
    }
}

// MARK: - Bildschirmecken

final class Ecken {
    enum Aktion: String, CaseIterable {
        case nichts = "Nichts", notch = "Notch öffnen", fragen = "Claude fragen", ablage = "Ablage öffnen"
        case missionControl = "Mission Control", schreibtisch = "Schreibtisch zeigen"
        case bildschirmschoner = "Bildschirmschoner", sperren = "Bildschirm aus (sperrt)"
    }
    static let ecken = [("ecke.ol", "Oben links"), ("ecke.or", "Oben rechts"), ("ecke.ul", "Unten links"), ("ecke.ur", "Unten rechts")]

    var notch: ((Aktion) -> Void)?
    private var aktuelle: String?
    private var seit = Date()
    private var ausgeloest = false

    func starten() {
        // ponytail: Abfrage alle 0,2 s statt Ereignis-Monitor – braucht keine Erlaubnis und kostet kaum etwas.
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.pruefen() }
    }

    static func ecke(_ p: NSPoint, in f: NSRect) -> String? {
        let links = p.x <= f.minX + 2, rechts = p.x >= f.maxX - 3, unten = p.y <= f.minY + 2, oben = p.y >= f.maxY - 3
        switch (oben, unten, links, rechts) {
        case (true, _, true, _): return "ecke.ol"
        case (true, _, _, true): return "ecke.or"
        case (_, true, true, _): return "ecke.ul"
        case (_, true, _, true): return "ecke.ur"
        default: return nil
        }
    }

    private static func starte(_ pfad: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: pfad)
        p.arguments = args
        try? p.run()
    }

    private func pruefen() {
        let p = NSEvent.mouseLocation
        let e = NSEvent.pressedMouseButtons == 0 ? NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) }.flatMap { Self.ecke(p, in: $0.frame) } : nil
        guard let e else { aktuelle = nil; ausgeloest = false; return }
        if e != aktuelle { aktuelle = e; seit = Date(); ausgeloest = false; return }
        guard !ausgeloest, Date().timeIntervalSince(seit) >= 0.35,
              let a = UserDefaults.standard.string(forKey: e).flatMap(Aktion.init(rawValue:)), a != .nichts else { return }
        ausgeloest = true
        switch a {
        case .missionControl: Self.starte("/usr/bin/open", ["-a", "Mission Control"])
        case .schreibtisch: Self.starte("/System/Applications/Mission Control.app/Contents/MacOS/Mission Control", ["1"])
        case .bildschirmschoner: Self.starte("/usr/bin/open", ["-a", "ScreenSaverEngine"])
        case .sperren: Self.starte("/usr/bin/pmset", ["displaysleepnow"])
        default: notch?(a)
        }
    }
}

// MARK: - Akku-Verlauf

/// Je Gerät ein Messpunkt pro halbe Stunde (oder bei Änderung), 14 Tage lang.
enum AkkuVerlauf {
    private static let schluessel = "akku.verlauf"

    static func merken(_ liste: [GeraetAkku], jetzt: Date = Date()) {
        var alle = (UserDefaults.standard.dictionary(forKey: schluessel) as? [String: [[Double]]]) ?? [:]
        let t = jetzt.timeIntervalSince1970
        for g in liste {
            var p = (alle[g.name] ?? []).filter { $0.count == 2 && t - $0[0] < 14 * 86400 }
            if let l = p.last, t - l[0] < 1800, Int(l[1]) == g.prozent { continue }
            p.append([t, Double(g.prozent)])
            alle[g.name] = p
        }
        UserDefaults.standard.set(alle, forKey: schluessel)
    }

    static func punkte(_ name: String) -> [(Date, Int)] {
        let roh = (UserDefaults.standard.dictionary(forKey: schluessel) as? [String: [[Double]]])?[name] ?? []
        return roh.filter { $0.count == 2 }.map { (Date(timeIntervalSince1970: $0[0]), Int($0[1])) }
    }

    /// Tage bis leer, aus dem Verbrauch seit dem letzten Laden. Nil, solange zu wenig Daten da sind.
    static func restTage(_ p: [(Date, Int)]) -> Double? {
        guard p.count >= 2 else { return nil }
        var start = 0
        for i in 1..<p.count where p[i].1 > p[i - 1].1 + 3 { start = i }  // geladen → neu anfangen
        let a = p[start], b = p[p.count - 1]
        let dauer = b.0.timeIntervalSince(a.0), verbrauch = Double(a.1 - b.1)
        guard dauer >= 6 * 3600, verbrauch >= 2 else { return nil }
        return Double(b.1) / (verbrauch / dauer) / 86400
    }
}

// MARK: - Claude fragen (wie „Blip“)

final class Fragen: ObservableObject {
    @Published var frage = ""
    @Published var antwort = ""
    @Published var laeuft = false
    @Published var mitBildschirm = false
    private var prozess: Process?

    static var claudePfad: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(home)/.claude/local/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static let system = "Du bist ein Helfer in der Mac-Notch. Antworte knapp und auf Deutsch, außer die Frage ist in einer anderen Sprache."

    func senden() {
        let f = frage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !f.isEmpty, !laeuft else { return }
        var bild: Data?
        if mitBildschirm {
            bild = ClaudeAufruf.bildschirmfoto()
            guard bild != nil else {
                antwort = "Dafür braucht Mac Notche die Erlaubnis „Bildschirmaufnahme“ (Systemeinstellungen › Datenschutz & Sicherheit). Danach noch einmal fragen."
                return
            }
        }
        laeuft = true; antwort = ""
        let system = Self.system + (bild != nil ? " Du siehst ein Foto des aktuellen Bildschirms des Nutzers; beziehe dich darauf." : "")
        prozess = ClaudeAufruf.senden(f, system: system, bild: bild) { [weak self] a in
            self?.antwort = a
            self?.laeuft = false
        }
    }

    func stopp() { prozess?.terminate() }
}

// MARK: - Sport (OpenLigaDB, ohne Schlüssel)

struct Spiel: Identifiable, Equatable {
    let id: Int
    let heim, gast: String
    let anstoss: Date
    let fertig: Bool
    let tore: (Int, Int)?
    var live: Bool { !fertig && anstoss <= Date() }
    var ergebnis: String { tore.map { "\($0.0):\($0.1)" } ?? "–:–" }
    static func == (a: Spiel, b: Spiel) -> Bool { a.id == b.id && a.fertig == b.fertig && a.ergebnis == b.ergebnis }
}

final class Sport: ObservableObject {
    @Published var spiele: [Spiel] = []
    var melden: ((String, String, String) -> Void)?

    func starten() {
        laden()
        Timer.scheduledTimer(withTimeInterval: 90, repeats: true) { [weak self] _ in self?.laden() }
        NotificationCenter.default.addObserver(forName: .sportLaden, object: nil, queue: .main) { [weak self] _ in self?.laden() }
    }

    func laden() {
        let vereine = Self.vereine()
        guard !vereine.isEmpty else { spiele = []; return }
        let liga = (UserDefaults.standard.string(forKey: E.sportLiga) ?? "bl1").trimmingCharacters(in: .whitespaces)
        guard !liga.isEmpty, let url = URL(string: "https://api.openligadb.de/getmatchdata/\(liga)") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] d, _, _ in
            guard let d, let alle = Self.lesen(d) else { return }
            let meine = alle.filter { s in vereine.contains { s.heim.localizedCaseInsensitiveContains($0) || s.gast.localizedCaseInsensitiveContains($0) } }
            DispatchQueue.main.async {
                guard let self else { return }
                for s in meine where s.live {
                    if let alt = self.spiele.first(where: { $0.id == s.id }), alt.ergebnis != s.ergebnis, s.tore != nil {
                        self.melden?("sport", "soccerball", "Tor! \(s.heim) \(s.ergebnis) \(s.gast)")
                    }
                }
                if self.spiele != meine { self.spiele = meine }
            }
        }.resume()
    }

    static func vereine() -> [String] {
        (UserDefaults.standard.string(forKey: E.sportVereine) ?? "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func lesen(_ d: Data, jetzt: Date = Date()) -> [Spiel]? {
        guard let a = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return nil }
        let iso = ISO8601DateFormatter()
        return a.compactMap { m in
            guard let id = m["matchID"] as? Int,
                  let t1 = m["team1"] as? [String: Any], let t2 = m["team2"] as? [String: Any],
                  let zeit = (m["matchDateTimeUTC"] as? String).flatMap(iso.date(from:)) else { return nil }
            func name(_ t: [String: Any]) -> String { (t["shortName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? t["teamName"] as? String ?? "?" }
            let fertig = m["matchIsFinished"] as? Bool ?? false
            // Live ist die Tore-Liste aktueller als die Ergebnisse; nach dem Abpfiff zählt das Endergebnis.
            var tore: (Int, Int)?
            if let g = (m["goals"] as? [[String: Any]])?.last, let a = g["scoreTeam1"] as? Int, let b = g["scoreTeam2"] as? Int { tore = (a, b) }
            if fertig || tore == nil,
               let r = (m["matchResults"] as? [[String: Any]])?.max(by: { ($0["resultOrderID"] as? Int ?? 0) < ($1["resultOrderID"] as? Int ?? 0) }),
               let a = r["pointsTeam1"] as? Int, let b = r["pointsTeam2"] as? Int { tore = (a, b) }
            if tore == nil { tore = (0, 0) }
            return Spiel(id: id, heim: name(t1), gast: name(t2), anstoss: zeit, fertig: fertig, tore: zeit <= jetzt ? tore : nil)
        }
    }
}

extension Notification.Name { static let sportLaden = Notification.Name("kerbe.sportLaden") }
