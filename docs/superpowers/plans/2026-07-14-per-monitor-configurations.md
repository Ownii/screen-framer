# Per-Monitor-Konfigurationen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eine Ausschnitt-Konfiguration optional auf bestimmte Monitore (per stabiler Display-UUID) beschränken; die Monitor-Kennung per Klick auf die Menü-Zeile in die Zwischenablage legen.

**Architecture:** Neues optionales Feld `displays: [String]?` auf `CropConfiguration` (ScreenFramerCore) mit reiner `matches(displayUUID:)`-Logik (unit-getestet). `StatusBarController` ermittelt die UUID des angeklickten Monitors, filtert die Menü-Zeilen darüber und kopiert die Kennung beim Klick auf die Monitor-Zeile.

**Tech Stack:** Swift, Swift Package Manager, Yams (YAML), AppKit/CoreGraphics, XCTest.

## Global Constraints

- Firmenname (falls in Doku/Copy) immer `BRICKMAKERS` in Großbuchstaben.
- Deutschsprachige UI-Texte und Kommentare wie im Bestand; genderneutrale Sprache in offizieller Kommunikation.
- Kommentardichte und Stil an die umliegenden Dateien anpassen (kurze deutsche Doku-Kommentare).
- Core-Tests: `make test`. App-Kompilierung prüfen: `make build`.
- YAML-Schlüssel bleiben englisch (`name`, `grid`, `position`, `span`, neu: `displays`).
- Fehlendes/leeres `displays` → `nil` (Konfiguration gilt für alle Monitore, heutiges Verhalten).

---

### Task 1: `displays`-Feld und `matches` in `CropConfiguration`

**Files:**
- Modify: `Sources/ScreenFramerCore/CropConfiguration.swift`
- Test: `Tests/ScreenFramerCoreTests/CropConfigurationTests.swift`

**Interfaces:**
- Consumes: nichts (Basis-Task).
- Produces:
  - `CropConfiguration.displays: [String]?` (stored property; normalisiert: getrimmt, leere Einträge verworfen, leere Liste → `nil`).
  - Init-Parameter `displays: [String]? = nil` an der bestehenden memberwise-Init.
  - `func matches(displayUUID: String?) -> Bool`.
  - YAML-Schlüssel `displays` wird von `ConfigurationParser.parse` dekodiert und bleibt erhalten.

- [ ] **Step 1: Fehlende Tests schreiben**

In `Tests/ScreenFramerCoreTests/CropConfigurationTests.swift` vor der schließenden `}` einfügen:

```swift
    // MARK: - displays (Monitor-Bindung)

    func testParsesDisplaysList() throws {
        let configs = try ConfigurationParser.parse(yaml: """
            configurations:
              - name: Nur Ultrawide
                displays:
                  - "UUID-A"
                  - "UUID-B"
            """)
        XCTAssertEqual(configs.first?.displays, ["UUID-A", "UUID-B"])
    }

    func testMissingDisplaysIsNil() throws {
        let configs = try ConfigurationParser.parse(yaml: """
            configurations:
              - name: Überall
            """)
        XCTAssertNil(configs.first?.displays)
    }

    func testEmptyDisplaysListIsNil() throws {
        let configs = try ConfigurationParser.parse(yaml: """
            configurations:
              - name: Überall
                displays: []
            """)
        XCTAssertNil(configs.first?.displays)
    }

    func testWhitespaceDisplaysEntriesAreDropped() throws {
        let configs = try ConfigurationParser.parse(yaml: """
            configurations:
              - name: Gemischt
                displays:
                  - "  "
                  - " UUID-A "
            """)
        XCTAssertEqual(configs.first?.displays, ["UUID-A"])
    }

    func testMatchesWithoutDisplaysAlwaysTrue() {
        let config = CropConfiguration(name: "Überall")
        XCTAssertTrue(config.matches(displayUUID: "UUID-A"))
        XCTAssertTrue(config.matches(displayUUID: nil))
    }

    func testMatchesOnlyListedDisplays() {
        let config = CropConfiguration(name: "Gebunden", displays: ["UUID-A"])
        XCTAssertTrue(config.matches(displayUUID: "UUID-A"))
        XCTAssertFalse(config.matches(displayUUID: "UUID-B"))
        XCTAssertFalse(config.matches(displayUUID: nil))
    }
```

