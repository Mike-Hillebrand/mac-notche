import AppKit
import ImageCaptureCore
import Photos

/// iPhone per Kabel: Name, Akku, Fotos übernehmen – nur Apple-Bordmittel, keine Zusatzsoftware.
final class IPhone: NSObject, ObservableObject, ICDeviceBrowserDelegate, ICCameraDeviceDelegate {
    @Published var name: String?
    @Published var akku: Int?
    @Published var medien = 0
    @Published var neue: [ICCameraFile] = []
    @Published var fortschritt: (fertig: Int, gesamt: Int)?
    @Published var hinweis: String?
    var melden: ((String, String, String) -> Void)?

    private let browser = ICDeviceBrowser()
    private var kamera: ICCameraDevice?
    private var importiert = Set(UserDefaults.standard.stringArray(forKey: "iphone.importiert") ?? [])

    func starten() {
        browser.delegate = self
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue: ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue)!
        browser.start()
    }

    static func schluessel(_ f: ICCameraFile) -> String {
        "\(f.name ?? "")|\(f.fileSize)|\(f.creationDate?.timeIntervalSince1970 ?? 0)"
    }

    static func istVideo(_ url: URL) -> Bool { ["mov", "mp4", "m4v"].contains(url.pathExtension.lowercased()) }

    // MARK: Gerät kommt und geht

    func deviceBrowser(_ b: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let c = device as? ICCameraDevice,
              ["iPhone", "iPad"].contains(where: { (c.productKind ?? c.name ?? "").localizedCaseInsensitiveContains($0) }) else { return }
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
        UserDefaults.standard.set(Array(importiert), forKey: "iphone.importiert")
        neue = []
    }

    func importieren() {
        guard fortschritt == nil, !neue.isEmpty else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                guard status == .authorized || status == .limited else {
                    self.hinweis = "Kein Zugriff auf Fotos – Systemeinstellungen › Datenschutz › Fotos."
                    return
                }
                self.naechste(self.neue, fertig: 0, fehler: 0)
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
