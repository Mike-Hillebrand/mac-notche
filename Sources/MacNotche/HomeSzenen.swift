import AppKit
import Foundation

/// Szenen der Home-App als Kurzbefehle anlegen. HomeKit selbst ist für Apps außerhalb des App Store gesperrt;
/// die Home-App legt aber einen lesbaren Cache ab (NSKeyedArchiver), aus dem Name und Kennung jeder Szene hervorgehen.
/// Daraus entsteht je Szene eine signierte .shortcut-Datei mit der Aktion „Zuhause steuern“ (Protobuf: Szene + Haus),
/// die die Kurzbefehle-App nur noch per Klick übernimmt. Aufbau nach Apples WorkflowKit/HomeKit (HMActionSet.shortcutsDictionaryRepresentation).
enum HomeSzenen {
    struct Szene: Identifiable { let name: String; let uuid: UUID; var id: String { name } }
    struct Haus { let name: String; let uuid: UUID; let szenen: [Szene] }

    static let praefix = "Szene "
    static let ordner = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/Mac Notche Kurzbefehle", isDirectory: true)
    private static let cache = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Containers/com.apple.Home/Data/Library/Caches/com.apple.HomeKit/com.apple.Home/com.apple.HomeKit.configurations")

    /// Name ohne Präfix für die Kachel.
    static func anzeige(_ name: String) -> String { name.hasPrefix(praefix) ? String(name.dropFirst(praefix.count)) : name }

    /// Liest Haus und Szenen aus dem Home-App-Cache; nil, wenn der Cache fehlt oder nicht lesbar ist (Festplattenvollzugriff).
    static func lesen() -> Haus? {
        guard let dateien = try? FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil),
              let datei = dateien.first(where: { $0.lastPathComponent.hasPrefix("homeData.") }),
              let daten = try? Data(contentsOf: datei) else { return nil }
        var blobs: [Data] = [daten]
        sammeln(try? PropertyListSerialization.propertyList(from: daten, format: nil), in: &blobs)
        var haus: (String, UUID)?
        var szenen: [Szene] = []
        for b in blobs {
            guard let p = (try? PropertyListSerialization.propertyList(from: b, format: nil)) as? [String: Any], let objs = p["$objects"] as? [Any] else { continue }
            func text(_ v: Any?) -> String? {
                guard let v else { return nil }
                if let s = v as? String { return s }
                // CFKeyedArchiverUID: der Wert steht nur in der Beschreibung „{value = 978}“.
                let d = String(describing: v)
                guard let r = d.range(of: #"value = (\d+)"#, options: .regularExpression),
                      let i = Int(d[r].split(separator: "=").last!.trimmingCharacters(in: .whitespaces)), i < objs.count else { return nil }
                return objs[i] as? String
            }
            for o in objs {
                guard let d = o as? [String: Any] else { continue }
                if let n = text(d["homeName"]), let u = text(d["homeUUID"]).flatMap(UUID.init) { haus = (n, u) }
                if let n = text(d["actionSetName"]), let u = text(d["actionSetUUID"]).flatMap(UUID.init),
                   text(d["actionSetType"]) == "HMActionSetTypeUserDefined", !szenen.contains(where: { $0.uuid == u }) {
                    szenen.append(Szene(name: n, uuid: u))
                }
            }
        }
        guard let haus else { return nil }
        return Haus(name: haus.0, uuid: haus.1, szenen: szenen.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }

    private static func sammeln(_ o: Any?, in blobs: inout [Data]) {
        if let d = o as? Data, d.starts(with: Array("bplist00".utf8)) { blobs.append(d) }
        else if let dict = o as? [String: Any] { dict.values.forEach { sammeln($0, in: &blobs) } }
        else if let arr = o as? [Any] { arr.forEach { sammeln($0, in: &blobs) } }
    }

    /// Protobuf HMPBActionSet: Feld 4 = Szenen-UUID (16 Byte), Feld 5 = Haus-UUID (16 Byte). Ohne Name/Aktionen = bestehende Szene ausführen.
    private static func protobuf(_ szene: UUID, _ haus: UUID) -> Data {
        var d = Data([0x22, 0x10]); d.append(contentsOf: bytes(szene)); d.append(contentsOf: [0x2A, 0x10]); d.append(contentsOf: bytes(haus)); return d
    }
    private static func bytes(_ u: UUID) -> [UInt8] { let t = u.uuid; return [t.0, t.1, t.2, t.3, t.4, t.5, t.6, t.7, t.8, t.9, t.10, t.11, t.12, t.13, t.14, t.15] }

    /// Baut und signiert die .shortcut-Datei; gibt den Pfad zurück.
    static func datei(fuer s: Szene, haus: Haus) throws -> URL {
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        let name = praefix + s.name
        let plist: [String: Any] = [
            "WFWorkflowClientVersion": "2605.0.5", "WFWorkflowMinimumClientVersion": 900, "WFWorkflowMinimumClientVersionString": "900",
            "WFWorkflowHasOutputFallback": false, "WFWorkflowHasShortcutInputVariables": false, "WFWorkflowImportQuestions": [Any](),
            "WFWorkflowInputContentItemClasses": [Any](), "WFWorkflowTypes": [Any](),
            "WFWorkflowIcon": ["WFWorkflowIconGlyphNumber": 59511, "WFWorkflowIconStartColor": 4274264319],
            "WFWorkflowName": name,
            "WFWorkflowActions": [[
                "WFWorkflowActionIdentifier": "is.workflow.actions.homeaccessory",
                "WFWorkflowActionParameters": [
                    "WFHome": haus.name,
                    "WFHomeTriggerActionSets": [
                        "WFHFTriggerActionSetsBuilderParameterStateHome": haus.uuid.uuidString,
                        "WFHFTriggerActionSetsBuilderParameterStateActionSets": [[
                            "HMActionSetSerializedDictionaryVersion": "1.0", "HMActionSetSerializedDictionaryProtocol": "ProtoBuf",
                            "HMActionSetSerializedData": protobuf(s.uuid, haus.uuid)]]]]]]]
        let roh = ordner.appendingPathComponent(name + ".unsigned.shortcut")
        let ziel = ordner.appendingPathComponent(name + ".shortcut")
        try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0).write(to: roh)
        try? FileManager.default.removeItem(at: ziel)
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = ["sign", "--mode", "anyone", "--input", roh.path, "--output", ziel.path]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        try? FileManager.default.removeItem(at: roh)
        guard FileManager.default.fileExists(atPath: ziel.path) else { throw NSError(domain: "HomeSzenen", code: 1, userInfo: [NSLocalizedDescriptionKey: L("Signieren fehlgeschlagen.")]) }
        return ziel
    }
}

