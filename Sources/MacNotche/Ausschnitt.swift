import AppKit
import EventKit
import Vision

// MARK: - Termin-Countdown (zugeklappte Notch)

enum TerminCountdown {
    /// Nächster Termin mit Uhrzeit, der in den nächsten 60 Minuten beginnt oder vor höchstens 10 Minuten begonnen hat.
    static func naechster(_ termine: [EKEvent], jetzt: Date = Date()) -> EKEvent? {
        termine.filter { !$0.isAllDay && $0.startDate != nil }
            .filter { let d = $0.startDate.timeIntervalSince(jetzt); return d <= 3600 && d > -600 }
            .min { $0.startDate < $1.startDate }
    }

    /// Link zum Videocall aus URL, Ort oder Notizen (Zoom, Teams, Meet, Webex, FaceTime, Jitsi, Whereby).
    static func anrufLink(_ e: EKEvent) -> URL? {
        anrufLink(url: e.url, texte: [e.location, e.notes])
    }

    static func anrufLink(url: URL?, texte: [String?]) -> URL? {
        let hosts = ["zoom.us", "teams.microsoft.com", "teams.live.com", "meet.google.com", "webex.com", "facetime.apple.com", "meet.jit.si", "whereby.com", "gotomeeting.com", "discord.gg"]
        func passt(_ u: URL) -> Bool { let h = u.host?.lowercased() ?? ""; return hosts.contains { h == $0 || h.hasSuffix("." + $0) } }
        if let url, passt(url) { return url }
        let muster = try! NSRegularExpression(pattern: "https?://[^\\s<>\"')]+")
        for t in texte.compactMap({ $0 }) {
            for m in muster.matches(in: t, range: NSRange(t.startIndex..., in: t)) {
                if let r = Range(m.range, in: t), let u = URL(string: String(t[r])), passt(u) { return u }
            }
        }
        return nil
    }

    /// Öffnet den Call, sonst den Kalender.
    static func oeffnen(_ e: EKEvent) {
        if let u = anrufLink(e) { NSWorkspace.shared.open(u) }
        else { NSWorkspace.shared.open(URL(string: "ical://")!) }
    }
}

// MARK: - Bildschirm-Freistellen (⌥⌘4): Bereich aufziehen, Text per OCR in die Zwischenablage, Bild in die Ablage

final class Ausschnitt {
    var melden: ((String, String, String) -> Void)?
    var ablage: Ablage?
    private var laeuft = false
    static let ordner = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Mac Notche")

    func starten() {
        guard !laeuft else { return }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            melden?("ausschnitt", "rectangle.dashed", L("Bildschirmaufnahme erlauben: Systemeinstellungen › Datenschutz"))
            return
        }
        laeuft = true
        try? FileManager.default.createDirectory(at: Self.ordner, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HHmmss"
        let url = Self.ordner.appendingPathComponent(L("Ausschnitt ") + f.string(from: Date()) + ".png")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-i", "-x", url.path]  // -i: Bereich mit der Maus aufziehen, Esc bricht ab
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.laeuft = false
                guard FileManager.default.fileExists(atPath: url.path) else { return }  // abgebrochen
                self?.fertig(url)
            }
        }
        do { try p.run() } catch { laeuft = false }
    }

    private func fertig(_ url: URL) {
        if let a = ablage, !a.dateien.contains(url) { a.dateien.append(url) }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let text = Self.text(url)
            DispatchQueue.main.async {
                if text.isEmpty {
                    self?.melden?("ausschnitt", "rectangle.dashed", L("Ausschnitt in der Ablage (kein Text erkannt)"))
                } else {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    self?.melden?("ausschnitt", "text.viewfinder", L("Text kopiert: ") + Self.kurz(text))
                }
            }
        }
    }

    /// Texterkennung (Vision, auf dem Mac) – Zeilen in Lesereihenfolge.
    static func text(_ url: URL) -> String {
        guard let img = NSImage(contentsOf: url), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
        let anfrage = VNRecognizeTextRequest()
        anfrage.recognitionLevel = .accurate
        anfrage.usesLanguageCorrection = true
        anfrage.recognitionLanguages = ["de-DE", "en-US"]
        try? VNImageRequestHandler(cgImage: cg).perform([anfrage])
        return (anfrage.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func kurz(_ s: String) -> String {
        let eine = s.replacingOccurrences(of: "\n", with: " ")
        return eine.count > 40 ? String(eine.prefix(40)) + "…" : eine
    }
}
