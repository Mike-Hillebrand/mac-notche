import AppKit
import SwiftUI
import AVFoundation

// MARK: - Teleprompter unter der Notch
// Text läuft direkt unter der Kamera durch: man liest und schaut dabei in die Linse.
// Panel ist auf Wunsch unsichtbar für Bildschirmfreigabe, Aufnahmen und Screenshots (sharingType = .none).
// Maus drauf = Pause, Pfeiltasten ↑/↓ = Zeile zurück/vor, Leertaste = Laufen an/aus, Esc = beenden.
// Das Leuchten unten folgt nur der Lautstärke; Ton wird weder aufgenommen noch gesendet.

enum P {
    static let text = "prompter.text", tempo = "prompter.tempo", schrift = "prompter.schrift", breite = "prompter.breite",
               hoehe = "prompter.hoehe", farbe = "prompter.farbe", auto = "prompter.auto", verbergen = "prompter.verbergen", leuchten = "prompter.leuchten"
    static func registrieren() {
        UserDefaults.standard.register(defaults: [
            text: "Willkommen beim Teleprompter.\n\nDieser Text läuft direkt unter deiner Kamera. Wenn du ihn liest, schaust du in die Linse.\n\nMaus auf den Text hält ihn an. Mit ↑ und ↓ springst du zeilenweise.",
            tempo: 30.0, schrift: 22.0, breite: 420.0, hoehe: 170.0, farbe: "Weiß", auto: true, verbergen: true, leuchten: true])
    }
    static let farben: [(String, Color)] = [("Weiß", .white), ("Gelb", .yellow), ("Grün", .green), ("Orange", .orange), ("Cyan", .cyan)]
    static func farbe(_ n: String) -> Color { farben.first { $0.0 == n }?.1 ?? .white }
}

final class PrompterPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class Prompter: ObservableObject {
    static let shared = Prompter()
    @Published var laeuft = false       // Panel offen
    @Published var pause = false        // Maus drauf oder Leertaste
    @Published var versatz: CGFloat = 0
    @Published var inhaltHoehe: CGFloat = 0
    @Published var pegel: CGFloat = 0
    @Published var hinweis: String?

    private var panel: PrompterPanel?
    private var takt: Timer?
    private var tasten: Any?
    private let engine = AVAudioEngine()
    private var mikroAn = false

    private var d: UserDefaults { .standard }
    var zeile: CGFloat { d.double(forKey: P.schrift) * 1.35 }

    func umschalten() { laeuft ? stoppen() : starten() }

    func starten() {
        P.registrieren()
        versatz = 0; pause = false; hinweis = nil
        let p = panel ?? {
            let p = PrompterPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
            p.hidesOnDeactivate = false
            p.level = .statusBar
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            let h = NSHostingView(rootView: PrompterPanelAnsicht().environmentObject(self))
            h.sizingOptions = []
            p.contentView = h
            panel = p
            return p
        }()
        einpassen()
        p.orderFrontRegardless()
        laeuft = true
        takt?.invalidate()
        takt = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in self?.ticken() }
        tasten = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.panel?.isKeyWindow == true else { return e }
            switch e.keyCode {
            case 126: self.springen(-1); return nil   // ↑
            case 125: self.springen(1); return nil    // ↓
            case 49: self.pause.toggle(); return nil  // Leertaste
            case 53: self.stoppen(); return nil       // Esc
            default: return e
            }
        }
        if d.bool(forKey: P.leuchten) { mikroStarten() }
    }

    func stoppen() {
        takt?.invalidate(); takt = nil
        if let t = tasten { NSEvent.removeMonitor(t); tasten = nil }
        mikroStoppen()
        panel?.orderOut(nil)
        laeuft = false
    }

    /// Größe, Lage und Freigabe-Schutz aus den Einstellungen übernehmen (auch während es läuft).
    func einpassen() {
        guard let p = panel, let s = Geraet.bildschirm else { return }
        let menue = max(24, s.frame.maxY - s.visibleFrame.maxY)
        let w = d.double(forKey: P.breite), h = d.double(forKey: P.hoehe)
        // Oben bündig unter der Kamera: oberer Rand liegt hinter der Menüleiste, der Text beginnt darunter.
        p.setFrame(NSRect(x: s.frame.midX - w / 2, y: s.frame.maxY - h - menue, width: w, height: h + menue), display: true)
        p.sharingType = d.bool(forKey: P.verbergen) ? .none : .readOnly
    }

    func maus(_ drauf: Bool) {
        pause = drauf
        if drauf { panel?.makeKey() }   // damit ↑/↓ ankommen; aktiviert die App nicht (nonactivating)
    }

    func springen(_ zeilen: Int) {
        versatz = min(max(0, versatz + CGFloat(zeilen) * zeile), max(0, inhaltHoehe - zeile))
    }

    private func ticken() {
        guard laeuft, !pause, d.bool(forKey: P.auto), inhaltHoehe > 0 else { return }
        if versatz < inhaltHoehe - zeile { versatz += d.double(forKey: P.tempo) / 60 }
    }

    // MARK: Stimm-Leuchten (nur Pegel, keine Aufnahme)

    private func mikroStarten() {
        AVCaptureDevice.requestAccess(for: .audio) { ok in
            DispatchQueue.main.async {
                guard ok, self.laeuft else { if !ok { self.hinweis = L("Mikrofon nicht erlaubt – Leuchten aus, alles andere geht.") }; return }
                let ein = self.engine.inputNode
                ein.removeTap(onBus: 0)
                ein.installTap(onBus: 0, bufferSize: 1024, format: ein.outputFormat(forBus: 0)) { [weak self] puffer, _ in
                    guard let k = puffer.floatChannelData?[0] else { return }
                    let n = Int(puffer.frameLength)
                    var summe: Float = 0
                    for i in 0..<n { summe += k[i] * k[i] }
                    let db = 20 * log10(max(sqrt(summe / Float(max(n, 1))), 1e-6))   // etwa -60 (still) bis 0 (laut)
                    let ziel = CGFloat(min(max((db + 50) / 40, 0), 1))
                    DispatchQueue.main.async { guard let self else { return }; self.pegel += (ziel - self.pegel) * (ziel > self.pegel ? 0.5 : 0.12) }
                }
                do { try self.engine.start(); self.mikroAn = true } catch { self.hinweis = L("Mikrofon ließ sich nicht starten.") }
            }
        }
    }

    private func mikroStoppen() {
        guard mikroAn else { return }
        engine.stop(); engine.inputNode.removeTap(onBus: 0)
        mikroAn = false; pegel = 0
    }
}

