# Rahmen-Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ein grüner, klick-durchlässiger Rahmen markiert auf dem Quellmonitor den übertragenen 16:9-Bereich, solange die Übertragung läuft.

**Architecture:** Die Koordinaten-Umrechnung (display-lokales Top-Left-Rechteck → globales Cocoa-Bottom-Left-Frame) kommt als reine, unit-getestete Funktion in `ScreenFramerCore`. Ein neuer `CropFrameOverlayController` (randloses, transparentes, klick-durchlässiges Fenster, nur CALayer-Border) wird vom `StatusBarController` bei Start gezeigt, bei Positionswechsel verschoben und im zentralen `teardown()` entfernt.

**Tech Stack:** Swift 5 / AppKit (bestehend), XCTest.

## Global Constraints

- Plattform: macOS 14+, swift-tools-version 5.10; Repo-Root `/Library/Repos/Privat/screen-framer`, Branch `feature/screen-framer`
- Rahmen: `NSColor.systemGreen`, `borderWidth = 4`, kein Schatten, klick-durchlässig, Level über der Menüleiste (`mainMenu + 1`), `canJoinAllSpaces` + `stationary` + `ignoresCycle`
- Der Rahmen erscheint nach erfolgreichem Start, wandert beim Positionswechsel mit, verschwindet auf allen Stopp-Pfaden (alle laufen durch `teardown()`)
- Keine Konfigurierbarkeit, kein Menüpunkt (YAGNI)
- Die bestehenden 6 CropCalculator-Tests müssen grün bleiben; die neue Umrechnungsfunktion wird testgetrieben entwickelt

---

### Task 1: CropCalculator.cocoaFrame (TDD)

**Files:**
- Modify: `Sources/ScreenFramerCore/CropCalculator.swift`
- Test: `Tests/ScreenFramerCoreTests/CropCalculatorTests.swift`

**Interfaces:**
- Produces (für Task 2): `public static func CropCalculator.cocoaFrame(for cropRect: CGRect, in screenFrame: CGRect) -> CGRect` — rechnet ein display-lokales Rechteck mit Ursprung oben links in ein globales Frame mit Ursprung unten links um (`screenFrame` ist das globale Cocoa-Frame des Monitors, z. B. `NSScreen.frame`).

- [ ] **Step 1: Fehlschlagende Tests schreiben**

In `Tests/ScreenFramerCoreTests/CropCalculatorTests.swift` innerhalb der Klasse `CropCalculatorTests` (ans Ende, vor die schließende Klammer) ergänzen:

```swift
    // MARK: - cocoaFrame(for:in:)

    // Monitor am globalen Ursprung, Ausschnitt volle Höhe → identische Werte
    func testCocoaFrameFullHeightAtOrigin() {
        let frame = CropCalculator.cocoaFrame(
            for: CGRect(x: 1280, y: 0, width: 2560, height: 1440),
            in: CGRect(x: 0, y: 0, width: 5120, height: 1440))
        XCTAssertEqual(frame, CGRect(x: 1280, y: 0, width: 2560, height: 1440))
    }

    // Monitor mit globalem Offset (z. B. zweiter Monitor im Arrangement)
    func testCocoaFrameWithScreenOffset() {
        let frame = CropCalculator.cocoaFrame(
            for: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            in: CGRect(x: 100, y: 50, width: 2560, height: 1080))
        XCTAssertEqual(frame, CGRect(x: 100, y: 50, width: 1920, height: 1080))
    }

    // Teilhöhe: beweist die y-Spiegelung (oben-links → unten-links)
    func testCocoaFrameFlipsYForPartialHeight() {
        let frame = CropCalculator.cocoaFrame(
            for: CGRect(x: 0, y: 100, width: 800, height: 450),
            in: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        XCTAssertEqual(frame, CGRect(x: 0, y: 450, width: 800, height: 450))
    }
```

- [ ] **Step 2: Tests laufen lassen — sie müssen fehlschlagen**

Run: `swift test 2>&1 | grep -E "error|cocoaFrame" | head -5`
Expected: Compile-Fehler „type 'CropCalculator' has no member 'cocoaFrame'"

- [ ] **Step 3: Implementierung**

In `Sources/ScreenFramerCore/CropCalculator.swift` innerhalb von `public enum CropCalculator` (nach `cropRect(displaySize:position:)`) ergänzen:

```swift
    /// Rechnet ein display-lokales Rechteck (Ursprung oben links, wie
    /// `cropRect`) in ein globales Cocoa-Frame (Ursprung unten links) um.
    /// `screenFrame` ist das globale Frame des Monitors (`NSScreen.frame`).
    public static func cocoaFrame(for cropRect: CGRect, in screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.origin.x + cropRect.origin.x,
            y: screenFrame.origin.y + screenFrame.height - cropRect.maxY,
            width: cropRect.width,
            height: cropRect.height)
    }
```

- [ ] **Step 4: Tests laufen lassen — sie müssen bestehen**

