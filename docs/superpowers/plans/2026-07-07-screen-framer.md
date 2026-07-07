# Screen Framer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS-Menüleisten-App, die einen 16:9-Ausschnitt eines gewählten Monitors live in einem teilbaren Fenster spiegelt (für Teams-Screensharing auf Ultrawide-Monitoren).

**Architecture:** Swift/AppKit-App ohne Dock-Icon (`.accessory`). ScreenCaptureKit `SCStream` mit `sourceRect`-Crop liefert Frames als `CMSampleBuffer` an ein `AVSampleBufferDisplayLayer` in einem normalen, 16:9-fixierten Fenster. Reine Ausschnitts-Berechnung liegt in einer unit-getesteten Library (`ScreenFramerCore`); die App selbst ist ein Executable-Target.

**Tech Stack:** Swift 5 (Toolchain 6.3, Language-Mode 5 via tools-version 5.10), SPM, AppKit, ScreenCaptureKit, AVFoundation, XCTest.

## Global Constraints

- Plattform: macOS 14+ (`platforms: [.macOS(.v14)]`)
- Kein Dock-Icon: `LSUIElement = true` im Bundle, `NSApp.setActivationPolicy(.accessory)`
- Menü-Texte auf Deutsch: „Monitor", „Position", „Links", „Mitte", „Rechts", „Übertragung starten", „Übertragung stoppen", „Beenden"
- Fenstertitel exakt: `Screen Framer`
- 30 fps, Cursor sichtbar, eigene App vom Capture ausgeschlossen
- Bundle-ID: `de.martinfoerster.screen-framer`
- Alle Befehle laufen im Repo-Root `/Library/Repos/Privat/screen-framer`

---

### Task 1: Projektgerüst + CropCalculator (TDD)

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Sources/ScreenFramerCore/CropCalculator.swift`
- Create: `Sources/ScreenFramer/main.swift` (Platzhalter, damit das Executable-Target baut)
- Test: `Tests/ScreenFramerCoreTests/CropCalculatorTests.swift`

**Interfaces:**
- Produces: `enum CropPosition: String, CaseIterable { case left, center, right }` und `CropCalculator.cropRect(displaySize: CGSize, position: CropPosition) -> CGRect` (beides `public`, Modul `ScreenFramerCore`). Spätere Tasks importieren `ScreenFramerCore`.

- [ ] **Step 1: Projektgerüst anlegen**

`Package.swift`:

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ScreenFramer",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ScreenFramerCore"),
        .executableTarget(
            name: "ScreenFramer",
            dependencies: ["ScreenFramerCore"]
        ),
        .testTarget(
            name: "ScreenFramerCoreTests",
            dependencies: ["ScreenFramerCore"]
        ),
    ]
)
```

`.gitignore`:

```
.build/
build/
.DS_Store
```

`Sources/ScreenFramer/main.swift` (Platzhalter, wird in Task 4 ersetzt):

```swift
print("ScreenFramer placeholder")
```

- [ ] **Step 2: Fehlschlagende Tests schreiben**

`Tests/ScreenFramerCoreTests/CropCalculatorTests.swift`:

```swift
import XCTest
@testable import ScreenFramerCore

final class CropCalculatorTests: XCTestCase {

    // 32:9-Monitor (zuhause): 5120×1440 → Ausschnitt 2560×1440
    func testSuperUltrawideLeft() {
        let rect = CropCalculator.cropRect(
            displaySize: CGSize(width: 5120, height: 1440), position: .left)
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 2560, height: 1440))
    }

    func testSuperUltrawideCenter() {
        let rect = CropCalculator.cropRect(
            displaySize: CGSize(width: 5120, height: 1440), position: .center)
        XCTAssertEqual(rect, CGRect(x: 1280, y: 0, width: 2560, height: 1440))
    }

    func testSuperUltrawideRight() {
        let rect = CropCalculator.cropRect(
            displaySize: CGSize(width: 5120, height: 1440), position: .right)
        XCTAssertEqual(rect, CGRect(x: 2560, y: 0, width: 2560, height: 1440))
    }

    // 21:9-Monitor (Office): 2560×1080 → Ausschnitt 1920×1080
    func testUltrawideCenter() {
        let rect = CropCalculator.cropRect(
            displaySize: CGSize(width: 2560, height: 1080), position: .center)
        XCTAssertEqual(rect, CGRect(x: 320, y: 0, width: 1920, height: 1080))
    }

    // Monitor ist bereits 16:9 → Ausschnitt = ganzer Monitor
    func testExact16to9IsFullDisplay() {
        let rect = CropCalculator.cropRect(
            displaySize: CGSize(width: 1920, height: 1080), position: .center)
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 1920, height: 1080))
    }

    // Monitor schmaler als 16:9 → volle Breite, keine negative x-Position
    func testNarrowerThan16to9UsesFullWidth() {
        let rect = CropCalculator.cropRect(
            displaySize: CGSize(width: 1024, height: 1440), position: .right)
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 1024, height: 1440))
    }
}
```

