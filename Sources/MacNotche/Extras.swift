import AppKit
import AudioToolbox
import AVFoundation
import Carbon.HIToolbox
import CoreAudio
import SwiftUI

// MARK: - Tippen (für Zwischenablage, Textbausteine)

enum Tippen {
    /// Markiert eigene Tastendrücke, damit die Textbausteine sie nicht mitlesen.
    static let marke: Int64 = 0x4B455242

    static func taste(_ code: CGKeyCode, _ flags: CGEventFlags = []) {
        for runter in [true, false] {
            guard let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: runter) else { continue }
            e.flags = flags
            e.setIntegerValueField(.eventSourceUserData, value: marke)
            e.post(tap: .cghidEventTap)
        }
    }

    static func text(_ s: String) {
        let einheiten = Array(s.utf16)
        for start in stride(from: 0, to: einheiten.count, by: 16) {
            var teil = Array(einheiten[start..<min(start + 16, einheiten.count)])
            for runter in [true, false] {
                guard let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: runter) else { continue }
                e.keyboardSetUnicodeString(stringLength: teil.count, unicodeString: &teil)
                e.setIntegerValueField(.eventSourceUserData, value: marke)
                e.post(tap: .cghidEventTap)
            }
        }
    }
}

// MARK: - Globale Tastenkürzel (Carbon, braucht keine Erlaubnis)

enum Tastenkuerzel {
    private static var aktionen: [UInt32: () -> Void] = [:]
    private static var installiert = false

    static func registrieren(_ taste: Int, _ mods: Int, _ tun: @escaping () -> Void) {
        if !installiert {
            installiert = true
            var typ = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, ereignis, _ in
                var id = EventHotKeyID()
                GetEventParameter(ereignis, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                DispatchQueue.main.async { Tastenkuerzel.aktionen[id.id]?() }
                return noErr
            }, 1, &typ, nil, nil)
        }
        let nr = UInt32(aktionen.count + 1)
        aktionen[nr] = tun
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(taste), UInt32(mods), EventHotKeyID(signature: OSType(0x4B455242), id: nr),
                            GetApplicationEventTarget(), 0, &ref)
    }
}

// MARK: - Fenster einrasten (Bedienungshilfen)

enum Fenster {
    enum Ziel { case links, rechts, oben, unten, voll, mitte, drittel1, drittel2, drittel3 }

    static func fokusFenster() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        var wert: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXFocusedWindowAttribute as CFString, &wert) == .success,
              let wert, CFGetTypeID(wert) == AXUIElementGetTypeID() else { return nil }
        return (wert as! AXUIElement)
    }

    static func position(_ f: AXUIElement) -> CGPoint? {
        var p: CFTypeRef?, pos = CGPoint.zero
        guard AXUIElementCopyAttributeValue(f, kAXPositionAttribute as CFString, &p) == .success, let p else { return nil }
        AXValueGetValue(p as! AXValue, .cgPoint, &pos)
        return pos
    }

    /// Zielrechteck innerhalb des sichtbaren Bildschirmbereichs (ohne Lücken).
    static func rahmen(_ z: Ziel, in v: NSRect) -> NSRect {
        var r = v
        switch z {
        case .links: r.size.width = v.width / 2
        case .rechts: r.size.width = v.width / 2; r.origin.x = v.midX
        case .oben: r.size.height = v.height / 2; r.origin.y = v.midY
        case .unten: r.size.height = v.height / 2
        case .voll: break
        case .mitte: r = v.insetBy(dx: v.width / 6, dy: v.height / 8)
        case .drittel1, .drittel2, .drittel3:
            let i: CGFloat = z == .drittel1 ? 0 : z == .drittel2 ? 1 : 2
            r.size.width = v.width / 3; r.origin.x = v.minX + i * v.width / 3
        }
        return r
    }

    static func setzen(_ z: Ziel, fenster: AXUIElement? = nil) {
        guard UserDefaults.standard.bool(forKey: E.fensterAktiv) || fenster != nil, AXIsProcessTrusted(),
              let f = fenster ?? fokusFenster(), let pos = position(f) else { return }
        var groesse = CGSize.zero
        var g: CFTypeRef?
        if AXUIElementCopyAttributeValue(f, kAXSizeAttribute as CFString, &g) == .success, let g { AXValueGetValue(g as! AXValue, .cgSize, &groesse) }
        // Bedienungshilfen zählen von oben links am Hauptbildschirm, AppKit von unten links.
        guard let haupt = NSScreen.screens.first else { return }
        let oben = haupt.frame.maxY
        let mitte = CGPoint(x: pos.x + groesse.width / 2, y: oben - (pos.y + groesse.height / 2))
        let v = (NSScreen.screens.first { $0.frame.contains(mitte) } ?? NSScreen.main ?? haupt).visibleFrame
        let r = rahmen(z, in: v)
        var neuPos = CGPoint(x: r.minX, y: oben - r.maxY)
        var neuGroesse = r.size
        // Größe vor und nach dem Verschieben setzen: beim Wechsel des Bildschirms beschneidet macOS sonst.
        AXUIElementSetAttributeValue(f, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &neuGroesse)!)
        AXUIElementSetAttributeValue(f, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &neuPos)!)
        AXUIElementSetAttributeValue(f, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &neuGroesse)!)
    }

    static func kuerzelAnmelden() {
        let m = controlKey | optionKey
        let liste: [(Int, Ziel)] = [(kVK_LeftArrow, .links), (kVK_RightArrow, .rechts), (kVK_UpArrow, .oben),
                                    (kVK_DownArrow, .unten), (kVK_Return, .voll), (kVK_ANSI_C, .mitte),
                                    (kVK_ANSI_D, .drittel1), (kVK_ANSI_F, .drittel2), (kVK_ANSI_G, .drittel3)]
        for (taste, ziel) in liste { Tastenkuerzel.registrieren(taste, m) { setzen(ziel) } }
    }
}

