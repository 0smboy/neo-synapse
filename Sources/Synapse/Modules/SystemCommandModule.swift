// MARK: - Modules/SystemCommandModule.swift
// 系统命令模块 - 锁屏/休眠/截图/清废纸篓/弹出磁盘/暗黑模式

import AppKit

/// 系统命令（Raycast 风格）
final class SystemCommandModule {
    
    struct SystemCommand {
        let id: String
        let keywords: [String]
        let title: String
        let icon: String
        let action: () -> ExecutionResult
    }
    
    lazy var commands: [SystemCommand] = [
        SystemCommand(
            id: "lock",
            keywords: ["锁屏", "lock", "lock screen"],
            title: "锁定屏幕",
            icon: "lock",
            action: {
                let task = Process()
                task.launchPath = "/usr/bin/pmset"
                task.arguments = ["displaysleepnow"]
                try? task.run()
                return .success("✅ 已锁定屏幕")
            }
        ),
        SystemCommand(
            id: "sleep",
            keywords: ["休眠", "sleep", "睡眠"],
            title: "休眠",
            icon: "moon.zzz",
            action: {
                let script = "tell application \"System Events\" to sleep"
                return SystemAdapter.runAppleScript(script)
            }
        ),
        SystemCommand(
            id: "screenshot",
            keywords: ["截图", "screenshot", "截屏"],
            title: "截图",
            icon: "camera",
            action: {
                let task = Process()
                task.launchPath = "/usr/sbin/screencapture"
                task.arguments = ["-i", "-c"] // 交互截图到剪贴板
                try? task.run()
                return .success("✅ 请框选截图区域")
            }
        ),
        SystemCommand(
            id: "trash",
            keywords: ["废纸篓", "清空回收站", "empty trash", "trash"],
            title: "清空废纸篓",
            icon: "trash",
            action: {
                let script = """
                    tell application "Finder"
                        empty the trash
                    end tell
                """
                let scriptResult = SystemAdapter.runAppleScript(script)
                if scriptResult.isSuccess { return .success("✅ 已清空废纸篓") }
                return Self.fallbackEmptyTrash()
            }
        ),
        SystemCommand(
            id: "eject",
            keywords: ["弹出", "eject", "推出磁盘"],
            title: "弹出磁盘",
            icon: "eject",
            action: {
                let script = """
                    tell application "Finder"
                        eject (every disk whose ejectable is true)
                    end tell
                """
                return SystemAdapter.runAppleScript(script)
            }
        ),
        SystemCommand(
            id: "darkmode",
            keywords: ["暗黑", "深色", "dark mode", "dark", "夜间模式"],
            title: "切换暗黑模式",
            icon: "moon",
            action: {
                let script = """
                    tell application "System Events"
                        tell appearance preferences
                            set dark mode to not dark mode
                        end tell
                    end tell
                """
                return SystemAdapter.runAppleScript(script)
            }
        ),
        SystemCommand(
            id: "dnd",
            keywords: ["勿扰", "dnd", "do not disturb", "免打扰"],
            title: "切换勿扰模式",
            icon: "bell.slash",
            action: {
                let script = """
                    tell application "System Events"
                        keystroke "D" using {command down, shift down, control down}
                    end tell
                """
                return SystemAdapter.runAppleScript(script)
            }
        ),
        SystemCommand(
            id: "shutdown",
            keywords: ["关机", "shutdown", "关闭电脑"],
            title: "关机",
            icon: "power",
            action: {
                let script = """
                    tell application "System Events"
                        shut down
                    end tell
                """
                return SystemAdapter.runAppleScript(script)
            }
        ),
        SystemCommand(
            id: "restart",
            keywords: ["重启", "restart", "reboot"],
            title: "重启",
            icon: "arrow.counterclockwise",
            action: {
                let script = """
                    tell application "System Events"
                        restart
                    end tell
                """
                return SystemAdapter.runAppleScript(script)
            }
        ),
        SystemCommand(
            id: "quit_synapse",
            keywords: ["退出synapse", "quit synapse", "quit", "退出", "离开synapse", "exit synapse"],
            title: "退出 Synapse",
            icon: "xmark.circle",
            action: {
                DispatchQueue.main.async {
                    ClipboardModule.shared.stopMonitoring()
                    NSApp.terminate(nil)
                }
                return .success("👋 正在退出 Synapse")
            }
        ),
        SystemCommand(
            id: "ip",
            keywords: ["ip", "ip地址", "网络地址"],
            title: "IP 信息",
            icon: "network",
            action: {
                let localRaw = Self.capture("/bin/zsh", arguments: [
                    "-lc",
                    "ifconfig | awk '/inet / && $2 != \"127.0.0.1\" {print $2}' | sort -u"
                ])
                let localIPs = localRaw
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                
                let publicIP = Self.capture("/bin/zsh", arguments: [
                    "-lc",
                    "curl -s --max-time 2 ifconfig.me 2>/dev/null"
                ]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                var lines: [String] = []
                lines.append("本机: \(localIPs.isEmpty ? "未获取到" : localIPs.joined(separator: "  "))")
                lines.append("公网: \(publicIP.isEmpty ? "暂不可用" : publicIP)")
                return .success(lines.joined(separator: "\n"))
            }
        ),
        SystemCommand(
            id: "battery",
            keywords: ["电池", "battery", "电量"],
            title: "电池信息",
            icon: "battery.100",
            action: {
                guard let snapshot = Self.batterySnapshotPayload() else {
                    return .failure("获取电池状态失败")
                }
                return .success(snapshot)
            }
        ),
        SystemCommand(
            id: "disk",
            keywords: ["存储", "磁盘", "disk", "storage", "空间"],
            title: "磁盘空间",
            icon: "internaldrive",
            action: {
                let task = Process()
                let pipe = Pipe()
                task.launchPath = "/bin/df"
                task.arguments = ["-h", "/"]
                task.standardOutput = pipe
                
                do {
                    try task.run()
                    task.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? "获取失败"
                    return .success("💾 磁盘空间\n\n\(output)")
                } catch {
                    return .failure("获取磁盘空间失败")
                }
            }
        ),
        SystemCommand(
            id: "date",
            keywords: ["日期", "时间", "date", "time", "几点", "今天"],
            title: "日期时间",
            icon: "calendar",
            action: {
                let fmt = DateFormatter()
                fmt.locale = Locale(identifier: "zh_CN")
                fmt.dateFormat = "yyyy年MM月dd日 EEEE HH:mm:ss"
                let dateStr = fmt.string(from: Date())
                
                // 农历
                let cal = Calendar(identifier: .chinese)
                let components = cal.dateComponents([.year, .month, .day], from: Date())
                
                let months = ["正月","二月","三月","四月","五月","六月","七月","八月","九月","十月","冬月","腊月"]
                let days = ["初一","初二","初三","初四","初五","初六","初七","初八","初九","初十",
                           "十一","十二","十三","十四","十五","十六","十七","十八","十九","二十",
                           "廿一","廿二","廿三","廿四","廿五","廿六","廿七","廿八","廿九","三十"]
                
                var lunarStr = ""
                if let m = components.month, let d = components.day, m > 0, m <= 12, d > 0, d <= 30 {
                    lunarStr = "农历 \(months[m-1])\(days[d-1])"
                }
                
                return .success("\(dateStr)\n\(lunarStr)")
            }
        ),
    ]

    private static func fallbackEmptyTrash() -> ExecutionResult {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = [
            "-lc",
            "rm -rf ~/.Trash/* ~/.Trash/.[!.]* ~/.Trash/..?* 2>/dev/null; exit 0"
        ]
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            return .success("✅ 已清空废纸篓")
        } catch {
            return .failure("清空废纸篓失败: \(error.localizedDescription)")
        }
    }
    