- [ ] **Step 3: Tests laufen lassen — sie müssen fehlschlagen**

Run: `swift test 2>&1 | tail -5`
Expected: Compile-Fehler „cannot find 'CropCalculator' in scope" (Datei existiert noch nicht — leere Datei anlegen falls der Target-Ordner fehlt: `Sources/ScreenFramerCore/CropCalculator.swift` mit leerem Inhalt reicht nicht; SPM braucht mindestens eine Swift-Datei im Target. Lege dafür die Datei mit nur `import CoreGraphics` an.)

- [ ] **Step 4: Implementierung**

`Sources/ScreenFramerCore/CropCalculator.swift`:

```swift
import CoreGraphics

public enum CropPosition: String, CaseIterable, Sendable {
    case left, center, right
}

public enum CropCalculator {
    /// 16:9-Ausschnitt (in Punkten) für ein Display der gegebenen Größe.
    /// Höhe = volle Displayhöhe; ist das Display schmaler als 16:9,
    /// wird die volle Breite verwendet.
    public static func cropRect(displaySize: CGSize, position: CropPosition) -> CGRect {
        let targetWidth = min(displaySize.width, (displaySize.height * 16.0 / 9.0).rounded())
        let x: CGFloat
        switch position {
        case .left:
            x = 0
        case .center:
            x = ((displaySize.width - targetWidth) / 2).rounded(.down)
        case .right:
            x = displaySize.width - targetWidth
        }
        return CGRect(x: x, y: 0, width: targetWidth, height: displaySize.height)
    }
}
```

- [ ] **Step 5: Tests laufen lassen — sie müssen bestehen**

Run: `swift test 2>&1 | tail -5`
Expected: `Test Suite 'All tests' passed` mit 6 Tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add Package.swift .gitignore Sources Tests
git commit -m "feat: add SPM scaffold and unit-tested CropCalculator"
```

---

### Task 2: CaptureEngine (ScreenCaptureKit-Kapselung)

**Files:**
- Create: `Sources/ScreenFramer/CaptureEngine.swift`
- Modify: `Sources/ScreenFramer/main.swift` (bleibt Platzhalter, keine Änderung nötig)

**Interfaces:**
- Consumes: `CropPosition`, `CropCalculator.cropRect(displaySize:position:)` aus `ScreenFramerCore` (Task 1)
- Produces (für Task 4):
  - `final class CaptureEngine: NSObject`
  - `var onFrame: ((CMSampleBuffer) -> Void)?` — wird auf einer Hintergrund-Queue aufgerufen
  - `var onStopped: ((Error?) -> Void)?` — wird auf dem Main-Thread aufgerufen, wenn der Stream extern stoppt (z. B. Monitor getrennt)
  - `func start(displayID: CGDirectDisplayID, position: CropPosition) async throws`
  - `func updatePosition(_ position: CropPosition) async throws` — live, ohne Stream-Neustart
  - `func stop() async`
  - `enum CaptureError: LocalizedError { case displayNotFound }`

- [ ] **Step 1: CaptureEngine implementieren**

`Sources/ScreenFramer/CaptureEngine.swift`:

```swift
import AppKit
import AVFoundation
import ScreenCaptureKit
import ScreenFramerCore

