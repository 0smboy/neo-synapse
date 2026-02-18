// MARK: - Adapters/SystemAdapter.swift
// 系统操作适配器 - 系统设置、脚本执行、进程控制

import AppKit

/// 系统操作适配器
final class SystemAdapter {
    
    // MARK: - 系统设置 URL Scheme 映射
    private static let settingsMap: [(keywords: [String], url: String)] = [
        (["wifi", "无线", "网络", "network"],
         "x-apple.systempreferences:com.apple.preference.network"),
        (["蓝牙", "bluetooth"],
         "x-apple.systempreferences:com.apple.preferences.Bluetooth"),
        (["声音", "音量", "sound", "volume"],
         "x-apple.systempreferences:com.apple.preference.sound"),
        (["显示", "亮度", "display", "brightness"],
         "x-apple.systempreferences:com.apple.preference.displays"),
        (["壁纸", "桌面", "wallpaper", "desktop"],
         "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension"),
        (["安全", "隐私", "权限", "privacy", "security"],
         "x-apple.systempreferences:com.apple.preference.security"),
        (["键盘", "keyboard"],
         "x-apple.systempreferences:com.apple.preference.keyboard"),
        (["触控板", "trackpad"],
         "x-apple.systempreferences:com.apple.preference.trackpad"),
        (["电池", "电源", "battery", "power"],
         "x-apple.systempreferences:com.apple.preference.battery"),
        (["通知", "notification"],
         "x-apple.systempreferences:com.apple.preference.notifications"),
        (["存储", "storage"],
         "x-apple.systempreferences:com.apple.settings.Storage"),
    ]
    
