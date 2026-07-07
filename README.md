# Screen Framer

Menüleisten-App für macOS: spiegelt einen 16:9-Ausschnitt eines
(Ultrawide-)Monitors live auf einen virtuellen Bildschirm „Screen Framer",
der sich in Microsoft Teams als Bildschirm teilen lässt.

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
   (danach App neu starten). Das Build-Skript signiert mit dem Apple-
   Development-Zertifikat aus dem Schlüsselbund, damit die Berechtigung
   Rebuilds übersteht (Fallback: Ad-hoc — dann nach jedem Rebuild neu erteilen)
4. In Teams **Bildschirm teilen** → „Screen Framer"

**Übertragung stoppen** im Menü beendet die Übertragung und entfernt den
virtuellen Bildschirm. Hinweis: Die Übertragung nutzt die private
`CGVirtualDisplay`-API; ein macOS-Update kann sie brechen (die App meldet
das dann per Fehlerdialog).