    private static func capture(_ executablePath: String, arguments: [String]) -> String {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: executablePath)
        task.arguments = arguments
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
    
    private static func batterySnapshotPayload() -> String? {
        let pmsetOutput = capture("/usr/bin/pmset", arguments: ["-g", "batt"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pmsetOutput.isEmpty else { return nil }
        
        let lines = pmsetOutput
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        let source = lines.first.flatMap { extractRegex(#"'([^']+)'"#, from: $0) } ?? "Unknown"
        let detailLine = lines.dropFirst().first ?? ""
        let level = Int(extractRegex(#"([0-9]{1,3})%"#, from: detailLine) ?? "") ?? 0
        
        let detailParts = detailLine
            .components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let statusRaw = detailParts.count > 1 ? detailParts[1].lowercased() : "unknown"
        let remainingRaw = detailParts.count > 2 ? detailParts[2].lowercased() : ""
        let remaining = remainingRaw
            .replacingOccurrences(of: "remaining", with: "")
            .replacingOccurrences(of: "present: true", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let ioregOutput = capture("/usr/sbin/ioreg", arguments: ["-rn", "AppleSmartBattery"])
        let cycleCount = Int(extractRegex(#""CycleCount"\s*=\s*([0-9]+)"#, from: ioregOutput) ?? "")
        let designCapacity = Double(extractRegex(#""DesignCapacity"\s*=\s*([0-9]+)"#, from: ioregOutput) ?? "")
        let rawMaxCapacity = Double(extractRegex(#""AppleRawMaxCapacity"\s*=\s*([0-9]+)"#, from: ioregOutput) ?? "")
        let temperatureRaw = Double(extractRegex(#""Temperature"\s*=\s*([0-9]+)"#, from: ioregOutput) ?? "")
        
        let healthPercent: Int? = {
            guard let designCapacity, let rawMaxCapacity, designCapacity > 0 else { return nil }
            return Int((rawMaxCapacity / designCapacity * 100.0).rounded())
        }()
        let tempCelsius: String? = {
            guard let temperatureRaw, temperatureRaw > 0 else { return nil }
            return String(format: "%.1f", temperatureRaw / 100.0)
        }()
        
        let isCharging = statusRaw.contains("charging")
            || statusRaw.contains("charged")
            || source.lowercased().contains("ac power")
        
        var payload: [String] = []
        payload.append("BATTERY_LEVEL=\(level)")
        payload.append("BATTERY_CHARGING=\(isCharging ? "1" : "0")")
        payload.append("BATTERY_STATUS=\(statusRaw.isEmpty ? "unknown" : statusRaw)")
        payload.append("BATTERY_REMAINING=\(remaining.isEmpty ? "--:--" : remaining)")
        payload.append("BATTERY_SOURCE=\(source)")
        if let healthPercent { payload.append("BATTERY_HEALTH=\(healthPercent)") }
        if let cycleCount { payload.append("BATTERY_CYCLES=\(cycleCount)") }
        if let tempCelsius { payload.append("BATTERY_TEMP=\(tempCelsius)") }
        
        return payload.joined(separator: "\n")
    }
    
    private static func extractRegex(_ pattern: String, from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let capturedRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[capturedRange])
    }
    
    /// 查找匹配的系统命令
    func findCommand(_ query: String) -> SystemCommand? {
        let lower = query.lowercased()
        return commands.first { cmd in
            cmd.keywords.contains(where: { lower.contains($0) })
        }
    }
    
    /// 获取所有命令（模糊过滤）
    func search(_ query: String) -> [SystemCommand] {
        let lower = query.lowercased()
        if lower.isEmpty { return commands }
        return commands.filter { cmd in
            cmd.keywords.contains(where: { $0.contains(lower) || lower.contains($0) }) ||
            cmd.title.lowercased().contains(lower)
        }
    }
}
