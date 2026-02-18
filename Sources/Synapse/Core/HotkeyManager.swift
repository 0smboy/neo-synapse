// MARK: - Core/HotkeyManager.swift
// 全局快捷键管理（Carbon API）

import AppKit
import Carbon

/// 全局快捷键管理器 - 使用 Carbon API 注册系统级热键
final class HotkeyManager {
    private struct HotkeyPreset {
        let id: String
        let title: String
        let keyCode: UInt32
        let modifiers: UInt32
    }

    private static let presets: [HotkeyPreset] = [
        HotkeyPreset(
            id: "option_space",
            title: "Option + Space",
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(optionKey)
        ),
        HotkeyPreset(
            id: "control_space",
            title: "Control + Space",
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(controlKey)
        ),
        HotkeyPreset(
            id: "command_shift_space",
            title: "Command + Shift + Space",
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(cmdKey | shiftKey)
        ),
        HotkeyPreset(
            id: "option_command_k",
            title: "Option + Command + K",
            keyCode: UInt32(kVK_ANSI_K),
            modifiers: UInt32(optionKey | cmdKey)
        ),
    ]
    
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let callback: () -> Void
    
    init(callback: @escaping () -> Void) {
        self.callback = callback
    }
    
    deinit {
        unregister()
    }
    
    /// 注册全局快捷键（可配置预设）
    func register() {
        unregister()

        let preset = Self.preset(for: SynapseSettings.hotkeyPreset)
        let hotKeyID = EventHotKeyID(
            signature: OSType(0x53594E50),  // 'SYNP'
            id: UInt32(1)
        )
        
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        // Install the event handler - use a static-compatible approach
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    mgr.callback()
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )
        
        guard status == noErr else {
            print("❌ 无法安装事件处理器: \(status)")
            return
        }
        
        // Register configured hotkey
        let result = RegisterEventHotKey(
            preset.keyCode,
            preset.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if result == noErr {
            print("✅ 已注册全局快捷键: \(preset.title)")
        } else {
            print("❌ 注册快捷键失败: \(result)")
        }
    }

    private static func preset(for id: String) -> HotkeyPreset {
        let normalized = id.lowercased()
        if let matched = presets.first(where: { $0.id == normalized }) {
            return matched
        }
        return presets.first(where: { $0.id == SynapseSettings.defaultHotkeyPreset }) ?? presets[0]
    }

    static func currentHotkeyTitle() -> String {
        preset(for: SynapseSettings.hotkeyPreset).title
    }
    
    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }
    }
}
