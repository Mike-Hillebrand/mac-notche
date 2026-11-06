import Carbon.HIToolbox
import AppKit
import EventKit
import IOKit.ps
import IOBluetooth
import CoreBluetooth

/// Übersetzung aus Resources/<Sprache>.lproj, sonst der deutsche Text.
func L(_ s: String) -> String { NSLocalizedString(s, comment: "") }

enum Zustand { case zu, offen, meldung }
enum Reiter: String, CaseIterable { case uebersicht = "Übersicht", mitteilungen = "Mitteilungen", wetter = "Wetter", claude = "KI", fragen = "Fragen", ablage = "Ablage", iphone = "iPhone", fokus = "Fokus", werkzeuge = "Werkzeuge" }

extension Reiter {
    /// Vom Nutzer ausgeschaltete Reiter (Einstellungen › Allgemein), Übersicht nie.
    static var ausgeblendet: Set<Reiter> {
        get { Set((UserDefaults.standard.string(forKey: E.reiterAus) ?? "").split(separator: ",").compactMap { Reiter(rawValue: String($0)) }).subtracting([.uebersicht]) }
        set { UserDefaults.standard.set(newValue.map(\.rawValue).sorted().joined(separator: ","), forKey: E.reiterAus) }
    }
    static var sichtbar: [Reiter] { allCases.filter { !ausgeblendet.contains($0) } }
}

// MARK: - Modell

final class NotchModell: ObservableObject {
    @Published var zustand: Zustand = .zu
    @Published var reiter: Reiter = .uebersicht
    /// Zusätzliche Breite der zugeklappten Notch, wenn mehrere KI-Ringe gezeigt werden.
    @Published var zuExtraBreite: CGFloat = 0
    @Published var meldung: (symbol: String, text: String)?
    @Published var meldungWert: Double?
    @Published var leistenHoehe: CGFloat = 24
    /// MacBook mit echter Notch: die Reiterleiste rutscht unter die Notch, sonst verdeckt sie die mittleren Reiter.
    var echteNotch: CGFloat { (NSScreen.screens.first?.safeAreaInsets.top ?? 0) > 0 ? leistenHoehe : 0 }

    let musik = Musik()
    let kalender = Kalender()
    let claude = ClaudeUsage()
    let andereKIs = AndereKIs()
    let updates = Updates()
    let menueleiste = Menueleiste()
    let ecken = Ecken()
    let fragen = Fragen()
    let sport = Sport()
    let ziehen = FensterZiehen()
    let terminHinweis = TerminHinweis()
    let appTon = AppLautstaerke()
    let agent = Agent()
    let ablage = Ablage()
    let status = Status()
    let geraete = Geraete()
    let wetter = Wetter()
    let iphone = IPhone()
    let mitteilungen = Mitteilungen()
    let wach = WachHalten()
    let zwischenablage = Zwischenablage()
    let spiegel = Spiegel()
    let entsperren = Entsperren()
    let systemAnzeige = SystemAnzeige()
    let audio = AudioAusgabe()
    let fokus = FokusTimer()
    let augen = Erinnerung(art: "augen", minuten: E.augenMinuten, symbol: "eye", text: L("Augenpause: 20 Sekunden in die Ferne schauen"))
    let trinken = Erinnerung(art: "trinken", minuten: E.trinkenMinuten, symbol: "drop.fill", text: L("Zeit für einen Schluck Wasser und kurz aufstehen"))
    let bausteine = Textbausteine()
    let kurse = Kurse()
    var einstellungenOeffnen: (() -> Void)?
    private var schliessen: DispatchWorkItem?