/// Führt den Import Schritt für Schritt: Datei öffnen, warten bis der Kurzbefehl in der Bibliothek ist, nächste.
final class HomeImport: ObservableObject {
    @Published var haus: HomeSzenen.Haus?
    @Published var vorhanden: Set<String> = []
    @Published var status = ""
    @Published var laeuft = false

    func laden() {
        DispatchQueue.global(qos: .userInitiated).async {
            let h = HomeSzenen.lesen()
            let alle = Set(Kurzbefehle.alle())
            DispatchQueue.main.async { self.haus = h; self.vorhanden = alle }
        }
    }

    var fehlend: [HomeSzenen.Szene] { (haus?.szenen ?? []).filter { !vorhanden.contains(HomeSzenen.praefix + $0.name) } }

    func anlegen() {
        guard let haus, !laeuft else { return }
        let liste = fehlend
        laeuft = true
        DispatchQueue.global(qos: .userInitiated).async {
            var fertig: [String] = []
            for (i, s) in liste.enumerated() {
                let name = HomeSzenen.praefix + s.name
                DispatchQueue.main.async { self.status = "\(i + 1)/\(liste.count): „\(name)“ – in der Kurzbefehle-App auf „Kurzbefehl hinzufügen“ klicken …" }
                guard let url = try? HomeSzenen.datei(fuer: s, haus: haus) else { continue }
                DispatchQueue.main.async { NSWorkspace.shared.open(url) }
                // Bis zu 90 s warten, bis der Kurzbefehl in der Bibliothek ist.
                var da = false
                for _ in 0..<45 { Thread.sleep(forTimeInterval: 2); if Kurzbefehle.alle().contains(name) { da = true; break } }
                if da { fertig.append(name) } else { break }
            }
            DispatchQueue.main.async {
                self.vorhanden.formUnion(fertig)
                // Neue gleich im Reiter anhaken.
                var auswahl = (UserDefaults.standard.string(forKey: E.zuhauseAuswahl) ?? "").split(separator: "\n").map(String.init).filter { !$0.isEmpty }
                for n in fertig where !auswahl.contains(n) { auswahl.append(n) }
                UserDefaults.standard.set(auswahl.joined(separator: "\n"), forKey: E.zuhauseAuswahl)
                self.status = fertig.count == liste.count ? L("Fertig – \(fertig.count) Szenen in der Notch.") : L("\(fertig.count) von \(liste.count) übernommen; der Rest wurde nicht bestätigt.")
                self.laeuft = false
            }
        }
    }
}
