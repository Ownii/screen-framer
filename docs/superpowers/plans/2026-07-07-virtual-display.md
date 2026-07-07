# Virtueller Bildschirm Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Screen Framer überträgt den 16:9-Ausschnitt nicht mehr in ein teilbares Fenster, sondern auf einen virtuellen Bildschirm „Screen Framer", der in Teams als Bildschirm geteilt wird.

**Architecture:** Ein neues Objective-C-Target kapselt die private `CGVirtualDisplay`-API vollständig hinter einer einzigen Klasse `SFVirtualDisplay` (Zugriff nur via `NSClassFromString` — kein Link-Time-Symbol, nil bei fehlender API). `VirtualDisplayController` (Swift) erzeugt/zerstört den virtuellen Bildschirm pro Übertragung und wartet auf die `NSScreen`-Registrierung. `MirrorWindowController` wird zum randlosen Vollbild-Fenster auf diesem Screen umgebaut; `StatusBarController` orchestriert den dreistufigen Start (virtueller Bildschirm → Vollbild-Fenster → CaptureEngine) und das Teardown in umgekehrter Reihenfolge. `CropCalculator` und `CaptureEngine` bleiben unverändert.

**Tech Stack:** Swift 5 / AppKit / ScreenCaptureKit (bestehend), neu: Objective-C-SPM-Target mit privater CoreGraphics-API (`CGVirtualDisplay`).

## Global Constraints

- Plattform: macOS 14+ (`platforms: [.macOS(.v14)]`), swift-tools-version 5.10
- Name des virtuellen Bildschirms exakt: `Screen Framer`
- Auflösung des virtuellen Bildschirms = Pixelgröße des Ausschnitts (cropRect × backingScaleFactor der Quelle), 60 Hz, ohne HiDPI (`hiDPI = 0`)
- Lebensdauer: nur während der Übertragung (Erzeugen bei Start, Zerstören bei Stopp)
- Der virtuelle Bildschirm ist nie Capture-Quelle (Menü-Klick auf ihm → Positionen deaktiviert)
- Kein schließbares Fenster mehr: Stopp nur über Menü oder Stream-Fehler
- Bestehende Menü-Texte unverändert: „Links", „Mitte", „Rechts", „Übertragung stoppen", „Beenden"
- Alle Befehle laufen im Repo-Root `/Library/Repos/Privat/screen-framer`, Branch `feature/screen-framer`
- Die bestehenden 6 CropCalculator-Tests müssen in jedem Task grün bleiben (`swift test`)

---

### Task 1: CGVirtualDisplayShim (Objective-C-Target für die private API)

**Files:**
- Modify: `Package.swift`
- Create: `Sources/CGVirtualDisplayShim/include/CGVirtualDisplayShim.h`
- Create: `Sources/CGVirtualDisplayShim/SFVirtualDisplay.m`

**Interfaces:**
- Produces (für Task 2): ObjC-Klasse `SFVirtualDisplay` — `init?(name: String, pixelWidth: UInt, pixelHeight: UInt)` (nil, wenn die private API fehlt oder die Erzeugung scheitert), `var displayID: CGDirectDisplayID { get }`. Solange die Instanz lebt, existiert der virtuelle Bildschirm; Freigabe entfernt ihn.

- [ ] **Step 1: Package.swift erweitern**

Kompletter neuer Inhalt von `Package.swift`:

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ScreenFramer",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ScreenFramerCore"),
        .target(name: "CGVirtualDisplayShim"),
        .executableTarget(
            name: "ScreenFramer",
            dependencies: ["ScreenFramerCore", "CGVirtualDisplayShim"]
        ),
        .testTarget(
            name: "ScreenFramerCoreTests",
            dependencies: ["ScreenFramerCore"]
        ),
    ]
)
```

- [ ] **Step 2: Public Header schreiben**

`Sources/CGVirtualDisplayShim/include/CGVirtualDisplayShim.h`:

```objc
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// Kapselt die private CGVirtualDisplay-API vollständig.
/// Solange die Instanz lebt, existiert der virtuelle Bildschirm;
/// die Freigabe der Instanz entfernt ihn wieder.
/// init gibt nil zurück, wenn die private API nicht (mehr) verfügbar ist
/// oder die Erzeugung fehlschlägt.
@interface SFVirtualDisplay : NSObject

