import SwiftUI

// MARK: - Glas-Theme
// Grundlage ist Apples Liquid Glass (macOS 26+): bricht live, was hinter der Notch liegt.
// Darauf liegen die Looks aus dem Werkzeug „Glas“ (glas.js › PRESETS): Tönung, Frost, Lichtkante (rim),
// Glanzlicht (specular), Farbsäume (dispersion) und Innenschatten. Licht kommt wie dort von links oben (-45°).
// Ältere Systeme bekommen dieselben Schichten über einem Material.

struct GlasArt {
    let name: String
    let tint: Color, tintAmount: Double
    let frost: Double          // 0 klar … 14 Milchglas (wie glas.js)
    let rim: Double, rimWidth: CGFloat
    let specular: Double, dispersion: Double, innerShadow: Double
    var dunkel = false

    static let alle: [(id: String, art: GlasArt)] = [
        ("klar", GlasArt(name: "Klar – ruhig, kaum Rand", tint: .white, tintAmount: 0.02, frost: 0, rim: 0.55, rimWidth: 1.1, specular: 0.2, dispersion: 0.012, innerShadow: 0.08)),
        ("standard", GlasArt(name: "Standard – kräftiger Rand", tint: .white, tintAmount: 0.04, frost: 0, rim: 0.9, rimWidth: 1.6, specular: 0.5, dispersion: 0.024, innerShadow: 0.18)),
        ("milchglas", GlasArt(name: "Milchglas – stark gefrostet, gut lesbar", tint: .white, tintAmount: 0.12, frost: 14, rim: 0.7, rimWidth: 1, specular: 0.15, dispersion: 0.01, innerShadow: 0.12)),
        ("eis", GlasArt(name: "Eis – leichter Frost, kühl, viel Glanz", tint: Color(red: 0.87, green: 0.95, blue: 1), tintAmount: 0.14, frost: 6, rim: 1.1, rimWidth: 1.6, specular: 0.7, dispersion: 0.05, innerShadow: 0.18)),
        ("prisma", GlasArt(name: "Prisma – harter Rand, Farbsäume", tint: .white, tintAmount: 0.04, frost: 0, rim: 1.2, rimWidth: 1, specular: 0.9, dispersion: 0.14, innerShadow: 0.18)),
        ("rauch", GlasArt(name: "Rauch – dunkles Glas, helle Schrift", tint: Color(red: 0.04, green: 0.04, blue: 0.05), tintAmount: 0.45, frost: 0, rim: 1, rimWidth: 1.6, specular: 0.6, dispersion: 0.06, innerShadow: 0.18, dunkel: true)),
    ]
    static func gewaehlt(_ id: String) -> GlasArt { alle.first { $0.id == id }?.art ?? alle[0].art }
}

extension E { static let glasArt = "glas.art" }

struct GlasFlaeche: View {
    let form: AnyShape
    let art: GlasArt
    /// Geöffnete Notch: viel Text, daher Frost-Schicht dazu (Regel aus dem Glas-Werkzeug: Schrift muss lesbar bleiben).
    var lesbar = false

    var body: some View {
        ZStack {
            basis
            form.fill(art.tint.opacity(art.tintAmount * 0.8))
            if lesbar {
                if art.dunkel { form.fill(Color.black.opacity(0.45)) } else { form.fill(.regularMaterial).opacity(0.85) }
            }
            // Glanzlicht links oben (specular).
            form.fill(RadialGradient(colors: [.white.opacity(art.specular * 0.28), .clear],
                                     center: UnitPoint(x: 0.12, y: 0), startRadius: 0, endRadius: 320))
                .blendMode(.plusLighter)
            // Innenschatten unten: gibt dem Glas Dicke.
            form.stroke(Color.black.opacity(art.innerShadow), lineWidth: 8).blur(radius: 5).offset(y: 3).clipShape(form)
            // Farbsäume (dispersion): Rot und Blau leicht gegeneinander versetzt an der Kante.
            if art.dispersion > 0.02 {
                form.stroke(Color.red.opacity(min(art.dispersion * 4, 0.6)), lineWidth: 1).offset(x: -art.dispersion * 14)
                form.stroke(Color.blue.opacity(min(art.dispersion * 4, 0.6)), lineWidth: 1).offset(x: art.dispersion * 14)
            }
            // Lichtkante (rim): hell, wo das Licht auftrifft (links oben), schwach gegenüber.
            form.stroke(LinearGradient(colors: [.white.opacity(min(art.rim * 0.75, 1)), .white.opacity(art.rim * 0.12), .white.opacity(art.rim * 0.35)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: art.rimWidth)
        }
        .clipShape(form)
        .allowsHitTesting(false)
    }

    @ViewBuilder private var basis: some View {
        if #available(macOS 26.0, *) {
            // Frost über das stärkere Glas, sonst klares Glas; Tönung wie tint/tintAmount.
            let glas: Glass = art.frost >= 6 ? .regular : .clear
            Color.clear.glassEffect(glas.tint(art.tint.opacity(art.tintAmount)), in: form)
            if art.frost >= 14 { form.fill(.ultraThinMaterial).opacity(0.6) }
        } else {
            form.fill(art.frost >= 14 ? AnyShapeStyle(.regularMaterial) : art.frost >= 6 ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(.ultraThinMaterial))
        }
    }
}
