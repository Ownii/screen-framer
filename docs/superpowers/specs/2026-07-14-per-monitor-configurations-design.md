# Per-Monitor-Konfigurationen

## Ziel

Eine Ausschnitt-Konfiguration soll optional auf bestimmte Monitore
beschränkt werden können. Fehlt die Beschränkung, gilt die Konfiguration
wie bisher für alle Monitore. Zur Unterstützung wird die Monitor-Kennung
per Klick auf die Monitor-Zeile im Menü in die Zwischenablage gelegt.

## Nicht-Ziele

- Kein UI zum Bearbeiten der Konfigurationen (weiterhin YAML-Datei).
- Keine Validierung, ob eine referenzierte Monitor-UUID gerade
  angeschlossen ist (UUIDs unbekannter Monitore werden schlicht nie
  gematcht).

## Monitor-Kennung

Als stabile Kennung dient die **Display-UUID**
(`CGDisplayCreateUUIDFromDisplayID` → `CFUUIDCreateString`). Sie ist über
Neustart und Umstecken stabil, im Gegensatz zur `CGDirectDisplayID`
(nur zur Laufzeit gültig).

Im YAML wird die UUID als Match-Wert verwendet. Beim Kopieren wird der
lesbare Monitorname als YAML-Kommentar angehängt, damit die Datei lesbar
bleibt:

```
37D8832A-2D66-02CA-B9F7-8F30A301B230  # DELL U2720Q
```

## Datenmodell (`CropConfiguration`, ScreenFramerCore)

Neues optionales Feld:

```swift
public var displays: [String]?
```

- `nil` → Konfiguration gilt für **alle** Monitore (heutiges Verhalten).
- YAML-Schlüssel: `displays` (Liste von UUID-Strings).
- Dekodierung über die vorhandene `Decodable`-Init:
  - Schlüssel abwesend → `nil`.
  - Leere Liste (`displays: []`) → `nil`.
  - Whitespace-only Einträge werden verworfen; bleibt danach nichts
    übrig → `nil`.

Neue reine Hilfsmethode (in `ScreenFramerCore`, ohne AppKit, damit
unit-testbar):

```swift
func matches(displayUUID: String?) -> Bool
// displays == nil                          → true  (alle Monitore)
// displays != nil && displayUUID == nil    → false
// sonst                                    → displays.contains(displayUUID)
```

## Menü-Verhalten (`StatusBarController`)

### Filterung

In `menuNeedsUpdate` wird die UUID des angeklickten Monitors ermittelt
und `configurations` auf `configuration.matches(displayUUID:)` gefiltert.
Nur passende Konfigurationen erhalten Menü-Zeilen.

- Sind Konfigurationen vorhanden, aber keine für diesen Monitor passend,
  erscheint „Keine Konfiguration für diesen Monitor" statt des
  generischen Leer-Textes.

### Klick auf die Monitor-Zeile

Die erste Zeile „Monitor: <name>" wird klickbar (`target`/`action`).
Ein Klick schreibt `"<uuid>  # <name>"` in die `NSPasteboard`.
Tooltip: „Monitor-Kennung in die Zwischenablage kopieren". Das Schließen
des Menüs dient als Bestätigung; kein zusätzliches Popup.

Kann für den angeklickten Monitor keine UUID ermittelt werden, bleibt die
Zeile wie bisher nicht-klickbar.

## Monitor-Kennung im Code

Neue Hilfe zur Umrechnung `CGDirectDisplayID` → UUID-String, angesiedelt
bei der bestehenden `NSScreen`-Extension in `StatusBarController.swift`:

```swift
extension NSScreen {
    var displayUUID: String? { /* CGDisplayCreateUUIDFromDisplayID ... */ }
}
```

## Seed-Config & README

- Seed-Content (`ConfigStore`) um ein kommentiertes `displays:`-Beispiel
  ergänzen, mit Hinweis, dass man die ID per Klick auf die Monitor-Zeile
  erhält.
- README um die `displays:`-Option erweitern.

## Tests

`Tests/ScreenFramerCoreTests/CropConfigurationTests.swift`:

- Dekodieren von `displays`: vorhanden (Liste), abwesend (→ nil),
  leere Liste (→ nil), Whitespace-Einträge (→ verworfen).
- `matches(displayUUID:)` in allen Fällen:
  - `displays == nil` → immer true.
  - passende UUID → true.
  - nicht passende UUID → false.
  - `displayUUID == nil` bei gesetzter `displays`-Liste → false.
- Parser: `displays` bleibt über `ConfigurationParser.parse` erhalten.