@property (readonly, nonatomic) CGDirectDisplayID displayID;

- (nullable instancetype)initWithName:(NSString *)name
                           pixelWidth:(NSUInteger)pixelWidth
                          pixelHeight:(NSUInteger)pixelHeight;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
```

- [ ] **Step 3: Implementierung schreiben**

`Sources/CGVirtualDisplayShim/SFVirtualDisplay.m`:

```objc
#import "CGVirtualDisplayShim.h"

// Private CoreGraphics-Klassen. Bewusst mit SF-Präfix deklariert und nur
// über NSClassFromString aufgelöst: kein Link-Time-Symbol nötig, und bei
// einer API-Änderung durch ein macOS-Update schlägt init kontrolliert
// mit nil fehl statt zur Link-/Ladezeit zu brechen.

@interface SFCGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(NSUInteger)width
                       height:(NSUInteger)height
                  refreshRate:(double)refreshRate;
@end

@interface SFCGVirtualDisplaySettings : NSObject
@property (nonatomic, strong) NSArray *modes;
@property (nonatomic) unsigned int hiDPI;
@end

@interface SFCGVirtualDisplayDescriptor : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic) unsigned int maxPixelsWide;
@property (nonatomic) unsigned int maxPixelsHigh;
@property (nonatomic) CGSize sizeInMillimeters;
@property (nonatomic) unsigned int productID;
@property (nonatomic) unsigned int vendorID;
@property (nonatomic) unsigned int serialNum;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@interface SFCGVirtualDisplay : NSObject
@property (readonly, nonatomic) uint32_t displayID;
- (instancetype)initWithDescriptor:(id)descriptor;
- (BOOL)applySettings:(id)settings;
@end

@implementation SFVirtualDisplay {
    SFCGVirtualDisplay *_display;
}

- (nullable instancetype)initWithName:(NSString *)name
                           pixelWidth:(NSUInteger)pixelWidth
                          pixelHeight:(NSUInteger)pixelHeight {
    self = [super init];
    if (!self) {
        return nil;
    }

    Class descriptorClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class displayClass = NSClassFromString(@"CGVirtualDisplay");
    Class settingsClass = NSClassFromString(@"CGVirtualDisplaySettings");
    Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
    if (!descriptorClass || !displayClass || !settingsClass || !modeClass) {
        return nil;
    }

    SFCGVirtualDisplayDescriptor *descriptor =
        (SFCGVirtualDisplayDescriptor *)[[descriptorClass alloc] init];
    descriptor.name = name;
    descriptor.maxPixelsWide = (unsigned int)pixelWidth;
    descriptor.maxPixelsHigh = (unsigned int)pixelHeight;
    // Physische Größe nur für die Monitor-Metadaten (~92 dpi)
    descriptor.sizeInMillimeters =
        CGSizeMake(pixelWidth * 25.4 / 92.0, pixelHeight * 25.4 / 92.0);
    descriptor.productID = 0x5346;
    descriptor.vendorID = 0x5346;
    descriptor.serialNum = 1;
    descriptor.queue = dispatch_get_main_queue();

    SFCGVirtualDisplay *display =
        (SFCGVirtualDisplay *)[[displayClass alloc] initWithDescriptor:descriptor];
    if (!display) {
        return nil;
    }

    SFCGVirtualDisplayMode *mode =
        (SFCGVirtualDisplayMode *)[[modeClass alloc] initWithWidth:pixelWidth
                                                            height:pixelHeight
                                                       refreshRate:60.0];
    SFCGVirtualDisplaySettings *settings =
        (SFCGVirtualDisplaySettings *)[[settingsClass alloc] init];
    settings.hiDPI = 0;
    settings.modes = @[ mode ];
    if (![display applySettings:settings]) {
        return nil;
    }

    _display = display;
    _displayID = display.displayID;
    return self;
}

