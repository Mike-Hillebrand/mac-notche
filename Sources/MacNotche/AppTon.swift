import AppKit
import CoreAudio
import AudioToolbox

/// Lautstärke pro App über Process Taps (macOS 14.2+): der Tap fängt den Ton der App ab und stummt
/// das Original, ein eigener IOProc spielt ihn mit angepasster Lautstärke auf dem Ausgabegerät ab.
/// Braucht die Erlaubnis „Systemaudio aufnehmen“ beim ersten Regler.
struct AppTon: Identifiable, Equatable {
    let pid: pid_t
    let objekt: AudioObjectID
    let name: String
    var id: pid_t { pid }
}

final class AppLautstaerke: ObservableObject {
    @Published var apps: [AppTon] = []
    @Published var pegel: [pid_t: Float] = [:]  // 1 = unverändert, 0 = stumm
    private var taps: [pid_t: Tap] = [:]
    private var geraeteListener: AudioObjectPropertyListenerBlock?

    func starten() {
        laden()
        Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in self?.laden() }
        // Ausgabegerät gewechselt → Taps neu aufbauen, sonst spielen sie auf dem alten Gerät weiter.
        var adr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let alt = self.taps.map { ($0.key, $0.value.gain) }
                self.taps.removeAll()
                for (pid, g) in alt { self.setzen(pid, g) }
            }
        }
        geraeteListener = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &adr, .main, block)
    }

    func laden() {
        let liste = Self.prozesse()
        // Taps von Apps, die keinen Ton mehr machen, erst entfernen, wenn der Prozess weg ist.
        for pid in taps.keys where !liste.contains(where: { $0.pid == pid }) && NSRunningApplication(processIdentifier: pid) == nil {
            taps[pid] = nil; pegel[pid] = nil
        }
        // Apps mit Regler bleiben stehen, auch wenn sie gerade still sind – sonst springt der Regler weg.
        var neu = liste.filter { a in a.name != "Mac Notche" }
        for a in apps where taps[a.pid] != nil && !neu.contains(where: { $0.pid == a.pid }) { neu.append(a) }
        neu.sort { $0.name < $1.name }
        if neu != apps { apps = neu }
    }

    func setzen(_ pid: pid_t, _ g: Float) {
        pegel[pid] = g
        if let t = taps[pid] { t.gain = g; return }
        guard let a = apps.first(where: { $0.pid == pid }), case let aus? = AudioAusgabe.standard() as AudioDeviceID?,
              let t = Tap(objekt: a.objekt, ausgabe: aus) else { return }
        t.gain = g
        taps[pid] = t
    }

    /// Alle Prozesse, die gerade Ton ausgeben.
    static func prozesse() -> [AppTon] {
        var adr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var groesse: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &adr, 0, nil, &groesse) == noErr else { return [] }
        var objekte = [AudioObjectID](repeating: 0, count: Int(groesse) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &adr, 0, nil, &groesse, &objekte) == noErr else { return [] }
        var ergebnis: [AppTon] = []
        for o in objekte {
            var pid: pid_t = 0, laeuft: UInt32 = 0
            var s = UInt32(MemoryLayout<pid_t>.size)
            adr.mSelector = kAudioProcessPropertyPID
            guard AudioObjectGetPropertyData(o, &adr, 0, nil, &s, &pid) == noErr else { continue }
            s = 4; adr.mSelector = kAudioProcessPropertyIsRunningOutput
            guard AudioObjectGetPropertyData(o, &adr, 0, nil, &s, &laeuft) == noErr, laeuft != 0 else { continue }
            var name = NSRunningApplication(processIdentifier: pid)?.localizedName
            if name == nil {
                // Helfer-Prozesse (z. B. von Browsern) haben nur eine Bundle-ID.
                var b: CFString? = nil; var bs = UInt32(MemoryLayout<CFString?>.size)
                adr.mSelector = kAudioProcessPropertyBundleID
                if AudioObjectGetPropertyData(o, &adr, 0, nil, &bs, &b) == noErr, let b = b as String?, !b.isEmpty {
                    name = NSRunningApplication.runningApplications(withBundleIdentifier: b).first?.localizedName
                        ?? b.split(separator: ".").dropFirst().first.map(String.init)?.capitalized
                }
            }
            ergebnis.append(AppTon(pid: pid, objekt: o, name: name ?? "Prozess \(pid)"))
        }
        return ergebnis.sorted { $0.name < $1.name }
    }

    final class Tap {
        var gain: Float = 1
        private let tapID: AudioObjectID
        private let aggregat: AudioObjectID
        private var proc: AudioDeviceIOProcID?

        init?(objekt: AudioObjectID, ausgabe: AudioDeviceID) {
            let beschreibung = CATapDescription(stereoMixdownOfProcesses: [objekt])
            beschreibung.muteBehavior = .mutedWhenTapped
            beschreibung.isPrivate = true
            var tap: AudioObjectID = 0
            guard AudioHardwareCreateProcessTap(beschreibung, &tap) == noErr else { return nil }
            tapID = tap
            var adr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var uid: CFString? = nil; var s = UInt32(MemoryLayout<CFString?>.size)
            guard AudioObjectGetPropertyData(ausgabe, &adr, 0, nil, &s, &uid) == noErr, let uid = uid as String? else {
                AudioHardwareDestroyProcessTap(tap); return nil
            }
            let desc: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Mac Notche App-Ton",
                kAudioAggregateDeviceUIDKey: "com.mikehillebrand.kerbe.tap.\(objekt)",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceMainSubDeviceKey: uid,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: uid]],
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: beschreibung.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]],
                kAudioAggregateDeviceTapAutoStartKey: true,
            ]
            var agg: AudioObjectID = 0
            guard AudioHardwareCreateAggregateDevice(desc as CFDictionary, &agg) == noErr else { AudioHardwareDestroyProcessTap(tap); return nil }
            aggregat = agg
            var procID: AudioDeviceIOProcID?
            let status = AudioDeviceCreateIOProcIDWithBlock(&procID, agg, nil) { [weak self] _, ein, _, aus, _ in
                let g = self?.gain ?? 1
                let einListe = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: ein))
                let ausListe = UnsafeMutableAudioBufferListPointer(aus)
                guard let eb = einListe.first, let ep = eb.mData?.assumingMemoryBound(to: Float.self), eb.mNumberChannels > 0 else { return }
                let ek = Int(eb.mNumberChannels), ef = Int(eb.mDataByteSize) / 4 / ek
                var kanal = 0
                for ab in ausListe {
                    guard let ap = ab.mData?.assumingMemoryBound(to: Float.self), ab.mNumberChannels > 0 else { continue }
                    let ak = Int(ab.mNumberChannels), af = Int(ab.mDataByteSize) / 4 / ak
                    for f in 0..<min(ef, af) {
                        for c in 0..<ak {
                            let ic = kanal + c
                            ap[f * ak + c] = ic < ek ? ep[f * ek + ic] * g : 0
                        }
                    }
                    kanal += ak
                }
            }
            guard status == noErr, let procID else { AudioHardwareDestroyAggregateDevice(agg); AudioHardwareDestroyProcessTap(tap); return nil }
            proc = procID
            AudioDeviceStart(agg, procID)
        }

        deinit {
            if let proc { AudioDeviceStop(aggregat, proc); AudioDeviceDestroyIOProcID(aggregat, proc) }
            AudioHardwareDestroyAggregateDevice(aggregat)
            AudioHardwareDestroyProcessTap(tapID)
        }
    }
}
