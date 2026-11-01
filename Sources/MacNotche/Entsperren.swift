import AppKit
import AVFoundation
import Vision
import CoreML
import Security
import OpenDirectory
import ApplicationServices
import IOKit

/// Eigene Einträge im Schlüsselbund (Passwort, Gesichtsmerkmale).
enum Schluesselbund {
    static let dienst = "Mac Notche Entsperren"

    static func speichern(_ d: Data, konto: String) -> Bool {
        loeschen(konto: konto)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: dienst,
                                kSecAttrAccount as String: konto, kSecValueData as String: d,
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func laden(konto: String) -> Data? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: dienst,
                                kSecAttrAccount as String: konto, kSecReturnData as String: true]
        var r: AnyObject?
        return SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess ? r as? Data : nil
    }

    static func loeschen(konto: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: dienst,
                                kSecAttrAccount as String: konto]
        SecItemDelete(q as CFDictionary)
    }
}

/// Erkennt ein Blinzeln: Augen offen → deutlich zu → wieder offen. Ein Foto blinzelt nicht.
struct Blinzeln {
    private var basis: Double?
    private var zuGesehen = false

    mutating func neu(_ oeffnung: Double) -> Bool {
        guard let b = basis else { basis = oeffnung; return false }
        if oeffnung < b * 0.55 { zuGesehen = true; return false }
        if zuGesehen, oeffnung > b * 0.8 { zuGesehen = false; return true }
        if !zuGesehen { basis = b * 0.9 + oeffnung * 0.1 }
        return false
    }
}

/// FaceNet (Core ML) auf einem Gesichtsausschnitt → 512 Merkmale, dazu Augenöffnung aus Vision-Landmarken.
final class GesichtsErkennung {
    private let modell: VNCoreMLModel? = Bundle.main.url(forResource: "Gesicht", withExtension: "mlmodelc")
        .flatMap { try? MLModel(contentsOf: $0) }.flatMap { try? VNCoreMLModel(for: $0) }
    private let kontext = CIContext()
    var bereit: Bool { modell != nil }

    struct Ergebnis { let merkmal: [Float]?; let augen: Double? }

    /// nil, wenn kein oder mehr als ein Gesicht im Bild ist.
    func analysieren(_ pixel: CVPixelBuffer) -> Ergebnis? {
        let landmarken = VNDetectFaceLandmarksRequest()
        try? VNImageRequestHandler(cvPixelBuffer: pixel, orientation: .up).perform([landmarken])
        guard let gesichter = landmarken.results, gesichter.count == 1, let g = gesichter.first else { return nil }
        let augen = Self.augenOeffnung(g.landmarks)
        guard let modell else { return Ergebnis(merkmal: nil, augen: augen) }
        let bild = CIImage(cvPixelBuffer: pixel)
        let box = VNImageRectForNormalizedRect(g.boundingBox, Int(bild.extent.width), Int(bild.extent.height))
        let rahmen = box.insetBy(dx: -box.width * 0.1, dy: -box.height * 0.1).intersection(bild.extent)
        guard let ausschnitt = kontext.createCGImage(bild, from: rahmen) else { return nil }
        let anfrage = VNCoreMLRequest(model: modell)
        anfrage.imageCropAndScaleOption = .scaleFill
        try? VNImageRequestHandler(cgImage: ausschnitt).perform([anfrage])
        guard let feld = (anfrage.results?.first as? VNCoreMLFeatureValueObservation)?.featureValue.multiArrayValue else {
            return Ergebnis(merkmal: nil, augen: augen)
        }
        return Ergebnis(merkmal: Self.normiert((0..<feld.count).map { Float(truncating: feld[$0]) }), augen: augen)
    }

    static func normiert(_ v: [Float]) -> [Float] {
        let n = sqrt(v.reduce(0) { $0 + $1 * $1 })
        return n > 0 ? v.map { $0 / n } : v
    }

    static func aehnlichkeit(_ a: [Float], _ b: [Float]) -> Float { zip(a, b).reduce(0) { $0 + $1.0 * $1.1 } }

    static func augenOeffnung(_ l: VNFaceLandmarks2D?) -> Double? {
        func verhaeltnis(_ r: VNFaceLandmarkRegion2D?) -> Double? {
            guard let p = r?.normalizedPoints, p.count >= 4 else { return nil }
            let xs = p.map(\.x), ys = p.map(\.y)
            let breite = Double(xs.max()! - xs.min()!)
            return breite > 0 ? Double(ys.max()! - ys.min()!) / breite : nil
        }
        let a = [verhaeltnis(l?.leftEye), verhaeltnis(l?.rightEye)].compactMap { $0 }
        return a.isEmpty ? nil : a.reduce(0, +) / Double(a.count)
    }
}

