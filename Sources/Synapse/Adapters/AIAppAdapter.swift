// MARK: - Adapters/AIAppAdapter.swift
// AI App 调度适配器 - URL Scheme + AppleScript 调用本地 AI App

import AppKit

/// AI App 调度适配器
/// 调度优先级: URL Scheme > AppleScript > 直接启动
final class AIAppAdapter {
    
    // MARK: - App 配置
    
    struct AIAppConfig {
        let name: String
        let bundleId: String
        let urlScheme: String?              // URL Scheme 前缀
        let appleScriptTemplate: String?    // AppleScript 模板
        let capabilities: [String]          // 擅长的任务类型
    }
    
    /// 已知 AI App 配置
    static let knownApps: [AIAppConfig] = [
        // Cursor
        AIAppConfig(
            name: "Cursor",
            bundleId: "com.todesktop.230313mzl4w4u92",
            urlScheme: "cursor://",
            appleScriptTemplate: """
                tell application "Cursor"
                    activate
                end tell
                delay 1
                tell application "System Events"
                    keystroke "k" using {command down}
                    delay 0.3
                    keystroke "{{PROMPT}}"
                    delay 0.2
                    keystroke return
                end tell
            """,
            capabilities: ["代码", "编程", "debug", "python", "swift", "开发"]
        ),
        
        // VS Code
        AIAppConfig(
            name: "Visual Studio Code",
            bundleId: "com.microsoft.VSCode",
            urlScheme: "vscode://",
            appleScriptTemplate: """
                tell application "Visual Studio Code"
                    activate
                end tell
            """,
            capabilities: ["代码", "编程", "ide"]
        ),
        
        // ChatGPT
        AIAppConfig(
            name: "ChatGPT",
            bundleId: "com.openai.chat",
            urlScheme: nil,
            appleScriptTemplate: """
                tell application "ChatGPT"
                    activate
                end tell
                delay 1
                tell application "System Events"
                    keystroke "{{PROMPT}}"
                    delay 0.2
                    keystroke return
                end tell
            """,
            capabilities: ["ai", "问答", "创作", "代码"]
        ),
    ]
    
    // MARK: - 调度逻辑
    
    /// 找到最适合执行该任务的 AI App
    static func findBestApp(for task: String) -> AIAppConfig? {
        let lower = task.lowercased()
        let running = NSWorkspace.shared.runningApplications.map { $0.bundleIdentifier ?? "" }
        
        // 优先选择正在运行的 App
        var candidates = knownApps.filter { config in
            config.capabilities.contains(where: { lower.contains($0) })
        }
        
        // 按"已运行"优先排序
        candidates.sort { a, b in
            let aRunning = running.contains(a.bundleId)
            let bRunning = running.contains(b.bundleId)
            if aRunning != bRunning { return aRunning }
            return false
        }
        
        // 如果没匹配到特定能力，返回第一个已安装的 AI App
        if candidates.isEmpty {
            candidates = knownApps.filter { config in
                isInstalled(bundleId: config.bundleId)
            }
        }
        
        return candidates.first
    }
    
    /// 通过 URL Scheme 调度
    static func dispatchViaURLScheme(app: AIAppConfig, prompt: String) -> ExecutionResult {
        guard let scheme = app.urlScheme else {
            return .failure("该 App 不支持 URL Scheme")
        }
        
        // 尝试 URL Scheme
        if let url = URL(string: "\(scheme)open") {
            NSWorkspace.shared.open(url)
            return .success("✅ 已通过 URL Scheme 启动 \(app.name)")
        }
        
        return .failure("URL Scheme 调用失败")
    }
    
    /// 通过 AppleScript 调度（含 Prompt 注入）
    static func dispatchViaAppleScript(app: AIAppConfig, prompt: String) -> ExecutionResult {
        guard let template = app.appleScriptTemplate else {
            return .failure("该 App 不支持 AppleScript")
        }
        
        // 先检查 App 是否已安装
        guard isInstalled(bundleId: app.bundleId) else {
            return .failure("\(app.name) 未安装")
        }
        
        // 替换 Prompt 模板
        let escapedPrompt = prompt.replacingOccurrences(of: "\"", with: "\\\"")
        let script = template.replacingOccurrences(of: "{{PROMPT}}", with: escapedPrompt)
        
        return SystemAdapter.runAppleScript(script)
    }
    
    /// 自动选择最佳策略调度
    static func dispatch(task: String, prompt: String) -> ExecutionResult {
        guard let app = findBestApp(for: task) else {
            return .failure("未找到可用的 AI 应用\n\n建议安装 Cursor 或 ChatGPT")
        }
        
        // 优先级: URL Scheme > AppleScript > 直接启动
        if app.urlScheme != nil {
            let result = dispatchViaURLScheme(app: app, prompt: prompt)
            if result.isSuccess { return result }
        }
        
        if app.appleScriptTemplate != nil {
            let result = dispatchViaAppleScript(app: app, prompt: prompt)
            if result.isSuccess { return result }
        }
        
        // 兜底：直接启动
        let url = URL(fileURLWithPath: "/Applications/\(app.name).app")
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
            return .success("✅ 已启动 \(app.name)\n\n请手动输入:\n\(prompt)")
        }
        
        return .failure("无法调度 \(app.name)")
    }
    
    // MARK: - 辅助
    
    static func isInstalled(bundleId: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil
    }
}
