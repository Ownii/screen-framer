# Screen Framer — Design

## Problem

Auf einem 32:9-Super-Ultrawide-Monitor ist das Teilen des gesamten Bildschirms in
Microsoft Teams unbrauchbar: Das Seitenverhältnis macht den Inhalt für die
Teilnehmenden unlesbar klein. Bisher bleibt nur das Teilen einzelner Fenster.

## Lösung

Eine macOS-Menüleisten-App (kein Dock-Icon), die einen 16:9-Ausschnitt eines
Monitors live auf einen **virtuellen Bildschirm** spiegelt. Der virtuelle
Bildschirm heißt „Screen Framer", existiert nur während der Übertragung und
wird in Teams als **Bildschirm** geteilt (nicht als Fenster).

## Bedienung (Menüleisten-Icon)

- **Monitor: automatische Erkennung.** Übertragen wird der Bildschirm, auf
  dessen Menüleiste das Icon angeklickt wurde (`statusItem.button?.window?.screen`
  beim Menü-Öffnen; Fallback `NSScreen.main`). Ein deaktivierter Info-Eintrag
  im Menü zeigt den erkannten Monitor an. Voraussetzung für die Menüleiste auf
  allen Monitoren ist die macOS-Einstellung „Monitore verwenden verschiedene
  Spaces" (Standard).
- **Links / Mitte / Rechts startet direkt:** Ein Klick auf eine Position
  startet die Übertragung für diese Position sofort. Läuft die Übertragung
  bereits auf demselben Monitor, wird nur die Position live umgeschaltet
  (ohne Unterbrechung); wurde das Menü auf einem anderen Monitor geöffnet,
  wechselt die Übertragung dorthin (Neustart des Streams).
- **Selbst-Capture-Schutz:** Wird das Menü auf dem virtuellen Bildschirm
  selbst geöffnet (auch der hat eine Menüleiste), sind die Positionen
  deaktiviert — der virtuelle Bildschirm ist nie Capture-Quelle.
- **Rahmen um den Ausschnitt:** Solange die Übertragung läuft, markiert ein
  grüner Rahmen (4 pt, `systemGreen`) auf dem Quellmonitor den übertragenen
  16:9-Bereich; er wandert beim Positionswechsel mit und verschwindet bei
  Stopp. Nur lokal sichtbar — die eigenen Fenster der App sind vom Capture
  ausgeschlossen, Teilnehmende sehen ihn nicht.
- **Übertragung stoppen** (nur sichtbar, während die Übertragung läuft).
  Gestoppt wird ausschließlich über das Menü oder durch Stream-Fehler; ein
  schließbares Fenster gibt es nicht mehr.
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
- **Virtueller Bildschirm:** `CGVirtualDisplay` (private CoreGraphics-API,
  bewährt durch DeskPad/BetterDisplay; nur fehlende Header-Deklarationen,
  kein Laufzeit-Hack). Name „Screen Framer", Auflösung = Pixelgröße des
  Ausschnitts (cropRect × backingScaleFactor der Quelle), 60 Hz, ohne HiDPI.
  Wird bei Übertragungsstart erzeugt und bei Stopp zerstört. Nach der
  Erzeugung wird auf die `NSScreen`-Registrierung gewartet
  (Polling, max. 2 s).
- **Rendering:** randloses Vollbild-Fenster auf dem virtuellen Bildschirm,
  Frames über `AVSampleBufferDisplayLayer` (latenzarm, GPU-basiert).
- **Rahmen-Overlay:** randloses, transparentes, klick-durchlässiges Fenster
  (`ignoresMouseEvents = true`) auf dem Quellmonitor, nur Rand gezeichnet
  (CALayer-Border), kein Schatten, Level über der Menüleiste,
  `canJoinAllSpaces` + `stationary`. Koordinaten-Umrechnung (display-lokales
  Top-Left-Rechteck → globales Cocoa-Bottom-Left-Frame) als reine,
  unit-getestete Funktion `CropCalculator.cocoaFrame(for:in:)` in
  `ScreenFramerCore`.
- **Packaging:** Swift Package (SPM) + Build-Skript, das ein echtes
  `Screen Framer.app`-Bundle mit Info.plist und stabiler Bundle-ID erzeugt —
  nötig, damit macOS die Bildschirmaufnahme-Berechtigung (TCC) der App
  dauerhaft zuordnet.

## Komponenten

- **StatusBarController** — Menüleisten-Icon und Menü; hält den App-Zustand
  (erkannter Klick-Monitor, aktiver Monitor, Position, läuft/läuft nicht) und
  verdrahtet die Aktionen.
- **CaptureEngine** — kapselt ScreenCaptureKit vollständig: Stream-Aufbau,
  Frame-Lieferung als `CMSampleBuffer`, Live-Update des `sourceRect`, sauberes
  Stoppen, Fehler-Callbacks.
- **CGVirtualDisplayShim** — Objective-C-Target, das nur die Header-
  Deklarationen der vier privaten Klassen (`CGVirtualDisplay`, `-Descriptor`,
  `-Settings`, `-Mode`) bereitstellt.
- **VirtualDisplayController** — erzeugt/zerstört den virtuellen Bildschirm,
  wartet auf den zugehörigen `NSScreen`, meldet Fehler als `LocalizedError`.
- **MirrorWindow** — randloses Vollbild-Fenster auf dem virtuellen Bildschirm
  inkl. Display-Layer; nimmt `CMSampleBuffer` entgegen und zeigt sie an.
- **CropFrameOverlayController** — der grüne Rahmen auf dem Quellmonitor;
  wird bei Start gezeigt, bei Positionswechsel verschoben, bei Stopp
  entfernt.
- **CropCalculator** — reine Funktion: (Monitorgröße, Position) → Ausschnitts-
  Rechteck. Unit-getestet.

## Fehlerbehandlung

- Fehlende Bildschirmaufnahme-Berechtigung → Hinweis-Dialog mit Direktlink in
  die Systemeinstellungen (Datenschutz & Sicherheit → Bildschirmaufnahme).
- Gewählter Monitor wird getrennt / Stream-Fehler → Übertragung stoppt sauber
  (inkl. Zerstörung des virtuellen Bildschirms), Hinweis an Nutzer*in.
- Erzeugung des virtuellen Bildschirms schlägt fehl (z. B. private API nach
  macOS-Update gebrochen) → Fehlerdialog, sauberes Teardown, kein Absturz.

## Bekannte Eigenheiten (akzeptiert)

- `CGVirtualDisplay` ist eine private API und kann mit einem macOS-Update
  brechen; der frühere Fenster-Modus ist über die Git-Historie
  reaktivierbar.
- Start/Stopp löst eine kurze Display-Neukonfiguration aus (Fenster anderer
  Apps können kurz zucken).
- Der Mauszeiger kann auf den virtuellen Bildschirm wandern — in v1 bewusst
  nicht mitigiert.
- Ein Monitorwechsel während laufender Übertragung erzeugt den virtuellen
  Bildschirm neu — eine laufende Teams-Freigabe endet dadurch und muss neu
  gestartet werden.

## Tests

- `CropCalculator` mit Unit-Tests (32:9, 21:9, 16:9, schmaler als 16:9; alle
  drei Positionen; Koordinaten-Umrechnung `cocoaFrame(for:in:)` inkl.
  Monitor-Offset und y-Spiegelung).
- Capture und UI: manuelle Verifikation durch Starten der App.

## Bewusst außen vor (YAGNI)

- Frei wählbarer Ausschnitt per Maus-Aufziehen
- Andere Zielseitenverhältnisse als 16:9
- Audio-Übertragung
- Auto-Start beim Login