- [ ] **Step 2: Tests laufen lassen, Fehlschlag prüfen**

Run: `make test`
Expected: FAIL — Kompilierfehler, u. a. „extra argument 'displays' in call" und „value of type 'CropConfiguration' has no member 'displays'/'matches'".

- [ ] **Step 3: Feld, Init-Parameter, Normalisierung und `matches` implementieren**

In `Sources/ScreenFramerCore/CropConfiguration.swift` die Stored-Properties um `displays` erweitern (nach `rowSpan`):

```swift
    public var columnSpan: Int
    public var rowSpan: Int
    /// Monitor-Kennungen (Display-UUIDs), auf die diese Konfiguration
    /// beschränkt ist. `nil` → gilt für alle Monitore.
    public var displays: [String]?
```

Die memberwise-Init um den Parameter und die Normalisierung ergänzen:

```swift
    /// `columnSpan`/`rowSpan` = nil → Span reicht bis zum Grid-Ende.
    public init(
        name: String, gridColumns: Int = 1, gridRows: Int = 1,
        column: Int = 0, row: Int = 0,
        columnSpan: Int? = nil, rowSpan: Int? = nil,
        displays: [String]? = nil
    ) {
        self.name = name
        self.gridColumns = gridColumns
        self.gridRows = gridRows
        self.column = column
        self.row = row
        self.columnSpan = columnSpan ?? gridColumns - column
        self.rowSpan = rowSpan ?? gridRows - row
        // Leere Einträge verwerfen; bleibt nichts übrig → nil (alle Monitore).
        let cleaned = displays?
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        self.displays = (cleaned?.isEmpty ?? true) ? nil : cleaned
    }

    /// True, wenn die Konfiguration auf dem Monitor mit dieser Kennung
    /// erscheinen soll. Ohne `displays` gilt sie für alle Monitore.
    public func matches(displayUUID: String?) -> Bool {
        guard let displays else { return true }
        guard let displayUUID else { return false }
        return displays.contains(displayUUID)
    }
```

- [ ] **Step 4: `displays` im Decoder lesen**

In der `extension CropConfiguration: Decodable` den `CodingKeys`-Fall und die Dekodierung ergänzen:

```swift
    private enum CodingKeys: String, CodingKey {
        case name, grid, position, span, displays
    }
```

und in `init(from:)` vor dem `self.init(...)`-Aufruf:

```swift
        let displays = try container.decodeIfPresent([String].self, forKey: .displays)
        self.init(
            name: try container.decode(String.self, forKey: .name),
            gridColumns: grid?.columns ?? 1,
            gridRows: grid?.rows ?? 1,
            column: position?.column ?? 0,
            row: position?.row ?? 0,
            columnSpan: span?.columns,
            rowSpan: span?.rows,
            displays: displays)
```

- [ ] **Step 5: Tests laufen lassen, Erfolg prüfen**

Run: `make test`
Expected: PASS (alle bestehenden + 6 neue Tests grün).

- [ ] **Step 6: Commit**

```bash
git add Sources/ScreenFramerCore/CropConfiguration.swift Tests/ScreenFramerCoreTests/CropConfigurationTests.swift
git commit -m "feat: add optional per-monitor displays field to CropConfiguration"
```

---

### Task 2: Monitor-UUID ermitteln und per Klick kopieren

**Files:**
- Modify: `Sources/ScreenFramer/StatusBarController.swift`

