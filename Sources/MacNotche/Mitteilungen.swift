import AppKit
import SQLite3
import Contacts

struct Mitteilung: Identifiable { let id: Int64; let app: String; let appName: String; let titel: String; let text: String; let zeit: Date }
struct Gespraech: Identifiable { let id: String; let name: String; let text: String; let zeit: Date; let vonMir: Bool }
struct UngeleseneMail: Identifiable { let id: Int; let absender: String; let betreff: String }

/// Liest die Mitteilungs-Datenbank von macOS und die Nachrichten-Datenbank (beides braucht Festplattenvollzugriff).
/// Antworten gehen nur über Nachrichten (AppleScript) und Mail (Antwortfenster) – andere Apps erlauben das nicht.
final class Mitteilungen: ObservableObject {
    @Published var liste: [Mitteilung] = []
    @Published var gespraeche: [Gespraech] = []
    @Published var mails: [UngeleseneMail] = []
    @Published var zugriff = true
    @Published var status: String?
    var melden: ((String, String, String) -> Void)?

    private var letzteID: Int64?
    private var namen: [String: String] = [:]  // nur auf warteschlange
    private let warteschlange = DispatchQueue(label: "macnotche.mitteilungen")

    static let heim = FileManager.default.homeDirectoryForCurrentUser.path
    static let mitteilungsDB = heim + "/Library/Group Containers/group.com.apple.usernoted/db2/db"
    static let nachrichtenDB = heim + "/Library/Messages/chat.db"

