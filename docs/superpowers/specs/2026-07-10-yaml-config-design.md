# Design: YAML-Konfigurationen für Grid-basierte Ausschnitte

Datum: 2026-07-10
Status: genehmigt

## Ziel

Die drei fest einprogrammierten Ausschnitt-Konfigurationen (Links/Mitte/Rechts,
16:9) werden durch benutzerdefinierbare Konfigurationen aus einer YAML-Datei
ersetzt. Eine Konfiguration teilt den Monitor in ein Grid und beschreibt den
Ausschnitt über Position (Zelle oben links) und Span (Ausdehnung in Zellen).
Zwei neue Menüeinträge öffnen die Config-Datei im Standard-Editor bzw. laden
sie neu und wenden sie an.

## Entscheidungen

- **Eine Quelle der Wahrheit:** Alle Konfigurationen kommen aus der Datei.
  Beim ersten Start wird die Datei mit drei Seed-Konfigurationen angelegt, die
  die bisherigen Positionen approximieren (siehe Seeds). Das exakte
  16:9-Verhalten entfällt; `CropPosition` wird ersatzlos ersetzt.
- **Speicherort:** `~/.config/screen-framer/config.yaml`
- **Indizierung:** 0-basiert (`column: 0` ist die linke Spalte).
- **Span-Default:** fehlender Span reicht von der Position bis zum Grid-Ende.
- **YAML-Parser:** Yams als SPM-Dependency von `ScreenFramerCore` (erste
  externe Abhängigkeit des Projekts), damit Parsing inkl. Default-Logik
  unit-testbar ist.

## YAML-Schema

```yaml
# Screen Framer Konfigurationen
#
# grid:     Raster, in das der Monitor geteilt wird (columns/rows, Default je 1)
# position: Zelle oben links des Ausschnitts, 0-basiert (Default 0/0)
# span:     Ausdehnung in Zellen (Default: bis zum Grid-Ende)
configurations:
  - name: Links
    grid:
      columns: 2
    position:
      column: 0
    span:
      columns: 1

  - name: Mitte
    grid:
      columns: 4
    position:
      column: 1
    span:
      columns: 2

  - name: Rechts
    grid:
      columns: 2
    position:
      column: 1
```

### Default-Regeln

| Feld | fehlt → |
|---|---|
| `grid.columns`, `grid.rows` | `1` |
| `position.column`, `position.row` | `0` |
| `span.columns` | `grid.columns - position.column` (bis zum Grid-Ende) |
| `span.rows` | `grid.rows - position.row` (bis zum Grid-Ende) |

Fehlende Objekte (`grid`, `position`, `span`) verhalten sich wie Objekte, in
denen alle Felder fehlen.

### Validierung (pro Eintrag)

- `name` nicht leer und über alle Einträge eindeutig
- `grid.columns` ≥ 1, `grid.rows` ≥ 1
- `0 ≤ position.column < grid.columns`, `0 ≤ position.row < grid.rows`
- `span.columns` ≥ 1, `span.rows` ≥ 1
- `position.column + span.columns ≤ grid.columns`,
  `position.row + span.rows ≤ grid.rows`

Verstößt ein Eintrag, ist die gesamte Datei ungültig (Fehlermeldung nennt den
Eintrag und das Problem).

### Seeds (Erstanlage)

- **Links:** 2 Spalten, Position 0, Span 1 → linke Hälfte, volle Höhe
- **Mitte:** 4 Spalten, Position 1, Span 2 → mittlere Hälfte, volle Höhe
- **Rechts:** 2 Spalten, Position 1 → rechte Hälfte (Span-Default), volle Höhe

## Architektur

### ScreenFramerCore

- **`CropConfiguration`** (neu): `name`, Grid-, Positions- und Span-Werte.
  `Decodable` mit der Default-Logik; Validierung mit sprechenden Fehlern.
  Eine Funktion parst den kompletten Dateiinhalt (`configurations:`-Liste)
  via Yams.