Run: `swift test 2>&1 | grep -E "Executed|failures" | head -2`
Expected: `Executed 9 tests, with 0 failures`

- [ ] **Step 5: Commit**

```bash
git add Sources/ScreenFramerCore/CropCalculator.swift Tests/ScreenFramerCoreTests/CropCalculatorTests.swift
git commit -m "feat: add unit-tested top-left to Cocoa coordinate conversion"
```

---

### Task 2: CropFrameOverlayController + Verdrahtung

**Files:**
- Create: `Sources/ScreenFramer/CropFrameOverlayController.swift`
- Modify: `Sources/ScreenFramer/StatusBarController.swift` (vier punktuelle Änderungen, siehe Steps 2–3)

**Interfaces:**
- Consumes: `CropCalculator.cocoaFrame(for:in:)` (Task 1), `CropCalculator.cropRect(displaySize:position:)` (bestehend)
- Produces: `final class CropFrameOverlayController: NSWindowController` mit `init(cropRect: CGRect, on screen: NSScreen)` (zeigt das Fenster sofort) und `func move(to cropRect: CGRect, on screen: NSScreen)`

- [ ] **Step 1: CropFrameOverlayController anlegen**

`Sources/ScreenFramer/CropFrameOverlayController.swift`:

```swift
import AppKit
import ScreenFramerCore

/// Grüner, klick-durchlässiger Rahmen um den übertragenen Ausschnitt auf
/// dem Quellmonitor. Nur lokal sichtbar — die eigenen Fenster der App sind
/// vom Capture ausgeschlossen, Teilnehmende sehen ihn nicht.
final class CropFrameOverlayController: NSWindowController {
    init(cropRect: CGRect, on screen: NSScreen) {
        let frame = CropCalculator.cocoaFrame(for: cropRect, in: screen.frame)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        // Über der Menüleiste, damit der Rahmen oben durchgängig sichtbar ist
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        super.init(window: window)

        let view = NSView()
        view.wantsLayer = true
        view.layer?.borderColor = NSColor.systemGreen.cgColor
        view.layer?.borderWidth = 4
        window.contentView = view
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func move(to cropRect: CGRect, on screen: NSScreen) {
        let frame = CropCalculator.cocoaFrame(for: cropRect, in: screen.frame)
        window?.setFrame(frame, display: true)
    }
}
```

- [ ] **Step 2: StatusBarController — Property und Helfer ergänzen**

In `Sources/ScreenFramer/StatusBarController.swift`:

a) Nach der Zeile `private var mirrorWindowController: MirrorWindowController?` ergänzen:

```swift
    private var frameOverlayController: CropFrameOverlayController?
```

b) Direkt vor der Methode `@objc private func stopCapture()` diese Methode einfügen:

```swift
    /// Zeigt den Rahmen um den aktuellen Ausschnitt bzw. verschiebt ihn.
    private func showFrameOverlay(for displayID: CGDirectDisplayID) {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID })
        else { return }
        let crop = CropCalculator.cropRect(
            displaySize: screen.frame.size, position: position)
        if let overlay = frameOverlayController {
            overlay.move(to: crop, on: screen)
        } else {
            frameOverlayController = CropFrameOverlayController(cropRect: crop, on: screen)
        }
    }
```

- [ ] **Step 3: StatusBarController — Aufrufe verdrahten**

a) Im Erfolgspfad von `startCapture(on:)`, direkt nach der Zeile `self.isStarting = false` (der Zeile im `do`-Block, nicht der im `catch`), ergänzen:

```swift
                self.showFrameOverlay(for: displayID)
```

b) Im Positionswechsel-Pfad von `startTransmission(_:)`, direkt nach der Zeile `try await self.captureEngine.updatePosition(newPosition)`, ergänzen:

```swift
                    self.showFrameOverlay(for: displayID)
```

c) In `teardown(stopEngine:)`, direkt nach der Zeile `mirrorWindowController = nil`, ergänzen:

```swift
        frameOverlayController?.close()
        frameOverlayController = nil
```

- [ ] **Step 4: Build + Tests prüfen**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | grep -E "Executed|failures" | head -2`
Expected: `Build complete!`, `Executed 9 tests, with 0 failures`

- [ ] **Step 5: Commit**

```bash
git add Sources/ScreenFramer/CropFrameOverlayController.swift Sources/ScreenFramer/StatusBarController.swift
git commit -m "feat: show green frame around transmitted crop on the source monitor"
```

- [ ] **Step 6: Bundle neu bauen + manuelle Verifikation (Controller/Mensch)**

Run: `pkill -x ScreenFramer; scripts/build-app.sh && open "build/Screen Framer.app"`

Checkliste (manuell):
- Start → grüner Rahmen um den übertragenen Bereich auf dem Quellmonitor
- Rahmen ist klick-durchlässig (Fenster darunter normal bedienbar)
- Positionswechsel → Rahmen wandert mit
- In Teams/im virtuellen Bildschirm ist der Rahmen NICHT zu sehen
- Stopp → Rahmen verschwindet
