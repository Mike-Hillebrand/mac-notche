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
