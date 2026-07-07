# Screen Framer

Menüleisten-App für macOS: spiegelt einen 16:9-Ausschnitt eines
(Ultrawide-)Monitors live in ein normales Fenster, das sich in
Microsoft Teams als Fenster teilen lässt.

## Bauen

```bash
scripts/build-app.sh
open "build/Screen Framer.app"
```

## Benutzung

1. Menüleisten-Icon → **Monitor** → Monitor auswählen
2. **Position** → Links / Mitte / Rechts (auch während der Übertragung umschaltbar)
3. **Übertragung starten** — beim ersten Mal fragt macOS nach der
   Berechtigung „Bildschirmaufnahme" (danach App neu starten)
   — nach einem Rebuild muss die Berechtigung ggf. erneut aktiviert werden
4. In Teams **Fenster teilen** → „Screen Framer"

Fenster schließen oder **Übertragung stoppen** beendet die Übertragung.