// MARK: - Lautstärke und Feststelltaste → Anzeige in der Notch

final class SystemAnzeige: ObservableObject {
    @Published var lautstaerke: Double = 0  // 0…1, 0 auch bei stumm
    var melden: ((String, String, String, Double?) -> Void)?
    private var geraet = AudioObjectID(kAudioObjectUnknown)
    private let start = Date()
    private static let lautAdr = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                                            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    private static let stummAdr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                             mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    private lazy var block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.geaendert() }

    func starten() {
        var adr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                             mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &adr, .main) { [weak self] _, _ in self?.geraetWechseln() }
        geraetWechseln()
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            guard e.keyCode == UInt16(kVK_CapsLock) else { return }
            let an = e.modifierFlags.contains(.capsLock)
            self?.melden?("feststell", an ? "capslock.fill" : "capslock", L(an ? "Feststelltaste an" : "Feststelltaste aus"), nil)
        }
    }

    private func geraetWechseln() {
        var l = Self.lautAdr, s = Self.stummAdr
        if geraet != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(geraet, &l, .main, block)
            AudioObjectRemovePropertyListenerBlock(geraet, &s, .main, block)
        }
        geraet = AudioAusgabe.standard()
        AudioObjectAddPropertyListenerBlock(geraet, &l, .main, block)
        AudioObjectAddPropertyListenerBlock(geraet, &s, .main, block)
        lautstaerke = Self.lesen(geraet).wert
    }

    static func lesen(_ geraet: AudioObjectID) -> (wert: Double, stumm: Bool) {
        var v: Float32 = 0, m: UInt32 = 0
        var g = UInt32(MemoryLayout<Float32>.size), l = lautAdr, s = stummAdr
        AudioObjectGetPropertyData(geraet, &l, 0, nil, &g, &v)
        g = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(geraet, &s, 0, nil, &g, &m)
        return (Double(v), m != 0 || v == 0)
    }

    func setzen(_ wert: Double) {
        var v = Float32(min(max(wert, 0), 1)), l = Self.lautAdr, s = Self.stummAdr
        var stumm: UInt32 = v == 0 ? 1 : 0
        AudioObjectSetPropertyData(geraet, &l, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
        AudioObjectSetPropertyData(geraet, &s, 0, nil, UInt32(MemoryLayout<UInt32>.size), &stumm)
        lautstaerke = Double(v)
    }

    private func geaendert() {
        let (wert, stumm) = Self.lesen(geraet)
        let v = Float32(wert)
        lautstaerke = stumm ? 0 : wert
        guard Date().timeIntervalSince(start) > 3 else { return }
        let symbol = stumm ? "speaker.slash.fill" : v < 0.34 ? "speaker.wave.1.fill" : v < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        melden?("lautstaerke", symbol, stumm ? L("Stumm") : L("Lautstärke") + " \(Int((v * 100).rounded())) %", stumm ? 0 : Double(v))
    }
}

// MARK: - Audio-Ausgabe umschalten