    /// 打开系统设置
    static func openSettings(query: String) -> ExecutionResult {
        let lower = query.lowercased()
        
        var urlString = "x-apple.systempreferences:"
        for entry in settingsMap {
            if entry.keywords.contains(where: { lower.contains($0) }) {
                urlString = entry.url
                break
            }
        }
        
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
            return .success("✅ 已打开系统设置")
        }
        return .failure("无法打开系统设置")
    }
    
    // MARK: - AppleScript 执行
    
    static func runAppleScript(_ script: String) -> ExecutionResult {
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        let result = appleScript?.executeAndReturnError(&error)
        
        if let error = error {
            let msg = error[NSAppleScript.errorMessage] as? String ?? "未知错误"
            return .failure("AppleScript 错误: \(msg)")
        }
        
        let output = result?.stringValue ?? "执行成功"
        return .success("✅ \(output)")
    }
    
    // MARK: - 音量控制
    
    static func setVolume(level: Int) -> ExecutionResult {
        return runAppleScript("set volume output volume \(max(0, min(100, level)))")
    }
    
    static func toggleMute() -> ExecutionResult {
        return runAppleScript("""
            set curMuted to output muted of (get volume settings)
            set volume output muted (not curMuted)
            if curMuted then
                return "已取消静音"
            else
                return "已静音"
            end if
        """)
    }
    
    // MARK: - 进程控制
    
    /// 列出运行中的进程（前 N 个占用最多 CPU 的）
    static func listProcesses(top n: Int = 10) -> ExecutionResult {
        let task = Process()
        task.launchPath = "/usr/bin/top"
        task.arguments = ["-l", "1", "-n", "\(n)", "-stats", "pid,command,cpu,mem"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return .failure("无法读取进程信息")
            }
            
            // 提取进程列表部分
            let lines = output.components(separatedBy: "\n")
            let processLines = lines.suffix(n + 1).joined(separator: "\n")
            return .success("📊 活跃进程 (Top \(n)):\n\n\(processLines)")
        } catch {
            return .failure("获取进程列表失败: \(error.localizedDescription)")
        }
    }
    
    /// 终止进程
    static func killProcess(name: String, bundleIdentifier: String? = nil) -> ExecutionResult {
        let query = normalizeAppQuery(name)
        guard !query.isEmpty else {
            return .failure("请提供要关闭的应用名称")
        }

        let running = NSWorkspace.shared.runningApplications.filter { app in
            app.localizedName != nil || app.bundleIdentifier != nil
        }

        if let bundleIdentifier {
            let normalizedBundle = bundleIdentifier.lowercased()
            if let app = running.first(where: { ($0.bundleIdentifier ?? "").lowercased() == normalizedBundle }) {
                return terminateRunningApplication(app, fallbackName: name)
            }
        }

        let scoredMatches: [(app: NSRunningApplication, score: Int)] = running.compactMap { app in
            let appName = app.localizedName ?? ""
            let normalizedName = normalizeAppQuery(appName)
            let normalizedBundle = normalizeAppQuery(app.bundleIdentifier ?? "")
            guard !normalizedName.isEmpty || !normalizedBundle.isEmpty else { return nil }

            var score = 0
            if normalizedName == query { score = max(score, 1000) }
            if normalizedName.hasPrefix(query) { score = max(score, 920) }
            if normalizedName.contains(query) { score = max(score, 820) }
            if normalizedBundle.contains(query) { score = max(score, 760) }
            if isSubsequence(query, in: normalizedName) { score = max(score, 700) }
            if score == 0 { return nil }
            return (app, score)
        }

        if let best = scoredMatches.sorted(by: { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return (lhs.app.localizedName ?? "") < (rhs.app.localizedName ?? "")
        }).first {
            return terminateRunningApplication(best.app, fallbackName: name)
        }

        return .failure("未找到运行中的应用「\(name)」")
    }

    private static func terminateRunningApplication(
        _ app: NSRunningApplication,
        fallbackName: String
    ) -> ExecutionResult {
        let appName = app.localizedName ?? fallbackName
        if app.terminate() || app.forceTerminate() {
            return .success("✅ 已关闭 \(appName)")
        }
        return .failure("无法关闭 \(appName)")
    }

    private static func normalizeAppQuery(_ raw: String) -> String {
        let folded = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: .current)
        return folded.replacingOccurrences(
            of: #"[^a-z0-9\u4e00-\u9fa5]+"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func isSubsequence(_ pattern: String, in target: String) -> Bool {
        guard !pattern.isEmpty else { return false }
        var index = target.startIndex
        for char in pattern {
            guard let found = target[index...].firstIndex(of: char) else { return false }
            index = target.index(after: found)
        }
        return true
    }
    
    // MARK: - 文件操作
    
    /// 在 Finder 中显示文件
    static func revealInFinder(path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return true
    }
    
    /// 移动文件
    static func moveFile(from source: String, to destination: String) -> ExecutionResult {
        do {
            try FileManager.default.moveItem(atPath: source, toPath: destination)
            return .success("✅ 已移动文件到 \(destination)")
        } catch {
            return .failure("移动失败: \(error.localizedDescription)")
        }
    }
    
    /// 复制文件
    static func copyFile(from source: String, to destination: String) -> ExecutionResult {
        do {
            try FileManager.default.copyItem(atPath: source, toPath: destination)
            return .success("✅ 已复制文件到 \(destination)")
        } catch {
            return .failure("复制失败: \(error.localizedDescription)")
        }
    }
    
    /// 删除文件（移到废纸篓）
    static func trashFile(path: String) -> ExecutionResult {
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            return .success("✅ 已将文件移到废纸篓")
        } catch {
            return .failure("删除失败: \(error.localizedDescription)")
        }
    }
    
    /// 压缩文件
    static func compressFile(path: String) -> ExecutionResult {
        let task = Process()
        task.launchPath = "/usr/bin/zip"
        task.arguments = ["-r", "\(path).zip", path]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                return .success("✅ 已压缩为 \(path).zip")
            } else {
                return .failure("压缩失败")
            }
        } catch {
            return .failure("压缩失败: \(error.localizedDescription)")
        }
    }
}
