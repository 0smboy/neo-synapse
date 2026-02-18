// MARK: - UI/RayBubblePanelManager.swift
// Floating panel manager for the Ray voice pet bubble

import AppKit
import SwiftUI

/// Manages a borderless, always-on-top floating panel for the Ray bubble.
/// Separate from PanelManager (keyboard panel). Position and size configurable.
@MainActor
final class RayBubblePanelManager {

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var isExpanded = false

    private let idleSize = NSSize(width: 80, height: 80)
    private let expandedWidth: CGFloat = 360
    private let expandedMinHeight: CGFloat = 120
    private let animationDuration: TimeInterval = 0.25

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Create and configure the Ray bubble panel
    func setup(with rootView: some View) {
        guard panel == nil else { return }

        let hosting = NSHostingView(rootView: AnyView(rootView))
        hosting.frame = NSRect(origin: .zero, size: idleSize)
        hosting.autoresizingMask = []

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: idleSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = true

        panel.contentView?.addSubview(hosting)

        self.panel = panel
        self.hostingView = hosting
    }

    func show() {
        guard let panel = panel, let screen = NSScreen.main else { return }

        if panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let frame = frameForCurrentState(screen: screen)
        panel.setFrame(frame, display: true)
        panel.orderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func expand() {
        guard let panel = panel, let screen = NSScreen.main else { return }
        guard !isExpanded else { return }

        isExpanded = true
        let targetFrame = frameForCurrentState(screen: screen)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animationDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.hostingView?.frame = panel.contentView?.bounds ?? .zero
                self?.hostingView?.autoresizingMask = [.width, .height]
            }
        }
    }

    func collapse() {
        guard let panel = panel, let screen = NSScreen.main else { return }
        guard isExpanded else { return }

        isExpanded = false
        let targetFrame = frameForCurrentState(screen: screen)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animationDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.hostingView?.frame = panel.contentView?.bounds ?? .zero
                self?.hostingView?.autoresizingMask = []
            }
        }
    }

    private func frameForCurrentState(screen: NSScreen) -> NSRect {
        let screenFrame = screen.visibleFrame
        let size = isExpanded ? NSSize(width: expandedWidth, height: expandedMinHeight) : idleSize
        let origin = originForPosition(SynapseSettings.rayPosition, size: size, screenFrame: screenFrame)
        return NSRect(origin: origin, size: size)
    }

    private func originForPosition(_ position: String, size: NSSize, screenFrame: NSRect) -> NSPoint {
        let padding: CGFloat = 16
        switch position {
        case "bottom_right":
            return NSPoint(
                x: screenFrame.maxX - size.width - padding,
                y: screenFrame.minY + padding
            )
        case "bottom_left":
            return NSPoint(
                x: screenFrame.minX + padding,
                y: screenFrame.minY + padding
            )
        case "top_right":
            return NSPoint(
                x: screenFrame.maxX - size.width - padding,
                y: screenFrame.maxY - size.height - padding
            )
        case "top_left":
            return NSPoint(
                x: screenFrame.minX + padding,
                y: screenFrame.maxY - size.height - padding
            )
        default:
            return NSPoint(
                x: screenFrame.maxX - size.width - padding,
                y: screenFrame.minY + padding
            )
        }
    }
}