// MARK: - Panel unter der Notch

private struct HoeheSchluessel: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct PrompterPanelAnsicht: View {
    @EnvironmentObject var p: Prompter
    @AppStorage(P.text) var text = ""
    @AppStorage(P.schrift) var schrift = 22.0
    @AppStorage(P.farbe) var farbe = "Weiß"
    @AppStorage(P.leuchten) var leuchten = true
    @AppStorage(P.breite) var breite = 420.0
    @AppStorage(P.hoehe) var hoehe = 170.0
    @AppStorage(P.verbergen) var verbergen = true
    @State private var drauf = false

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(bottomLeadingRadius: 22, bottomTrailingRadius: 22).fill(.black)
                Text(text)
                    .font(.system(size: schrift, weight: .medium))
                    .foregroundStyle(P.farbe(farbe))
                    .multilineTextAlignment(.center)
                    .lineSpacing(schrift * 0.35)
                    .frame(width: g.size.width - 40)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { t in Color.clear.preference(key: HoeheSchluessel.self, value: t.size.height) })
                    .offset(y: g.size.height - hoehe + 12 - p.versatz)
                    .onPreferenceChange(HoeheSchluessel.self) { p.inhaltHoehe = $0 }
                // Lesezone oben weich auslaufen lassen.
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: g.size.height - hoehe + 10)
                if leuchten {
                    VStack { Spacer()
                        Ellipse().fill(P.farbe(farbe).opacity(0.15 + 0.6 * p.pegel))
                            .frame(width: g.size.width * (0.4 + 0.5 * p.pegel), height: 26).blur(radius: 14).offset(y: 18)
                    }
                    .allowsHitTesting(false)
                }
                if drauf {
                    VStack { Spacer()
                        HStack(spacing: 12) {
                            Image(systemName: "pause.fill")
                            Text("↑ ↓ Zeile · Leertaste · Esc")
                            Button { p.stoppen() } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                        }
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.6)).padding(.bottom, 8)
                    }
                }
            }
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 22, bottomTrailingRadius: 22))
            .onHover { drauf = $0; p.maus($0) }
        }
        .onChange(of: breite) { _, _ in p.einpassen() }
        .onChange(of: hoehe) { _, _ in p.einpassen() }
        .onChange(of: verbergen) { _, _ in p.einpassen() }
    }
}

// MARK: - Reiter in der Notch: Text schreiben, einstellen, starten

struct PrompterAnsicht: View {
    @ObservedObject var p = Prompter.shared
    @AppStorage(P.text) var text = ""
    @AppStorage(P.tempo) var tempo = 30.0
    @AppStorage(P.schrift) var schrift = 22.0
    @AppStorage(P.breite) var breite = 420.0
    @AppStorage(P.hoehe) var hoehe = 170.0
    @AppStorage(P.farbe) var farbe = "Weiß"
    @AppStorage(P.auto) var auto = true
    @AppStorage(P.verbergen) var verbergen = true
    @AppStorage(P.leuchten) var leuchten = true

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            TextEditor(text: $text)
                .font(.system(size: 13)).scrollContentBackground(.hidden).padding(6)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.08)))
            VStack(alignment: .leading, spacing: 6) {
                Button { p.umschalten() } label: {
                    Label(p.laeuft ? L("Teleprompter stoppen") : L("Teleprompter starten"), systemImage: p.laeuft ? "stop.circle.fill" : "play.circle.fill")
                        .foregroundStyle(p.laeuft ? .red : .orange)
                }
                .buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).disabled(text.isEmpty)
                regler("Tempo", $tempo, 5...120)
                regler("Schrift", $schrift, 14...44)
                regler("Breite", $breite, 260...700)
                regler("Höhe", $hoehe, 90...360)
                Picker("Farbe", selection: $farbe) { ForEach(P.farben, id: \.0) { Text(LocalizedStringKey($0.0)).tag($0.0) } }
                    .controlSize(.small)
                Toggle("Läuft von selbst (sonst ↑/↓)", isOn: $auto).controlSize(.small)
                Toggle("In Bildschirmfreigabe verbergen", isOn: $verbergen).controlSize(.small)
                Toggle("Leuchten folgt der Stimme", isOn: $leuchten).controlSize(.small)
                if let h = p.hinweis { Text(h).font(.system(size: 10)).foregroundStyle(.orange) }
            }
            .frame(width: 250)
            .font(.system(size: 11))
        }
    }

    private func regler(_ name: LocalizedStringKey, _ wert: Binding<Double>, _ bereich: ClosedRange<Double>) -> some View {
        HStack { Text(name).frame(width: 46, alignment: .leading); Slider(value: wert, in: bereich).controlSize(.mini) }
    }
}