enum CaptureError: LocalizedError {
    case displayNotFound

    var errorDescription: String? {
        switch self {
        case .displayNotFound:
            return "Der gewählte Monitor wurde nicht gefunden. Ist er noch angeschlossen?"
        }
    }
}

/// Kapselt ScreenCaptureKit: baut den Stream mit 16:9-sourceRect auf,
/// liefert Frames über `onFrame` und meldet externe Stopps über `onStopped`.
final class CaptureEngine: NSObject {
    var onFrame: ((CMSampleBuffer) -> Void)?
    var onStopped: ((Error?) -> Void)?

    private var stream: SCStream?
    private var configuration: SCStreamConfiguration?
    private var displaySize: CGSize = .zero
    private var scaleFactor: CGFloat = 1
    private let sampleQueue = DispatchQueue(label: "de.martinfoerster.screen-framer.capture")

    func start(displayID: CGDirectDisplayID, position: CropPosition) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }

        // Eigene App ausschließen → kein Spiegel-im-Spiegel-Effekt
        let ownBundleID = Bundle.main.bundleIdentifier
        let excludedApps = content.applications.filter {
            $0.bundleIdentifier == ownBundleID && ownBundleID != nil
        }
        let filter = SCContentFilter(
            display: display, excludingApplications: excludedApps, exceptingWindows: [])

        scaleFactor = NSScreen.screens.first { screen in
            let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return number?.uint32Value == displayID
        }?.backingScaleFactor ?? 1

        displaySize = CGSize(width: display.width, height: display.height)
        let config = SCStreamConfiguration()
        applyCrop(position: position, to: config)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = true
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 5

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream
        self.configuration = config
    }

    func updatePosition(_ position: CropPosition) async throws {
        guard let stream, let config = configuration else { return }
        applyCrop(position: position, to: config)
        try await stream.updateConfiguration(config)
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        self.configuration = nil
        try? await stream.stopCapture()
    }

    private func applyCrop(position: CropPosition, to config: SCStreamConfiguration) {
        let crop = CropCalculator.cropRect(displaySize: displaySize, position: position)
        config.sourceRect = crop
        config.width = Int(crop.width * scaleFactor)
        config.height = Int(crop.height * scaleFactor)
    }
}

extension CaptureEngine: SCStreamOutput {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen, sampleBuffer.isValid else { return }
        // Nur vollständige Frames weiterreichen
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
            let statusRaw = attachments.first?[.status] as? Int,
            statusRaw == SCFrameStatus.complete.rawValue
        else { return }
        onFrame?(sampleBuffer)
    }
}

extension CaptureEngine: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream != nil else { return }
            self.stream = nil
            self.configuration = nil
            self.onStopped?(error)
        }
    }
}
```

- [ ] **Step 2: Build prüfen**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!` (Warnungen sind ok, keine Errors)

- [ ] **Step 3: Commit**

```bash
git add Sources/ScreenFramer/CaptureEngine.swift
git commit -m "feat: add CaptureEngine wrapping ScreenCaptureKit with 16:9 sourceRect crop"
```

---

### Task 3: MirrorWindowController (teilbares Vorschau-Fenster)

**Files:**
- Create: `Sources/ScreenFramer/MirrorWindowController.swift`

