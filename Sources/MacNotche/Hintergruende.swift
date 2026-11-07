import AppKit
import SwiftUI

/// Mitgelieferte Schreibtischhintergründe (5120×2880), die die Notch als Bildelement einbinden.
enum Hintergruende {
    static let titel: [String: String] = [
        "katze": "Katze", "tropfen": "Tropfen", "taschenlampe": "Taschenlampe", "planeten": "Planeten", "insel": "Insel", "glasbruch": "Glasbruch",
        "programmierer": "Programmierer", "weizenfeld": "Weizenfeld", "astronaut-tinte": "Astronaut im Tintenfleck", "katzen-schreibtisch": "Katzen am Schreibtisch",
        "weltraum": "Weltraum", "sonnenuntergang": "Sonnenuntergang", "dschungel": "Dschungel", "haengekatze": "Hängekatze"]
    static let reihenfolge = ["katze", "tropfen", "taschenlampe", "planeten", "insel", "glasbruch", "haengekatze", "programmierer", "weizenfeld", "astronaut-tinte", "katzen-schreibtisch", "weltraum", "sonnenuntergang", "dschungel"]

    static var alle: [(name: String, url: URL)] {
        guard let ordner = Bundle.main.resourceURL?.appendingPathComponent("Hintergruende") else { return [] }
        return reihenfolge.compactMap { n in
            let u = ordner.appendingPathComponent(n + ".jpg")
            return FileManager.default.fileExists(atPath: u.path) ? (n, u) : nil
        }
    }

    /// Kopiert das Bild nach ~/Pictures/Mac Notche/Hintergründe und setzt es auf allen Bildschirmen.
    static func setzen(_ url: URL) -> String? {
        let ziel = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Mac Notche/Hintergründe", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
            let datei = ziel.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: datei.path) { try FileManager.default.removeItem(at: datei) }
            try FileManager.default.copyItem(at: url, to: datei)
            for s in NSScreen.screens {
                try NSWorkspace.shared.setDesktopImageURL(datei, for: s, options: [.imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: true])
            }
            return nil
        } catch { return error.localizedDescription }
    }
}

struct HintergruendeSeite: View {
    @State private var hinweis: String?
    @State private var gesetzt: String?
    private let spalten = [GridItem(.adaptive(minimum: 150), spacing: 12)]
    var body: some View {
        Section {
            Text("14 Hintergründe in 5K (5120 × 2880), bei denen die Notch Teil des Bildes ist. Klick setzt den Hintergrund auf allen Bildschirmen; die Datei landet in Bilder › Mac Notche › Hintergründe.")
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: spalten, spacing: 12) {
                ForEach(Hintergruende.alle, id: \.name) { h in
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
            if let hinweis { Text(hinweis).font(.caption).foregroundStyle(.orange) }
            if let gesetzt { Text(L("Gesetzt: ") + (Hintergruende.titel[gesetzt] ?? gesetzt)).font(.caption).foregroundStyle(.secondary) }
            Button("Ordner im Finder zeigen") {
                let o = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Mac Notche/Hintergründe")
                try? FileManager.default.createDirectory(at: o, withIntermediateDirectories: true)
                NSWorkspace.shared.open(o)
            }
        }
    }
}
