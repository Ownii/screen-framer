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

1. Menüleisten-Icon **auf dem Monitor anklicken, der übertragen werden soll**
   (der erkannte Monitor steht oben im Menü)
2. **Links / Mitte / Rechts** anklicken — die Übertragung startet sofort:
   Es erscheint ein virtueller Bildschirm „Screen Framer" mit dem Ausschnitt;
   ein weiterer Klick schaltet die Position live um, ein Klick auf dem anderen
   Monitor wechselt die Übertragung dorthin
3. Beim ersten Mal fragt macOS nach der Berechtigung „Bildschirmaufnahme"
   (danach App neu starten) — nach einem Rebuild muss die Berechtigung
   ggf. erneut aktiviert werden
4. In Teams **Bildschirm teilen** → „Screen Framer"

**Übertragung stoppen** im Menü beendet die Übertragung und entfernt den
virtuellen Bildschirm. Hinweis: Die Übertragung nutzt die private
`CGVirtualDisplay`-API; ein macOS-Update kann sie brechen (die App meldet
das dann per Fehlerdialog).