**Interfaces:**
- Produces (für Task 4):
  - `final class MirrorWindowController: NSWindowController`
  - `init()` — erzeugt das Fenster (Titel „Screen Framer", 16:9-fixiert, skalierbar)
  - `var onClose: (() -> Void)?` — feuert auf dem Main-Thread beim Schließen des Fensters
  - `func enqueue(_ sampleBuffer: CMSampleBuffer)` — threadsicher von beliebiger Queue aufrufbar

- [ ] **Step 1: MirrorWindowController implementieren**

`Sources/ScreenFramer/MirrorWindowController.swift`:

```swift
import AppKit
import AVFoundation

/// Das Fenster, das in Teams geteilt wird: frei skalierbar,
/// Seitenverhältnis fest 16:9, rendert CMSampleBuffer via
/// AVSampleBufferDisplayLayer (GPU-basiert, latenzarm).
final class MirrorWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    private let displayLayer = AVSampleBufferDisplayLayer()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "Screen Framer"
        window.contentAspectRatio = NSSize(width: 16, height: 9)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor
        let contentView = NSView()
        contentView.layer = displayLayer
        contentView.wantsLayer = true
        window.contentView = contentView
        window.center()
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

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
```

- [ ] **Step 2: Build prüfen**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/ScreenFramer/MirrorWindowController.swift
git commit -m "feat: add 16:9-locked mirror window rendering sample buffers"
```

---

### Task 4: StatusBarController + App-Einstieg

**Files:**
- Create: `Sources/ScreenFramer/StatusBarController.swift`
- Modify: `Sources/ScreenFramer/main.swift` (Platzhalter ersetzen)

**Interfaces:**
- Consumes: `CaptureEngine` (Task 2), `MirrorWindowController` (Task 3), `CropPosition` (Task 1)
- Produces: `final class StatusBarController: NSObject, NSMenuDelegate` mit `override init()`; `main.swift` startet die App mit `.accessory`-Policy.

- [ ] **Step 1: StatusBarController implementieren**

`Sources/ScreenFramer/StatusBarController.swift`:

```swift
import AppKit
import ScreenFramerCore

/// Menüleisten-Icon und Menü; hält den App-Zustand und verdrahtet
/// CaptureEngine und MirrorWindowController.
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let captureEngine = CaptureEngine()
    private var mirrorWindowController: MirrorWindowController?

    private var selectedDisplayID: CGDirectDisplayID?
    private var position: CropPosition = .center
    private var isRunning = false

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

    // Menü bei jedem Öffnen neu aufbauen (Monitore können sich ändern)
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let monitorItem = NSMenuItem(title: "Monitor", action: nil, keyEquivalent: "")
        let monitorMenu = NSMenu()
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            let item = NSMenuItem(
                title: screen.localizedName,
                action: #selector(selectMonitor(_:)),
                keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: id)
            item.state = (id == selectedDisplayID) ? .on : .off
            monitorMenu.addItem(item)
        }
        monitorItem.submenu = monitorMenu
        menu.addItem(monitorItem)

        let positionItem = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        let positionMenu = NSMenu()
        for (value, title) in Self.positionTitles {
            let item = NSMenuItem(
                title: title, action: #selector(selectPosition(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value.rawValue
            item.state = (value == position) ? .on : .off
            positionMenu.addItem(item)
        }
        positionItem.submenu = positionMenu
        menu.addItem(positionItem)

        menu.addItem(.separator())
        if isRunning {
            let stopItem = NSMenuItem(
                title: "Übertragung stoppen", action: #selector(stopCapture),
                keyEquivalent: "")
            stopItem.target = self
            menu.addItem(stopItem)
        } else {
            let startItem = NSMenuItem(
                title: "Übertragung starten", action: #selector(startCapture),
                keyEquivalent: "")
            // Ohne Monitorauswahl kein Start (target = nil → Item ausgegraut)
            startItem.target = (selectedDisplayID != nil) ? self : nil
            menu.addItem(startItem)
        }

        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "Beenden", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    @objc private func selectMonitor(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }
        let newID = CGDirectDisplayID(number.uint32Value)
        guard newID != selectedDisplayID else { return }
        selectedDisplayID = newID
        if isRunning {
            // Monitorwechsel während laufender Übertragung: neu starten
            Task { @MainActor in
                await self.teardown()
                self.startCapture()
            }
        }
    }

    @objc private func selectPosition(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let newPosition = CropPosition(rawValue: raw) else { return }
        position = newPosition
        if isRunning {
            Task { @MainActor in
                do {
                    try await self.captureEngine.updatePosition(newPosition)
                } catch {
                    self.showError(error)
                }
            }
        }
    }

    @objc private func startCapture() {
        guard let displayID = selectedDisplayID, !isRunning else { return }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            showPermissionAlert()
            return
        }

        let windowController = MirrorWindowController()
        windowController.onClose = { [weak self] in
            guard let self, self.isRunning else { return }
            Task { @MainActor in await self.teardown(closeWindow: false) }
        }
        captureEngine.onFrame = { [weak windowController] buffer in
            windowController?.enqueue(buffer)
        }
        captureEngine.onStopped = { [weak self] error in
            guard let self else { return }
            Task { @MainActor in
                await self.teardown(stopEngine: false)
                if let error { self.showError(error) }
            }
        }

        Task { @MainActor in
            do {
                try await self.captureEngine.start(displayID: displayID, position: self.position)
                self.mirrorWindowController = windowController
                self.isRunning = true
                windowController.showWindow(nil)
                NSApp.activate(ignoringOtherApps: true)
            } catch {
                self.showError(error)
            }
        }
    }

    @objc private func stopCapture() {
        Task { @MainActor in await self.teardown() }
    }

    @MainActor
    private func teardown(stopEngine: Bool = true, closeWindow: Bool = true) async {
        isRunning = false
        if stopEngine {
            await captureEngine.stop()
        }
        if closeWindow, let controller = mirrorWindowController {
            controller.onClose = nil
            controller.close()
        }
        mirrorWindowController = nil
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

- [ ] **Step 2: main.swift ersetzen**

`Sources/ScreenFramer/main.swift` (kompletter neuer Inhalt):

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 3: Build + Tests prüfen**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | tail -3`
Expected: `Build complete!` und `Test Suite 'All tests' passed`

- [ ] **Step 4: Commit**

```bash
git add Sources/ScreenFramer/StatusBarController.swift Sources/ScreenFramer/main.swift
git commit -m "feat: add menu bar UI and app entry point"
```

---

### Task 5: App-Bundle-Skript + manueller Test

**Files:**
- Create: `scripts/build-app.sh`
- Create: `README.md`

**Interfaces:**
- Consumes: das Executable `.build/release/ScreenFramer` (Tasks 1–4)
- Produces: `build/Screen Framer.app` — ad-hoc-signiertes Bundle mit `LSUIElement`, das die TCC-Berechtigung dauerhaft hält.

- [ ] **Step 1: Build-Skript schreiben**

`scripts/build-app.sh`:

```bash
#!/bin/bash
# Baut das Release-Binary und verpackt es als "Screen Framer.app".
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/Screen Framer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ScreenFramer "$APP/Contents/MacOS/ScreenFramer"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ScreenFramer</string>
    <key>CFBundleIdentifier</key>
    <string>de.martinfoerster.screen-framer</string>
    <key>CFBundleName</key>
    <string>Screen Framer</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Ad-hoc-Signatur: nötig, damit macOS die Bildschirmaufnahme-Berechtigung
# der App über Rebuilds hinweg zuordnen kann.
codesign --force --sign - "$APP"

echo "Fertig: $APP"
```

Danach ausführbar machen:

```bash
chmod +x scripts/build-app.sh
```

- [ ] **Step 2: README schreiben**

`README.md`:

```markdown
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
4. In Teams **Fenster teilen** → „Screen Framer"

Fenster schließen oder **Übertragung stoppen** beendet die Übertragung.
```

- [ ] **Step 3: Bundle bauen**

Run: `scripts/build-app.sh`
Expected: `Fertig: build/Screen Framer.app`, `codesign` ohne Fehler.

- [ ] **Step 4: Manuelle Verifikation**

Run: `open "build/Screen Framer.app"`

Checkliste (manuell):
- Icon erscheint in der Menüleiste, kein Dock-Icon
- „Übertragung starten" ist ausgegraut, bis ein Monitor gewählt ist
- Monitor wählen → Start → TCC-Abfrage erscheint (einmalig; danach App neu starten)
- Fenster „Screen Framer" zeigt den Live-Ausschnitt, 16:9 bleibt beim Skalieren erhalten
- Position Links/Mitte/Rechts live umschalten funktioniert
- Fenster schließen stoppt die Übertragung (Menü zeigt wieder „Übertragung starten")

- [ ] **Step 5: Commit**

```bash
git add scripts/build-app.sh README.md
git commit -m "feat: add app bundle build script and README"
```
