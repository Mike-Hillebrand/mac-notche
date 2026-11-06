import AppKit

/// Anmeldungen der KI-Werkzeuge auf diesem Mac. Alle laufen über den Login der jeweiligen
/// Kommandozeile (OAuth im Browser), Mac Notche liest nur, was die Werkzeuge selbst ablegen.
struct Verbindung: Identifiable {
    let id: String
    let name: String
    let angemeldet: Bool
    let konto: String?      // E-Mail oder Plan
    let hinweis: String     // wo gefunden oder was fehlt
    let befehl: String?     // Terminal-Befehl zum Anmelden, nil = nicht möglich
}

enum Verbindungen {
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    static func alle() -> [Verbindung] { [claude(), codex(), gemini()] + [KI.grok, .perplexity, .mistral].map(schluessel) + [iphoneWLAN()] }

    /// iPhone über WLAN: braucht libimobiledevice (Homebrew) und den Finder-Schalter „Dieses iPhone anzeigen, wenn WLAN aktiv ist“.
    static func iphoneWLAN() -> Verbindung {
        let name = L("iPhone über WLAN")
        guard IPhoneWLAN.installiert else {
            return Verbindung(id: "iphone", name: name, angemeldet: false, konto: nil,
                              hinweis: L("libimobiledevice fehlt. „Installieren“ holt es über Homebrew; danach im Finder beim iPhone WLAN-Sync einschalten (einmal per Kabel koppeln)."),
                              befehl: IPhoneWLAN.install)
        }
        guard let u = IPhoneWLAN.udid() else {
            return Verbindung(id: "iphone", name: name, angemeldet: false, konto: nil,
                              hinweis: L("Werkzeuge da, aber kein iPhone im Netz. Im Finder beim iPhone „Dieses iPhone anzeigen, wenn WLAN aktiv ist“ einschalten, gleiches WLAN, einmal entsperren."), befehl: nil)
        }
        let info = IPhoneWLAN.info(u)
        return Verbindung(id: "iphone", name: name, angemeldet: true, konto: info.name, hinweis: L("Im Netz erreichbar") + (info.akku.map { " · Akku \($0) %" } ?? ""), befehl: nil)
    }

    /// Eine Zeile für die Fehlersuche: was die App auf diesem Mac sieht.
    static func diagnose() -> String {
        let home = Self.home.path
        func kurz(_ p: String?) -> String { p.map { $0.replacingOccurrences(of: home, with: "~") } ?? "–" }
        let eintraege = ClaudeUsage.schluesselbundDienste().count
        let datei = FileManager.default.fileExists(atPath: home + "/.claude/.credentials.json")
        return "claude: \(kurz(pfad("claude"))) · codex: \(kurz(pfad("codex"))) · agy: \(kurz(pfad("agy"))) · "
            + L("Schlüsselbund-Einträge: ") + "\(eintraege) · credentials.json: " + (datei ? L("ja") : L("nein"))
    }