    func starten() {
        musik.starten()
        kalender.starten()
        claude.starten()
        andereKIs.starten()
        wetter.starten()
        iphone.melden = { [weak self] a, s, t in self?.zeigeMeldung(a, s, t) }
        iphone.starten()
        mitteilungen.melden = { [weak self] a, s, t in self?.zeigeMeldung(a, s, t) }
        mitteilungen.starten()
        zwischenablage.starten()
        entsperren.starten()
        geraete.starten()
        status.melden = { [weak self] a, s, t in
            self?.zeigeMeldung(a, s, t)
            if a == "bluetooth" { DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self?.geraete.laden() } }
        }
        status.starten()
        let melden: (String, String, String) -> Void = { [weak self] a, s, t in self?.zeigeMeldung(a, s, t) }
        systemAnzeige.melden = { [weak self] a, s, t, w in self?.zeigeMeldung(a, s, t, wert: w) }
        systemAnzeige.starten()
        audio.starten()
        fokus.melden = melden
        augen.melden = melden
        augen.starten()
        trinken.melden = melden
        trinken.starten()
        updates.melden = melden
        updates.starten()
        ablage.melden = melden
        kurse.starten()
        sport.melden = melden
        sport.starten()
        ziehen.starten()
        terminHinweis.melden = melden
        terminHinweis.starten(kalender)
        appTon.starten()
        menueleiste.starten()
        ecken.notch = { [weak self] a in
            guard let self else { return }
            if a == .fragen { self.reiter = .fragen } else if a == .ablage { self.reiter = .ablage }
            self.zustand = .offen
        }
        ecken.starten()
        // ⌥⌘K: Claude fragen.
        Tastenkuerzel.registrieren(kVK_ANSI_K, cmdKey | optionKey) { [weak self] in
            self?.reiter = .fragen
            self?.zustand = .offen
        }
        Fenster.kuerzelAnmelden()
        // ⌥⌘V: Zwischenablage-Verlauf öffnen, Klick fügt in die vorherige App ein.
        Tastenkuerzel.registrieren(kVK_ANSI_V, cmdKey | optionKey) { [weak self] in
            guard let self else { return }
            self.zwischenablage.zielApp = NSWorkspace.shared.frontmostApplication
            self.reiter = .werkzeuge
            self.zustand = .offen
        }
        zwischenablage.schliessen = { [weak self] in self?.zustand = .zu }
        // Textbausteine brauchen Bedienungshilfen – starten, sobald die Erlaubnis da ist.
        bausteine.starten()
        Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.bausteine.starten() }
        // Klick irgendwo anders klappt die Notch zu.
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            if self?.zustand == .offen, UserDefaults.standard.bool(forKey: E.klickSchliesst) { self?.zustand = .zu }
        }
    }

    func hover(_ drin: Bool) {
        schliessen?.cancel()
        if drin {
            guard zustand != .offen else { return }
            let v = UserDefaults.standard.double(forKey: E.verzoegerung)
            if v > 0 { spaeter(v) { $0.kalender.laden(); $0.zustand = .offen } }
            else { kalender.laden(); zustand = .offen }
            return
        }
        spaeter(0.35) { $0.zustand = .zu; $0.spiegel.stoppen() }
    }

    func zeigeMeldung(_ art: String, _ symbol: String, _ text: String, wert: Double? = nil) {
        guard zustand != .offen, UserDefaults.standard.bool(forKey: E.meldung(art)) else { return }
        meldung = (symbol, text)
        meldungWert = wert
        zustand = .meldung
        // Lautstärke und Feststelltaste sind kurze Anzeigen, alles andere bleibt 3 Sekunden.
        spaeter(wert != nil || art == "feststell" ? 1.5 : 3) { if $0.zustand == .meldung { $0.zustand = .zu } }
    }

    private func spaeter(_ s: Double, _ tun: @escaping (NotchModell) -> Void) {
        schliessen?.cancel()
        let w = DispatchWorkItem { [weak self] in self.map(tun) }
        schliessen = w
        DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: w)
    }
}

// MARK: - Musik (Apple Music + Spotify per AppleScript)

final class Musik: ObservableObject {
    struct Titel: Equatable {
        var name, kuenstler, album: String
        var dauer, position: Double
        var spielt: Bool
        var quelle: String
    }

    @Published var titel: Titel?
    @Published var cover: NSImage?
    private var coverSchluessel = ""

    private let quellen: [(id: String, name: String, skript: NSAppleScript)] = [
        ("com.spotify.client", "Spotify", NSAppleScript(source: """
        tell application "Spotify"
            if player state is stopped then return {"stopped"}
            return {player state as text, name of current track, artist of current track, album of current track, (duration of current track) / 1000, player position, artwork url of current track}
        end tell
        """)!),
        ("com.apple.Music", "Music", NSAppleScript(source: """
        tell application "Music"
            if player state is stopped then return {"stopped"}
            set t to current track
            return {player state as text, name of t, artist of t, album of t, duration of t, player position, ""}
        end tell
        """)!),
    ]
    private let musikCover = NSAppleScript(source: """
    tell application "Music"
        try
            return raw data of artwork 1 of current track
        on error
            try
                return data of artwork 1 of current track
            end try
        end try
    end tell
    """)!