final class AudioAusgabe: ObservableObject {
    struct Geraet: Identifiable, Hashable { let id: AudioObjectID; let name: String }
    @Published var geraete: [Geraet] = []
    @Published var aktuell = AudioObjectID(kAudioObjectUnknown)

    private static func adresse(_ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    func starten() {
        for sel in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            var adr = Self.adresse(sel)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &adr, .main) { [weak self] _, _ in self?.laden() }
        }
        laden()
    }

    static func standard() -> AudioObjectID {
        var id = AudioObjectID(kAudioObjectUnknown), g = UInt32(MemoryLayout<AudioObjectID>.size)
        var adr = adresse(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &adr, 0, nil, &g, &id)
        return id
    }

    func laden() {
        let sys = AudioObjectID(kAudioObjectSystemObject)
        var adr = Self.adresse(kAudioHardwarePropertyDevices), g: UInt32 = 0
        AudioObjectGetPropertyDataSize(sys, &adr, 0, nil, &g)
        var ids = [AudioObjectID](repeating: 0, count: Int(g) / MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(sys, &adr, 0, nil, &g, &ids)
        geraete = ids.compactMap { id in
            var s = Self.adresse(kAudioDevicePropertyStreams, kAudioDevicePropertyScopeOutput), n: UInt32 = 0
            AudioObjectGetPropertyDataSize(id, &s, 0, nil, &n)
            guard n > 0 else { return nil }
            var name: Unmanaged<CFString>?, ng = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var na = Self.adresse(kAudioObjectPropertyName)
            guard AudioObjectGetPropertyData(id, &na, 0, nil, &ng, &name) == noErr, let name else { return nil }
            return Geraet(id: id, name: name.takeRetainedValue() as String)
        }
        aktuell = Self.standard()
    }

    func waehlen(_ id: AudioObjectID) {
        var neu = id
        for sel in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice] {
            var adr = Self.adresse(sel)
            AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &adr, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &neu)
        }
        laden()
    }
}

// MARK: - Timer, Fokus-Sitzung, Rauschen

final class FokusTimer: ObservableObject {
    enum Art: String { case timer = "Timer", fokus = "Fokus", pause = "Pause" }
    @Published var art: Art?
    @Published var ende: Date?
    @Published var gesamt: Double = 0
    @Published var rauschen = false { didSet { if rauschen != oldValue { rauschen ? rauschenAn() : rauschenAus() } } }
    var melden: ((String, String, String) -> Void)?
    private var timer: Timer?
    private var engine: AVAudioEngine?

    func start(_ art: Art, minuten: Double) {
        self.art = art
        gesamt = minuten * 60
        ende = Date().addingTimeInterval(gesamt)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: gesamt, repeats: false) { [weak self] _ in self?.fertig() }
    }

    func stopp() {
        timer?.invalidate(); timer = nil
        art = nil; ende = nil
        rauschen = false
    }

    private func fertig() {
        NSSound(named: "Glass")?.play()
        switch art {
        case .fokus:
            rauschen = false
            melden?("timer", "cup.and.saucer.fill", L("Fokus geschafft – 5 Minuten Pause"))
            start(.pause, minuten: 5)
        case .pause:
            melden?("timer", "brain.head.profile", L("Pause vorbei – weiter geht's"))
            stopp()
        default:
            melden?("timer", "timer", L("Timer abgelaufen"))
            stopp()
        }
    }

    /// Braunes Rauschen, selbst erzeugt – keine Audiodateien nötig.
    private func rauschenAn() {
        let e = AVAudioEngine()
        let rate = e.outputNode.outputFormat(forBus: 0).sampleRate
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate > 0 ? rate : 44100, channels: 1) else { return }
        var letzt: Float = 0
        let quelle = AVAudioSourceNode(format: format) { _, _, frames, liste in
            for puffer in UnsafeMutableAudioBufferListPointer(liste) {
                guard let p = puffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for i in 0..<Int(frames) {
                    letzt = (letzt + 0.02 * Float.random(in: -1...1)) / 1.02
                    p[i] = letzt * 0.9
                }
            }
            return noErr
        }
        e.attach(quelle)
        e.connect(quelle, to: e.mainMixerNode, format: format)
        if (try? e.start()) != nil { engine = e }
    }

    private func rauschenAus() { engine?.stop(); engine = nil }
}

// MARK: - Erinnerungen (Augenpause, Trinken und Aufstehen)

final class Erinnerung {
    var melden: ((String, String, String) -> Void)?
    private let art, minutenSchluessel, symbol, text: String
    private var zuletzt = Date()

