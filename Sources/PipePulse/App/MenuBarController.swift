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
        let timer = Timer(timeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advanceFrame() }
        }
        timer.tolerance = 0.02
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
        let symbol = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 17, weight: .medium))!
        return (0..<12).map { index in
            let pulse = (1 - cos(Double(index) / 12 * 2 * .pi)) / 2
            let side = 17 + 3 * pulse
            let image = NSImage(size: NSSize(width: 22, height: 22))
            image.lockFocus()
            let rect = NSRect(x: (22 - side) / 2, y: (22 - side) / 2, width: side, height: side)
            symbol.draw(in: rect)
            color.withAlphaComponent(0.65 + 0.35 * pulse).setFill()
            rect.fill(using: .sourceIn)
            image.unlockFocus()
            image.isTemplate = false
            return image
        }
    }
}
