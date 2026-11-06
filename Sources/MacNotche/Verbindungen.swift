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

    static func alle() -> [Verbindung] { [claude(), codex(), gemini(), grok()] }

    /// Eine Zeile für die Fehlersuche: was die App auf diesem Mac sieht.
    static func diagnose() -> String {
        let home = Self.home.path
        func kurz(_ p: String?) -> String { p.map { $0.replacingOccurrences(of: home, with: "~") } ?? "–" }
        let eintraege = ClaudeUsage.schluesselbundDienste().count
        let datei = FileManager.default.fileExists(atPath: home + "/.claude/.credentials.json")
        return "claude: \(kurz(pfad("claude"))) · codex: \(kurz(pfad("codex"))) · gemini: \(kurz(pfad("gemini"))) · "
            + L("Schlüsselbund-Einträge: ") + "\(eintraege) · credentials.json: " + (datei ? L("ja") : L("nein"))
    }

    /// Login-Shell, damit PATH wie im Terminal gilt (nvm, ~/.local/bin).
    static func shell(_ befehl: String, sekunden: Double = 20) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", befehl]
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let frist = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + sekunden, execute: frist)
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit(); frist.cancel()
        return p.terminationStatus == 0 ? String(decoding: d, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) : nil
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

    static func gemini() -> Verbindung {
        let konten = home.appendingPathComponent(".gemini/google_accounts.json")
        let creds = home.appendingPathComponent(".gemini/oauth_creds.json")
        let mail = (try? Data(contentsOf: konten)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["active"] as? String
        guard let d = try? Data(contentsOf: creds), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              j["refresh_token"] is String else {
            let da = pfad("gemini") != nil
            return Verbindung(id: "gemini", name: "Gemini CLI", angemeldet: false, konto: mail,
                              hinweis: da ? L("Installiert, aber kein Login. „Anmelden“ startet Gemini im Terminal, dort „Login with Google“ wählen – der Browser öffnet sich.")
                                          : L("Nicht installiert. „Installieren“ holt Gemini CLI (über Homebrew oder npm) und startet die Google-Anmeldung im Browser."),
                              befehl: da ? "gemini" : geminiInstall)
        }
        return Verbindung(id: "gemini", name: "Gemini CLI", angemeldet: true, konto: mail, hinweis: "~/.gemini/oauth_creds.json", befehl: "gemini")
    }

    static func grok() -> Verbindung {
        Verbindung(id: "grok", name: "Grok (xAI)", angemeldet: false, konto: nil,
                   hinweis: L("Kein lokales Werkzeug und keine öffentliche Schnittstelle für das Kontingent eines Grok-Abos. Sobald xAI eines anbietet, kommt es dazu."),
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
