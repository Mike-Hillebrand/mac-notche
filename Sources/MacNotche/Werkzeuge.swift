import AppKit
import AVFoundation
import IOKit.pwr_mgt
import SwiftUI

/// Mac wach halten (wie Caffeine): verhindert Ruhezustand des Bildschirms.
final class WachHalten: ObservableObject {
    @Published var bis: Date?  // nil = aus, .distantFuture = unbegrenzt
    private var zusicherung: IOPMAssertionID = 0
    private var timer: Timer?

    func an(minuten: Int?) {
        aus()
        var id: IOPMAssertionID = 0
        guard IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                          IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                          "Mac Notche: wach halten" as CFString, &id) == kIOReturnSuccess else { return }
        zusicherung = id
        bis = minuten.map { Date().addingTimeInterval(Double($0) * 60) } ?? .distantFuture
        if let m = minuten {
            timer = Timer.scheduledTimer(withTimeInterval: Double(m) * 60, repeats: false) { [weak self] _ in self?.aus() }
        }
    }

    func aus() {
        if zusicherung != 0 { IOPMAssertionRelease(zusicherung); zusicherung = 0 }
        timer?.invalidate(); timer = nil
        bis = nil
    }
}

/// Verlauf der letzten kopierten Texte – nur im Speicher, Passwort-Manager-Inhalte bleiben draußen.
final class Zwischenablage: ObservableObject {
    @Published var eintraege: [String] = []
    /// Gesetzt, wenn ⌥⌘V den Verlauf geöffnet hat: dann fügt ein Klick direkt dort ein.
    var zielApp: NSRunningApplication?
    var schliessen: (() -> Void)?
    private var zaehler = NSPasteboard.general.changeCount

    func starten() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.pruefen() }
    }

    func pruefen() {
        let pb = NSPasteboard.general
        guard pb.changeCount != zaehler else { return }
        zaehler = pb.changeCount
        let typen = (pb.types ?? []).map(\.rawValue)
        guard !typen.contains("org.nspasteboard.ConcealedType"), !typen.contains("org.nspasteboard.TransientType"),
              let s = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return }
        merken(s)
    }

    func kopieren(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
        zaehler = pb.changeCount
        merken(s)
        guard let app = zielApp else { return }
        zielApp = nil
        schliessen?()
        app.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { Tippen.taste(9, .maskCommand) }  // ⌘V
    }

    private func merken(_ s: String) {
        eintraege.removeAll { $0 == s }
        eintraege.insert(s, at: 0)
        eintraege = Array(eintraege.prefix(20))
    }
}

/// Kamera-Vorschau („Spiegel“) – läuft nur, solange sie eingeschaltet ist.
final class Spiegel: ObservableObject {
    let sitzung = AVCaptureSession()
    @Published var laeuft = false
    @Published var hinweis: String?
    private var eingerichtet = false

    func starten() {
        AVCaptureDevice.requestAccess(for: .video) { ok in
            DispatchQueue.main.async {
                guard ok else { self.hinweis = "Kein Kamerazugriff – Systemeinstellungen › Datenschutz › Kamera."; return }
                if !self.eingerichtet, let kamera = AVCaptureDevice.default(for: .video),
                   let eingang = try? AVCaptureDeviceInput(device: kamera), self.sitzung.canAddInput(eingang) {
                    self.sitzung.addInput(eingang)
                    self.eingerichtet = true
                }
                self.laeuft = true
                DispatchQueue.global(qos: .userInitiated).async { self.sitzung.startRunning() }
            }
        }
    }

    func stoppen() {
        laeuft = false
        DispatchQueue.global(qos: .userInitiated).async { self.sitzung.stopRunning() }
    }
}

struct KameraBild: NSViewRepresentable {
    let sitzung: AVCaptureSession
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.layer = CALayer()
        v.wantsLayer = true
        let vorschau = AVCaptureVideoPreviewLayer(session: sitzung)
        vorschau.videoGravity = .resizeAspectFill
        vorschau.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        vorschau.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))  // seitenverkehrt wie ein Spiegel
        v.layer?.addSublayer(vorschau)
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {
        v.layer?.sublayers?.first?.frame = v.bounds
    }
}