    func starten() {
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.abfragen() }
        abfragen()
    }

    // AppleScript wartet beim ersten Mal auf den Erlaubnis-Dialog → nie auf dem Hauptthread ausführen.
    private let warteschlange = DispatchQueue(label: "kerbe.musik")

    func abfragen() {
        warteschlange.async { [weak self] in
            guard let self else { return }
            let (bester, coverURL) = self.lesen()
            DispatchQueue.main.async { self.uebernehmen(bester, coverURL) }
        }
    }

    private func lesen() -> (Titel?, String) {
        var bester: Titel?
        var coverURL = ""
        // Nur laufende Apps fragen, sonst startet AppleScript sie.
        for q in quellen where !NSRunningApplication.runningApplications(withBundleIdentifier: q.id).isEmpty {
            var fehler: NSDictionary?
            let d: NSAppleEventDescriptor? = q.skript.executeAndReturnError(&fehler)
            guard let d, d.numberOfItems >= 7 else { continue }
            let text = { (i: Int) in d.atIndex(i)?.stringValue ?? "" }
            let zahl = { (i: Int) in d.atIndex(i)?.doubleValue ?? 0 }
            let t = Titel(name: text(2), kuenstler: text(3), album: text(4), dauer: zahl(5), position: zahl(6),
                          spielt: ["playing", "kPSP"].contains(text(1)), quelle: q.name)
            if bester == nil || (t.spielt && !bester!.spielt) { bester = t; coverURL = text(7) }
        }
        return (bester, coverURL)
    }

    private func uebernehmen(_ bester: Titel?, _ coverURL: String) {
        if titel != bester { titel = bester }
        guard let b = bester else { cover = nil; coverSchluessel = ""; return }
        let schluessel = b.quelle + b.name + b.album
        if schluessel != coverSchluessel { coverSchluessel = schluessel; coverLaden(b, url: coverURL) }
    }

    private func coverLaden(_ t: Titel, url: String) {
        if t.quelle == "Music" {
            warteschlange.async {
                var fehler: NSDictionary?
                let d: NSAppleEventDescriptor? = self.musikCover.executeAndReturnError(&fehler)
                let bild = d.flatMap { NSImage(data: $0.data) }
                DispatchQueue.main.async { self.cover = bild }
            }
        } else if let u = URL(string: url) {
            URLSession.shared.dataTask(with: u) { daten, _, _ in
                DispatchQueue.main.async { self.cover = daten.flatMap(NSImage.init(data:)) }
            }.resume()
        } else {
            cover = nil
        }
    }

    /// befehl: "playpause", "next track", "previous track" – versteht Music und Spotify.
    func befehl(_ b: String) {
        guard let q = titel?.quelle else { return }
        warteschlange.async {
            var fehler: NSDictionary?
            NSAppleScript(source: "tell application \"\(q)\" to \(b)")?.executeAndReturnError(&fehler)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.abfragen() }
    }
}

// MARK: - Kalender & Erinnerungen

final class Kalender: ObservableObject {
    let store = EKEventStore()
    @Published var termine: [EKEvent] = []
    @Published var erinnerungen: [EKReminder] = []
    @Published var zugriff = true

    func starten() {
        store.requestFullAccessToEvents { ok, _ in
            DispatchQueue.main.async { self.zugriff = ok; self.laden() }
        }
        store.requestFullAccessToReminders { _, _ in
            DispatchQueue.main.async { self.laden() }
        }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in self?.laden() }
    }

    func laden() {
        let p = store.predicateForEvents(withStart: Date(), end: Date().addingTimeInterval(2 * 86400), calendars: nil)
        termine = Array(store.events(matching: p).sorted { $0.startDate < $1.startDate }.prefix(3))
        store.fetchReminders(matching: store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)) { r in
            let sortiert = (r ?? []).sorted {
                ($0.dueDateComponents?.date ?? .distantFuture) < ($1.dueDateComponents?.date ?? .distantFuture)
            }
            DispatchQueue.main.async { self.erinnerungen = Array(sortiert.prefix(3)) }
        }
    }

    func erledigt(_ r: EKReminder) {
        r.isCompleted = true
        try? store.save(r, commit: true)
        laden()
    }
}