@end
```

- [ ] **Step 4: Build prüfen**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | grep -c "passed"`
Expected: `Build complete!`, Tests weiter grün (grep zählt > 0 passed-Zeilen)

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/CGVirtualDisplayShim
git commit -m "feat: add CGVirtualDisplayShim wrapping the private virtual display API"
```

---

### Task 2: VirtualDisplayController

**Files:**
- Create: `Sources/ScreenFramer/VirtualDisplayController.swift`
- Modify: `docs/superpowers/specs/2026-07-07-screen-framer-design.md` (eine Zeile, siehe Step 2)

**Interfaces:**
- Consumes: `SFVirtualDisplay` aus `CGVirtualDisplayShim` (Task 1)
- Produces (für Task 4):
  - `final class VirtualDisplayController`
  - `var displayID: CGDirectDisplayID?` — ID des aktuell existierenden virtuellen Bildschirms, sonst nil
  - `@MainActor func create(name: String, pixelSize: CGSize) async throws -> NSScreen`
  - `func destroy()`
  - `enum VirtualDisplayError: LocalizedError { case creationFailed, screenNotFound }`

- [ ] **Step 1: VirtualDisplayController implementieren**

`Sources/ScreenFramer/VirtualDisplayController.swift`:

```swift
import AppKit
import CGVirtualDisplayShim

enum VirtualDisplayError: LocalizedError {
    case creationFailed
    case screenNotFound

    var errorDescription: String? {
        switch self {
        case .creationFailed:
            return """
                Der virtuelle Bildschirm konnte nicht erstellt werden. \
                Möglicherweise hat ein macOS-Update die verwendete \
                Schnittstelle geändert.
                """
        case .screenNotFound:
            return "Der virtuelle Bildschirm wurde von macOS nicht registriert."
        }
    }
}

/// Erzeugt und zerstört den virtuellen Bildschirm (Lebensdauer: eine
/// Übertragung) und wartet nach der Erzeugung darauf, dass macOS den
/// zugehörigen NSScreen registriert.
final class VirtualDisplayController {
    private var virtualDisplay: SFVirtualDisplay?

    var displayID: CGDirectDisplayID? {
        virtualDisplay?.displayID
    }

