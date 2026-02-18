// MARK: - Core/PanelManager.swift
// 悬浮窗管理器 - 窗口顶部锚定，向下扩展

import AppKit
import SwiftUI
import Combine

// MARK: - 自定义 Panel
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// 悬浮窗管理器
@MainActor
final class PanelManager: NSObject, NSWindowDelegate {
    
    private var panel: KeyablePanel?
    private var heightObserver: AnyCancellable?
    private var widthObserver: AnyCancellable?
    private var isAdjustingHeight = false
    private var isAdjustingWidth = false
    private var isLiveResizing = false
    private var manualPanelHeight: CGFloat = 64
    private var preferredPanelWidth: CGFloat = 620
    
    /// 窗口顶部 Y 坐标锚点（macOS 坐标 = origin.y + height）
    private var anchorTopY: CGFloat = 0
    private let minPanelWidth: CGFloat = 520
    private let maxPanelWidth: CGFloat = 1180
    private let initialHeight: CGFloat = 64
    
    var isVisible: Bool { panel?.isVisible ?? false }
    
    /// 创建悬浮窗
    func setup(
        with rootView: some View,
        heightPublisher: AnyPublisher<CGFloat, Never>,
        widthPublisher: AnyPublisher<CGFloat, Never>
    ) {
        let initialWidth = preferredPanelWidth
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight),
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.becomesKeyOnlyIfNeeded = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.minSize = NSSize(width: minPanelWidth, height: initialHeight)
        panel.delegate = self
        
        let hostingView = NSHostingView(rootView: AnyView(rootView))
        hostingView.frame = panel.contentView!.bounds
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(hostingView)
        
        self.panel = panel
        self.manualPanelHeight = initialHeight
        
        // 监听高度变化 → 向下扩展
        heightObserver = heightPublisher
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] newHeight in
                self?.resizeDownward(to: newHeight)
            }
        
        widthObserver = widthPublisher
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] newWidth in
                self?.resizeWidth(to: newWidth)
            }
        
        print("✅ 悬浮窗已创建")
    }
    
    /// 保持顶部锚定，向下扩展
    private func resizeDownward(to newHeight: CGFloat) {
        guard let panel = panel else { return }
        
        let targetHeight = max(initialHeight, newHeight)
        let currentFrame = panel.frame
        let delta = targetHeight - currentFrame.height
        if abs(delta) <= 0.5 { return }
        
        // 顶部 Y 坐标 = origin.y + height（macOS 坐标系）
        let topY = anchorTopY
        // 新的 origin.y = topY - newHeight（向下扩展）
        let newY = topY - targetHeight
        
        let newFrame = NSRect(
            x: currentFrame.origin.x,
            y: newY,
            width: currentFrame.width,
            height: targetHeight
        )
        
        isAdjustingHeight = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(newFrame, display: true)
        } completionHandler: { [weak self] in
            DispatchQueue.main.async {
                self?.manualPanelHeight = max(self?.initialHeight ?? 64, targetHeight)
                self?.isAdjustingHeight = false
            }
        }
    }
    
    private func resizeWidth(to newWidth: CGFloat) {
        guard let panel = panel else { return }
        
        let clampedWidth = min(max(newWidth, minPanelWidth), maxPanelWidth)
        preferredPanelWidth = clampedWidth
        
        guard panel.isVisible else { return }
        if isLiveResizing { return }
        
        let currentFrame = panel.frame
        if abs(currentFrame.width - clampedWidth) < 0.5 { return }
        
        let centerX = currentFrame.midX
        let visibleFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var newX = centerX - clampedWidth / 2
        if visibleFrame != .zero {
            newX = max(visibleFrame.minX + 12, min(newX, visibleFrame.maxX - clampedWidth - 12))
        }
        
        let newFrame = NSRect(
            x: newX,
            y: currentFrame.origin.y,
            width: clampedWidth,
            height: currentFrame.height
        )
        
        isAdjustingWidth = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(newFrame, display: true)
        } completionHandler: { [weak self] in
            DispatchQueue.main.async {
                self?.isAdjustingWidth = false
            }
        }
    }
    
    func toggle() {
        guard let panel = panel else { return }
        if panel.isVisible { hide() } else { show() }
    }
    
    func show() {
        guard let panel = panel, let screen = NSScreen.main else { return }

        if panel.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKey()
            NotificationCenter.default.post(name: .synapseFocus, object: nil)
            return
        }
        
        let screenFrame = screen.visibleFrame
        let desiredWidth = min(max(preferredPanelWidth, minPanelWidth), min(maxPanelWidth, screenFrame.width - 24))
        var x = screenFrame.midX - desiredWidth / 2
        x = max(screenFrame.minX + 12, min(x, screenFrame.maxX - desiredWidth - 12))
        // 搜索栏顶部在屏幕上方 ~30% 处
        let topY = screenFrame.origin.y + screenFrame.height * 0.72
        let targetHeight = max(initialHeight, manualPanelHeight)
        let y = topY - targetHeight
        
        self.anchorTopY = topY  // 记住顶部锚点
        
        panel.setFrame(NSRect(x: x, y: y, width: desiredWidth, height: targetHeight), display: true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
        
        // 发送焦点通知
        NotificationCenter.default.post(name: .synapseFocus, object: nil)
        
        print("🪟 窗口已显示")
    }
    
    func hide() {
        panel?.orderOut(nil)
        print("🪟 窗口已隐藏")
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillStartLiveResize(_ notification: Notification) {
        isLiveResizing = true
    }
    
    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        isLiveResizing = false
        anchorTopY = window.frame.maxY
        manualPanelHeight = max(initialHeight, window.frame.height)
        preferredPanelWidth = min(max(window.frame.width, minPanelWidth), maxPanelWidth)
    }
    
    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        anchorTopY = window.frame.maxY
        
        if isLiveResizing {
            return
        }
        
        // 程序内部只允许调整高度，不自动改写用户宽度
        if isAdjustingHeight || isAdjustingWidth { return }
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        // 非用户手动拖拽时，禁止自动收缩高度（保持仅手动缩回）
        guard !isLiveResizing, !isAdjustingHeight else { return frameSize }
        if frameSize.height < sender.frame.height {
            return NSSize(width: frameSize.width, height: sender.frame.height)
        }
        return frameSize
    }
}

extension Notification.Name {
    static let synapseFocus = Notification.Name("synapseFocus")
}