    init(art: String, minuten: String, symbol: String, text: String) {
        self.art = art; minutenSchluessel = minuten; self.symbol = symbol; self.text = text
    }

    func starten() {
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.pruefen() }
    }

    private func pruefen() {
        // Wer 5 Minuten nichts tut, macht schon Pause → Uhr neu starten.
        if Entsperren.leerlauf() > 300 || Entsperren.bildschirmGesperrt() { zuletzt = Date(); return }
        let minuten = max(UserDefaults.standard.double(forKey: minutenSchluessel), 5)
        guard UserDefaults.standard.bool(forKey: E.meldung(art)), Date().timeIntervalSince(zuletzt) >= minuten * 60 else { return }
        zuletzt = Date()
        melden?(art, symbol, text)
    }
}

// MARK: - Textbausteine und Emoji-Kürzel

final class Textbausteine {
    static let emojis: [String: String] = [
        ":herz:": "❤️", ":lach:": "😂", ":smile:": "😊", ":zwinker:": "😉", ":daumen:": "👍", ":ok:": "👌",
        ":feuer:": "🔥", ":party:": "🎉", ":denk:": "🤔", ":rakete:": "🚀", ":check:": "✅", ":kreuz:": "❌",
        ":stern:": "⭐️", ":sonne:": "☀️", ":kaffee:": "☕️", ":bier:": "🍺", ":traurig:": "😢", ":wow:": "😮",
        ":klatsch:": "👏", ":bitte:": "🙏", ":augen:": "👀", ":hundert:": "💯", ":warnung:": "⚠️", ":idee:": "💡",
        ":geld:": "💰", ":kamera:": "📷", ":muskel:": "💪", ":uhr:": "⏰", ":haus:": "🏠", ":auto:": "🚗",
    ]
    private var puffer = ""
    private var tap: CFMachPort?

    /// Braucht Bedienungshilfen; ohne Erlaubnis bleibt alles aus.
    func starten() {
        guard tap == nil, AXIsProcessTrusted() else { return }
        let maske = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: maske, callback: { _, typ, e, ctx in
            if let ctx {
                let selbst = Unmanaged<Textbausteine>.fromOpaque(ctx).takeUnretainedValue()
                if typ == .tapDisabledByTimeout || typ == .tapDisabledByUserInput { selbst.tap.map { CGEvent.tapEnable(tap: $0, enable: true) } }
                else if typ == .keyDown { selbst.taste(e) }
            }
            return Unmanaged.passUnretained(e)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        tap = t
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, t, 0), .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
    }

    private func taste(_ e: CGEvent) {
        guard e.getIntegerValueField(.eventSourceUserData) != Tippen.marke else { return }
        if e.flags.contains(.maskCommand) || e.flags.contains(.maskControl) { puffer = ""; return }
        if e.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Delete) {
            if !puffer.isEmpty { puffer.removeLast() }
            return
        }
        var laenge = 0
        var zeichen = [UniChar](repeating: 0, count: 4)
        e.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &laenge, unicodeString: &zeichen)
        guard laenge > 0 else { puffer = ""; return }
        puffer = String((puffer + String(utf16CodeUnits: zeichen, count: laenge)).suffix(48))
        guard let (kuerzel, text) = Self.treffer(puffer) else { return }
        puffer = ""
        DispatchQueue.main.async {
            for _ in 0..<kuerzel.count { Tippen.taste(CGKeyCode(kVK_Delete)) }
            Tippen.text(text)
        }
    }

    /// Längstes passendes Kürzel am Ende des Getippten gewinnt (";mfg" vor ";m").
    static func treffer(_ getippt: String) -> (String, String)? {
        var liste = UserDefaults.standard.dictionary(forKey: E.bausteine) as? [String: String] ?? [:]
        if UserDefaults.standard.bool(forKey: E.emojiKuerzel) { liste.merge(emojis) { eigen, _ in eigen } }
        return liste.filter { !$0.key.isEmpty && getippt.hasSuffix($0.key) }.max { $0.key.count < $1.key.count }.map { ($0.key, $0.value) }
    }
}

// MARK: - Aktienkurse (Yahoo Finance, ohne Schlüssel)

final class Kurse: ObservableObject {
    struct Kurs: Identifiable, Equatable {
        let symbol, name: String
        let preis, vortag: Double
        let waehrung: String
        var id: String { symbol }
        var aenderung: Double { vortag > 0 ? (preis - vortag) / vortag * 100 : 0 }
    }
    @Published var liste: [Kurs] = []

