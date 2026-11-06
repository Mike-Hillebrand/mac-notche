import Foundation

/// Codex (ChatGPT-Abo) und Gemini CLI: beide schreiben ihre Sitzungen lokal mit, daraus lesen wir Token und Limits.
final class AndereKIs: ObservableObject {
    @Published var codexDa = false
    @Published var geminiDa = false
    @Published var codexLimits: [Limit] = []
    @Published var codexPlan: String?
    @Published var codexHeute = TokenSumme()
    @Published var geminiHeute = TokenSumme()
    /// Antigravity CLI: Zeilen aus „agy -p /usage“ (nil = nicht installiert oder nicht angemeldet).
    @Published var agyUsage: [String]?
    @Published var agyLimits: [Limit] = []
    private var agyStand = Date.distantPast

    private static let home = FileManager.default.homeDirectoryForCurrentUser
    private static let codexOrdner = home.appendingPathComponent(".codex/sessions")
    private static let geminiOrdner = home.appendingPathComponent(".gemini/tmp")
    private static let warteschlange = DispatchQueue(label: "kerbe.andere-kis", qos: .utility)
    // Nur auf der Warteschlange benutzen.
    private static var zwischenspeicher: [URL: (geaendert: Date, text: String)] = [:]

    func starten() {
        aktualisieren()
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.aktualisieren() }
    }

    func aktualisieren() {
        if Date().timeIntervalSince(agyStand) > 600 {
            agyStand = Date()
            DispatchQueue.global(qos: .utility).async {
                let u = Verbindungen.agyUsage()
                let zeilen = u.flatMap { $0.angemeldet ? $0.text : nil }?
                    .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                let limits = zeilen.map(Self.agyLimitsLesen) ?? []
                DispatchQueue.main.async { self.agyUsage = zeilen.map { Array($0.prefix(6)) }; self.agyLimits = limits }
            }
        }
        Self.warteschlange.async {
            let fm = FileManager.default
            let heute = Calendar.current.startOfDay(for: Date())
            let codexDa = fm.fileExists(atPath: Self.codexOrdner.path), geminiDa = fm.fileExists(atPath: Self.geminiOrdner.path)
            // Limits stehen im jüngsten Eintrag, daher eine Woche zurück; Token zählen nur ab heute.
            let c = Self.texte(Self.codexOrdner, seit: Date().addingTimeInterval(-7 * 86400), endung: "jsonl")
                .reduce(into: Codex()) { $0.dazu(Self.codexLesen($1, ab: heute)) }
            let g = Self.texte(Self.geminiOrdner, seit: heute, endung: nil)
                .reduce(into: TokenSumme()) { $0.add(Self.geminiLesen($1, ab: heute)) }
            DispatchQueue.main.async {
                self.codexDa = codexDa; self.geminiDa = geminiDa
                self.codexHeute = c.summe; self.codexLimits = c.limits; self.codexPlan = c.plan
                self.geminiHeute = g
            }
        }
    }

    private static func texte(_ ordner: URL, seit: Date, endung: String?) -> [String] {
        guard let e = FileManager.default.enumerator(at: ordner, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        var neu: [URL: (geaendert: Date, text: String)] = [:]
        for case let url as URL in e where endung.map { url.pathExtension == $0 } ?? ["json", "jsonl"].contains(url.pathExtension) {
            guard let t = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, t >= seit else { continue }
            if let c = zwischenspeicher[url], c.geaendert == t { neu[url] = c; continue }
            if let text = try? String(contentsOf: url, encoding: .utf8) { neu[url] = (t, text) }
        }
        // Beide Ordner teilen sich den Speicher, also nur den eigenen Teil ersetzen.
        zwischenspeicher = zwischenspeicher.filter { !$0.key.path.hasPrefix(ordner.path) }.merging(neu) { $1 }
        return neu.values.map(\.text)
    }

    // MARK: Antigravity

    /// Zeilen wie „Gemini 3.1 Pro: 42% used“ → Balken; alles ohne Prozentzahl bleibt Text.
    static func agyLimitsLesen(_ zeilen: [String]) -> [Limit] {
        let muster = try! NSRegularExpression(pattern: "^(.*?)[:\\s]+(\\d{1,3}(?:[.,]\\d+)?)\\s*%")
        return zeilen.compactMap { z in
            guard let m = muster.firstMatch(in: z, range: NSRange(z.startIndex..., in: z)),
                  let n = Range(m.range(at: 1), in: z), let w = Range(m.range(at: 2), in: z),
                  let p = Double(z[w].replacingOccurrences(of: ",", with: ".")) else { return nil }
            let name = z[n].trimmingCharacters(in: .whitespacesAndNewlines)
            return Limit(id: "agy." + name, name: name.isEmpty ? "Gemini" : name, prozent: p, reset: nil)
        }
    }

    // MARK: Codex

    struct Codex {
        var summe = TokenSumme()
        var limits: [Limit] = []
        var plan: String?
        var stand = Date.distantPast

        mutating func dazu(_ o: Codex) {
            summe.add(o.summe)
            if o.stand > stand { limits = o.limits; plan = o.plan; stand = o.stand }
        }
    }

    /// Jede Antwort schreibt ein `token_count`-Ereignis: Verbrauch dieser Runde plus aktueller Stand der Abo-Limits.
    static func codexLesen(_ text: String, ab: Date, jetzt: Date = Date()) -> Codex {
        var c = Codex()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for zeile in text.split(separator: "\n") where zeile.contains("\"token_count\"") {
            guard let j = try? JSONSerialization.jsonObject(with: Data(zeile.utf8)) as? [String: Any],
                  let p = j["payload"] as? [String: Any], p["type"] as? String == "token_count",
                  let ts = (j["timestamp"] as? String).flatMap(iso.date(from:)) else { continue }
            if ts >= ab, let u = (p["info"] as? [String: Any])?["last_token_usage"] as? [String: Any] {
                // Bei OpenAI steckt der Cache in input_tokens, das Nachdenken in output_tokens.
                let ein = u["input_tokens"] as? Int ?? 0, cache = u["cached_input_tokens"] as? Int ?? 0
                c.summe.add(TokenSumme(eingabe: ein - cache, ausgabe: u["output_tokens"] as? Int ?? 0, cacheLesen: cache))
            }
            if ts > c.stand, let r = p["rate_limits"] as? [String: Any] {
                c.stand = ts
                c.plan = r["plan_type"] as? String
                c.limits = ["primary", "secondary"].compactMap { schluessel in
                    guard let l = r[schluessel] as? [String: Any], let prozent = l["used_percent"] as? Double else { return nil }
                    let minuten = l["window_minutes"] as? Int ?? 0
                    let reset = (l["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
                    let name = minuten <= 300 ? "\(minuten / 60) Stunden" : minuten >= 10080 ? "Woche" : "\(minuten / 1440) Tage"
                    // Fenster schon abgelaufen → der alte Wert gilt nicht mehr.
                    if let reset, reset < jetzt { return Limit(id: "codex-\(schluessel)", name: name, prozent: 0, reset: nil) }
                    return Limit(id: "codex-\(schluessel)", name: name, prozent: prozent, reset: reset)
                }
            }
        }
        return c
    }

    // MARK: Gemini

    /// Gemini CLI speichert Chats als JSON (ältere Versionen) oder JSONL; Antworten tragen `tokens` und `timestamp`.
    static func geminiLesen(_ text: String, ab: Date) -> TokenSumme {
        var s = TokenSumme()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func durchgehen(_ o: Any) {
            if let a = o as? [Any] { a.forEach(durchgehen); return }
            guard let d = o as? [String: Any] else { return }
            if let t = d["tokens"] as? [String: Any],
               let ts = (d["timestamp"] as? String).flatMap(iso.date(from:)), ts >= ab {
                let ein = t["input"] as? Int ?? 0, cache = t["cached"] as? Int ?? 0
                s.add(TokenSumme(eingabe: ein - cache, ausgabe: (t["output"] as? Int ?? 0) + (t["thoughts"] as? Int ?? 0), cacheLesen: cache))
                return
            }
            d.values.forEach(durchgehen)
        }
        let zeilen = text.hasPrefix("{\n") || text.hasPrefix("[") ? [Substring(text)] : text.split(separator: "\n")
        for z in zeilen where z.contains("\"tokens\"") {
            if let j = try? JSONSerialization.jsonObject(with: Data(z.utf8)) { durchgehen(j) }
        }
        return s
    }
}