    func starten() {
        CNContactStore().requestAccess(for: .contacts) { _, _ in }
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.abfragen() }
        abfragen()
    }

    func abfragen() {
        warteschlange.async {
            let liste = Self.mitteilungenLesen()
            let gespraeche = Self.gespraecheLesen()?.map { g in
                Gespraech(id: g.id, name: self.kontaktName(g.name) ?? g.name, text: g.text, zeit: g.zeit, vonMir: g.vonMir)
            }
            DispatchQueue.main.async {
                self.zugriff = liste != nil
                guard let liste else { return }
                if let alt = self.letzteID {
                    for n in liste.reversed() where n.id > alt {
                        self.melden?("mitteilungen", "bell.fill", "\(n.appName): \(n.titel.isEmpty ? n.text : n.titel)")
                    }
                }
                self.letzteID = max(self.letzteID ?? 0, liste.map(\.id).max() ?? 0)
                self.liste = liste
                self.gespraeche = gespraeche ?? []
            }
        }
    }

    // MARK: SQLite (nur lesen)

    @discardableResult
    static func abfrage(_ pfad: String, _ sql: String, _ zeile: (OpaquePointer) -> Void) -> Bool {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(pfad, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return false }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK, let st else { return false }
        defer { sqlite3_finalize(st) }
        while sqlite3_step(st) == SQLITE_ROW { zeile(st) }
        return true
    }

    static func text(_ st: OpaquePointer, _ i: Int32) -> String? { sqlite3_column_text(st, i).map { String(cString: $0) } }
    static func blob(_ st: OpaquePointer, _ i: Int32) -> Data? {
        guard let p = sqlite3_column_blob(st, i) else { return nil }
        return Data(bytes: p, count: Int(sqlite3_column_bytes(st, i)))
    }

    static func appName(_ id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func mitteilungenLesen() -> [Mitteilung]? {
        var r: [Mitteilung] = []
        let sql = "SELECT r.rec_id, a.identifier, r.data, r.delivered_date FROM record r JOIN app a ON a.app_id = r.app_id ORDER BY r.rec_id DESC LIMIT 8"
        let ok = abfrage(mitteilungsDB, sql) { st in
            guard let app = text(st, 1), !app.hasPrefix("_"), app != Bundle.main.bundleIdentifier,
                  let d = blob(st, 2),
                  let p = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any],
                  let req = p["req"] as? [String: Any] else { return }
            r.append(Mitteilung(id: sqlite3_column_int64(st, 0), app: app, appName: appName(app),
                                titel: [req["titl"], req["subt"]].compactMap { $0 as? String }.filter { !$0.isEmpty }.joined(separator: " – "),
                                text: req["body"] as? String ?? "",
                                zeit: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(st, 3))))
        }
        return ok ? r : nil
    }

    static func gespraecheLesen() -> [Gespraech]? {
        var r: [Gespraech] = []
        let sql = """
        SELECT c.guid, c.chat_identifier, c.display_name, m.text, m.attributedBody, m.date, m.is_from_me
        FROM chat c JOIN chat_message_join j ON j.chat_id = c.ROWID JOIN message m ON m.ROWID = j.message_id
        WHERE j.message_id IN (SELECT MAX(message_id) FROM chat_message_join GROUP BY chat_id)
        ORDER BY m.date DESC LIMIT 4
        """
        let ok = abfrage(nachrichtenDB, sql) { st in
            guard let guid = text(st, 0) else { return }
            let anzeige = text(st, 2).flatMap { $0.isEmpty ? nil : $0 } ?? text(st, 1) ?? "?"
            let inhalt = text(st, 3).flatMap { $0.isEmpty ? nil : $0 } ?? blob(st, 4).flatMap(nachrichtText) ?? "Anhang"
            r.append(Gespraech(id: guid, name: anzeige, text: inhalt,
                               zeit: Date(timeIntervalSinceReferenceDate: Double(sqlite3_column_int64(st, 5)) / 1e9),
                               vonMir: sqlite3_column_int(st, 6) == 1))
        }
        return ok ? r : nil
    }

    /// Neuere macOS speichern den Text nur im „attributedBody“ (typedstream): Länge steht hinter 0x01 0x2B nach „NSString“.
    static func nachrichtText(_ d: Data) -> String? {
        let b = [UInt8](d)
        guard let start = b.firstRange(of: Array("NSString".utf8))?.upperBound else { return nil }
        var i = start
        while i + 1 < b.count, !(b[i] == 0x01 && b[i + 1] == 0x2B) { i += 1 }
        i += 2
        guard i < b.count else { return nil }
        var n = Int(b[i]); i += 1
        if n == 0x81 {
            guard i + 1 < b.count else { return nil }
            n = Int(b[i]) | Int(b[i + 1]) << 8; i += 2
        }
        guard n > 0, i + n <= b.count else { return nil }
        return String(bytes: b[i..<(i + n)], encoding: .utf8)
    }

    private func kontaktName(_ handle: String) -> String? {
        if let n = namen[handle] { return n.isEmpty ? nil : n }
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized,
              handle.contains("@") || handle.hasPrefix("+") || handle.first?.isNumber == true else { return nil }
        let p = handle.contains("@") ? CNContact.predicateForContacts(matchingEmailAddress: handle)
                                     : CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: handle))
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey] as [CNKeyDescriptor]
        let c = (try? CNContactStore().unifiedContacts(matching: p, keysToFetch: keys))?.first
        let n = c.map { "\($0.givenName) \($0.familyName)".trimmingCharacters(in: .whitespaces) } ?? ""
        namen[handle] = n
        return n.isEmpty ? nil : n
    }

    // MARK: Antworten

    static func maskieren(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    func senden(_ text: String, an g: Gespraech) {
        let skript = "tell application \"Messages\" to send \"\(Self.maskieren(text))\" to chat id \"\(Self.maskieren(g.id))\""
        warteschlange.async {
            var fehler: NSDictionary?
            NSAppleScript(source: skript)?.executeAndReturnError(&fehler)
            DispatchQueue.main.async {
                self.status = fehler == nil ? "Gesendet an \(g.name)" : "Senden fehlgeschlagen – Nachrichten-App erlauben?"
                self.abfragen()
            }
        }
    }

    func mailsLaden() {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").isEmpty else { mails = []; return }
        let skript = """
        tell application "Mail"
            set out to {}
            repeat with m in (messages of inbox whose read status is false)
                set end of out to {id of m, sender of m, subject of m}
                if (count of out) ≥ 3 then exit repeat
            end repeat
            return out
        end tell
        """
        warteschlange.async {
            var fehler: NSDictionary?
            let d: NSAppleEventDescriptor? = NSAppleScript(source: skript)?.executeAndReturnError(&fehler)
            var r: [UngeleseneMail] = []
            if let d, d.numberOfItems > 0 {
                for i in 1...d.numberOfItems {
                    guard let e = d.atIndex(i), e.numberOfItems >= 3 else { continue }
                    r.append(UngeleseneMail(id: Int(e.atIndex(1)?.int32Value ?? 0),
                                            absender: e.atIndex(2)?.stringValue ?? "",
                                            betreff: e.atIndex(3)?.stringValue ?? ""))
                }
            }
            DispatchQueue.main.async { self.mails = r }
        }
    }

    func mailAntworten(_ m: UngeleseneMail) {
        let skript = """
        tell application "Mail"
            set m to first message of inbox whose id is \(m.id)
            reply m with opening window
            activate
        end tell
        """
        warteschlange.async {
            var fehler: NSDictionary?
            NSAppleScript(source: skript)?.executeAndReturnError(&fehler)
        }
    }

    static func festplattenzugriffOeffnen() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }
}
