import AppKit
import EventKit

// MARK: - Fenster per Ziehen einrasten

/// Fenster an den linken, rechten oder oberen Rand ziehen → Zone leuchtet auf, Loslassen rastet ein.
final class FensterZiehen {
    private var fenster: AXUIElement?
    private var startPos: CGPoint?
    private var zone: Fenster.Ziel?
    private var overlay: NSWindow?

    func starten() {
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] e in self?.ereignis(e) }
    }

    private func ereignis(_ e: NSEvent) {
        guard UserDefaults.standard.bool(forKey: E.fensterZiehen), AXIsProcessTrusted() else { return }
        switch e.type {
        case .leftMouseDown:
            fenster = Fenster.fokusFenster()
            startPos = fenster.flatMap(Fenster.position)
            zone = nil
        case .leftMouseDragged:
            // Nur wenn sich das Fenster wirklich bewegt – sonst ist es eine Textauswahl oder ein Regler.
            guard let f = fenster, let s = startPos, let p = Fenster.position(f), p != s else { return }
            let m = NSEvent.mouseLocation
            guard let s = NSScreen.screens.first(where: { NSMouseInRect(m, $0.frame, false) }) else { return }
            let r = s.frame
            let neu: Fenster.Ziel? = m.x <= r.minX + 4 ? .links : m.x >= r.maxX - 5 ? .rechts : m.y >= r.maxY - 4 ? .voll : nil
            if neu != zone { zone = neu; zeigen(neu, auf: s) }
        case .leftMouseUp:
            if let z = zone, let f = fenster {
                // Kurz warten, bis macOS das Loslassen verarbeitet hat.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { Fenster.setzen(z, fenster: f) }
            }
            zone = nil; fenster = nil; startPos = nil
            zeigen(nil, auf: nil)
        default: break
        }
    }

    private func zeigen(_ z: Fenster.Ziel?, auf s: NSScreen?) {
        guard let z, let s else { overlay?.orderOut(nil); return }
        let r = Fenster.rahmen(z, in: s.visibleFrame).insetBy(dx: 6, dy: 6)
        if overlay == nil {
            let w = NSWindow(contentRect: r, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
            w.ignoresMouseEvents = true; w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .transient]
            w.contentView = ZonenBild()
            overlay = w
        }
        overlay?.setFrame(r, display: true)
        overlay?.orderFrontRegardless()
    }
}

private final class ZonenBild: NSView {
    override func draw(_ r: NSRect) {
        let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 14, yRadius: 14)
        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill(); p.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.7).setStroke(); p.lineWidth = 3; p.stroke()
    }
}

// MARK: - Kurzbefehle