    func starten() {
        Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in self?.laden() }
        NotificationCenter.default.addObserver(forName: .kurseLaden, object: nil, queue: .main) { [weak self] _ in self?.laden() }
        laden()
    }

    func laden() {
        let symbole = (UserDefaults.standard.string(forKey: E.aktien) ?? "")
            .split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
        guard !symbole.isEmpty else { liste = []; return }
        let gruppe = DispatchGroup()
        var ergebnis: [String: Kurs] = [:]
        let sperre = NSLock()
        for s in symbole {
            guard let kodiert = s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(kodiert)?range=1d&interval=1d") else { continue }
            var anfrage = URLRequest(url: url)
            anfrage.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            gruppe.enter()
            URLSession.shared.dataTask(with: anfrage) { d, _, _ in
                defer { gruppe.leave() }
                guard let d, let k = Self.lesen(d, symbol: s) else { return }
                sperre.lock(); ergebnis[s] = k; sperre.unlock()
            }.resume()
        }
        gruppe.notify(queue: .main) { self.liste = symbole.compactMap { ergebnis[$0] } }
    }

    static func lesen(_ d: Data, symbol: String) -> Kurs? {
        guard let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let meta = ((json["chart"] as? [String: Any])?["result"] as? [[String: Any]])?.first?["meta"] as? [String: Any],
              let preis = meta["regularMarketPrice"] as? Double else { return nil }
        let vortag = meta["chartPreviousClose"] as? Double ?? preis
        let name = (meta["shortName"] as? String)?.trimmingCharacters(in: .whitespaces) ?? symbol
        return Kurs(symbol: symbol, name: name.isEmpty ? symbol : name, preis: preis, vortag: vortag, waehrung: meta["currency"] as? String ?? "")
    }
}

// MARK: - Ablage: Bilder umwandeln, DMG installieren

extension Ablage {
    static let bildEndungen: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "gif", "bmp", "webp"]

    func umwandeln(_ url: URL, in format: String) {
        let endung = format == "jpeg" ? "jpg" : format
        var ziel = url.deletingPathExtension().appendingPathExtension(endung)
        var n = 2
        while FileManager.default.fileExists(atPath: ziel.path) {
            ziel = url.deletingLastPathComponent().appendingPathComponent("\(url.deletingPathExtension().lastPathComponent) \(n).\(endung)")
            n += 1
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = Self.ausfuehren("/usr/bin/sips", ["-s", "format", format, url.path, "--out", ziel.path]) != nil
                && FileManager.default.fileExists(atPath: ziel.path)
            DispatchQueue.main.async {
                if ok { self.dateien.append(ziel) }
                self.melden?("ablage", ok ? "photo" : "exclamationmark.triangle", ok ? "\(ziel.lastPathComponent) erstellt" : "Umwandeln fehlgeschlagen")
            }
        }
    }

    /// DMG einhängen, enthaltene App nach /Programme kopieren, wieder auswerfen.
    func installieren(_ dmg: URL) {
        melden?("ablage", "arrow.down.app", "Installiere \(dmg.deletingPathExtension().lastPathComponent) …")
        DispatchQueue.global(qos: .userInitiated).async {
            var meldung = "Keine App im Image gefunden"
            if let d = Self.ausfuehren("/usr/bin/hdiutil", ["attach", "-nobrowse", "-noautoopen", "-plist", dmg.path]),
               let plist = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any],
               let punkt = (plist["system-entities"] as? [[String: Any]])?.compactMap({ $0["mount-point"] as? String }).first {
                let inhalt = (try? FileManager.default.contentsOfDirectory(atPath: punkt)) ?? []
                if let app = inhalt.first(where: { $0.hasSuffix(".app") }) {
                    let ziel = "/Applications/\(app)"
                    if FileManager.default.fileExists(atPath: ziel) { try? FileManager.default.trashItem(at: URL(fileURLWithPath: ziel), resultingItemURL: nil) }
                    meldung = Self.ausfuehren("/usr/bin/ditto", ["\(punkt)/\(app)", ziel]) != nil
                        ? "\(app.replacingOccurrences(of: ".app", with: "")) installiert" : "Kopieren fehlgeschlagen"
                }
                _ = Self.ausfuehren("/usr/bin/hdiutil", ["detach", punkt, "-quiet"])
            }
            DispatchQueue.main.async { self.melden?("ablage", "app.badge.checkmark", meldung) }
        }
    }

    static func ausfuehren(_ pfad: String, _ args: [String]) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: pfad)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? d : nil
    }
}