    /// Login-Shell, damit PATH wie im Terminal gilt (nvm, ~/.local/bin).
    static func shell(_ befehl: String, sekunden: Double = 20, mitFehlern: Bool = false) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // exec: das Werkzeug ersetzt die Shell, damit SIGKILL nach der Frist wirklich das Werkzeug trifft.
        p.arguments = ["-lc", "exec " + befehl]
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = mitFehlern ? pipe : FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        // Lesen auf einem Nebenthread: Werkzeuge wie agy warten sonst ewig auf den Browser.
        let schloss = NSLock(); var daten = Data(); let fertig = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            let d = pipe.fileHandleForReading.readDataToEndOfFile()
            schloss.lock(); daten = d; schloss.unlock(); fertig.signal()
        }
        if fertig.wait(timeout: .now() + sekunden) == .timedOut {
            kill(p.processIdentifier, SIGKILL)
            _ = fertig.wait(timeout: .now() + 2)
        }
        p.waitUntilExit()
        schloss.lock(); let text = String(decoding: daten, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines); schloss.unlock()
        return p.terminationStatus == 0 || mitFehlern ? text : nil
    }

    static func pfad(_ werkzeug: String) -> String? {
        shell("command -v \(werkzeug)", sekunden: 10).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// „claude auth status“: loggedIn, email, subscriptionType.
    static func claudeStatus() -> (angemeldet: Bool, konto: String?)? {
        guard let t = shell("claude auth status"), let d = t.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        let an = j["loggedIn"] as? Bool ?? false
        let konto = [j["email"] as? String, (j["subscriptionType"] as? String).map { "Claude \($0.capitalized)" }].compactMap { $0 }.joined(separator: " · ")
        return (an, konto.isEmpty ? nil : konto)
    }

    static let claudeInstall = "curl -fsSL https://claude.ai/install.sh | bash && exec zsh -lc claude"
    /// Erst Homebrew, dann npm; fehlt beides, wird Homebrew nachinstalliert (fragt nach dem Mac-Passwort).
    static func installer(brew: String, npm: String, danach: String) -> String {
        """
        if command -v brew >/dev/null 2>&1; then brew install \(brew); \
        elif command -v npm >/dev/null 2>&1; then npm install -g \(npm); \
        else echo 'Weder Homebrew noch npm gefunden – Homebrew wird installiert (Mac-Passwort nötig).'; \
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" && \
        eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)" && brew install \(brew); fi && \(danach)
        """.replacingOccurrences(of: "\n", with: " ")
    }
    static var codexInstall: String { installer(brew: "--cask codex", npm: "@openai/codex", danach: "codex login") }
    static var geminiInstall: String { installer(brew: "gemini-cli", npm: "@google/gemini-cli", danach: "gemini") }

    static func claude() -> Verbindung {
        guard pfad("claude") != nil else {
            return Verbindung(id: "claude", name: "Claude Code", angemeldet: false, konto: nil,
                              hinweis: L("Nicht installiert. „Installieren“ holt Claude Code und startet die Anmeldung im Browser."), befehl: claudeInstall)
        }
        let status = claudeStatus()
        let dienste = ClaudeUsage.schluesselbundDienste()
        let token = dienste.first.flatMap { ClaudeUsage.token(dienst: $0) } ?? ClaudeUsage.dateiToken()
        let tokenGueltig = token.map { $0.ablauf / 1000 > Date().timeIntervalSince1970 } ?? false
        let fundort = dienste.first.map { L("Schlüsselbund: ") + $0 } ?? (ClaudeUsage.dateiToken() != nil ? "~/.claude/.credentials.json" : nil)
        if let s = status, s.angemeldet {
            let hinweis = tokenGueltig ? (fundort ?? "")
                : token != nil ? L("Anmeldung abgelaufen – Claude Code erneuert sie beim nächsten Start.")
                : L("Claude Code ist angemeldet, aber Mac Notche kann den Schlüsselbund-Eintrag „Claude Code-credentials“ nicht lesen. Schlüsselbundverwaltung öffnen, Eintrag suchen, Reiter „Zugriff“, Mac Notche erlauben – oder bei der Nachfrage „Immer erlauben“ wählen.")
            return Verbindung(id: "claude", name: "Claude Code", angemeldet: tokenGueltig, konto: s.konto, hinweis: hinweis, befehl: "claude")
        }
        if tokenGueltig {
            return Verbindung(id: "claude", name: "Claude Code", angemeldet: true, konto: nil, hinweis: fundort ?? "", befehl: "claude")
        }
        return Verbindung(id: "claude", name: "Claude Code", angemeldet: false, konto: nil,
                          hinweis: status == nil ? L("Claude Code antwortet nicht auf „claude auth status“. Einmal „claude“ im Terminal starten und anmelden.")
                                                 : L("Claude Code ist installiert, aber nicht angemeldet. „Anmelden“ öffnet das Terminal, dort /login eingeben."),
                          befehl: "claude")
    }

    static func codex() -> Verbindung {
        let url = home.appendingPathComponent(".codex/auth.json")
        let da = pfad("codex") != nil
        guard let d = try? Data(contentsOf: url), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            return Verbindung(id: "codex", name: "Codex (ChatGPT)", angemeldet: false, konto: nil,
                              hinweis: da ? L("Installiert, aber kein Login. „Anmelden“ öffnet das Terminal und den Browser (ChatGPT-Konto).")
                                          : L("Nicht installiert. „Installieren“ holt Codex (über Homebrew oder npm) und startet die Anmeldung im Browser."),
                              befehl: da ? "codex login" : codexInstall)
        }
        if let t = j["tokens"] as? [String: Any], let id = t["id_token"] as? String, let c = jwt(id) {
            let plan = ((c["https://api.openai.com/auth"] as? [String: Any])?["chatgpt_plan_type"] as? String)?.capitalized
            let mail = c["email"] as? String
            return Verbindung(id: "codex", name: "Codex (ChatGPT)", angemeldet: true,
                              konto: [mail, plan.map { "ChatGPT \($0)" }].compactMap { $0 }.joined(separator: " · "),
                              hinweis: "~/.codex/auth.json", befehl: "codex login")
        }
        if j["OPENAI_API_KEY"] is String {
            return Verbindung(id: "codex", name: "Codex (ChatGPT)", angemeldet: true, konto: L("API-Schlüssel"),
                              hinweis: L("API-Schlüssel statt ChatGPT-Login: keine Plan-Limits."), befehl: "codex login")
        }
        return Verbindung(id: "codex", name: "Codex (ChatGPT)", angemeldet: false, konto: nil,
                          hinweis: L("auth.json ohne Anmeldung."), befehl: "codex login")
    }

    static let agyInstall = "curl -fsSL https://antigravity.google/cli/install.sh | bash && exec zsh -lc agy"

    /// Antigravity CLI: „agy -p /usage“ antwortet mit dem Kontingent oder (auf stderr) mit „Authentication required“.
    /// Ohne Login wartet agy auf den Browser, daher kurze Frist.
    static func agyUsage() -> (angemeldet: Bool, text: String)? {
        guard pfad("agy") != nil, let t = shell("agy -p /usage --output-format text --print-timeout 10s 2>&1", sekunden: 12, mitFehlern: true) else { return nil }
        let an = !t.contains("Authentication required") && !t.contains("authentication required")
        return (an, t)
    }

    static func gemini() -> Verbindung {
        let name = "Gemini (Antigravity CLI)"
        guard pfad("agy") != nil else {
            let altesCli = pfad("gemini") != nil
            return Verbindung(id: "gemini", name: name, angemeldet: false, konto: nil,
                              hinweis: altesCli
                                ? L("Gemini CLI nimmt seit Juni 2026 keine privaten Google-Konten mehr an. Nachfolger ist Antigravity CLI („agy“) – „Installieren“ holt es und öffnet die Google-Anmeldung im Browser.")
                                : L("Nicht installiert. „Installieren“ holt Antigravity CLI (Googles Nachfolger von Gemini CLI) und öffnet die Google-Anmeldung im Browser."),
                              befehl: agyInstall)
        }
        guard let u = agyUsage() else {
            return Verbindung(id: "gemini", name: name, angemeldet: false, konto: nil, hinweis: L("agy antwortet nicht. Einmal „agy“ im Terminal starten."), befehl: "agy")
        }
        if !u.angemeldet {
            return Verbindung(id: "gemini", name: name, angemeldet: false, konto: nil,
                              hinweis: L("Installiert, aber nicht angemeldet. „Anmelden“ startet agy im Terminal, der Browser öffnet sich für das Google-Konto."), befehl: "agy")
        }
        let erste = u.text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        return Verbindung(id: "gemini", name: name, angemeldet: true, konto: erste.count < 60 ? erste : nil,
                          hinweis: L("Google-Konto im Schlüsselbund (Antigravity)"), befehl: "agy")
    }

    /// Anbieter ohne Abo-Werkzeug: Antworten über eigenen API-Schlüssel, Kontingent nicht auslesbar.
    static func schluessel(_ ki: KI) -> Verbindung {
        let da = ki.schluesselDa
        return Verbindung(id: ki.rawValue, name: ki.rawValue + (ki == .grok ? " (xAI)" : ""), angemeldet: da, konto: da ? L("API-Schlüssel") : nil,
                          hinweis: da ? L("Antwortet im Reiter „Fragen“, pro Anfrage bezahlt. Kein Kontingent-Ring, da der Anbieter kein Abo-Kontingent verrät.")
                                      : L("Kein Abo-Werkzeug. Mit eigenem API-Schlüssel (unten eintragen) antwortet er im Reiter „Fragen“, pro Anfrage bezahlt."),
                          befehl: nil)
    }

    /// Nutzdaten eines JWT (ohne Prüfung der Signatur – wir lesen nur, was das Werkzeug selbst gespeichert hat).
    static func jwt(_ token: String) -> [String: Any]? {
        let teile = token.split(separator: ".")
        guard teile.count >= 2 else { return nil }
        var s = String(teile[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        s += String(repeating: "=", count: (4 - s.count % 4) % 4)
        guard let d = Data(base64Encoded: s) else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }

    /// Öffnet den Login-Befehl im Terminal; die Anmeldung läuft dann im Browser des Werkzeugs.
    static func anmelden(_ befehl: String) {
        let b = befehl.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let skript = "tell application \"Terminal\"\nactivate\ndo script \"\(b)\"\nend tell"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", skript]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}
