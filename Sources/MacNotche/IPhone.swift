import AppKit
import ImageCaptureCore
import Photos

/// iPhone per Kabel (Apple-Bordmittel) oder über WLAN (Finder-WLAN-Sync + libimobiledevice): Name, Akku, Fotos übernehmen.
final class IPhone: NSObject, ObservableObject, ICDeviceBrowserDelegate, ICCameraDeviceDelegate {
    @Published var name: String?
    @Published var akku: Int?
    @Published var medien = 0
    @Published var neue: [ICCameraFile] = []
    @Published var fortschritt: (fertig: Int, gesamt: Int)?
    @Published var hinweis: String?
    /// Über WLAN verbunden (nur wenn kein Kabel-iPhone da ist).
    @Published var wlan = false
    @Published var neueWLAN: [IPhoneWLAN.Datei] = []
    private var udid: String?
    private var wlanLaeuft = false
    var anzahlNeu: Int { wlan ? neueWLAN.count : neue.count }
    var melden: ((String, String, String) -> Void)?

    private let browser = ICDeviceBrowser()
    private var kamera: ICCameraDevice?
    private var importiert = Set(UserDefaults.standard.stringArray(forKey: "iphone.importiert") ?? [])

    func starten() {
        browser.delegate = self
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue: ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue)!
        browser.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.wlanPruefen() }
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.wlanPruefen() }
    }

    // MARK: WLAN

    /// Sucht alle 30 s ein iPhone im Netz; Kabel hat Vorrang. Läuft im Hintergrund, die Werkzeuge brauchen Sekunden.
    func wlanPruefen() {
        guard kamera == nil, IPhoneWLAN.installiert, !wlanLaeuft, fortschritt == nil else { return }
        wlanLaeuft = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            defer { DispatchQueue.main.async { self.wlanLaeuft = false } }
            guard let u = IPhoneWLAN.udid() else {
                DispatchQueue.main.async {
                    guard self.wlan else { return }
                    self.melden?("iphone", "iphone.slash", "\(self.name ?? "iPhone") " + L("nicht mehr im WLAN"))
                    self.wlan = false; self.udid = nil; self.name = nil; self.akku = nil; self.medien = 0; self.neueWLAN = []
                }
                return
            }
            let info = IPhoneWLAN.info(u)
            if self.udid == u {
                DispatchQueue.main.async { self.akku = info.akku ?? self.akku }
                return
            }
            let dateien = IPhoneWLAN.dateien(u)
            DispatchQueue.main.async {
                guard self.kamera == nil else { return }
                self.udid = u; self.wlan = true
                self.name = info.name ?? "iPhone"; self.akku = info.akku; self.hinweis = nil
                self.medien = dateien.count
                // Kabel-Einträge tragen das Aufnahmedatum, WLAN das Änderungsdatum – daher nur Name und Größe vergleichen.
                let bekannt = Set(self.importiert.map { $0.split(separator: "|").prefix(2).joined(separator: "|") })
                self.neueWLAN = dateien.filter { !bekannt.contains("\($0.name)|\($0.groesse)") }
                self.melden?("iphone", "wifi", "\(self.name ?? "iPhone") " + L("über WLAN verbunden") + (self.akku.map { " – Akku \($0) %" } ?? ""))
                // Über WLAN nie unbeabsichtigt die ganze Mediathek ziehen: automatisch nur bis 20 neue Dateien.
                if UserDefaults.standard.bool(forKey: E.iphoneAuto), self.neueWLAN.count <= 20 { self.importieren() }
            }
        }
    }

    static func schluessel(_ f: ICCameraFile) -> String {
        "\(f.name ?? "")|\(f.fileSize)|\(f.creationDate?.timeIntervalSince1970 ?? 0)"
    }

    static func istVideo(_ url: URL) -> Bool { ["mov", "mp4", "m4v"].contains(url.pathExtension.lowercased()) }

    // MARK: Gerät kommt und geht

    func deviceBrowser(_ b: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let c = device as? ICCameraDevice,
              ["iPhone", "iPad"].contains(where: { (c.productKind ?? c.name ?? "").localizedCaseInsensitiveContains($0) }) else { return }
        // Kabel hat Vorrang: WLAN-Zustand verwerfen.
        wlan = false; udid = nil; neueWLAN = []
        kamera = c
        c.delegate = self
        name = c.name
        hinweis = nil
        c.requestOpenSession()
    }

    func deviceBrowser(_ b: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        guard device == kamera else { return }
        melden?("iphone", "iphone.slash", "\(name ?? "iPhone") getrennt")
        kamera = nil; name = nil; akku = nil; medien = 0; neue = []; fortschritt = nil
    }

    func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        if error != nil { hinweis = "iPhone entsperren und „Vertrauen“ tippen." }
    }

    func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        akku = device.batteryLevelAvailable ? device.batteryLevel : nil
        let dateien = (device.mediaFiles ?? []).compactMap { $0 as? ICCameraFile }
        medien = dateien.count
        neue = dateien.filter { !importiert.contains(Self.schluessel($0)) }
        melden?("iphone", "iphone", "\(name ?? "iPhone") verbunden" + (akku.map { " – Akku \($0) %" } ?? ""))
        if UserDefaults.standard.bool(forKey: E.iphoneAuto) { importieren() }
    }

    // Pflicht-Methoden der Delegates, hier ohne Aufgabe.
    func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {}
    func didRemove(_ device: ICDevice) {}
    func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {}
    func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {}
    func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: Error?) {}
    func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?, for item: ICCameraItem, error: Error?) {}
    func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
    func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}
    func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}
    func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {}
    func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {}

    // MARK: Import

    /// Beim ersten Anschließen wären alle alten Bilder „neu“ – damit startet man bei null.
    func alleBekannt() {
        neue.forEach { importiert.insert(Self.schluessel($0)) }
        neueWLAN.forEach { importiert.insert($0.schluessel) }
        UserDefaults.standard.set(Array(importiert), forKey: "iphone.importiert")
        neue = []; neueWLAN = []
    }

    func importieren() {
        guard fortschritt == nil, anzahlNeu > 0 else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                guard status == .authorized || status == .limited else {
                    self.hinweis = "Kein Zugriff auf Fotos – Systemeinstellungen › Datenschutz › Fotos."
                    return
                }
                if self.wlan { self.naechsteWLAN(self.neueWLAN, fertig: 0, fehler: 0) } else { self.naechste(self.neue, fertig: 0, fehler: 0) }
            }
        }
    }

    /// WLAN: Datei per afcclient holen, dann wie beim Kabel in Fotos legen.
    private func naechsteWLAN(_ liste: [IPhoneWLAN.Datei], fertig: Int, fehler: Int) {
        guard fertig < liste.count, let udid else {
            fortschritt = nil
            let bekannt = Set(importiert.map { $0.split(separator: "|").prefix(2).joined(separator: "|") })
            neueWLAN = neueWLAN.filter { !bekannt.contains("\($0.name)|\($0.groesse)") }
            melden?("iphone", "photo.on.rectangle", "\(liste.count - fehler) Fotos übernommen" + (fehler > 0 ? ", \(fehler) fehlgeschlagen" : ""))
            return
        }
        fortschritt = (fertig, liste.count)
        let datei = liste[fertig]
        let ordner = FileManager.default.temporaryDirectory.appendingPathComponent("macnotche-iphone", isDirectory: true)
        try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let url = IPhoneWLAN.laden(udid, datei, nach: ordner) else {
                DispatchQueue.main.async { self?.naechsteWLAN(liste, fertig: fertig + 1, fehler: fehler + 1) }; return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.forAsset().addResource(with: Self.istVideo(url) ? .video : .photo, fileURL: url, options: nil)
            }) { ok, _ in
                try? FileManager.default.removeItem(at: url)
                DispatchQueue.main.async {
                    guard let self else { return }
                    if ok { self.importiert.insert(datei.schluessel); UserDefaults.standard.set(Array(self.importiert), forKey: "iphone.importiert") }
                    self.naechsteWLAN(liste, fertig: fertig + 1, fehler: fehler + (ok ? 0 : 1))
                }
            }
        }
    }

    // ponytail: eine Datei nach der anderen; Live-Fotos landen als Foto und Video getrennt.
    private func naechste(_ liste: [ICCameraFile], fertig: Int, fehler: Int) {
        guard fertig < liste.count else {
            fortschritt = nil
            neue = neue.filter { !importiert.contains(Self.schluessel($0)) }
            melden?("iphone", "photo.on.rectangle", "\(liste.count - fehler) Fotos übernommen" + (fehler > 0 ? ", \(fehler) fehlgeschlagen" : ""))
            return
        }
        fortschritt = (fertig, liste.count)
        let datei = liste[fertig]
        let ordner = FileManager.default.temporaryDirectory.appendingPathComponent("macnotche-iphone", isDirectory: true)
        try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        let weiter = { (ok: Bool) in
            DispatchQueue.main.async {
                if ok {
                    self.importiert.insert(Self.schluessel(datei))
                    UserDefaults.standard.set(Array(self.importiert), forKey: "iphone.importiert")
                }
                self.naechste(liste, fertig: fertig + 1, fehler: fehler + (ok ? 0 : 1))
            }
        }
        datei.requestDownload(options: [.downloadsDirectoryURL: ordner, .overwrite: true]) { dateiname, fehlerDownload in
            guard fehlerDownload == nil, let dateiname else { weiter(false); return }
            let url = ordner.appendingPathComponent(dateiname)
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.forAsset().addResource(with: Self.istVideo(url) ? .video : .photo, fileURL: url, options: nil)
            }) { ok, _ in
                try? FileManager.default.removeItem(at: url)
                weiter(ok)
            }
        }
    }
}
