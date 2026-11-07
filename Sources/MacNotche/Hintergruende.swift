import AppKit
import SwiftUI

/// Mitgelieferte Schreibtischhintergründe: das Motiv setzt oben mittig an der Notch an, die Notch selbst malt die App.
enum Hintergruende {
    static let titel: [String: String] = ["farbroller": "Farbroller", "erni": "Erni", "taschenlampe": "Taschenlampe"]
    static let reihenfolge = ["farbroller", "erni", "taschenlampe"]

    static var alle: [(name: String, url: URL)] {
        guard let ordner = Bundle.main.resourceURL?.appendingPathComponent("Hintergruende") else { return [] }
        return reihenfolge.compactMap { n in
            let u = ordner.appendingPathComponent(n + ".jpg")
            return FileManager.default.fileExists(atPath: u.path) ? (n, u) : nil
        }
    }

    static let eigeneOrdner = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Mac Notche/Hintergründe", isDirectory: true)

    /// Eigene Bilder aus dem Ordner – ohne die je Bildschirm erzeugten Dateien (…-5120x2880.jpg).
    static var eigene: [(name: String, url: URL)] {
        let dateien = (try? FileManager.default.contentsOfDirectory(at: eigeneOrdner, includingPropertiesForKeys: nil)) ?? []
        return dateien.filter { ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased()) }
            .map { ($0.deletingPathExtension().lastPathComponent, $0) }
            .filter { !reihenfolge.contains($0.0) && $0.0.range(of: #"-\d+x\d+$"#, options: .regularExpression) == nil }
            .sorted { $0.0 < $1.0 }
    }

    /// Setzt das Motiv auf allen Bildschirmen. Je Bildschirm wird eine passgenaue Datei gebaut: auf Bildschirmbreite
    /// skaliert und oben bündig, damit das Dekor an der Notch bleibt; was unten fehlt, füllt die Randfarbe des Bilds.
    static func setzen(_ url: URL) -> String? {
        guard let quelle = NSImage(contentsOf: url), let cg = quelle.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return L("Bild ließ sich nicht laden.") }
        do {
            try FileManager.default.createDirectory(at: eigeneOrdner, withIntermediateDirectories: true)
            let basis = url.deletingPathExtension().lastPathComponent
            for s in NSScreen.screens {
                let f = s.backingScaleFactor
                let breite = Int(s.frame.width * f), hoehe = Int(s.frame.height * f)
                let datei = eigeneOrdner.appendingPathComponent("\(basis)-\(breite)x\(hoehe).jpg")
                guard let daten = passend(cg, breite: breite, hoehe: hoehe) else { return L("Bild ließ sich nicht anpassen.") }
                try daten.write(to: datei)
                try NSWorkspace.shared.setDesktopImageURL(datei, for: s, options: [.imageScaling: NSImageScaling.scaleAxesIndependently.rawValue, .allowClipping: true])
            }
            return nil
        } catch { return error.localizedDescription }
    }

    static func passend(_ cg: CGImage, breite: Int, hoehe: Int) -> Data? {
        let skala = CGFloat(breite) / CGFloat(cg.width)
        let bildHoehe = Int(CGFloat(cg.height) * skala)
        guard let ctx = CGContext(data: nil, width: breite, height: hoehe, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(randfarbe(cg))
        ctx.fill(CGRect(x: 0, y: 0, width: breite, height: hoehe))
        ctx.interpolationQuality = .high
        // CoreGraphics zählt y von unten: oben bündig heißt y = hoehe - bildHoehe.
        ctx.draw(cg, in: CGRect(x: 0, y: CGFloat(hoehe - bildHoehe), width: CGFloat(breite), height: CGFloat(bildHoehe)))
        guard let aus = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: aus).representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    }

    /// Mittlere Farbe der untersten Bildzeile (für die Auffüllung unter kurzen Bildern).
    static func randfarbe(_ cg: CGImage) -> CGColor {
        guard let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let streifen = cg.cropping(to: CGRect(x: 0, y: cg.height - max(1, cg.height / 50), width: cg.width, height: max(1, cg.height / 50))) else { return CGColor(gray: 0, alpha: 1) }
        ctx.interpolationQuality = .high
        ctx.draw(streifen, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let d = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return CGColor(gray: 0, alpha: 1) }
        return CGColor(red: CGFloat(d[0]) / 255, green: CGFloat(d[1]) / 255, blue: CGFloat(d[2]) / 255, alpha: 1)
    }
}

struct HintergruendeSeite: View {
    @State private var hinweis: String?
    @State private var gesetzt: String?
    private let spalten = [GridItem(.adaptive(minimum: 150), spacing: 12)]
    var body: some View {
        Section {
            Text("Hintergründe, deren Motiv oben mittig an der Notch ansetzt – die Notch selbst ist die echte mit deinem Skin. Klick setzt den Hintergrund auf allen Bildschirmen; die Datei landet in Bilder › Mac Notche › Hintergründe. Eigene Bilder in diesem Ordner erscheinen hier ebenfalls.")
                .font(.caption).foregroundStyle(.secondary)
            raster(Hintergruende.alle)
            if !Hintergruende.eigene.isEmpty {
                Text("Eigene Bilder aus dem Ordner").font(.system(size: 12, weight: .semibold)).padding(.top, 6)
                raster(Hintergruende.eigene)
            }
            if let hinweis { Text(hinweis).font(.caption).foregroundStyle(.orange) }
            if let gesetzt { Text(L("Gesetzt: ") + (Hintergruende.titel[gesetzt] ?? gesetzt)).font(.caption).foregroundStyle(.secondary) }
            Button("Ordner im Finder zeigen") {
                try? FileManager.default.createDirectory(at: Hintergruende.eigeneOrdner, withIntermediateDirectories: true)
                NSWorkspace.shared.open(Hintergruende.eigeneOrdner)
            }
        }
    }

    private func raster(_ liste: [(name: String, url: URL)]) -> some View {
        LazyVGrid(columns: spalten, spacing: 12) {
            ForEach(liste, id: \.name) { h in
                Button {
                    hinweis = Hintergruende.setzen(h.url)
                    gesetzt = hinweis == nil ? h.name : nil
                } label: {
                    VStack(spacing: 4) {
                        AsyncImage(url: h.url) { bild in bild.resizable().aspectRatio(16 / 9, contentMode: .fill) } placeholder: { Color.gray.opacity(0.2) }
                            .frame(height: 84).clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(gesetzt == h.name ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: gesetzt == h.name ? 3 : 1))
                        Text(Hintergruende.titel[h.name] ?? h.name).font(.system(size: 11)).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .help("Als Schreibtischhintergrund setzen")
            }
        }
    }
}
