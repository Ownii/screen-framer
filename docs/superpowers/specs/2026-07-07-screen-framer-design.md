# Screen Framer — Design

## Problem

Auf einem 32:9-Super-Ultrawide-Monitor ist das Teilen des gesamten Bildschirms in
Microsoft Teams unbrauchbar: Das Seitenverhältnis macht den Inhalt für die
Teilnehmenden unlesbar klein. Bisher bleibt nur das Teilen einzelner Fenster.

## Lösung

Eine macOS-Menüleisten-App (kein Dock-Icon), die einen 16:9-Ausschnitt eines
gewählten Monitors live in einem normalen Fenster spiegelt. Dieses Fenster wird
in Teams als Fenster geteilt.

## Bedienung (Menüleisten-Icon)

- **Monitor:** Liste aller angeschlossenen Displays, manuelle Auswahl (Pflicht).
- **Position:** Links / Mitte / Rechts — live umschaltbar, ohne die Übertragung
  zu unterbrechen.
- **Übertragung starten / stoppen.**
- **Beenden.**

## Ausschnitt-Berechnung

Dynamisch aus der Geometrie des gewählten Monitors, nichts hartcodiert:

- Höhe = volle Monitorhöhe
- Breite = Höhe × 16/9
- Verankerung: links (x = 0), mittig (zentriert), rechts (rechtsbündig)
- Ist der Monitor schmaler als 16:9, wird die volle Breite verwendet
  (Ausschnitt = ganzer Monitor).

Beispiele: 5120×1440 (32:9) → 2560×1440; 2560×1080 (21:9) → 1920×1080.

## Technik

- **Sprache/Framework:** Swift, AppKit. Menüleiste via `NSStatusItem`,
  `LSUIElement = true` (kein Dock-Icon).
- **Capture:** ScreenCaptureKit. `SCStream` mit `SCContentFilter` auf das
  gewählte Display; die eigenen Fenster der App werden vom Capture
  ausgeschlossen (kein Spiegel-im-Spiegel-Effekt). `sourceRect` =
  16:9-Ausschnitt, 30 fps, Cursor sichtbar (`showsCursor = true`).
- **Positionswechsel:** live über `SCStream.updateConfiguration` (neues
  `sourceRect`), Stream läuft weiter.
- **Vorschau-Fenster:** Titel „Screen Framer", normales Fenster mit
  Titelleiste, frei skalierbar, Seitenverhältnis fest 16:9
  (`window.contentAspectRatio`). Rendering über `AVSampleBufferDisplayLayer`
  (latenzarm, GPU-basiert). Fenster schließen stoppt die Übertragung.
- **Packaging:** Swift Package (SPM) + Build-Skript, das ein echtes
  `Screen Framer.app`-Bundle mit Info.plist und stabiler Bundle-ID erzeugt —
  nötig, damit macOS die Bildschirmaufnahme-Berechtigung (TCC) der App
  dauerhaft zuordnet.

## Komponenten

- **StatusBarController** — Menüleisten-Icon und Menü; hält den App-Zustand
  (gewählter Monitor, Position, läuft/läuft nicht) und verdrahtet die Aktionen.
- **CaptureEngine** — kapselt ScreenCaptureKit vollständig: Stream-Aufbau,
  Frame-Lieferung als `CMSampleBuffer`, Live-Update des `sourceRect`, sauberes
  Stoppen, Fehler-Callbacks.
- **MirrorWindow** — das teilbare Fenster inkl. Display-Layer; nimmt
  `CMSampleBuffer` entgegen und zeigt sie an.
- **CropCalculator** — reine Funktion: (Monitorgröße, Position) → Ausschnitts-
  Rechteck. Unit-getestet.

## Fehlerbehandlung

- Fehlende Bildschirmaufnahme-Berechtigung → Hinweis-Dialog mit Direktlink in
  die Systemeinstellungen (Datenschutz & Sicherheit → Bildschirmaufnahme).
- Gewählter Monitor wird getrennt / Stream-Fehler → Übertragung stoppt sauber,
  Hinweis an Nutzer*in.

## Tests

- `CropCalculator` mit Unit-Tests (32:9, 21:9, 16:9, schmaler als 16:9; alle
  drei Positionen).
- Capture und UI: manuelle Verifikation durch Starten der App.

## Bewusst außen vor (YAGNI)

- Frei wählbarer Ausschnitt per Maus-Aufziehen
- Andere Zielseitenverhältnisse als 16:9
- Audio-Übertragung
- Auto-Start beim Login