**Interfaces:**
- Consumes: bestehende `NSScreen.displayID`-Extension (unten in der Datei).
- Produces:
  - `NSScreen.displayUUID: String?` (stabile Display-UUID als String).
  - `@objc func copyMonitorIdentifier(_:)` — schreibt `representedObject` in die Zwischenablage.
  - Die Monitor-Info-Zeile ist bei ermittelbarer UUID klickbar und kopiert `"<uuid>  # <name>"`.

- [ ] **Step 1: `displayUUID`-Helfer ergänzen**

In `Sources/ScreenFramer/StatusBarController.swift` die `extension NSScreen` am Dateiende erweitern:

```swift
extension NSScreen {
    var displayID: CGDirectDisplayID? {
        let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return number.map { CGDirectDisplayID($0.uint32Value) }
    }

    /// Stabile Kennung des Monitors (überlebt Neustart/Umstecken), anders
    /// als die nur zur Laufzeit gültige `displayID`.
    var displayUUID: String? {
        guard let displayID,
              let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, cfUUID) as String
    }
}
```

- [ ] **Step 2: Kopier-Action implementieren**

Als neue Methode in `StatusBarController` (z. B. direkt nach `copyMonitorIdentifier` einbaubar, hier unter `openConfigFile`):

```swift
    /// Klick auf die Monitor-Zeile: legt „<uuid>  # <name>" in die
    /// Zwischenablage, damit die Kennung direkt in die YAML kopiert werden
    /// kann (der Name als Kommentar bleibt lesbar).
    @objc private func copyMonitorIdentifier(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
```

- [ ] **Step 3: Monitor-Info-Zeile klickbar machen**

In `menuNeedsUpdate` den Block, der `infoItem` erzeugt, ersetzen. Bisher:

```swift
        if let clickedScreen {
            let infoItem = NSMenuItem(
                title: "Monitor: \(clickedScreen.localizedName)", action: nil,
                keyEquivalent: "")
            menu.addItem(infoItem)
            menu.addItem(.separator())
        }
```

Neu:

```swift
        let clickedUUID = clickedScreen?.displayUUID
        if let clickedScreen {
            let infoItem = NSMenuItem(
                title: "Monitor: \(clickedScreen.localizedName)", action: nil,
                keyEquivalent: "")
            if let clickedUUID {
                infoItem.action = #selector(copyMonitorIdentifier(_:))
                infoItem.target = self
                infoItem.representedObject = "\(clickedUUID)  # \(clickedScreen.localizedName)"
                infoItem.toolTip = "Monitor-Kennung in die Zwischenablage kopieren"
            }
            menu.addItem(infoItem)
            menu.addItem(.separator())
        }
```

Hinweis: `clickedUUID` wird in Task 3 auch für die Filterung genutzt — die Bindung hier an dieser Stelle einführen.

- [ ] **Step 4: App kompilieren**

Run: `make build`
Expected: Build erfolgreich (`build/Screen Framer.app`), keine Compilerfehler/Warnungen zu `displayUUID`/`copyMonitorIdentifier`.

- [ ] **Step 5: Manuell verifizieren**

Run: `make run`
Prüfen: Menü öffnen → oberste Zeile „Monitor: <name>" anklicken → in einem Editor einfügen. Erwartet: `<uuid>  # <name>` (UUID-Form `XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX`, danach zwei Leerzeichen, `#` und der Monitorname).

- [ ] **Step 6: Commit**

```bash
git add Sources/ScreenFramer/StatusBarController.swift
git commit -m "feat: copy stable monitor identifier from the menu's monitor row"
```

---

### Task 3: Menü-Zeilen nach Monitor filtern

**Files:**
- Modify: `Sources/ScreenFramer/StatusBarController.swift`

**Interfaces:**
- Consumes: `CropConfiguration.matches(displayUUID:)` (Task 1), `clickedUUID` (Task 2).
- Produces: Nur zum angeklickten Monitor passende Konfigurationen erhalten Menü-Zeilen; eigener Leer-Text bei „keine passende Konfiguration".

- [ ] **Step 1: Konfigurationen filtern und Leer-Zustände unterscheiden**

