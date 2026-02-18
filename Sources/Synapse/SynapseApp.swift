// MARK: - SynapseApp.swift
// 应用入口

import SwiftUI
import AppKit

@main
struct SynapseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SynapseSettingsView()
                .frame(minWidth: 640, minHeight: 560)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var panelManager: PanelManager?
    private var hotkeyManager: HotkeyManager?
    private var statusItem: NSStatusItem?
    private var dismissObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    private var settingsWindowController: NSWindowController?
    private var lastHotkeyPreset: String = SynapseSettings.hotkeyPreset
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("Synapse 启动中...")
        
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        
        // 悬浮窗
        let heightNotifier = HeightNotifier()
        let panel = PanelManager()
        panel.setup(
            with: SynapseView(heightNotifier: heightNotifier),
            heightPublisher: heightNotifier.publisher,
            widthPublisher: heightNotifier.widthPublisher
        )
        self.panelManager = panel
        
        // 全局快捷键
        hotkeyManager = HotkeyManager { [weak self] in
            self?.panelManager?.toggle()
        }
        hotkeyManager?.register()
        observeSettingsChanges()

        // App 索引：先读缓存，再后台刷新一次，便于启动/关闭应用模糊匹配
        _ = AppIndexer.shared.loadCache()
        Task { await AppIndexer.shared.indexAll() }
        
        // ESC 关闭
        dismissObserver = NotificationCenter.default.addObserver(
            forName: .synapseDismiss, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.panelManager?.hide() }
        }
        
        // 启动剪贴板监控
        ClipboardModule.shared.startMonitoring()
        
        // 启动后显示
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { panel.show() }
        
        print("✅ Synapse 就绪 — 按 \(HotkeyManager.currentHotkeyTitle()) 唤醒")
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            let icon = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "Synapse")
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            let configured = icon?.withSymbolConfiguration(config)
            configured?.isTemplate = true
            button.image = configured
        }
        
        let menu = NSMenu()

        let showItem = NSMenuItem(title: "显示 Synapse", action: #selector(showPanel(_:)), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        let preferencesItem = NSMenuItem(title: "偏好设置", action: #selector(openPreferences(_:)), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出 Synapse", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }
    
    @objc private func showPanel(_ sender: Any?) { panelManager?.show() }
    
    @objc private func openPreferences(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        if settingsWindowController == nil {
            let settingsView = SynapseSettingsView()
                .frame(minWidth: 640, minHeight: 560)
            let host = NSHostingController(rootView: settingsView)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 680),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "Synapse 配置"
            window.contentViewController = host
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 640, height: 560)
            settingsWindowController = NSWindowController(window: window)
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }
    
    @objc private func quit(_ sender: Any?) { ClipboardModule.shared.stopMonitoring(); NSApp.terminate(nil) }
    
    private func observeSettingsChanges() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let preset = SynapseSettings.hotkeyPreset
                guard preset != self.lastHotkeyPreset else { return }
                self.lastHotkeyPreset = preset
                self.hotkeyManager?.register()
            }
        }
    }

    deinit {
        if let obs = dismissObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = settingsObserver { NotificationCenter.default.removeObserver(obs) }
    }
}