    @MainActor
    func create(name: String, pixelSize: CGSize) async throws -> NSScreen {
        guard let display = SFVirtualDisplay(
            name: name,
            pixelWidth: UInt(pixelSize.width),
            pixelHeight: UInt(pixelSize.height))
        else {
            throw VirtualDisplayError.creationFailed
        }
        virtualDisplay = display

        // Auf die NSScreen-Registrierung warten (Polling, max. 2 s)
        let targetID = display.displayID
        for _ in 0..<40 {
            if let screen = NSScreen.screens.first(where: { $0.displayID == targetID }) {
                return screen
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        destroy()
        throw VirtualDisplayError.screenNotFound
    }

    /// Die Freigabe der SFVirtualDisplay-Instanz entfernt den Bildschirm.
    func destroy() {
        virtualDisplay = nil
    }
}
```

- [ ] **Step 2: Spec-Formulierung angleichen**

In `docs/superpowers/specs/2026-07-07-screen-framer-design.md` die Zeile

```
  Erzeugung wird auf die `NSScreen`-Registrierung gewartet
  (`didChangeScreenParametersNotification` + 2 s Timeout).
```

ersetzen durch:

```
  Erzeugung wird auf die `NSScreen`-Registrierung gewartet
  (Polling, max. 2 s).
```

- [ ] **Step 3: Build prüfen**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!` (Hinweis: `NSScreen.displayID` existiert bereits als Extension in `StatusBarController.swift` und ist im selben Modul sichtbar)

- [ ] **Step 4: Commit**

```bash
git add Sources/ScreenFramer/VirtualDisplayController.swift docs/superpowers/specs/2026-07-07-screen-framer-design.md
git commit -m "feat: add VirtualDisplayController managing the virtual screen lifecycle"
```

---

### Task 3: MirrorWindowController → randloses Vollbild-Fenster

**Files:**
- Modify: `Sources/ScreenFramer/MirrorWindowController.swift` (kompletter Ersatz)

**Interfaces:**
- Produces (für Task 4): `final class MirrorWindowController: NSWindowController` mit `init(screen: NSScreen)` und `func enqueue(_ sampleBuffer: CMSampleBuffer)` (threadsicher). **`onClose` und `init()` entfallen ersatzlos** — das Fenster ist randlos und nicht schließbar.

- [ ] **Step 1: Datei komplett ersetzen**

Kompletter neuer Inhalt von `Sources/ScreenFramer/MirrorWindowController.swift`:

```swift
import AppKit
import AVFoundation

/// Randloses Vollbild-Fenster auf dem virtuellen Bildschirm; rendert
/// CMSampleBuffer via AVSampleBufferDisplayLayer (GPU-basiert, latenzarm).
final class MirrorWindowController: NSWindowController {
    private let displayLayer = AVSampleBufferDisplayLayer()

    init(screen: NSScreen) {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.level = .normal
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        super.init(window: window)

        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor
        let contentView = NSView()
        contentView.layer = displayLayer
        contentView.wantsLayer = true
        window.contentView = contentView
        window.setFrame(screen.frame, display: true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        let renderer = displayLayer.sampleBufferRenderer
        if renderer.status == .failed {
            renderer.flush()
        }
        renderer.enqueue(sampleBuffer)
    }
}
```

- [ ] **Step 2: Build prüfen**

Run: `swift build 2>&1 | tail -5`
Expected: Fehler in `StatusBarController.swift` (nutzt noch `init()` und `onClose`) sind in diesem Zwischenstand NICHT erlaubt — deshalb prüfen: Wenn der Build wegen `StatusBarController.swift` fehlschlägt, ist das erwartet und wird in Task 4 behoben. Um Task 3 dennoch einzeln bauen zu können: NICHT committen, bevor geprüft wurde, dass die Fehler ausschließlich aus `StatusBarController.swift` stammen (Aufrufer, kein Fehler in `MirrorWindowController.swift` selbst).

**Hinweis für die Ausführung:** Task 3 und Task 4 werden zusammen in einem Commit abgeschlossen, wenn der Zwischenzustand nicht baut. Der Implementer von Task 4 committet dann beide Dateien. Alternativ (bevorzugt, falls Task 3 separat committet werden soll): Task 3 und 4 vom selben Implementer in einer Dispatch-Runde umsetzen.

- [ ] **Step 3: Kein separater Commit** — Commit erfolgt zusammen mit Task 4 (siehe Hinweis oben).

---

### Task 4: StatusBarController-Integration + README

**Files:**
- Modify: `Sources/ScreenFramer/StatusBarController.swift` (kompletter Ersatz)
- Modify: `README.md` (Abschnitt „Benutzung")

**Interfaces:**
- Consumes: `VirtualDisplayController` (Task 2: `create(name:pixelSize:) async throws -> NSScreen`, `destroy()`, `displayID`), `MirrorWindowController` (Task 3: `init(screen:)`, `enqueue(_:)`), `CaptureEngine` (unverändert: `onFrame`, `onStopped`, `start(displayID:position:)`, `updatePosition(_:)`, `stop()`), `CropCalculator.cropRect(displaySize:position:)` (unverändert)

- [ ] **Step 1: StatusBarController komplett ersetzen**

Kompletter neuer Inhalt von `Sources/ScreenFramer/StatusBarController.swift`:

```swift
import AppKit
import ScreenFramerCore

/// Menüleisten-Icon und Menü; hält den App-Zustand und verdrahtet
/// VirtualDisplayController, CaptureEngine und MirrorWindowController.
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let captureEngine = CaptureEngine()
    private let virtualDisplayController = VirtualDisplayController()
    private var mirrorWindowController: MirrorWindowController?

    /// Monitor, auf dessen Menüleiste zuletzt geklickt wurde (beim Menü-Öffnen ermittelt)
    private var clickedDisplayID: CGDirectDisplayID?
    /// Monitor, der gerade übertragen wird
    private var activeDisplayID: CGDirectDisplayID?
    private var position: CropPosition = .center
    private var isRunning = false
    private var isStarting = false

    private static let positionTitles: [(CropPosition, String)] = [
        (.left, "Links"), (.center, "Mitte"), (.right, "Rechts"),
    ]

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        statusItem.button?.image = NSImage(
            systemSymbolName: "rectangle.center.inset.filled",
            accessibilityDescription: "Screen Framer")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // Menü bei jedem Öffnen neu aufbauen: Der Zielmonitor ist der Bildschirm,
    // auf dessen Menüleiste geklickt wurde (automatische Erkennung).
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let clickedScreen = statusItem.button?.window?.screen ?? NSScreen.main
        clickedDisplayID = clickedScreen?.displayID
        // Der virtuelle Bildschirm ist nie Capture-Quelle (Endlosschleife)
        let clickedIsVirtual =
            clickedDisplayID != nil
            && clickedDisplayID == virtualDisplayController.displayID

        if let clickedScreen {
            let infoItem = NSMenuItem(
                title: "Monitor: \(clickedScreen.localizedName)", action: nil,
                keyEquivalent: "")
            menu.addItem(infoItem)
            menu.addItem(.separator())
        }

        for (value, title) in Self.positionTitles {
            let item = NSMenuItem(
                title: title, action: #selector(startTransmission(_:)), keyEquivalent: "")
            item.target =
                (clickedDisplayID != nil && !clickedIsVirtual && !isStarting) ? self : nil
            item.representedObject = value.rawValue
            item.state = (isRunning && value == position) ? .on : .off
            menu.addItem(item)
        }

        if isRunning {
            menu.addItem(.separator())
            let stopItem = NSMenuItem(
                title: "Übertragung stoppen", action: #selector(stopCapture),
                keyEquivalent: "")
            stopItem.target = self
            menu.addItem(stopItem)
        }

        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "Beenden", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    // Klick auf Links/Mitte/Rechts: startet die Übertragung für den Monitor,
    // auf dem das Menü geöffnet wurde — bzw. schaltet nur die Position um,
    // wenn genau dieser Monitor bereits übertragen wird.
    @objc private func startTransmission(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let newPosition = CropPosition(rawValue: raw),
              let displayID = clickedDisplayID,
              displayID != virtualDisplayController.displayID,
              !isStarting else { return }

        if isRunning, displayID == activeDisplayID {
            guard newPosition != position else { return }
            position = newPosition
            Task { @MainActor in
                do {
                    try await self.captureEngine.updatePosition(newPosition)
                } catch {
                    self.showError(error)
                }
            }
            return
        }

        position = newPosition
        startCapture(on: displayID)
    }

    private func startCapture(on displayID: CGDirectDisplayID) {
        guard !isStarting else { return }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            showPermissionAlert()
            return
        }
        guard let pixelSize = cropPixelSize(for: displayID) else { return }

        isStarting = true
        Task { @MainActor in
            // Laufende Übertragung (z. B. auf dem anderen Monitor) zuerst beenden
            if self.isRunning {
                await self.teardown()
            }

            do {
                let screen = try await self.virtualDisplayController.create(
                    name: "Screen Framer", pixelSize: pixelSize)
                let windowController = MirrorWindowController(screen: screen)
                self.captureEngine.onFrame = { [weak windowController] buffer in
                    windowController?.enqueue(buffer)
                }
                self.captureEngine.onStopped = { [weak self] error in
                    guard let self else { return }
                    Task { @MainActor in
                        await self.teardown(stopEngine: false)
                        if let error { self.showError(error) }
                    }
                }
                try await self.captureEngine.start(
                    displayID: displayID, position: self.position)
                windowController.window?.orderFrontRegardless()
                self.mirrorWindowController = windowController
                self.activeDisplayID = displayID
                self.isRunning = true
                self.isStarting = false
            } catch {
                self.isStarting = false
                // Räumt einen ggf. schon erzeugten virtuellen Bildschirm ab
                await self.teardown()
                self.showError(error)
            }
        }
    }

    /// Pixelgröße des 16:9-Ausschnitts = Auflösung des virtuellen Bildschirms.
    /// (Unabhängig von der Position — Breite/Höhe sind für alle Anker gleich.)
    private func cropPixelSize(for displayID: CGDirectDisplayID) -> CGSize? {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID })
        else { return nil }
        let crop = CropCalculator.cropRect(
            displaySize: screen.frame.size, position: position)
        let scale = screen.backingScaleFactor
        return CGSize(width: crop.width * scale, height: crop.height * scale)
    }

    @objc private func stopCapture() {
        Task { @MainActor in await self.teardown() }
    }

    @MainActor
    private func teardown(stopEngine: Bool = true) async {
        isRunning = false
        activeDisplayID = nil
        if stopEngine {
            await captureEngine.stop()
        }
        mirrorWindowController?.close()
        mirrorWindowController = nil
        virtualDisplayController.destroy()
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Bildschirmaufnahme nicht erlaubt"
        alert.informativeText = """
            Screen Framer braucht die Berechtigung „Bildschirmaufnahme".
            Bitte in den Systemeinstellungen unter
            Datenschutz & Sicherheit → Bildschirmaufnahme aktivieren
            und die App danach neu starten.
            """
        alert.addButton(withTitle: "Systemeinstellungen öffnen")
        alert.addButton(withTitle: "Abbrechen")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Übertragung beendet"
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return number.map { CGDirectDisplayID($0.uint32Value) }
    }
}
```

- [ ] **Step 2: README-Abschnitt „Benutzung" ersetzen**

In `README.md` den kompletten Abschnitt ab `## Benutzung` (bis Dateiende) ersetzen durch:

```markdown
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
```

- [ ] **Step 3: Build + Tests prüfen**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | grep -E "Executed|failed" | head -3`
Expected: `Build complete!`, `Executed 6 tests, with 0 failures`

- [ ] **Step 4: Commit (inkl. MirrorWindowController aus Task 3)**

```bash
git add Sources/ScreenFramer/MirrorWindowController.swift Sources/ScreenFramer/StatusBarController.swift README.md
git commit -m "feat: transmit onto ephemeral virtual display instead of shareable window"
```

- [ ] **Step 5: App-Bundle neu bauen (Controller/Mensch)**

Run: `pkill -x ScreenFramer; scripts/build-app.sh && open "build/Screen Framer.app"`
Expected: `Fertig: build/Screen Framer.app`, App läuft.

- [ ] **Step 6: Manuelle Verifikation (Mensch)**

- Position klicken → virtueller Bildschirm „Screen Framer" erscheint (Systemeinstellungen → Displays) und zeigt den Live-Ausschnitt
- Teams listet „Screen Framer" unter „Bildschirm teilen"
- Position live umschalten; Monitor wechseln (Icon auf anderem Monitor anklicken)
- Menü auf dem virtuellen Bildschirm öffnen → Positionen ausgegraut
- „Übertragung stoppen" → virtueller Bildschirm verschwindet
- Beenden → virtueller Bildschirm verschwindet (Prozessende)