In `menuNeedsUpdate`, den Block ab `if configurations.isEmpty { … }` bis einschließlich der Erzeugung von `items`/`views` anpassen. Zunächst direkt nach dem `infoItem`-Block (nach der `.separator()`) die gefilterte Liste bilden:

```swift
        let visibleConfigurations = configurations.filter {
            $0.matches(displayUUID: clickedUUID)
        }
```

Dann den bisherigen Leer-Block

```swift
        if configurations.isEmpty {
            let emptyItem = NSMenuItem(
                title: "Keine gültigen Konfigurationen", action: nil,
                keyEquivalent: "")
            menu.addItem(emptyItem)
        }
```

ersetzen durch:

```swift
        if configurations.isEmpty {
            let emptyItem = NSMenuItem(
                title: "Keine gültigen Konfigurationen", action: nil,
                keyEquivalent: "")
            menu.addItem(emptyItem)
        } else if visibleConfigurations.isEmpty {
            let emptyItem = NSMenuItem(
                title: "Keine Konfiguration für diesen Monitor", action: nil,
                keyEquivalent: "")
            menu.addItem(emptyItem)
        }
```

- [ ] **Step 2: Zeilen aus der gefilterten Liste bauen**

In denselben Block die beiden Vorkommen von `configurations.map { … }` (für `items` und `views`) auf `visibleConfigurations.map { … }` umstellen. Ergebnis:

```swift
        let items = visibleConfigurations.map { configuration -> NSMenuItem in
            let item = NSMenuItem(
                title: configuration.name, action: nil, keyEquivalent: "")
            item.representedObject = configuration.name
            return item
        }
        let views = visibleConfigurations.map { configuration in
            ConfigurationMenuItemView(
                configuration: configuration, displaySize: displaySize,
                isActive: isRunning && configuration.name == activeConfiguration?.name,
                isEnabled: isEnabled, width: 0,
                onSelect: { [weak self] in self?.selectConfiguration(named: configuration.name) })
        }
```

(`selectConfiguration(named:)` bleibt unverändert — es sucht weiter in der vollständigen `configurations`-Liste, und nur sichtbare Zeilen können es auslösen.)

- [ ] **Step 3: App kompilieren**

Run: `make build`
Expected: Build erfolgreich, keine Fehler.

- [ ] **Step 4: Manuell verifizieren**

Run: `make run`
Prüfen (falls mehrere Monitore verfügbar):
1. In `~/.config/screen-framer/config.yaml` eine Konfiguration mit `displays:` und der per Klick kopierten UUID eines bestimmten Monitors versehen, „Konfiguration neu laden".
2. Menü auf diesem Monitor öffnen → Konfiguration erscheint.
3. Menü auf einem anderen Monitor öffnen → Konfiguration erscheint nicht. Sind dort keine anderen Konfigurationen, steht „Keine Konfiguration für diesen Monitor".
Ohne zweiten Monitor: prüfen, dass Konfigurationen ohne `displays` weiterhin erscheinen und eine mit fremder UUID nicht.

- [ ] **Step 5: Commit**

```bash
git add Sources/ScreenFramer/StatusBarController.swift
git commit -m "feat: show only configurations matching the clicked monitor"
```

---

### Task 4: Seed-Config und README dokumentieren

**Files:**
- Modify: `Sources/ScreenFramer/ConfigStore.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes: die `displays`-Semantik (Task 1) und den Kopier-Ablauf (Task 2).
- Produces: keine Code-Schnittstelle; dokumentiert die Funktion.

- [ ] **Step 1: Seed-Kommentar um `displays` erweitern**

In `Sources/ScreenFramer/ConfigStore.swift` den Kommentarkopf von `seedContent` ergänzen. Nach der `span:`-Kommentarzeile und vor `configurations:` einfügen:

```swift
        #   span:     columns/rows – Ausdehnung in Zellen (Default: bis zum Grid-Ende)
        #
        # Optional bindet displays eine Konfiguration an bestimmte Monitore
        # (Liste von Monitor-Kennungen). Fehlt das Feld, gilt sie für alle
        # Monitore. Die Kennung eines Monitors bekommst du per Klick auf die
        # oberste Menü-Zeile („Monitor: …") — sie landet in der Zwischenablage:
        #
        #   - name: Nur Ultrawide
        #     displays:
        #       - "37D8832A-2D66-02CA-B9F7-8F30A301B230"  # DELL U2720Q
        #     grid:
        #       columns: 2
        #     position:
        #       column: 0
        configurations:
