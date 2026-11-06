import Foundation
import CoreLocation

struct WetterJetzt { let temp: Double; let code: Int; let tag: Bool }
struct WetterTag: Identifiable { let id: String; let datum: Date; let code: Int; let max, min: Double; let regen: Int }

/// Wetter von Open-Meteo (kostenlos, ohne Konto), Ort per CoreLocation.
final class Wetter: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var jetzt: WetterJetzt?
    @Published var tage: [WetterTag] = []
    @Published var ort = "…"
    /// Woher der Ort stammt: "system", "ip", "manuell" oder "" (noch keiner).
    @Published var quelle = ""

    private let standort = CLLocationManager()
    private var koordinate: CLLocationCoordinate2D?
    private var ipVersucht = false

    func starten() {
        standort.delegate = self
        standort.desiredAccuracy = kCLLocationAccuracyKilometer
        ortBestimmen()
        Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in self?.ortBestimmen() }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            let m = Self.manuellerOrt
            if (m == nil) != (self.quelle != "manuell") || (m != nil && m != self.gesucht) { self.ortBestimmen() }
        }
    }

    private var gesucht: String?

    static var manuellerOrt: String? {
        let o = UserDefaults.standard.string(forKey: E.wetterOrt)?.trimmingCharacters(in: .whitespaces) ?? ""
        return o.isEmpty ? nil : o
    }

    /// Reihenfolge: eingetragener Ort → Systemortung → Standort aus der Internetadresse.
    func ortBestimmen() {
        if let m = Self.manuellerOrt { if m != gesucht { gesucht = m; ortSuchen(m) } else { laden() }; return }
        if quelle == "manuell" { quelle = ""; koordinate = nil; gesucht = nil }
        standort.requestWhenInUseAuthorization()
        if ![.notDetermined, .denied, .restricted].contains(standort.authorizationStatus) { standort.requestLocation() }
        else if standort.authorizationStatus != .notDetermined { perIP() }
        laden()
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        guard Self.manuellerOrt == nil else { return }
        if ![.notDetermined, .denied, .restricted].contains(m.authorizationStatus) { m.requestLocation() }
        else if m.authorizationStatus != .notDetermined { perIP() }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations orte: [CLLocation]) {
        guard Self.manuellerOrt == nil, let p = orte.last else { return }
        koordinate = p.coordinate; quelle = "system"
        laden()
        CLGeocoder().reverseGeocodeLocation(p) { marken, _ in
            if let n = marken?.first?.locality { DispatchQueue.main.async { self.ort = n } }
        }
    }

    // Kein Wi-Fi (Ethernet-iMac) oder Ortung aus: Systemortung scheitert still → Internetadresse.
    func locationManager(_ m: CLLocationManager, didFailWithError fehler: Error) { if Self.manuellerOrt == nil { perIP() } }

    private func perIP() {
        guard quelle != "system", !ipVersucht || koordinate == nil else { return }
        ipVersucht = true
        URLSession.shared.dataTask(with: URL(string: "https://ipwho.is/?fields=success,latitude,longitude,city")!) { d, _, _ in
            guard let d, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], j["success"] as? Bool == true,
                  let la = (j["latitude"] as? NSNumber)?.doubleValue, let lo = (j["longitude"] as? NSNumber)?.doubleValue else { return }
            DispatchQueue.main.async {
                guard self.quelle != "system", Self.manuellerOrt == nil else { return }
                self.koordinate = CLLocationCoordinate2D(latitude: la, longitude: lo); self.quelle = "ip"
                self.ort = j["city"] as? String ?? self.ort
                self.laden()
            }
        }.resume()
    }

    /// Ortsname → Koordinate über Open-Meteo-Geocoding.
    private func ortSuchen(_ name: String) {
        guard let n = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(n)&count=1&language=de") else { return }
        URLSession.shared.dataTask(with: url) { d, _, _ in
            guard let d, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let e = (j["results"] as? [[String: Any]])?.first,
                  let la = (e["latitude"] as? NSNumber)?.doubleValue, let lo = (e["longitude"] as? NSNumber)?.doubleValue else {
                DispatchQueue.main.async { self.ort = name + " ?"; self.quelle = "manuell" }; return
            }
            DispatchQueue.main.async {
                self.koordinate = CLLocationCoordinate2D(latitude: la, longitude: lo); self.quelle = "manuell"
                self.ort = e["name"] as? String ?? name
                self.laden()
            }
        }.resume()
    }

    func laden() {
        guard let k = koordinate else { return }
        let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(k.latitude)&longitude=\(k.longitude)"
            + "&current=temperature_2m,weather_code,is_day"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"
            + "&timezone=auto&forecast_days=4"
            + (UserDefaults.standard.bool(forKey: E.fahrenheit) ? "&temperature_unit=fahrenheit" : ""))!
        URLSession.shared.dataTask(with: url) { daten, _, _ in
            guard let daten, let (j, t) = Self.lesen(daten) else { return }
            DispatchQueue.main.async { self.jetzt = j; self.tage = t }
        }.resume()
    }

    static func lesen(_ d: Data) -> (WetterJetzt, [WetterTag])? {
        guard let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let c = o["current"] as? [String: Any],
              let temp = (c["temperature_2m"] as? NSNumber)?.doubleValue,
              let code = (c["weather_code"] as? NSNumber)?.intValue,
              let tag = o["daily"] as? [String: Any],
              let zeiten = tag["time"] as? [String] else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        func zahl(_ k: String, _ i: Int) -> Double {
            guard let a = tag[k] as? [Any], i < a.count else { return 0 }
            return (a[i] as? NSNumber)?.doubleValue ?? 0
        }
        let tage = zeiten.enumerated().compactMap { i, s -> WetterTag? in
            guard let datum = f.date(from: s) else { return nil }
            return WetterTag(id: s, datum: datum, code: Int(zahl("weather_code", i)),
                             max: zahl("temperature_2m_max", i), min: zahl("temperature_2m_min", i),
                             regen: Int(zahl("precipitation_probability_max", i)))
        }
        let istTag = ((c["is_day"] as? NSNumber)?.intValue ?? 1) == 1
        return (WetterJetzt(temp: temp, code: code, tag: istTag), tage)
    }

    /// WMO-Wettercode → SF-Symbol und deutscher Text.
    static func beschreibung(_ code: Int, tag: Bool = true) -> (symbol: String, text: String) {
        switch code {
        case 0: return (tag ? "sun.max.fill" : "moon.stars.fill", "Klar")
        case 1: return (tag ? "cloud.sun.fill" : "cloud.moon.fill", "Überwiegend klar")
        case 2: return (tag ? "cloud.sun.fill" : "cloud.moon.fill", "Teilweise bewölkt")
        case 3: return ("cloud.fill", "Bedeckt")
        case 45, 48: return ("cloud.fog.fill", "Nebel")
        case 51, 53, 55, 56, 57: return ("cloud.drizzle.fill", "Nieselregen")
        case 61, 63, 65, 66, 67: return ("cloud.rain.fill", "Regen")
        case 80, 81, 82: return ("cloud.heavyrain.fill", "Regenschauer")
        case 71, 73, 75, 77, 85, 86: return ("cloud.snow.fill", "Schnee")
        case 95, 96, 99: return ("cloud.bolt.rain.fill", "Gewitter")
        default: return ("cloud.fill", "Wechselhaft")
        }
    }
}