- **`CropCalculator`**: neue Funktion `cropRect(displaySize:configuration:)`.
  Zellgrenzen als gerundete Display-Bruchteile:
  `boundary(i) = round(size * i / count)`; der Ausschnitt reicht von
  `boundary(position)` bis `boundary(position + span)` (je Achse). Dadurch
  stoßen benachbarte Ausschnitte lückenlos und überlappungsfrei aneinander.
  Das Ergebnis ist wie bisher display-lokal mit Ursprung oben links.
  `CropPosition` und die alte `cropRect(displaySize:position:)` entfallen.

### ScreenFramer (App-Target)

- **`ConfigStore`** (neu): kennt den Pfad
  `~/.config/screen-framer/config.yaml`, legt beim ersten Start Ordner und
  Datei mit den kommentierten Seeds an, liest die Datei und liefert entweder
  die validierte Liste oder einen Fehler. Hält die zuletzt gültige Liste.
- **`StatusBarController`**: hält statt `position: CropPosition` die aktive
  `CropConfiguration` (Identifikation über den Namen). Menüaufbau und
  Reload-Verhalten siehe unten. `CaptureEngine` und Overlay erhalten die
  Konfiguration statt der Position.

## Menü

Aufbau (weiterhin bei jedem Öffnen dynamisch):

1. Monitor-Info (unverändert)
2. Ein Eintrag pro Konfiguration, Reihenfolge wie in der Datei, Häkchen an
   der aktiven, Klick startet/wechselt die Übertragung (Verhalten wie bisher
   bei Links/Mitte/Rechts)
3. „Übertragung stoppen" (nur wenn laufend, unverändert)
4. **„Konfigurationsdatei öffnen"** → `NSWorkspace.shared.open(fileURL)`
   (Standard-Editor, identisch zum Finder-Doppelklick)
5. **„Konfiguration neu laden"** → Datei neu einlesen und anwenden
6. „Beenden" (unverändert)

## Reload-Verhalten

Beim Neuladen (Menüpunkt) wird die Datei gelesen und validiert:

- **Datei gültig:** Liste ersetzt die bisherige.
  - Läuft eine Übertragung und existiert die aktive Konfiguration
    (per Name) mit **unveränderter Geometrie** → Übertragung läuft weiter.
  - Existiert sie mit **geänderter Geometrie** → Übertragung startet mit der
    neuen Geometrie neu (die Auflösung des virtuellen Displays kann sich
    ändern).
  - Existiert der Name **nicht mehr** → Übertragung stoppt.
- **Datei ungültig:** Alert mit konkreter Fehlermeldung; die zuletzt gültige
  Liste bleibt aktiv, eine laufende Übertragung läuft unverändert weiter.

## Fehlerbehandlung

- Parse-/Validierungsfehler beim Reload: Alert, letzte gültige Liste bleibt.
- Fehler beim App-Start (Datei vorhanden, aber kaputt): Alert; das Menü zeigt
  keine Konfigurationseinträge, aber weiterhin „Konfigurationsdatei öffnen"
  und „Konfiguration neu laden", damit man die Datei reparieren kann.
- Datei/Ordner beim Start nicht vorhanden: wird mit den Seeds angelegt.

## Tests

Unit-Tests in `ScreenFramerCoreTests`:

- Parsing: vollständiger Eintrag; jede Default-Regel einzeln (fehlende
  Felder und fehlende Objekte); leere Liste
- Validierung: Span über den Rand, Position außerhalb des Grids, Werte < 1,
  doppelte Namen, leerer Name — je mit erwartetem Fehler
- Geometrie: Zellgrenzen-Rundung (ungerade Displaybreiten →
  Lückenlosigkeit benachbarter Ausschnitte), volle Höhe bei `rows`-Defaults,
  die drei Seed-Geometrien auf einer Beispiel-Displaygröße
