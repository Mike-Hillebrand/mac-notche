import AppKit

/// Fragt die GitHub-Releases ab und vergleicht mit der eigenen Version.
final class Updates: ObservableObject {
    @Published var neu: (version: String, url: URL)?
    @Published var hinweis: String?
    @Published var laeuft = false
    var melden: ((String, String, String) -> Void)?

    static let eigene = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    private static let api = URL(string: "https://api.github.com/repos/Mike-Hillebrand/mac-notche/releases/latest")!
    private var gemeldet: String?

    func starten() {
        guard UserDefaults.standard.bool(forKey: E.updatesAuto) else { return }
        // Erst nach dem Start, dann alle 6 Stunden.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { self.pruefen(still: true) }
        Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            guard UserDefaults.standard.bool(forKey: E.updatesAuto) else { return }
            self?.pruefen(still: true)
        }
    }

    func pruefen(still: Bool = false) {
        laeuft = true
        if !still { hinweis = nil }
        Task.detached(priority: .utility) {
            var r = URLRequest(url: Self.api)
            r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            r.timeoutInterval = 15
            var gefunden: (String, URL)?? = nil  // nil = Fehler, .some(nil) = aktuell
            if let (d, _) = try? await URLSession.shared.data(for: r), let (v, u) = Self.lesen(d) {
                gefunden = .some(Self.neuer(v, als: Self.eigene) ? (v, u) : nil)
            }
            let ergebnis = gefunden
            await MainActor.run {
                self.laeuft = false
                guard let n = ergebnis else { if !still { self.hinweis = L("GitHub nicht erreichbar.") }; return }
                self.neu = n.map { (version: $0.0, url: $0.1) }
                self.hinweis = n == nil ? L("Du hast die neueste Version.") : nil
                if let n, self.gemeldet != n.0 {
                    self.gemeldet = n.0
                    self.melden?("update", "arrow.down.circle.fill", L("Mac Notche ") + n.0 + L(" ist da – Einstellungen › Über Mac Notche"))
                }
            }
        }
    }

    /// (Version ohne „v“, Download der DMG) aus der Release-Antwort.
    static func lesen(_ d: Data) -> (String, URL)? {
        guard let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let tag = j["tag_name"] as? String else { return nil }
        let v = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let assets = j["assets"] as? [[String: Any]] ?? []
        let dmg = assets.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }?["browser_download_url"] as? String
        let seite = j["html_url"] as? String
        guard let u = (dmg ?? seite).flatMap(URL.init(string:)) else { return nil }
        return (v, u)
    }

    static func neuer(_ a: String, als b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
}
