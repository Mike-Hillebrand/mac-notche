import Foundation

/// Hält den Claude-Code-Login am Leben, auch wenn Claude Code selbst nicht läuft.
/// Claude Code erneuert sein 8-Stunden-Token nur, solange es läuft. Mac Notche erneuert es hier genauso
/// (gleicher Endpunkt, gleiche Client-ID, belegt im Claude-Code-Binary 2.1.329) und schreibt es in
/// denselben Schlüsselbund-Eintrag zurück, damit Claude Code danach mit dem neuen Token weiterarbeitet.
/// Verliert der Eintrag seinen Login (kam vor: nur noch „mcpOAuth“ drin), stellt die eigene Sicherung ihn wieder her.
enum ClaudeLogin {
    static let dienst = "Claude Code-credentials"
    static let sicherung = "Mac Notche-Claude-Login"
    static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let sperre = NSLock()

    /// Sorgt dafür, dass im Haupteintrag ein gültiges Token liegt. Läuft synchron (Hintergrund-Threads).
    @discardableResult
    static func sicherstellen() -> Bool {
        sperre.lock(); defer { sperre.unlock() }
        var json = lesen(dienst) ?? [:]
        var o = json["claudeAiOauth"] as? [String: Any]
        let gesichert = lesen(sicherung)?["claudeAiOauth"] as? [String: Any]

        if let o, gueltig(o) {
            if (gesichert?["refreshToken"] as? String) != (o["refreshToken"] as? String) {
                schreiben(sicherung, ["claudeAiOauth": o])
            }
            return true
        }
        // Login fehlt im Haupteintrag: mit der Sicherung weitermachen.
        if o?["refreshToken"] == nil { o = gesichert }
        guard var login = o, let alt = login["refreshToken"] as? String,
              let neu = erneuern(alt, scopes: login["scopes"] as? [String]) else { return false }

        // Hat Claude Code inzwischen selbst erneuert, dessen Stand behalten (sonst überschreiben wir ein neueres Token).
        if let jetzt = lesen(dienst)?["claudeAiOauth"] as? [String: Any], gueltig(jetzt) { return true }

        login["accessToken"] = neu.access
        login["refreshToken"] = neu.refresh ?? alt
        login["expiresAt"] = Int64((Date().timeIntervalSince1970 + neu.sekunden) * 1000)
        if let r = neu.refreshSekunden { login["refreshTokenExpiresAt"] = Int64((Date().timeIntervalSince1970 + r) * 1000) }
        json["claudeAiOauth"] = login
        guard schreiben(dienst, json) else { return false }
        schreiben(sicherung, ["claudeAiOauth": login])
        return true
    }

    static func gueltig(_ o: [String: Any]) -> Bool {
        guard o["accessToken"] is String, let e = (o["expiresAt"] as? NSNumber)?.doubleValue else { return false }
        return (e < 1e11 ? e : e / 1000) > Date().timeIntervalSince1970 + 120
    }

    private static func erneuern(_ refresh: String, scopes: [String]?) -> (access: String, refresh: String?, sekunden: Double, refreshSekunden: Double?)? {
        var body: [String: Any] = ["grant_type": "refresh_token", "refresh_token": refresh, "client_id": clientID]
        if let scopes, !scopes.isEmpty { body["scope"] = scopes.joined(separator: " ") }
        var r = URLRequest(url: tokenURL)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        r.timeoutInterval = 30
        var ergebnis: (String, String?, Double, Double?)?
        let fertig = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: r) { d, a, _ in
            defer { fertig.signal() }
            guard (a as? HTTPURLResponse)?.statusCode == 200, let d,
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let t = j["access_token"] as? String else { return }
            ergebnis = (t, j["refresh_token"] as? String, (j["expires_in"] as? NSNumber)?.doubleValue ?? 28800,
                        (j["refresh_token_expires_in"] as? NSNumber)?.doubleValue)
        }.resume()
        fertig.wait()
        return ergebnis
    }

    // MARK: Schlüsselbund über /usr/bin/security (so legt Claude Code die Einträge selbst an – kein Dialog)

    static func lesen(_ s: String) -> [String: Any]? {
        guard let d = ClaudeUsage.security(["find-generic-password", "-s", s, "-w"]) else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }

    private static func konto(_ s: String) -> String {
        guard let d = ClaudeUsage.security(["find-generic-password", "-s", s]), let t = String(data: d, encoding: .utf8),
              let r = t.range(of: #""acct"<blob>="([^"]*)""#, options: .regularExpression) else { return NSUserName() }
        return String(t[r].dropFirst(14).dropLast())
    }

    @discardableResult
    private static func schreiben(_ s: String, _ json: [String: Any]) -> Bool {
        guard let d = try? JSONSerialization.data(withJSONObject: json) else { return false }
        let hex = d.map { String(format: "%02x", $0) }.joined()
        return ClaudeUsage.security(["add-generic-password", "-U", "-a", konto(s), "-s", s, "-X", hex]) != nil
    }
}
