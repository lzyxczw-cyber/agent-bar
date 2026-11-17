import AppKit
import SwiftUI
import QuartzCore
import Carbon
import Combine
import IOKit.ps
import CoreWLAN
import UserNotifications

final class BarContainerView: NSView {
    var onClick: ((NSPoint, Int) -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        return self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onClick?(point, event.clickCount)
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }
}

/// Borderless notch panel that can become key (so Esc works) and unfolds downward.
final class IslandPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - App delegate

