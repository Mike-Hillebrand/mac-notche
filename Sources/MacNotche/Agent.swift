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

// MARK: - Welche KI antwortet im Reiter „Fragen“

enum KI: String, CaseIterable, Identifiable {
    case claude = "Claude", gemini = "Gemini", chatgpt = "ChatGPT", grok = "Grok", perplexity = "Perplexity", mistral = "Mistral"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .claude: "sparkle"; case .gemini: "circle.hexagongrid"; case .chatgpt: "bubble.left.and.text.bubble.right"
        case .grok: "xmark.circle"; case .perplexity: "magnifyingglass.circle"; case .mistral: "wind"
        }
    }
    var werkzeug: String { switch self { case .claude: "claude"; case .gemini: "agy"; case .chatgpt: "codex"; default: "" } }
    /// Läuft über einen API-Schlüssel (pro Anfrage bezahlt) statt über ein Abo-Werkzeug.
    var perSchluessel: Bool { self == .grok || self == .perplexity || self == .mistral }
    var kannBild: Bool { self != .gemini && self != .perplexity }
    var schluesselKonto: String { "api." + rawValue }
    var schluesselSeite: String {
        switch self { case .grok: "https://console.x.ai"; case .perplexity: "https://www.perplexity.ai/settings/api"; case .mistral: "https://console.mistral.ai/api-keys"; default: "" }
    }
    var schluesselDa: Bool { Schluesselbund.laden(konto: schluesselKonto) != nil }
    static var gewaehlt: KI { KI(rawValue: UserDefaults.standard.string(forKey: E.fragenKI) ?? "") ?? .claude }
}

