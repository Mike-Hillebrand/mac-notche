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

    static func claude() -> Verbindung {
        let dienste = ClaudeUsage.schluesselbundDienste()
        let abgelaufen = L("Anmeldung abgelaufen – Claude Code erneuert sie beim nächsten Start.")
        if let d = dienste.first, let t = ClaudeUsage.token(dienst: d) {
            let gueltig = t.ablauf / 1000 > Date().timeIntervalSince1970
            return Verbindung(id: "claude", name: "Claude Code", angemeldet: gueltig, konto: nil,
                              hinweis: gueltig ? L("Schlüsselbund: ") + d : abgelaufen, befehl: "claude")
        }
        if let t = ClaudeUsage.dateiToken() {
            let gueltig = t.ablauf / 1000 > Date().timeIntervalSince1970
            return Verbindung(id: "claude", name: "Claude Code", angemeldet: gueltig, konto: nil,
                              hinweis: gueltig ? "~/.claude/.credentials.json" : abgelaufen, befehl: "claude")
        }
        return Verbindung(id: "claude", name: "Claude Code", angemeldet: false, konto: nil,
                          hinweis: L("Kein Login gefunden. Claude Code installieren und einmal „claude“ im Terminal starten, dort anmelden."),
                          befehl: "claude")
    }

    static func codex() -> Verbindung {
        let url = home.appendingPathComponent(".codex/auth.json")
        guard let d = try? Data(contentsOf: url), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            return Verbindung(id: "codex", name: "Codex (ChatGPT)", angemeldet: false, konto: nil,
                              hinweis: L("Kein Login gefunden. Codex installieren und „codex login“ im Terminal ausführen."), befehl: "codex login")
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
            return Verbindung(id: "gemini", name: "Gemini CLI", angemeldet: false, konto: mail,
                              hinweis: L("Kein Login gefunden. Gemini CLI installieren, „gemini“ starten und mit Google anmelden."), befehl: "gemini")
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
        let skript = "tell application \"Terminal\"\nactivate\ndo script \"\(befehl)\"\nend tell"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", skript]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}
