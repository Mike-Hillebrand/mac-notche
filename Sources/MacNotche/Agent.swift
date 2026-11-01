import AppKit

// MARK: - Claude-Aufruf (Text, mit Bild) über die Claude-Code-Kommandozeile

enum ClaudeAufruf {
    /// Schickt eine Nachricht (optional mit JPEG) an `claude -p` und liefert die Antwort. Keine Werkzeuge, kein Dateizugriff.
    @discardableResult
    static func senden(_ text: String, system: String, bild: Data? = nil, modell: String? = nil,
                       fertig: @escaping (String) -> Void) -> Process? {
        guard let pfad = Fragen.claudePfad else {
            fertig("Claude Code ist nicht installiert. Im Terminal: curl -fsSL https://claude.ai/install.sh | bash"); return nil
        }
        var inhalt: [[String: Any]] = []
        if let bild { inhalt.append(["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": bild.base64EncodedString()]]) }
        inhalt.append(["type": "text", "text": text])
        let nachricht: [String: Any] = ["type": "user", "message": ["role": "user", "content": inhalt]]
        guard var eingabe = try? JSONSerialization.data(withJSONObject: nachricht) else { fertig("Anfrage ließ sich nicht bauen."); return nil }
        eingabe.append(10)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: pfad)
        // Ohne Werkzeuge, ohne eigene Einstellungen/Hooks, ohne gespeicherte Sitzung: nur eine Antwort über dein Abo.
        p.arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                       "--model", modell ?? UserDefaults.standard.string(forKey: E.fragenModell) ?? "sonnet",
                       "--tools", "", "--no-session-persistence", "--strict-mcp-config", "--setting-sources", "project",
                       "--system-prompt", system]
        p.currentDirectoryURL = FileManager.default.temporaryDirectory
        let rein = Pipe(), raus = Pipe()
        p.standardInput = rein; p.standardOutput = raus; p.standardError = raus
        p.terminationHandler = { pr in
            let text = String(decoding: raus.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            var ergebnis: String?
            for zeile in text.split(separator: "\n") {
                if let j = try? JSONSerialization.jsonObject(with: Data(zeile.utf8)) as? [String: Any], j["type"] as? String == "result" {
                    ergebnis = j["result"] as? String ?? (j["error"] as? String)
                }
            }
            let antwort = pr.terminationReason == .uncaughtSignal ? "Abgebrochen." :
                text.contains("Not logged in") ? "Claude Code ist nicht angemeldet. Einmal „claude“ im Terminal starten." :
                ergebnis ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async { fertig(antwort) }
        }
        do { try p.run() } catch { fertig("Start fehlgeschlagen: \(error.localizedDescription)"); return nil }
        rein.fileHandleForWriting.write(eingabe)
        try? rein.fileHandleForWriting.close()
        return p
    }

    /// Bildschirmfoto des Hauptbildschirms als kleines JPEG (höchstens 1600 px breit). Nil ohne Bildschirmaufnahme-Erlaubnis.
    static func bildschirmfoto() -> Data? {
        guard CGPreflightScreenCaptureAccess() else { CGRequestScreenCaptureAccess(); return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kerbe-schirm.jpg")
        _ = Ablage.ausfuehren("/usr/sbin/screencapture", ["-x", "-t", "jpg", url.path])
        _ = Ablage.ausfuehren("/usr/bin/sips", ["-Z", "1600", "-s", "formatOptions", "70", url.path])
        defer { try? FileManager.default.removeItem(at: url) }
        return try? Data(contentsOf: url)
    }
}

// MARK: - Agent: Aufgabe planen, Schritte bestätigen, ausführen (wie „Blip“)

final class Agent: ObservableObject {
    struct Schritt: Identifiable {
        let id = UUID()
        let was: String
        let befehl: String
        var an = true
        var ausgabe = ""
        var zustand = Zustand.offen
        enum Zustand { case offen, laeuft, ok, fehler }
    }

    @Published var aufgabe = ""
    @Published var schritte: [Schritt] = []
    @Published var hinweis = ""
    @Published var plant = false
    @Published var laeuft = false
    private var prozess: Process?

    static let system = """
    Du planst Aufgaben auf dem Mac des Nutzers als zsh-Befehle. Antworte NUR mit JSON, ohne Erklärung:
    {"schritte":[{"was":"kurz auf Deutsch, was der Schritt tut","befehl":"ein zsh-Befehl"}]}
    Regeln: nur im Home-Ordner \(FileManager.default.homeDirectoryForCurrentUser.path) arbeiten. Nie rm – zum Löschen nach ~/.Trash verschieben.
    Kein sudo, keine Uploads, keine Passwörter. Höchstens 8 Schritte. Jeder Befehl muss ohne Nachfrage durchlaufen.
    Verfügbar: sips (Bilder), ffmpeg nur wenn installiert, mdfind, ditto, textutil, qlmanage, osascript, zip, shortcuts.
    Geht die Aufgabe so nicht, antworte {"schritte":[],"grund":"warum"}.
    """

    func planen() {
        let a = aufgabe.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty, !plant, !laeuft else { return }
        plant = true; schritte = []; hinweis = ""
        prozess = ClaudeAufruf.senden(a, system: Self.system) { [weak self] antwort in
            guard let self else { return }
            self.plant = false
            let (s, grund) = Self.lesen(antwort)
            self.schritte = s
            self.hinweis = s.isEmpty ? (grund ?? "Keinen Plan bekommen: \(antwort.prefix(200))") : "Prüfe die Schritte, dann „Ausführen“."
        }
    }

    static func lesen(_ antwort: String) -> ([Schritt], String?) {
        guard let a = antwort.firstIndex(of: "{"), let e = antwort.lastIndex(of: "}"),
              let j = try? JSONSerialization.jsonObject(with: Data(antwort[a...e].utf8)) as? [String: Any] else { return ([], nil) }
        let liste = (j["schritte"] as? [[String: Any]] ?? []).compactMap { s -> Schritt? in
            guard let was = s["was"] as? String, let b = s["befehl"] as? String, !b.isEmpty else { return nil }
            return Schritt(was: was, befehl: b)
        }
        return (liste, j["grund"] as? String)
    }

    func ausfuehren() {
        guard !laeuft else { return }
        laeuft = true; hinweis = ""
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            for i in schritte.indices where schritte[i].an {
                DispatchQueue.main.sync { schritte[i].zustand = .laeuft }
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/zsh")
                p.arguments = ["-lc", schritte[i].befehl]
                p.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
                let aus = Pipe(); p.standardOutput = aus; p.standardError = aus
                var text = "", ok = false
                if (try? p.run()) != nil {
                    // ponytail: 2 Minuten pro Schritt, danach abbrechen.
                    DispatchQueue.global().asyncAfter(deadline: .now() + 120) { if p.isRunning { p.terminate() } }
                    text = String(decoding: aus.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    p.waitUntilExit()
                    ok = p.terminationStatus == 0
                } else { text = "Start fehlgeschlagen" }
                DispatchQueue.main.sync {
                    schritte[i].ausgabe = String(text.trimmingCharacters(in: .whitespacesAndNewlines).suffix(300))
                    schritte[i].zustand = ok ? .ok : .fehler
                }
                if !ok { break }
            }
            DispatchQueue.main.async { laeuft = false; hinweis = schritte.contains { $0.zustand == .fehler } ? "Ein Schritt ist fehlgeschlagen, danach gestoppt." : "Fertig." }
        }
    }

    func abbrechen() { prozess?.terminate(); plant = false }
}
