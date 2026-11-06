import Foundation

/// iPhone über WLAN: Finder-WLAN-Sync (Lockdown über TCP) plus libimobiledevice aus Homebrew.
/// Liest Name, Akku und den DCIM-Ordner; der Kabelweg (ImageCaptureCore) hat Vorrang.
enum IPhoneWLAN {
    struct Datei: Equatable {
        let pfad: String      // /DCIM/114APPLE/IMG_4305.JPG
        let groesse: Int
        let geaendert: Date
        var name: String { (pfad as NSString).lastPathComponent }
        var schluessel: String { "\(name)|\(groesse)|\(Int(geaendert.timeIntervalSince1970))" }
    }

    static func pfad(_ name: String) -> String? {
        ["/opt/homebrew/bin/", "/usr/local/bin/"].map { $0 + name }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    static var installiert: Bool { pfad("idevice_id") != nil && pfad("ideviceinfo") != nil && pfad("afcclient") != nil }
    /// Installer über Homebrew (npm hat das Paket nicht); ohne Homebrew wird es zuerst installiert.
    static let install = """
        if ! command -v brew >/dev/null 2>&1; then echo 'Homebrew fehlt – wird installiert (Mac-Passwort nötig).'; \
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" && \
        eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"; fi && \
        brew install libimobiledevice && echo 'Fertig. Jetzt im Finder beim iPhone „Dieses iPhone anzeigen, wenn WLAN aktiv ist“ einschalten.'
        """

    /// Befehl mit Timeout; Eingabe wird in stdin geschrieben (afcclient ist eine kleine Shell).
    private static func lauf(_ werkzeug: String, _ args: [String], eingabe: String? = nil, sekunden: Double = 20) -> String? {
        guard let exe = pfad(werkzeug) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let aus = Pipe(), ein = Pipe()
        p.standardOutput = aus; p.standardError = FileHandle.nullDevice; p.standardInput = ein
        guard (try? p.run()) != nil else { return nil }
        if let eingabe { ein.fileHandleForWriting.write(Data(eingabe.utf8)) }
        try? ein.fileHandleForWriting.close()
        var daten = Data()
        let gruppe = DispatchGroup(); gruppe.enter()
        DispatchQueue.global(qos: .utility).async { daten = aus.fileHandleForReading.readDataToEndOfFile(); gruppe.leave() }
        if gruppe.wait(timeout: .now() + sekunden) == .timedOut { kill(p.processIdentifier, SIGKILL) }
        p.waitUntilExit()
        return String(data: daten, encoding: .utf8)
    }

    /// afcclient-Ausgabe ohne Farbcodes und Prompt.
    static func afcBereinigen(_ text: String) -> [String] {
        let ohneFarbe = text.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
        return ohneFarbe.split(separator: "\n").map { z in
            var s = String(z)
            while let r = s.range(of: "afc:/ > ") { s = String(s[r.upperBound...]) }
            return s.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
    }

    private static func afc(_ udid: String, _ befehle: [String], sekunden: Double = 20) -> [String] {
        afcBereinigen(lauf("afcclient", ["-n", "-u", udid], eingabe: befehle.joined(separator: "\n") + "\nquit\n", sekunden: sekunden) ?? "")
    }

    /// Erstes iPhone im Netz (UDID), nil wenn keins.
    static func udid() -> String? {
        lauf("idevice_id", ["-n"], sekunden: 10)?.split(separator: "\n").map(String.init).first { $0.count > 10 }
    }

    static func info(_ udid: String) -> (name: String?, akku: Int?) {
        let name = lauf("ideviceinfo", ["-n", "-u", udid, "-k", "DeviceName"], sekunden: 10)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let batterie = lauf("ideviceinfo", ["-n", "-u", udid, "-q", "com.apple.mobile.battery"], sekunden: 10) ?? ""
        let akku = batterie.split(separator: "\n").first { $0.hasPrefix("BatteryCurrentCapacity:") }
            .flatMap { Int($0.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "") }
        return (name.flatMap { $0.isEmpty ? nil : $0 }, akku)
    }

    /// Alle Fotos und Videos aus /DCIM/*APPLE – je Ordner ein eigener Aufruf, damit der Pfad stimmt.
    static func dateien(_ udid: String) -> [Datei] {
        let ordner = afc(udid, ["ls /DCIM"]).filter { $0.hasSuffix("APPLE") }.sorted()
        var ergebnis: [Datei] = []
        for o in ordner {
            for z in afc(udid, ["ls -l /DCIM/\(o)"], sekunden: 60) {
                guard let d = zeileLesen(z) else { continue }
                ergebnis.append(Datei(pfad: "/DCIM/\(o)/\(d.name)", groesse: d.groesse, geaendert: d.datum))
            }
        }
        return ergebnis
    }

    /// „-rw-r--r--    1 mobile mobile    1897323 07 Oct 2026 13:32:52 IMG_4305.JPG“
    static func zeileLesen(_ z: String) -> (name: String, groesse: Int, datum: Date)? {
        let t = z.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard t.count >= 9, t[0].hasPrefix("-"), let groesse = Int(t[4]) else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "dd MMM yyyy HH:mm:ss"
        let datum = f.date(from: "\(t[5]) \(t[6]) \(t[7]) \(t[8])") ?? Date(timeIntervalSince1970: 0)
        let name = t.dropFirst(9).joined(separator: " ")
        guard !name.isEmpty, !name.hasPrefix(".") else { return nil }
        return (name, groesse, datum)
    }

    /// Lädt eine Datei in den Ordner; nil bei Fehler.
    static func laden(_ udid: String, _ d: Datei, nach ordner: URL) -> URL? {
        let ziel = ordner.appendingPathComponent(d.name)
        try? FileManager.default.removeItem(at: ziel)
        _ = afc(udid, ["get \(d.pfad) \(ziel.path)"], sekunden: 600)
        let groesse = (try? FileManager.default.attributesOfItem(atPath: ziel.path)[.size] as? Int) ?? 0
        return groesse == d.groesse ? ziel : nil
    }
}
