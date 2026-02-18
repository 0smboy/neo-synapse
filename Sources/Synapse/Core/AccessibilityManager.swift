// MARK: - Core/AccessibilityManager.swift
// Accessibility API 封装 - 窗口管理、进程控制

import AppKit
import ApplicationServices

/// Accessibility 管理器
final class AccessibilityManager {
    static let shared = AccessibilityManager()
    
    /// 检查是否已获得辅助功能权限
    var hasPermission: Bool {
        AXIsProcessTrusted()
    }
    
    /// 请求辅助功能权限
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
    
    // MARK: - 窗口管理
    
    /// 获取当前前台 App 信息
    func frontmostApp() -> NSRunningApplication? {
        NSWorkspace.shared.frontmostApplication
    }
    
    /// 最小化前台 App 窗口
    func minimizeFrontWindow() -> Bool {
        guard hasPermission,
              let app = NSWorkspace.shared.frontmostApplication else { return false }
        
        let appRef = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef)
        
        guard let window = windowRef else { return false }
        let windowElement = window as! AXUIElement
        AXUIElementSetAttributeValue(windowElement, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        return true
    }
    
    /// 全屏切换前台 App 窗口
    func toggleFullscreen() -> Bool {
        guard hasPermission,
              let app = NSWorkspace.shared.frontmostApplication else { return false }
        
        let appRef = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef)
        
        guard let window = windowRef else { return false }
        
        let windowElement = window as! AXUIElement
        var buttonRef: CFTypeRef?
        AXUIElementCopyAttributeValue(windowElement, kAXFullScreenButtonAttribute as CFString, &buttonRef)
        
        if let button = buttonRef {
            AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
            return true
        }
        return false
    }
    
    /// 获取所有窗口列表
    func getWindows(of pid: pid_t) -> [(title: String, element: AXUIElement)] {
        let appRef = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
        
        guard let windows = windowsRef as? [AXUIElement] else { return [] }
        
        return windows.compactMap { win in
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleRef)
            let title = (titleRef as? String) ?? "Untitled"
            return (title: title, element: win)
        }
    }
    
    /// 将窗口移动到指定位置
    func moveWindow(_ element: AXUIElement, to point: CGPoint) {
        var position = point
        let positionValue = AXValueCreate(.cgPoint, &position)!
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
    }
    
    /// 调整窗口大小
    func resizeWindow(_ element: AXUIElement, to size: CGSize) {
        var s = size
        let sizeValue = AXValueCreate(.cgSize, &s)!
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
    }
    
    /// 左半屏
    func tileLeft() -> Bool {
        guard let screen = NSScreen.main,
              let app = NSWorkspace.shared.frontmostApplication else { return false }
        
        let windows = getWindows(of: app.processIdentifier)
        guard let win = windows.first else { return false }
        
        let screenFrame = screen.visibleFrame
        moveWindow(win.element, to: CGPoint(x: screenFrame.origin.x, y: screenFrame.origin.y))
        resizeWindow(win.element, to: CGSize(width: screenFrame.width / 2, height: screenFrame.height))
        return true
    }
    
    /// 右半屏
    func tileRight() -> Bool {
        guard let screen = NSScreen.main,
              let app = NSWorkspace.shared.frontmostApplication else { return false }
        
        let windows = getWindows(of: app.processIdentifier)
        guard let win = windows.first else { return false }
        
        let screenFrame = screen.visibleFrame
        moveWindow(win.element, to: CGPoint(x: screenFrame.midX, y: screenFrame.origin.y))
        resizeWindow(win.element, to: CGSize(width: screenFrame.width / 2, height: screenFrame.height))
        return true
    }
    
    /// 居中最大化
    func maximizeWindow() -> Bool {
        guard let screen = NSScreen.main,
              let app = NSWorkspace.shared.frontmostApplication else { return false }
        
        let windows = getWindows(of: app.processIdentifier)
        guard let win = windows.first else { return false }
        
        let screenFrame = screen.visibleFrame
        moveWindow(win.element, to: CGPoint(x: screenFrame.origin.x, y: screenFrame.origin.y))
        resizeWindow(win.element, to: CGSize(width: screenFrame.width, height: screenFrame.height))
        return true
    }
}
