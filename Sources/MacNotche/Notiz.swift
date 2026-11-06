import AppKit
import AVFoundation
import Speech

// MARK: - Diktat (Spracherkennung von Apple, bevorzugt auf dem Gerät)

final class Diktat: ObservableObject {
    @Published var laeuft = false
    @Published var text = ""          // gesamter Notiztext (editierbar)
    @Published var hinweis: String?
    private var erkenner: SFSpeechRecognizer?
    private let engine = AVAudioEngine()
    private var anfrage: SFSpeechAudioBufferRecognitionRequest?
    private var aufgabe: SFSpeechRecognitionTask?
    private var basis = ""            // Text vor dem aktuellen Diktat

    func umschalten() { laeuft ? stoppen() : starten() }

    func starten() {
        hinweis = nil
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else { self.hinweis = L("Spracherkennung nicht erlaubt (Systemeinstellungen › Datenschutz › Spracherkennung)."); return }
                AVCaptureDevice.requestAccess(for: .audio) { ok in
                    DispatchQueue.main.async { ok ? self.aufnehmen() : (self.hinweis = L("Mikrofon nicht erlaubt (Systemeinstellungen › Datenschutz › Mikrofon).")) }
                }
            }
        }
    }

    private func aufnehmen() {
        let sprache = Locale(identifier: UserDefaults.standard.string(forKey: E.diktatSprache) ?? "de-DE")
        guard let r = SFSpeechRecognizer(locale: sprache), r.isAvailable else { hinweis = L("Spracherkennung für diese Sprache nicht verfügbar."); return }
        erkenner = r
        let a = SFSpeechAudioBufferRecognitionRequest()
        a.shouldReportPartialResults = true
        if r.supportsOnDeviceRecognition { a.requiresOnDeviceRecognition = true }  // bleibt auf dem Mac
        a.addsPunctuation = true
        anfrage = a
        let eingang = engine.inputNode
        let format = eingang.outputFormat(forBus: 0)
        eingang.removeTap(onBus: 0)
        eingang.installTap(onBus: 0, bufferSize: 1024, format: format) { puffer, _ in a.append(puffer) }
        engine.prepare()
        do { try engine.start() } catch { hinweis = L("Mikrofon ließ sich nicht starten: ") + error.localizedDescription; return }
        basis = text.isEmpty ? "" : text.trimmingCharacters(in: .whitespacesAndNewlines) + " "
        laeuft = true
        aufgabe = r.recognitionTask(with: a) { [weak self] ergebnis, fehler in
            guard let self else { return }
            if let ergebnis { DispatchQueue.main.async { self.text = self.basis + ergebnis.bestTranscription.formattedString } }
            if fehler != nil || ergebnis?.isFinal == true { DispatchQueue.main.async { self.stoppen() } }
        }
    }

    func stoppen() {
        guard laeuft else { return }
        engine.stop(); engine.inputNode.removeTap(onBus: 0)
        anfrage?.endAudio(); aufgabe?.cancel()
        anfrage = nil; aufgabe = nil
        laeuft = false
    }
}

// MARK: - Notiz sichern

enum NotizSichern {
    static var standardOrdner: String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let vault = "/Volumes/CLAUDE/Obsidian/MHM-Brain/00_Inbox"
        return FileManager.default.fileExists(atPath: vault) ? vault : home.appendingPathComponent("Documents/Notizen").path
    }

    /// Markdown-Datei mit Frontmatter in den Ordner; liefert den Pfad.
    static func inOrdner(_ text: String) throws -> URL {
        let gesetzt = UserDefaults.standard.string(forKey: E.notizOrdner)?.trimmingCharacters(in: .whitespaces) ?? ""
        let ordner = gesetzt.isEmpty ? standardOrdner : (gesetzt as NSString).expandingTildeInPath
        try FileManager.default.createDirectory(atPath: ordner, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HHmm"
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
        let titel = text.split(separator: "\n").first.map { String($0.prefix(40)) } ?? "Notiz"
        let sicher = titel.replacingOccurrences(of: "[/:\\\\]", with: "-", options: .regularExpression)
        let url = URL(fileURLWithPath: ordner).appendingPathComponent("\(f.string(from: Date())) \(sicher).md")
        let inhalt = "---\nerstellt: \(iso.string(from: Date()))\nquelle: Mac Notche\ntags: [notiz, inbox]\n---\n\n\(text)\n"
        try inhalt.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Neue Notiz in Apple Notizen (Standardkonto).
    static func inNotizen(_ text: String) -> Bool {
        let zeilen = text.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        let titel = zeilen.first { !$0.isEmpty } ?? "Notiz"
        func esc(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
        let html = "<h1>" + esc(titel) + "</h1>" + zeilen.dropFirst().map { $0.isEmpty ? "<div><br></div>" : "<div>" + esc($0) + "</div>" }.joined()
        let skript = "tell application \"Notes\"\nmake new note with properties {name:\"\(esc(titel))\", body:\"\(html)\"}\nend tell"
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript"); p.arguments = ["-e", skript]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
        return p.terminationStatus == 0
    }
}

// MARK: - Downloads-Wächter

/// Meldet neue Dateien in ~/Downloads und legt sie in die Ablage.
final class DownloadsWaechter {
    var melden: ((String, String, String) -> Void)?
    var ablage: Ablage?
    private let ordner = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    private var bekannt = Set<String>()
    private var quelle: DispatchSourceFileSystemObject?
    private static let unfertig = ["crdownload", "part", "download", "tmp", "partial", "aria2"]

    func starten() {
        bekannt = Set(liste())
        let fd = open(ordner.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let q = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .global(qos: .utility))
        q.setEventHandler { [weak self] in
            // Kurz warten: Browser schreiben erst .crdownload und benennen dann um.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.5) { self?.pruefen() }
        }
        q.setCancelHandler { close(fd) }
        q.resume()
        quelle = q
    }

    private func liste() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: ordner.path))?.filter { !$0.hasPrefix(".") } ?? []
    }

    private func pruefen() {
        let jetzt = Set(liste())
        let neu = jetzt.subtracting(bekannt).filter { !Self.unfertig.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
        // Unfertige bleiben unbekannt, damit sie nach dem Umbenennen gemeldet werden.
        bekannt = jetzt.filter { !Self.unfertig.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
        guard !neu.isEmpty, UserDefaults.standard.bool(forKey: E.meldung("download")) else { return }
        for name in neu.sorted() {
            let url = ordner.appendingPathComponent(name)
            DispatchQueue.main.async {
                self.melden?("download", "arrow.down.circle.fill", L("Geladen: ") + name)
                if UserDefaults.standard.bool(forKey: E.downloadsAblage), let a = self.ablage, !a.dateien.contains(url) { a.dateien.append(url) }
            }
        }
    }
}
