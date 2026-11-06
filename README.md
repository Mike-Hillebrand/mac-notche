# Mac Notche

Die Notch als Schaltzentrale für den Mac – auch auf Macs ohne Notch (Mac Studio, Mac mini, externe Monitore). Alles frei, kein Abo, keine Sperren.

**[Download: Mac Notche 3.8.dmg](../../releases/latest)** · macOS 14.2 oder neuer · Apple Silicon

## Funktionen

**Zugeklappt:** Musik-Cover und Equalizer, Temperatur, Timer-Countdown, Claude-Limits in Prozent (5 Stunden, wo der Plan eines hat, und Woche).

**Aufgeklappt, nach Reitern:**

| Reiter | Inhalt |
|---|---|
| Übersicht | Musik mit Steuerung, Lautstärke (System und pro App), Termine, Erinnerungen, Akkus von Maus, Tastatur, AirPods und iPhone mit Verlauf, Aktienkurse, Sport-Ergebnisse, Kurzbefehle |
| Mitteilungen | Mitteilungen des Macs, Antworten auf iMessage und SMS direkt aus der Notch |
| Wetter | Aktuell und Vorhersage (Open-Meteo, ohne Schlüssel) |
| KI | Claude-Plan-Limits, Token und Kosten von Claude Code, Codex (ChatGPT-Limits) und Gemini über Antigravity CLI |
| Fragen | Claude, Gemini (Antigravity), ChatGPT (Codex) oder per API-Schlüssel Grok, Perplexity, Mistral fragen – als Text, mit Bildschirmfoto, oder als Aufgabe (Claude plant Schritte, du bestätigst, die App führt aus) |
| Ablage | Dateien ablegen, umwandeln (PNG/JPEG/HEIC), DMG installieren, per AirDrop senden |
| iPhone | Fotos vom iPhone am Kabel übernehmen |
| Fokus | Timer, Fokus 25+5, braunes Rauschen, Augen- und Trinkpause, Ton-Ausgabe, Lautstärke pro App, Notizen |
| Werkzeuge | Spiegel (Kamera), Wach halten, Zwischenablage-Verlauf |

**Im Hintergrund:** Lautstärke- und Feststell-Anzeige, Bluetooth- und Akku-Meldungen, Termin-Hinweis, Fenster einrasten (per ⌃⌥-Tastenkürzel oder Ziehen an den Rand), Textbausteine und Emoji-Kürzel (`;mfg`, `:herz:`), Menüleisten-Symbole ausblenden, Bildschirmecken mit Aktionen, Gesicht entsperren.

## Bauen

```bash
./bauen.sh      # build/Mac Notche.app
./dmg.sh        # ../Mac Notche <Version>.dmg
```

Braucht Xcode-Kommandozeilenwerkzeuge. `bauen.sh` signiert mit dem Zertifikat aus `KERBE_IDENTITAET` oder ad hoc.

Zum Prüfen ohne Maus: `open -a "Mac Notche" --args --zeige Fokus`, `--seite werkzeuge`, `--selbsttest` (im Terminal direkt über das Binary).

## Erlaubnisse

Jede Funktion fragt erst, wenn du sie nutzt: Kalender, Erinnerungen, Kontakte, Kamera, Bluetooth, Festplattenvollzugriff (Mitteilungen), Bedienungshilfen (Fenster, Textbausteine), Bildschirmaufnahme (Bildschirm-Frage), Systemaudio (Lautstärke pro App).

Claude-Funktionen laufen über eine lokale Claude-Code-Anmeldung (`claude` im Terminal), ohne API-Schlüssel.

## Hinweise

- Das Gesichtsmodell `Gesicht.mlmodelc` ist ein FaceNet-Modell in Core ML. Es läuft komplett auf dem Mac, nichts verlässt das Gerät.
- Die App ist mit einem Entwicklerzertifikat signiert, aber nicht notarisiert. Beim ersten Start: Rechtsklick › Öffnen.

made with ♥ by [Mike Hillebrand Media](https://mikehillebrand.com) · MIT-Lizenz
