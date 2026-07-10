# Screen Framer

Menüleisten-App für macOS: spiegelt einen frei konfigurierbaren Ausschnitt
eines (Ultrawide-)Monitors live auf einen virtuellen Bildschirm „Screen
Framer", der sich in Microsoft Teams (oder jeder anderen App) als Bildschirm
teilen lässt. So teilst du auf einem 21:9- oder 32:9-Monitor nur einen
sinnvollen Teilbereich statt der ganzen überbreiten Fläche.

Der Ausschnitt wird über ein Raster (Grid) beschrieben und ist per
YAML-Datei anpassbar — siehe [Konfiguration](#konfiguration).

## Installation

1. Unter [Releases](https://github.com/Ownii/screen-framer/releases) die
   aktuelle `Screen-Framer.app.zip` herunterladen und entpacken.
2. `Screen Framer.app` nach `/Programme` verschieben.
3. Die App ist nicht über den App Store notarisiert. macOS blockiert sie
   deshalb beim ersten Start. Einmalig im Terminal die Quarantäne entfernen:

   ```bash
   xattr -dr com.apple.quarantine "/Applications/Screen Framer.app"
   ```

   Danach die App normal per Doppelklick starten.
4. Beim ersten Start fragt macOS nach der Berechtigung **Bildschirmaufnahme**
   (Systemeinstellungen → Datenschutz & Sicherheit → Bildschirmaufnahme).
   Nach dem Erteilen die App neu starten.

Voraussetzung: macOS 14 (Sonoma) oder neuer.

## Benutzung

1. Menüleisten-Icon **auf dem Monitor anklicken, der übertragen werden soll**
   (der erkannte Monitor steht oben im Menü).
2. Eine **Konfiguration** anklicken — die Übertragung startet sofort: Es
   erscheint ein virtueller Bildschirm „Screen Framer" mit dem Ausschnitt,
   und auf dem Quellmonitor umrahmt ein grüner Rahmen den übertragenen
   Bereich. Ein weiterer Klick schaltet die Konfiguration live um; ein Klick
   auf einem anderen Monitor wechselt die Übertragung dorthin.
3. In Teams **Bildschirm teilen** → „Screen Framer".

**Übertragung stoppen** im Menü beendet die Übertragung und entfernt den
virtuellen Bildschirm.

**Beim Anmelden starten** im Menü schaltet den Autostart an bzw. aus — die
App startet dann automatisch nach jeder Anmeldung.

## Konfiguration

Beim ersten Start wird die Datei `~/.config/screen-framer/config.yaml` mit
drei Beispiel-Konfigurationen (Links / Mitte / Rechts) angelegt. Über das
Menü lässt sie sich direkt bearbeiten:

- **Konfigurationsdatei öffnen** — öffnet die Datei im Standard-Editor.
- **Konfiguration neu laden** — liest die Datei neu ein und wendet sie an.
  Läuft gerade eine Übertragung, übernimmt sie die geänderte Geometrie (bzw.
  stoppt, wenn die aktive Konfiguration gelöscht wurde). Ist die Datei
  fehlerhaft, bleibt die zuletzt gültige Konfiguration aktiv und eine
  Meldung nennt das Problem.

### Aufbau

Jede Konfiguration teilt den Monitor in ein Raster (`grid`) und beschreibt
den Ausschnitt über die linke obere Zelle (`position`) und die Ausdehnung in
Zellen (`span`). Alle Angaben sind **0-basiert**.

```yaml
configurations:
  - name: Links          # Linke Hälfte, volle Höhe
    grid:
      columns: 2
    position:
      column: 0
    span:
      columns: 1

  - name: Mitte          # Mittlere Hälfte (Viertel 2 + 3), volle Höhe
    grid:
      columns: 4
    position:
      column: 1
    span:
      columns: 2

  - name: Oben rechts    # Rechtes oberes Viertel
    grid:
      columns: 2
      rows: 2
    position:
      column: 1
      row: 0
    span:
      columns: 1
      rows: 1
```

### Standardwerte

| Feld | fehlt → |
|---|---|
| `grid.columns`, `grid.rows` | `1` |
| `position.column`, `position.row` | `0` |
| `span.columns` | bis zum rechten Rand (`grid.columns − position.column`) |
| `span.rows` | bis zum unteren Rand (`grid.rows − position.row`) |

Gibst du also nur `grid.columns` an, nutzt der Ausschnitt automatisch die
volle Höhe; lässt du `span` weg, reicht er von der Position bis zum
Rasterrand.

## Aus dem Quellcode bauen

```bash
make build        # baut build/Screen Framer.app
make run          # baut und startet
make restart      # stoppt laufende Instanz, baut neu, startet
make test         # Unit-Tests
```

Das Build-Skript signiert mit dem Apple-Development-Zertifikat aus dem
Schlüsselbund, damit die Bildschirmaufnahme-Berechtigung Rebuilds übersteht.
Ohne Zertifikat wird ad-hoc signiert (dann muss die Berechtigung nach jedem
Rebuild neu erteilt werden). Eine andere Identität lässt sich über
`SCREEN_FRAMER_SIGN_IDENTITY` erzwingen.

## Hinweise

Die Übertragung nutzt die private `CGVirtualDisplay`-API. Ein macOS-Update
kann sie brechen — die App meldet das dann per Fehlerdialog. Die App ist
nicht notarisiert und wird als Open-Source-Projekt „wie besehen" ohne
Gewähr bereitgestellt.
