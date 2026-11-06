import AppKit
import SwiftUI
import Combine
import ServiceManagement

Einstellungen.registrieren()

if CommandLine.arguments.contains("--selbsttest") {
    Selbsttest.laufen()
    exit(0)
}
if CommandLine.arguments.contains("--anmelden") {
    do { try SMAppService.mainApp.register(); print("Mac Notche startet ab jetzt beim Anmelden.") }
    catch { print("Anmelden fehlgeschlagen: \(error.localizedDescription)"); exit(1) }
    exit(0)
}
if CommandLine.arguments.contains("--token") {
    let (h, f) = ClaudeUsage.lokaleToken()
    print("Heute: \(h.gesamt) Token, \(h.kosten) $ · Letzte 5 Std.: \(f.gesamt) Token, \(f.kosten) $")
    exit(0)
}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let modell = NotchModell()
    var panel: NotchPanel!
    var statusItem: NSStatusItem!
    var abos = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ n: Notification) {
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false  // Panels verschwinden sonst, sobald eine andere App vorne ist.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let hosting = NSHostingView(rootView: NotchAnsicht().environmentObject(modell))
        hosting.sizingOptions = []
        panel.contentView = hosting

        // receive(on:) – @Published feuert vor dem Speichern; erst danach animiert anpassen.
        modell.$zustand.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] z in self?.anpassen(z) }.store(in: &abos)
        modell.$zuExtraBreite.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] _ in if self?.modell.zustand == .zu { self?.anpassen(.zu) } }.store(in: &abos)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.anpassen(self.modell.zustand)
        }
        panel.orderFrontRegardless()
        menuBauen()
        modell.starten()
        modell.einstellungenOeffnen = { [weak self] in self?.einstellungen() }
        // Zum Prüfen ohne Maus: --zeige <Reiter> öffnet die Notch direkt, --einstellungen das Fenster.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--zeige"), i + 1 < args.count,
           let r = Reiter.allCases.first(where: { $0.rawValue.lowercased() == args[i + 1].lowercased() }) {
            modell.reiter = r
            modell.zustand = .offen
        }
        // --aufgabe <Text>: Agent plant nur, führt nichts aus; Plan landet auf stdout (zum Prüfen).
        if let i = args.firstIndex(of: "--aufgabe"), i + 1 < args.count {
            modell.agent.aufgabe = args[i + 1]
            modell.agent.planen()
            modell.reiter = .fragen
            modell.zustand = .offen
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
                guard !self.modell.agent.plant else { return }
                t.invalidate()
                let text = self.modell.agent.schritte.map { "SCHRITT: \($0.was) → \($0.befehl)" }.joined(separator: "\n") + "\nHINWEIS: \(self.modell.agent.hinweis)\n"
                try? text.write(toFile: "/tmp/kerbe-aufgabe.txt", atomically: true, encoding: .utf8)
            }
        }
        // Test: --meldung <art> <symbol> <text> [wert]
        if let i = args.firstIndex(of: "--meldung"), i + 3 < args.count {
            modell.zeigeMeldung(args[i + 1], args[i + 2], args[i + 3], wert: i + 4 < args.count ? Double(args[i + 4]) : nil)
        }
        if let i = args.firstIndex(of: "--frage"), i + 1 < args.count {
            modell.fragen.frage = args[i + 1]
            modell.fragen.senden()
            modell.reiter = .fragen
            modell.zustand = .offen
        }
        if args.contains("--einstellungen") || args.contains("--entsperren-seite") || args.contains("--seite") { DispatchQueue.main.async { self.einstellungen() } }
        panel.hasShadow = UserDefaults.standard.bool(forKey: E.schatten)
        var fahrenheit = UserDefaults.standard.bool(forKey: E.fahrenheit)
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.panel.hasShadow = UserDefaults.standard.bool(forKey: E.schatten)
            self.anpassen(self.modell.zustand)
            if UserDefaults.standard.bool(forKey: E.fahrenheit) != fahrenheit {
                fahrenheit.toggle()
                self.modell.wetter.laden()
            }
        }
    }

    /// Notch sitzt oben mittig auf dem Hauptbildschirm; Größe hängt vom Zustand ab.
    func anpassen(_ z: Zustand) {
        guard let s = NSScreen.screens.first else { return }
        let leiste = max(24, s.frame.maxY - s.visibleFrame.maxY)
        modell.leistenHoehe = leiste
        // Je Seite ein „Ohr“ dazu, damit der Inhalt so breit bleibt wie bisher.
        let ohren = 2 * Island.ohr
        var g: CGSize = switch z {
        case .zu: CGSize(width: UserDefaults.standard.double(forKey: E.breite) + modell.zuExtraBreite + ohren, height: leiste)
        case .meldung: CGSize(width: 440 + ohren, height: leiste + 48)
        case .offen: CGSize(width: 780 + ohren, height: 290 + ((s.safeAreaInsets.top > 0) ? leiste : 0))
        }
        // Skins brauchen Platz für Ohren, Schwanz, Beine oder Tropfen.
        let rand = Skin.gewaehlt.rand
        g.width += rand.rechts + rand.links
        g.height += rand.oben + (z == .offen ? 0 : rand.unten)
        let r = NSRect(x: s.frame.midX - g.width / 2, y: s.frame.maxY - g.height, width: g.width, height: g.height)
        panel.setFrame(r, display: true, animate: panel.frame.width > 0)
    }

    func menuBauen() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Mac Notche")
        let m = NSMenu()
        m.addItem(withTitle: "Notch öffnen", action: #selector(oeffnen), keyEquivalent: "").target = self
        m.addItem(withTitle: "Einstellungen …", action: #selector(einstellungen), keyEquivalent: ",").target = self
        m.addItem(withTitle: "Claude-Usage aktualisieren", action: #selector(aktualisieren), keyEquivalent: "r").target = self
        let login = NSMenuItem(title: "Beim Anmelden starten", action: #selector(loginUmschalten(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        m.addItem(login)
        m.addItem(.separator())
        m.addItem(withTitle: "Mac Notche beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = m
    }

    @objc func oeffnen() { modell.zustand = .offen }

    var einstellungsFenster: NSWindow?
    @objc func einstellungen() {
        modell.zustand = .zu
        if einstellungsFenster == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: EinstellungenAnsicht().environmentObject(modell.entsperren).environmentObject(modell.updates).environmentObject(modell.wetter)))
            w.title = L("Mac Notche – Einstellungen")
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.setContentSize(NSSize(width: 760, height: 500))
            w.isReleasedWhenClosed = false
            w.center()
            einstellungsFenster = w
        }
        NSApp.activate(ignoringOtherApps: true)
        einstellungsFenster?.makeKeyAndOrderFront(nil)
    }
    @objc func aktualisieren() { modell.claude.aktualisieren(erzwingen: true); modell.andereKIs.aktualisieren() }
    @objc func loginUmschalten(_ i: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { NSSound.beep() }
        i.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
