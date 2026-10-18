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
    private let runningFrames = MenuBarController.makeFrames(color: .systemBlue)
    private let successFrames = MenuBarController.makeFrames(color: .systemGreen)

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
        guard activity != .idle else { return }
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
        case .success: statusItem.button?.image = successFrames[frameIndex]
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

    private static func makeFrames(color: NSColor) -> [NSImage] {
        // A periodic ECG trace moves right through a fixed viewport. Matching
        // baseline endpoints make the wrap seamless; amplitude never changes.
        let period: CGFloat = 20
        let waveform: [NSPoint] = [
            NSPoint(x: 0, y: 0), NSPoint(x: 3, y: 0),
            NSPoint(x: 4, y: 1.5), NSPoint(x: 5, y: 0),
            NSPoint(x: 7, y: 0), NSPoint(x: 8, y: -2),
            NSPoint(x: 9.5, y: 7), NSPoint(x: 11.5, y: -5),
            NSPoint(x: 13, y: 0), NSPoint(x: 15, y: 0),
            NSPoint(x: 16.5, y: 2), NSPoint(x: 18, y: 0),
            NSPoint(x: period, y: 0)
        ]
        return (0..<24).map { index in
            let offset = CGFloat(index) / 24 * period
            let image = NSImage(size: NSSize(width: 22, height: 22))
            image.lockFocus()
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: NSRect(x: 1, y: 1, width: 20, height: 20)).addClip()
            let trace = NSBezierPath()
            trace.lineWidth = 1.7
            trace.lineJoinStyle = .round
            trace.lineCapStyle = .round
            for tile in -2...1 {
                for (pointIndex, point) in waveform.enumerated() {
                    let position = NSPoint(x: 1 + CGFloat(tile) * period + point.x + offset, y: 10 + point.y)
                    if tile == -2 && pointIndex == 0 {
                        trace.move(to: position)
                    } else {
                        trace.line(to: position)
                    }
                }
            }
            color.setStroke()
            trace.stroke()
            NSGraphicsContext.restoreGraphicsState()
            image.unlockFocus()
            image.isTemplate = false
            return image
        }
    }
}