/// Antworten über Antigravity CLI (Gemini) und Codex (ChatGPT) – beide ohne Werkzeuge, nur Text.
enum AndereAufruf {
    @discardableResult
    static func senden(_ ki: KI, _ text: String, system: String, bild: Data?, fertig: @escaping (String) -> Void) -> Process? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        var bildPfad: String?
        if let bild {
            let u = FileManager.default.temporaryDirectory.appendingPathComponent("kerbe-frage.jpg")
            try? bild.write(to: u); bildPfad = u.path
        }
        let ausgabe = FileManager.default.temporaryDirectory.appendingPathComponent("kerbe-antwort.txt").path
        try? FileManager.default.removeItem(atPath: ausgabe)
        let prompt = system + "\n\n" + text
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let befehl: String
        switch ki {
        case .gemini:
            befehl = "exec agy -p \(q(prompt)) --output-format json --print-timeout 180s </dev/null"
        case .chatgpt:
            befehl = "exec codex exec --ignore-user-config --ephemeral -s read-only --skip-git-repo-check -o \(q(ausgabe))"
                + (bildPfad.map { " -i \(q($0))" } ?? "") + " \(q(prompt)) </dev/null"
        case .claude:
            return ClaudeAufruf.senden(text, system: system, bild: bild, fertig: fertig)
        case .grok, .perplexity, .mistral:
            api(ki, text, system: system, bild: bild, fertig: fertig); return nil
        }
        p.arguments = ["-lc", befehl]
        p.currentDirectoryURL = FileManager.default.temporaryDirectory
        let raus = Pipe(); p.standardOutput = raus; p.standardError = raus
        p.terminationHandler = { pr in
            let roh = String(decoding: raus.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            if let bildPfad { try? FileManager.default.removeItem(atPath: bildPfad) }
            var antwort: String
            if pr.terminationReason == .uncaughtSignal { antwort = L("Abgebrochen.") }
            else if roh.contains("command not found") { antwort = L("\(ki.rawValue) ist nicht eingerichtet. Einstellungen › Verbindungen.") }
            else if roh.lowercased().contains("authentication required") || roh.contains("Not logged in") {
                antwort = L("\(ki.rawValue) ist nicht angemeldet. Einstellungen › Verbindungen › Anmelden.")
            } else {
                switch ki {
                case .gemini:
                    let zeile = roh.split(separator: "\n").last { $0.hasPrefix("{") }.map(String.init) ?? ""
                    let j = try? JSONSerialization.jsonObject(with: Data(zeile.utf8)) as? [String: Any]
                    antwort = (j?["response"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                        ?? (j?["error"] as? String) ?? roh.trimmingCharacters(in: .whitespacesAndNewlines)
                case .chatgpt:
                    antwort = (try? String(contentsOfFile: ausgabe, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
                        ?? roh.split(separator: "\n").filter { !$0.contains("ERROR") }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                case .claude, .grok, .perplexity, .mistral: antwort = roh
                }
                if antwort.isEmpty { antwort = L("Keine Antwort erhalten.") }
            }
            DispatchQueue.main.async { fertig(antwort) }
        }
        do { try p.run() } catch { fertig("Start fehlgeschlagen: \(error.localizedDescription)"); return nil }
        return p
    }
}

// MARK: - Antworten über API-Schlüssel (xAI, Perplexity, Mistral)

extension AndereAufruf {
    static func api(_ ki: KI, _ text: String, system: String, bild: Data?, fertig: @escaping (String) -> Void) {
        guard let d = Schluesselbund.laden(konto: ki.schluesselKonto), let key = String(data: d, encoding: .utf8), !key.isEmpty else {
            fertig(L("Kein API-Schlüssel für ") + ki.rawValue + L(" hinterlegt. Einstellungen › Verbindungen.")); return
        }
        var r: URLRequest
        var koerper: [String: Any]
        switch ki {
        case .perplexity:
            r = URLRequest(url: URL(string: "https://api.perplexity.ai/v1/agent")!)
            koerper = ["effort": "fast", "input": system + "\n\n" + text]
        default:
            r = URLRequest(url: URL(string: ki == .grok ? "https://api.x.ai/v1/chat/completions" : "https://api.mistral.ai/v1/chat/completions")!)
            var inhalt: [[String: Any]] = [["type": "text", "text": text]]
            if let bild { inhalt.insert(["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + bild.base64EncodedString()]], at: 0) }
            koerper = ["model": ki == .grok ? "grok-4.7" : "mistral-large-latest",
                       "messages": [["role": "system", "content": system], ["role": "user", "content": inhalt]]]
        }
        r.httpMethod = "POST"
        r.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: koerper)
        r.timeoutInterval = 120
        URLSession.shared.dataTask(with: r) { daten, antwort, fehler in
            let text = Self.antwortLesen(ki, daten: daten, code: (antwort as? HTTPURLResponse)?.statusCode, fehler: fehler)
            DispatchQueue.main.async { fertig(text) }
        }.resume()
    }

    static func antwortLesen(_ ki: KI, daten: Data?, code: Int?, fehler: Error?) -> String {
        if let fehler { return L("Keine Verbindung: ") + fehler.localizedDescription }
        let j = daten.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        if let code, code != 200 {
            let m = (j?["error"] as? [String: Any])?["message"] as? String ?? j?["error"] as? String ?? j?["message"] as? String
                ?? daten.map { String(decoding: $0.prefix(200), as: UTF8.self) } ?? ""
            return code == 401 || code == 403 ? L("API-Schlüssel für ") + ki.rawValue + L(" wird abgelehnt. Einstellungen › Verbindungen.") : "\(ki.rawValue) \(code): \(m)"
        }
        if ki == .perplexity {
            if let t = j?["output_text"] as? String, !t.isEmpty { return t }
            let teile = (j?["output"] as? [[String: Any]] ?? []).flatMap { $0["content"] as? [[String: Any]] ?? [] }
                .filter { $0["type"] as? String == "output_text" }.compactMap { $0["text"] as? String }
            if !teile.isEmpty { return teile.joined(separator: "\n") }
        } else if let c = ((j?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] {
            if let t = c as? String { return t }
            if let teile = c as? [[String: Any]] { return teile.compactMap { $0["text"] as? String }.joined(separator: "\n") }
        }
        return L("Keine Antwort erhalten.")
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