enum Kurzbefehle {
    /// Alle Kurzbefehle aus der Kurzbefehle-App (dauert etwa eine Sekunde, daher im Hintergrund aufrufen).
    static func alle() -> [String] {
        guard let d = Ablage.ausfuehren("/usr/bin/shortcuts", ["list"]) else { return [] }
        return String(decoding: d, as: UTF8.self).split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    /// Kurzbefehle eines Ordners; nil, wenn es den Ordner nicht gibt.
    static func ordner(_ name: String) -> [String]? {
        guard let d = Ablage.ausfuehren("/usr/bin/shortcuts", ["list", "--folders"]),
              String(decoding: d, as: UTF8.self).split(separator: "\n").contains(where: { $0.trimmingCharacters(in: .whitespaces) == name }),
              let l = Ablage.ausfuehren("/usr/bin/shortcuts", ["list", "--folder-name", name]) else { return nil }
        return String(decoding: l, as: UTF8.self).split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    static func gewaehlt() -> [String] {
        (UserDefaults.standard.string(forKey: E.kurzbefehle) ?? "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func starten(_ name: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = ["run", name]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}

// MARK: - Zuhause: HomeKit über Kurzbefehle

/// HomeKit gibt es für Mac-Programme nicht direkt; die Kurzbefehle-App kann es. Wir zeigen die passenden Kurzbefehle als Kacheln.
final class Zuhause: ObservableObject {
    @Published var kacheln: [String] = []
    @Published var zuletzt: String?
    static let standardWoerter = "Heizung, Licht, Lampe, Steckdose, Szene, Rollo, Jalousie, Tür, Garage, Sauger, Wischer, Thermostat, Alarm, Kamera, Gute Nacht, Guten Morgen, Zuhause, Unterwegs"

    func laden() {
        DispatchQueue.global(qos: .userInitiated).async {
            let alle = Kurzbefehle.alle()
            let ordner = Kurzbefehle.ordner("Zuhause")
            let woerter = (UserDefaults.standard.string(forKey: E.zuhauseWoerter) ?? Self.standardWoerter)
                .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
            // Wortanfänge statt Teilstrings: „Langzeitbelichtung“ soll nicht als „Licht“ zählen.
            let auswahl = (UserDefaults.standard.string(forKey: E.zuhauseAuswahl) ?? "").split(separator: "\n").map(String.init).filter { !$0.isEmpty }
            // Angehakte Kurzbefehle aus den Einstellungen haben Vorrang vor Ordner und Stichwörtern.
            let treffer = !auswahl.isEmpty ? auswahl.filter { alle.isEmpty || alle.contains($0) } : ordner ?? alle.filter { n in
                let teile = n.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
                return woerter.contains { w in teile.contains { $0.hasPrefix(w) } || (w.contains(" ") && n.lowercased().contains(w)) }
            }
            DispatchQueue.main.async { self.kacheln = treffer }
        }
    }

    func starten(_ name: String) {
        Kurzbefehle.starten(name)
        zuletzt = name
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if self.zuletzt == name { self.zuletzt = nil } }
    }

    /// Symbol nach Stichwort im Namen.
    static func symbol(_ n: String) -> String {
        let s = n.lowercased()
        if s.contains("heiz") || s.contains("thermo") || s.contains("temperatur") { return "thermometer.medium" }
        if s.contains("licht") || s.contains("lampe") || s.contains("leuchte") { return "lightbulb.fill" }
        if s.contains("steckdose") || s.contains("strom") { return "poweroutlet.type.f.fill" }
        if s.contains("rollo") || s.contains("jalousie") || s.contains("vorhang") { return "blinds.horizontal.closed" }
        if s.contains("tür") || s.contains("schloss") || s.contains("garage") { return "door.left.hand.closed" }
        if s.contains("saug") || s.contains("wisch") || s.contains("roboter") { return "fan.fill" }
        if s.contains("kamera") || s.contains("alarm") { return "video.fill" }
        if s.contains("nacht") || s.contains("schlaf") { return "moon.fill" }
        if s.contains("morgen") { return "sunrise.fill" }
        if s.contains("musik") || s.contains("lautsprecher") { return "hifispeaker.fill" }
        return "house.fill"
    }
}

// MARK: - Termin-Hinweis

/// Meldet 5 Minuten vorher und zum Beginn. Prüft alle 30 Sekunden die schon geladenen Termine.
final class TerminHinweis {
    var melden: ((String, String, String) -> Void)?
    private var gemeldet = Set<String>()

    func starten(_ kalender: Kalender) {
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self, weak kalender] _ in
            guard let self, let kalender else { return }
            self.pruefen(kalender.termine)
        }
    }

    func pruefen(_ termine: [EKEvent], jetzt: Date = Date()) {
        guard UserDefaults.standard.bool(forKey: E.meldung("termin")) else { return }
        for t in termine where !t.isAllDay {
            guard let id = t.eventIdentifier, let start = t.startDate else { continue }
            for (vorlauf, text) in [(300.0, L("In 5 Min.: ")), (0.0, L("Jetzt: "))] {
                let d = start.timeIntervalSince(jetzt) - vorlauf
                let schluessel = "\(id)|\(Int(vorlauf))"
                if d <= 20, d > -40, gemeldet.insert(schluessel).inserted {
                    melden?("termin", "calendar", text + (t.title ?? L("Termin")))
                }
            }
        }
    }
}
