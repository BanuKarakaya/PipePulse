import AppKit
import Combine
import SwiftUI

/// Fixed native frames avoid TimelineView's recursive MenuBarExtra label updates.
@MainActor
final class MenuBarController: NSObject {
    private let appState: AppState
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var observation: AnyCancellable?
    private var timer: Timer?
    private var frameIndex = 0
    private(set) var activity: MenuBarActivity = .idle
    private let idleImage = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "PipePulse")!
    private let runningFrames = MenuBarController.makeFrames(color: .white)
    private let successImage = MenuBarController.makeSuccessImage()

    var isAnimating: Bool { timer?.isValid == true }

    init(appState: AppState) {
        self.appState = appState
        statusItem = NSStatusBar.system.statusItem(withLength: 28)
        super.init()
        idleImage.isTemplate = true
        idleImage.size = NSSize(width: 18, height: 18)
        statusItem.button?.image = idleImage
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 420, height: 570)
        popover.contentViewController = NSHostingController(rootView: RootView().environmentObject(appState))

        // Published emits before storage changes; use emitted values here.
        observation = appState.$projects.combineLatest(appState.$isSuccessPulseActive)
            .map { MenuBarActivity.resolve(projects: $0, successPulse: $1) }
            .removeDuplicates()
            .sink { [weak self] activity in
                MainActor.assumeIsolated { self?.setActivity(activity) }
            }
    }

    private func setActivity(_ activity: MenuBarActivity) {
        self.activity = activity
        timer?.invalidate()
        timer = nil
        frameIndex = 0
        statusItem.button?.toolTip = activity == .running ? "PipePulse — Pipelines active" : "PipePulse"
        renderFrame()
        guard activity == .running else { return }
        let timer = Timer(timeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advanceFrame() }
        }
        timer.tolerance = 0.01
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func advanceFrame() {
        frameIndex = (frameIndex + 1) % runningFrames.count
        renderFrame()
    }

    private func renderFrame() {
        switch activity {
        case .idle: statusItem.button?.image = idleImage
        case .running: statusItem.button?.image = runningFrames[frameIndex]
        case .success: statusItem.button?.image = successImage
        }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            appState.returnToDashboard()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func shutdown() {
        timer?.invalidate()
        timer = nil
        observation = nil
        popover.performClose(nil)
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private static func makeSuccessImage() -> NSImage {
        let symbol = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "PipePulse — Success")!
            .withSymbolConfiguration(.init(pointSize: 17, weight: .medium))!
        let image = NSImage(size: NSSize(width: 22, height: 22))
        image.lockFocus()
        let rect = NSRect(x: 2, y: 2, width: 18, height: 18)
        symbol.draw(in: rect)
        NSColor.systemGreen.setFill()
        rect.fill(using: .sourceIn)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func makeFrames(color: NSColor) -> [NSImage] {
        // Pre-render one seamless running cycle. Only the limbs move; the
        // figure stays centered inside the same small, fixed status-item image.
        return (0..<24).map { index in
            let phase = CGFloat(index) / 24 * 2 * .pi
            let bob = 0.25 * cos(2 * phase)
            let hip = NSPoint(x: 10, y: 8.5 + bob)
            let shoulder = NSPoint(x: 11.5, y: 14 + bob)
            let image = NSImage(size: NSSize(width: 22, height: 22))
            image.lockFocus()
            NSGraphicsContext.saveGraphicsState()
            // Draw at full size (25% larger than the previous 0.8 scale).
            NSBezierPath(rect: NSRect(x: 1, y: 1, width: 20, height: 20)).addClip()

            func joint(from origin: NSPoint, angle: CGFloat, length: CGFloat) -> NSPoint {
                NSPoint(x: origin.x + sin(angle) * length, y: origin.y - cos(angle) * length)
            }

            func stroke(_ points: [NSPoint], opacity: CGFloat = 1) {
                let path = NSBezierPath()
                path.lineWidth = 2.2
                path.lineJoinStyle = .round
                path.lineCapStyle = .round
                path.move(to: points[0])
                for point in points.dropFirst() { path.line(to: point) }
                color.withAlphaComponent(opacity).setStroke()
                path.stroke()
            }

            // Opposite arms/legs swing together, with a bent trailing knee.
            for side in [CGFloat(-1), CGFloat(1)] {
                let swing = side * sin(phase)
                let thighAngle = 0.85 * swing
                let knee = joint(from: hip, angle: thighAngle, length: 4.4)
                let kneeBend = 0.35 + 1.1 * max(0, -swing)
                let foot = joint(from: knee, angle: thighAngle - kneeBend, length: 4.0)
                let armAngle = -0.9 * swing
                let elbow = joint(from: shoulder, angle: armAngle, length: 3.2)
                let hand = joint(from: elbow, angle: armAngle + 1.6, length: 2.8)
                let opacity: CGFloat = side < 0 ? 0.55 : 1
                stroke([hip, knee, foot], opacity: opacity)
                stroke([shoulder, elbow, hand], opacity: opacity)
            }
            stroke([hip, shoulder, NSPoint(x: 12, y: 15.8 + bob)])
            let head = NSBezierPath(ovalIn: NSRect(x: 10.2, y: 15.7 + bob, width: 4, height: 4))
            color.setFill()
            head.fill()
            NSGraphicsContext.restoreGraphicsState()
            image.unlockFocus()
            image.isTemplate = false
            return image
        }
    }
}