```

- [ ] **Step 2: README ergänzen**

In `README.md` unter „## Benutzung" nach dem Absatz zum Icon-Klick den Hinweis zur Kennung ergänzen. Konkret den bestehenden Listenpunkt 1 belassen und nach der nummerierten Liste (vor „**Übertragung stoppen**") einfügen:

```markdown
Ein Klick auf die oberste Menü-Zeile („Monitor: …") kopiert die stabile
Kennung des erkannten Monitors in die Zwischenablage — praktisch, um eine
Konfiguration auf diesen Monitor zu beschränken (siehe unten).
```

Und im Abschnitt „## Konfiguration" nach dem „### Standardwerte"-Block einen neuen Unterabschnitt anfügen:

```markdown
### Monitor-spezifische Konfigurationen

Standardmäßig erscheint jede Konfiguration auf jedem Monitor. Mit dem
optionalen Feld `displays` lässt sich eine Konfiguration auf bestimmte
Monitore beschränken — sie taucht dann nur im Menü auf, wenn du es auf einem
dieser Monitore öffnest.

Als Kennung dient die stabile Monitor-UUID (überlebt Neustart und Umstecken).
Du bekommst sie per Klick auf die oberste Menü-Zeile („Monitor: …"): die
Kennung landet in der Zwischenablage, der Monitorname wird als Kommentar
angehängt, damit die Datei lesbar bleibt.

```yaml
configurations:
  - name: Nur Ultrawide
    displays:
      - "37D8832A-2D66-02CA-B9F7-8F30A301B230"  # DELL U2720Q
    grid:
      columns: 2
    position:
      column: 0
```

Fehlt `displays` oder ist die Liste leer, gilt die Konfiguration wie bisher
für alle Monitore.
```

- [ ] **Step 3: App kompilieren (Seed unverändert gültig)**

Run: `make build`
Expected: Build erfolgreich.

- [ ] **Step 4: Seed manuell prüfen**

Run: bestehende Config wegsichern und neu erzeugen lassen:
```bash
mv ~/.config/screen-framer/config.yaml ~/.config/screen-framer/config.yaml.bak
make run
```
Prüfen: Neu angelegte `~/.config/screen-framer/config.yaml` enthält den `displays`-Kommentarblock; die App startet fehlerfrei und zeigt die drei Beispiel-Konfigurationen. Danach ggf. `config.yaml.bak` zurückspielen.

- [ ] **Step 5: Commit**

```bash
git add Sources/ScreenFramer/ConfigStore.swift README.md
git commit -m "docs: document per-monitor displays option in seed and README"
```

---

## Self-Review

- **Spec coverage:** Datenmodell + `matches` (Task 1) ✓; stabile Kennung (Task 2) ✓; Menü-Filterung inkl. eigener Leer-Text (Task 3) ✓; Klick → Zwischenablage mit Kommentar (Task 2) ✓; Seed & README (Task 4) ✓; Tests für Dekodierung/`matches`/Parser-Erhalt (Task 1) ✓.
- **Placeholder scan:** Keine TBD/TODO; alle Code-Schritte enthalten vollständigen Code.
- **Type consistency:** `displays: [String]?`, `matches(displayUUID:)`, `displayUUID`, `copyMonitorIdentifier(_:)`, `clickedUUID`, `visibleConfigurations` durchgängig identisch verwendet.