/// Webcam-Entsperren wie bei Sapphire: Gesicht + Blinzeln erkannt → Mac-Passwort ins Sperrfenster tippen.
final class Entsperren: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum Modus { case aus, einlernen, test, entsperren }

    @Published var status = ""
    @Published var eingelernt = 0
    @Published var passwortGespeichert = Schluesselbund.laden(konto: "passwort") != nil
    @Published var testAehnlichkeit: Float?
    @Published var testBlinzeln = false
    @Published var kameraLaeuft = false

    let sitzung = AVCaptureSession()
    private let erkennung = GesichtsErkennung()
    private let warteschlange = DispatchQueue(label: "macnotche.entsperren")
    private var eingerichtet = false

    // Nur auf warteschlange verändern:
    private var modus = Modus.aus
    private var merkmale: [[Float]] = []
    private var neueMerkmale: [[Float]] = []
    private var bis = Date.distantPast
    private var naechstesBild = Date.distantPast
    private var treffer = 0
    private var blinzeln = Blinzeln()
    private var blinzelnGesehen = false
    private var versuche = 0

    var modellBereit: Bool { erkennung.bereit }
    var bedienungshilfen: Bool { AXIsProcessTrusted() }
    static var aktiv: Bool { UserDefaults.standard.bool(forKey: E.entsperrenAktiv) }
    static var schwelle: Float { Float(UserDefaults.standard.double(forKey: E.entsperrenSchwelle)) }

    func starten() {
        if let d = Schluesselbund.laden(konto: "gesicht"), let m = try? JSONDecoder().decode([[Float]].self, from: d) {
            merkmale = m
            eingelernt = m.count
        }
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.warteschlange.async { self?.versuche = 0; if self?.modus == .entsperren { self?.stoppen() } }
        }
        // Kamera nur, wenn gesperrt UND gerade jemand Maus/Tastatur benutzt hat.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, Self.aktiv, Self.bildschirmGesperrt(), Self.leerlauf() < 2 else { return }
            self.warteschlange.async {
                guard self.modus == .aus, self.versuche < 3, !self.merkmale.isEmpty else { return }
                self.beginnen(.entsperren, sekunden: 12)
            }
        }
    }

    // MARK: Systemzustand

    static func bildschirmGesperrt() -> Bool {
        guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (d["CGSSessionScreenIsLocked"] as? Bool) == true || (d["CGSSessionScreenIsLocked"] as? Int) == 1
    }

    static func leerlauf() -> Double {
        let dienst = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        defer { IOObjectRelease(dienst) }
        guard let n = IORegistryEntryCreateCFProperty(dienst, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber else { return .infinity }
        return n.doubleValue / 1e9
    }

    func bedienungshilfenAnfragen() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    // MARK: Einstellungen

    /// Prüft das Passwort gegen das Mac-Konto, bevor es gespeichert wird.
    func passwortSpeichern(_ pw: String) {
        do {
            let knoten = try ODNode(session: ODSession.default(), type: ODNodeType(kODNodeTypeAuthentication))
            let konto = try knoten.record(withRecordType: kODRecordTypeUsers, name: NSUserName(), attributes: nil)
            try konto.verifyPassword(pw)
            passwortGespeichert = Schluesselbund.speichern(Data(pw.utf8), konto: "passwort")
            status = passwortGespeichert ? "Passwort geprüft und im Schlüsselbund gespeichert." : "Speichern fehlgeschlagen."
        } catch {
            status = "Das Passwort passt nicht zu deinem Mac-Konto."
        }
    }

    func passwortLoeschen() { Schluesselbund.loeschen(konto: "passwort"); passwortGespeichert = false }

    func einlernen() { warteschlange.async { self.neueMerkmale = []; self.beginnen(.einlernen, sekunden: 30) } }
    func testen() { warteschlange.async { self.beginnen(.test, sekunden: 20) } }

    func gesichtLoeschen() {
        Schluesselbund.loeschen(konto: "gesicht")
        warteschlange.async { self.merkmale = [] }
        eingelernt = 0
        UserDefaults.standard.set(false, forKey: E.entsperrenAktiv)
    }

    // MARK: Kamera

    private func beginnen(_ m: Modus, sekunden: Double) {
        modus = m
        bis = Date().addingTimeInterval(sekunden)
        treffer = 0
        blinzeln = Blinzeln()
        blinzelnGesehen = false
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized || m != .entsperren else { modus = .aus; return }
        AVCaptureDevice.requestAccess(for: .video) { ok in
            self.warteschlange.async {
                guard ok else { self.modus = .aus; self.melde("Kein Kamerazugriff."); return }
                if !self.eingerichtet, let kamera = AVCaptureDevice.default(for: .video),
                   let eingang = try? AVCaptureDeviceInput(device: kamera), self.sitzung.canAddInput(eingang) {
                    self.sitzung.addInput(eingang)
                    let ausgang = AVCaptureVideoDataOutput()
                    ausgang.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    ausgang.alwaysDiscardsLateVideoFrames = true
                    ausgang.setSampleBufferDelegate(self, queue: self.warteschlange)
                    if self.sitzung.canAddOutput(ausgang) { self.sitzung.addOutput(ausgang) }
                    self.eingerichtet = true
                }
                self.sitzung.startRunning()
                DispatchQueue.main.async { self.kameraLaeuft = true }
                self.melde(m == .einlernen ? "Schau in die Kamera und dreh den Kopf leicht …" : m == .test ? "Test läuft – schau in die Kamera und blinzle." : "")
            }
        }
    }

    private func stoppen() {
        modus = .aus
        sitzung.stopRunning()
        DispatchQueue.main.async { self.kameraLaeuft = false }
    }

    private func melde(_ s: String) { DispatchQueue.main.async { self.status = s } }

    func captureOutput(_ o: AVCaptureOutput, didOutput puffer: CMSampleBuffer, from c: AVCaptureConnection) {
        guard modus != .aus else { return }
        if Date() > bis {
            if modus == .einlernen { melde("Abgebrochen – kein Gesicht erkannt. Nochmal versuchen.") }
            if modus == .test { melde("Test beendet.") }
            stoppen()
            return
        }
        guard Date() >= naechstesBild, let pixel = CMSampleBufferGetImageBuffer(puffer) else { return }
        naechstesBild = Date().addingTimeInterval(0.12)
        guard let e = erkennung.analysieren(pixel) else { treffer = 0; return }
        if let a = e.augen, blinzeln.neu(a) { blinzelnGesehen = true }
        let bester = e.merkmal.map { m in merkmale.map { GesichtsErkennung.aehnlichkeit(m, $0) }.max() ?? 0 }

        switch modus {
        case .einlernen:
            guard let m = e.merkmal else { return }
            neueMerkmale.append(m)
            melde("Einlernen … \(neueMerkmale.count) von 20")
            if neueMerkmale.count >= 20 {
                merkmale = neueMerkmale
                let ok = (try? JSONEncoder().encode(merkmale)).map { Schluesselbund.speichern($0, konto: "gesicht") } ?? false
                let n = merkmale.count
                stoppen()
                DispatchQueue.main.async { self.eingelernt = ok ? n : 0; self.status = ok ? "Gesicht eingelernt." : "Speichern fehlgeschlagen." }
            }
        case .test:
            let blinzelnJetzt = blinzelnGesehen
            DispatchQueue.main.async { self.testAehnlichkeit = bester; self.testBlinzeln = blinzelnJetzt }
        case .entsperren:
            if let b = bester, b >= Self.schwelle { treffer += 1 } else { treffer = 0 }
            if treffer >= 3, blinzelnGesehen {
                stoppen()
                versuche += 1
                DispatchQueue.main.async { self.tippen() }
            }
        case .aus:
            break
        }
    }

    // MARK: Passwort eintippen

    // ponytail: tippt UTF-16-Einheiten einzeln; Emoji im Passwort würden so nicht funktionieren.
    private func tippen() {
        guard Self.bildschirmGesperrt(), AXIsProcessTrusted(),
              let d = Schluesselbund.laden(konto: "passwort"), let pw = String(data: d, encoding: .utf8) else { return }
        let quelle = CGEventSource(stateID: .hidSystemState)
        for einheit in pw.utf16 {
            guard Self.bildschirmGesperrt() else { return }  // nie in ein entsperrtes Fenster tippen
            var z = einheit
            for runter in [true, false] {
                let e = CGEvent(keyboardEventSource: quelle, virtualKey: 0, keyDown: runter)
                e?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &z)
                e?.post(tap: .cghidEventTap)
            }
            usleep(8000)
        }
        guard Self.bildschirmGesperrt() else { return }
        for runter in [true, false] { CGEvent(keyboardEventSource: quelle, virtualKey: 36, keyDown: runter)?.post(tap: .cghidEventTap) }
    }
}