// MARK: - Akkustände der Geräte (Maus, Tastatur, Trackpad, AirPods)

struct GeraetAkku: Identifiable, Equatable {
    let name: String
    let prozent: Int
    var id: String { name }
    var symbol: String {
        let n = name.lowercased()
        if n.contains("mouse") || n.contains("maus") { return "magicmouse" }
        if n.contains("keyboard") || n.contains("tastatur") { return "keyboard" }
        if n.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        if ["airpods", "beats", "buds"].contains(where: n.contains) { return "airpodspro" }
        return "dot.radiowaves.left.and.right"
    }
}

final class Geraete: ObservableObject {
    @Published var liste: [GeraetAkku] = []
    private let schlange = DispatchQueue(label: "kerbe.geraete")

    func starten() {
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.laden() }
        laden()
    }

    func laden() {
        schlange.async { [weak self] in
            let neu = Self.lesen()
            AkkuVerlauf.merken(neu)
            DispatchQueue.main.async { if self?.liste != neu { self?.liste = neu } }
        }
    }

    /// Magic-Geräte melden ihren Akku in der IORegistry, AirPods nur über system_profiler.
    static func lesen() -> [GeraetAkku] {
        var nachAdresse: [String: GeraetAkku] = [:]
        let bt = CBManager.authorization == .allowedAlways
        if let d = ausgabe("/usr/sbin/ioreg", ["-r", "-a", "-k", "BatteryPercent"]),
           let eintraege = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [[String: Any]] {
            for e in eintraege {
                guard let p = e["BatteryPercent"] as? Int, var name = e["Product"] as? String else { continue }
                let adresse = (e["DeviceAddress"] as? String)?.lowercased().replacingOccurrences(of: ":", with: "-") ?? name
                if bt, let n = IOBluetoothDevice(addressString: adresse)?.name, !n.isEmpty { name = n }
                nachAdresse[adresse] = GeraetAkku(name: name, prozent: p)
            }
        }
        if let d = ausgabe("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"]),
           let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let info = (json["SPBluetoothDataType"] as? [[String: Any]])?.first,
           let verbunden = info["device_connected"] as? [[String: [String: Any]]] {
            func wert(_ p: [String: Any], _ k: String) -> Int? { (p[k] as? String).flatMap { Int($0.filter(\.isNumber)) } }
            for e in verbunden { for (name, p) in e {
                let lr = [wert(p, "device_batteryLevelLeft"), wert(p, "device_batteryLevelRight")].compactMap { $0 }.min()
                guard let prozent = wert(p, "device_batteryLevelMain") ?? lr else { continue }
                let adresse = (p["device_address"] as? String)?.lowercased().replacingOccurrences(of: ":", with: "-") ?? name
                nachAdresse[adresse] = GeraetAkku(name: name, prozent: prozent)
            } }
        }
        return nachAdresse.values.sorted { $0.name < $1.name }
    }

    private static func ausgabe(_ pfad: String, _ args: [String]) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: pfad)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return d
    }
}

// MARK: - Akku, Bluetooth, Fokus → kurze Meldungen

final class Status: NSObject, CBCentralManagerDelegate {
    var melden: ((String, String, String) -> Void)?  // Art, Symbol, Text
    private var warLadend: Bool?
    private var warNiedrig = false
    private var fokus: String?
    private var fokusGelesen = false
    private let start = Date()

    func starten() {
        let quelle = IOPSNotificationCreateRunLoopSource({ ctx in
            Unmanaged<Status>.fromOpaque(ctx!).takeUnretainedValue().akkuPruefen()
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let quelle { CFRunLoopAddSource(CFRunLoopGetMain(), quelle, .defaultMode) }
        akkuPruefen()
        // IOBluetooth blockiert, bis die Erlaubnis da ist → erst asynchron über CoreBluetooth fragen.
        if CBManager.authorization == .allowedAlways { bluetoothAnmelden() }
        else { zentrale = CBCentralManager(delegate: self, queue: .main) }
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.fokusPruefen() }
        fokusPruefen()
    }

    func akkuPruefen() {
        // Ohne Akku (iMac, Mac Studio) gibt es keine Quelle → keine Meldungen.
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let liste = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let q = liste.first,
              let d = IOPSGetPowerSourceDescription(info, q)?.takeUnretainedValue() as? [String: Any],
              let prozent = d[kIOPSCurrentCapacityKey] as? Int else { return }
        let laedt = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        if let war = warLadend, war != laedt {
            melden?("akku", laedt ? "battery.100.bolt" : "battery.75", laedt ? "Lädt – \(prozent) %" : "Akkubetrieb – \(prozent) %")
        }
        warLadend = laedt
        let niedrig = !laedt && prozent <= 20
        if niedrig && !warNiedrig { melden?("akku", "battery.25", "Akku schwach – \(prozent) %") }
        warNiedrig = niedrig
    }

    private var zentrale: CBCentralManager?
    private var angemeldet = false

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        if CBManager.authorization == .allowedAlways { bluetoothAnmelden() }
    }

    private func bluetoothAnmelden() {
        guard !angemeldet else { return }
        angemeldet = true
        IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(verbunden(_:geraet:)))
    }

    @objc func verbunden(_ n: IOBluetoothUserNotification, geraet: IOBluetoothDevice) {
        geraet.register(forDisconnectNotification: self, selector: #selector(getrennt(_:geraet:)))
        // Beim Start meldet IOBluetooth alle schon verbundenen Geräte – die überspringen.
        guard Date().timeIntervalSince(start) > 3 else { return }
        melden?("bluetooth", Self.symbol(geraet), "\(geraet.name ?? "Gerät") verbunden")
    }

    @objc func getrennt(_ n: IOBluetoothUserNotification, geraet: IOBluetoothDevice) {
        melden?("bluetooth", Self.symbol(geraet), "\(geraet.name ?? "Gerät") getrennt")
    }

    static func symbol(_ g: IOBluetoothDevice) -> String {
        let n = (g.name ?? "").lowercased()
        return ["airpods", "beats", "buds", "kopfhörer"].contains { n.contains($0) } ? "airpodspro" : "dot.radiowaves.left.and.right"
    }

    // ponytail: liest die Fokus-Datei von macOS; ohne Festplattenvollzugriff bleibt es still.
    func fokusPruefen() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
        guard let daten = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: daten) as? [String: Any],
              let eintrag = (json["data"] as? [[String: Any]])?.first else { return }
        let datensatz = (eintrag["storeAssertionRecords"] as? [[String: Any]])?.first
        let modus = (datensatz?["assertionDetails"] as? [String: Any])?["assertionDetailsModeIdentifier"] as? String
        let neu = modus.map(Self.fokusName)
        if fokusGelesen, neu != fokus {
            melden?("fokus", neu == nil ? "moon" : "moon.fill", neu.map { "Fokus: \($0)" } ?? "Fokus aus")
        }
        fokus = neu
        fokusGelesen = true
    }

    static func fokusName(_ id: String) -> String {
        let kurz = id.split(separator: ".").last.map(String.init) ?? id
        return ["default": "Nicht stören", "sleep": "Schlafen", "work": "Arbeiten", "personal": "Persönlich",
                "driving": "Fahren", "fitness": "Fitness", "gaming": "Spielen", "mindfulness": "Achtsamkeit",
                "reading": "Lesen"][kurz] ?? "Eigener Fokus"
    }
}

// MARK: - Ablage

final class Ablage: ObservableObject {
    var melden: ((String, String, String) -> Void)?
    @Published var dateien: [URL] = (UserDefaults.standard.stringArray(forKey: "ablage") ?? [])
        .map { URL(fileURLWithPath: $0) }
        .filter { FileManager.default.fileExists(atPath: $0.path) } {
        didSet { UserDefaults.standard.set(dateien.map(\.path), forKey: "ablage") }
    }

    func hinzu(_ provider: [NSItemProvider]) -> Bool {
        for p in provider {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL else { return }
                DispatchQueue.main.async { if !self.dateien.contains(url) { self.dateien.append(url) } }
            }
        }
        return !provider.isEmpty
    }
}
