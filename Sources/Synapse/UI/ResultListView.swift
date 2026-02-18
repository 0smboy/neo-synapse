// MARK: - UI/ResultListView.swift
// 结果展示区 — 内联结果 + 执行状态

import SwiftUI
import AppKit
import Foundation

struct ResultListView: View {
    private enum AIBlock {
        case heading(String)
        case bullet(String)
        case numbered(index: String, text: String)
        case paragraph(String)
        case code(String)
        case divider
    }
    
    private struct BatterySnapshot {
        let level: Int
        let health: Int?
        let isCharging: Bool
        let statusText: String
        let remaining: String
        let source: String?
        let cycles: Int?
        let temperature: Double?
    }
    
    let intent: RecognizedIntent?
    let executionResult: ExecutionResult?
    let isExecuting: Bool
    let matchedApps: [AppInfo]
    let selectedAppIndex: Int
    let inlineText: String
    let onSelect: (AppInfo) -> Void
    
    @AppStorage(SynapseSettings.Keys.richAIFormatting) private var richAIFormatting = SynapseSettings.defaultRichAIFormatting
    @AppStorage(SynapseSettings.Keys.aiVisualStyle) private var aiVisualStyle = SynapseSettings.defaultAIVisualStyle
    
    private var hasFileResults: Bool {
        !(executionResult?.fileResults?.isEmpty ?? true)
    }
    
    private var isAIIntent: Bool {
        intent?.domain == .aiCapability
    }
    
    private var systemCommandID: String? {
        intent?.parameters["commandID"]
    }
    
    private var copyableText: String? {
        if !inlineText.isEmpty { return inlineText }
        if let output = executionResult?.output, !output.isEmpty { return output }
        return nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            // 执行中
            if isExecuting {
                executingView
            }
            
            // 文件搜索结果（结构化展示，支持点击打开）
            if let files = executionResult?.fileResults, !files.isEmpty, !isExecuting {
                fileSearchResultView(files)
            }
            
            // 内联文本结果
            if !inlineText.isEmpty && !isExecuting && !hasFileResults {
                if isAIIntent {
                    aiInlineResultView
                } else {
                    inlineResultView
                }
            }
            
            // 意图预览标题
            if let intent = intent, inlineText.isEmpty, !isExecuting, !hasFileResults {
                intentPreview(intent)
            }
            
            // 匹配的 App 列表
            if !matchedApps.isEmpty {
                appListView
            }
            
            // 执行结果
            if let result = executionResult, inlineText.isEmpty, !hasFileResults {
                if isAIIntent {
                    aiResultView(result)
                } else {
                    resultView(result)
                }
            }
            
            // 操作提示
            if !isExecuting, !hasFileResults, let copyText = copyableText {
                copyActionRow(copyText)
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - 内联结果
    
    private var inlineResultView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let intent = intent {
                Text(intent.displayTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
            }

            if let commandID = systemCommandID {
                systemCommandInlineView(commandID, text: inlineText)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            } else if intent?.parameters["type"] == "color" {
                colorInlineView(inlineText)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            } else {
                Text(inlineText)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func colorInlineView(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let hex = extractHex(text), let swatch = color(from: hex) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(swatch)
                    .frame(height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(TerminalTheme.line, lineWidth: 0.8)
                    )
            }
            
            Text(text)
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func extractHex(_ text: String) -> String? {
        let pattern = #"HEX:\s*#([0-9A-Fa-f]{6})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let hexRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[hexRange]).uppercased()
    }

    private func color(from hex: String) -> Color? {
        guard let value = Int(hex, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        return Color(nsColor: NSColor(calibratedRed: r, green: g, blue: b, alpha: 1.0))
    }
    
    @ViewBuilder
    private func systemCommandInlineView(_ commandID: String, text: String) -> some View {
        switch commandID {
        case "ip":
            ipInlineView(text)
        case "battery":
            batteryInlineView(text)
        case "date":
            dateInlineView(text)
        default:
            Text(text)
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private func ipInlineView(_ text: String) -> some View {
        let parsed = parseIPInfo(text)
        
        return VStack(alignment: .leading, spacing: 8) {
            if !parsed.local.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("本机网络")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    ForEach(Array(parsed.local.enumerated()), id: \.offset) { _, ip in
                        HStack(spacing: 8) {
                            Image(systemName: "wifi")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.accentColor)
                            Text(ip)
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            
            if let publicIP = parsed.publicIP {
                VStack(alignment: .leading, spacing: 4) {
                    Text("公网地址")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.cyan)
                        Text(publicIP)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                    }
                }
            }
            
            if parsed.local.isEmpty && parsed.publicIP == nil {
                Text(text)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TerminalTheme.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(TerminalTheme.line, lineWidth: 0.8)
        )
    }
    
    private func batteryInlineView(_ text: String) -> some View {
        let snapshot = parseBatteryInfo(text) ?? BatterySnapshot(
            level: 0,
            health: nil,
            isCharging: false,
            statusText: "Unknown",
            remaining: "--:--",
            source: nil,
            cycles: nil,
            temperature: nil
        )
        
        let level = snapshot.level
        let charging = snapshot.isCharging
        let metaLine = batteryMetaLine(snapshot)
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: charging ? "bolt.batteryblock.fill" : "battery.100percent")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(charging ? .green : batteryColor(level: level))
                
                Text("Power")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(level)%")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
            }
            
            batteryMetricRow(label: "Level", value: level, tint: batteryColor(level: level))
            
            if let health = snapshot.health {
                batteryMetricRow(label: "Health", value: health, tint: .mint)
            }
            
            Text("\(snapshot.statusText) · \(snapshot.remaining)\(charging ? " ⚡" : "")")
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .foregroundColor(charging ? .green : .secondary)
            
            if !metaLine.isEmpty {
                Text(metaLine)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TerminalTheme.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(TerminalTheme.line, lineWidth: 0.8)
        )
    }
    
    private func batteryMetricRow(label: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 54, alignment: .leading)
            
            GeometryReader { geo in
                let ratio = CGFloat(max(0, min(100, value))) / 100.0
                let barWidth = ratio * geo.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(0.10))
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(tint.opacity(0.85))
                        .frame(width: barWidth)
                }
            }
            .frame(height: 10)
            
            Text("\(value)%")
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
                .frame(width: 56, alignment: .trailing)
        }
    }
    
    private func batteryMetaLine(_ snapshot: BatterySnapshot) -> String {
        var parts: [String] = []
        
        if let source = snapshot.source, !source.isEmpty {
            parts.append(source)
        }
        if let cycles = snapshot.cycles {
            parts.append("\(cycles) cycles")
        }
        if let temp = snapshot.temperature {
            parts.append(String(format: "%.1f°C", temp))
        }
        
        return parts.joined(separator: " · ")
    }
    
    private func dateInlineView(_ text: String) -> some View {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let primary = lines.first ?? text
        let secondary = lines.dropFirst().joined(separator: " · ")
        
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.red)
                Text(primary)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
            }
            if !secondary.isEmpty {
                Text(secondary)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TerminalTheme.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(TerminalTheme.line, lineWidth: 0.8)
        )
    }
    
    private func batteryColor(level: Int) -> Color {
        if level >= 70 { return .green }
        if level >= 35 { return .yellow }
        return .red
    }
    
    private func parseIPInfo(_ text: String) -> (local: [String], publicIP: String?) {
        var localIPs: [String] = []
        var publicIP: String?
        
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        for line in lines {
            let lower = line.lowercased()
            let ips = extractIPv4(line)
            
            if line.hasPrefix("本机:") {
                localIPs.append(contentsOf: ips)
                continue
            }
            if line.hasPrefix("公网:") || lower.contains("public") {
                if let first = ips.first {
                    publicIP = first
                }
                continue
            }
            
            for ip in ips {
                if isPrivateIPv4(ip) {
                    localIPs.append(ip)
                } else if publicIP == nil {
                    publicIP = ip
                }
            }
        }
        
        let dedupedLocal = Array(Set(localIPs)).sorted()
        return (dedupedLocal, publicIP)
    }
    
    private func parseBatteryInfo(_ text: String) -> BatterySnapshot? {
        let payload = parseKeyValuePayload(text)
        if let levelValue = payload["BATTERY_LEVEL"], let level = Int(levelValue) {
            let statusRaw = (payload["BATTERY_STATUS"] ?? "unknown").lowercased()
            let source = payload["BATTERY_SOURCE"]
            let isCharging = payload["BATTERY_CHARGING"] == "1"
                || statusRaw.contains("charg")
                || (source?.lowercased().contains("ac power") ?? false)
            
            let statusText: String = {
                if statusRaw.contains("charged") { return "Charged" }
                if statusRaw.contains("charging") { return "Charging" }
                if statusRaw.contains("discharging") { return "Discharging" }
                if statusRaw.contains("finishing") { return "Finishing" }
                return statusRaw.capitalized
            }()
            
            let health = Int(payload["BATTERY_HEALTH"] ?? "")
            let cycles = Int(payload["BATTERY_CYCLES"] ?? "")
            let temp = Double(payload["BATTERY_TEMP"] ?? "")
            let remaining = payload["BATTERY_REMAINING"] ?? "--:--"
            
            return BatterySnapshot(
                level: level,
                health: health,
                isCharging: isCharging,
                statusText: statusText,
                remaining: remaining,
                source: source,
                cycles: cycles,
                temperature: temp
            )
        }
        
        guard let regex = try? NSRegularExpression(pattern: #"([0-9]{1,3})%"#) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let percentRange = Range(match.range(at: 1), in: text),
              let level = Int(text[percentRange]) else {
            return nil
        }
        
        let lower = text.lowercased()
        let isCharging = lower.contains("charging") || lower.contains("ac power") || lower.contains("charged")
        return BatterySnapshot(
            level: level,
            health: nil,
            isCharging: isCharging,
            statusText: isCharging ? "Charging" : "Battery",
            remaining: "--:--",
            source: nil,
            cycles: nil,
            temperature: nil
        )
    }
    
    private func parseKeyValuePayload(_ text: String) -> [String: String] {
        var map: [String: String] = [:]
        
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("BATTERY_"),
                  let eq = line.firstIndex(of: "=") else { continue }
            
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            map[key] = value
        }
        
        return map
    }
    
    private func extractIPv4(_ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        return matches.compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return String(text[swiftRange])
        }
    }
    
    private func isPrivateIPv4(_ ip: String) -> Bool {
        let chunks = ip.split(separator: ".").compactMap { Int($0) }
        guard chunks.count == 4 else { return false }
        if chunks[0] == 10 { return true }
        if chunks[0] == 172, (16...31).contains(chunks[1]) { return true }
        if chunks[0] == 192, chunks[1] == 168 { return true }
        return false
    }
    
    private var aiInlineResultView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let intent = intent {
                Text(intent.displayTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
            }
            
            aiCard {
                formattedAIResponse(inlineText)
            }
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
        }
    }
    
    // MARK: - 文件结果
    
    private func fileSearchResultView(_ files: [FileSearchResult]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("🔍 找到 \(files.count) 个结果（点击路径可直接打开）")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 4)
            
            ForEach(Array(files.prefix(20).enumerated()), id: \.offset) { _, file in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(file.icon)
                            .font(.system(size: 15))
                        Text(file.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(TerminalTheme.textPrimary)
                        Text(file.sizeString)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(TerminalTheme.textSecondary)
                        Spacer()
                    }
                    
                    Button(action: { openFile(file.path) }) {
                        Text(file.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(TerminalTheme.accentSoft)
                            .lineLimit(2)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.32))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(TerminalTheme.line, lineWidth: 0.7)
                )
                .padding(.horizontal, 8)
            }
        }
    }
    
    private func openFile(_ path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }
    
    // MARK: - 意图预览
    
    private func intentPreview(_ intent: RecognizedIntent) -> some View {
        HStack(spacing: 8) {
                Text(intent.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
            
            Spacer()
            
            Text("\(Int(intent.confidence * 100))%")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
            
            Text("↵")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.1))
                .cornerRadius(4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
    
    // MARK: - App 列表
    
    private var appListView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(matchedApps.prefix(5).enumerated()), id: \.offset) { idx, app in
                Button(action: { onSelect(app) }) {
                    HStack(spacing: 10) {
                        // App 图标
                        if let icon = NSWorkspace.shared.icon(forFile: app.path) as NSImage? {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 24, height: 24)
                        }
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                            Text(app.path)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        if idx == selectedAppIndex {
                            Text("↵")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white.opacity(0.5))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(idx == selectedAppIndex ? Color.accentColor.opacity(0.16) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - 执行中
    
    private var executingView: some View {
        HStack(spacing: 10) {
            GlowingBrainIndicator(color: statusColorForExecuting)
            
            Text(executingMessage)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    private var executingMessage: String {
        guard let intent else { return "执行中..." }
        
        switch intent.action {
        case .findFile:
            return "正在搜索文件..."
        case .launchApp:
            return "正在启动程序..."
        case .closeApp:
            return "正在关闭程序..."
        case .systemCommand:
            let command = intent.parameters["command"] ?? "系统命令"
            return "正在执行 \(command)..."
        case .knowledgeQuery:
            return "正在检索知识..."
        case .webSearch:
            return "正在联网搜索..."
        case .translateText:
            return "正在翻译内容..."
        case .codeWrite, .codeDebug, .scriptExec:
            return "正在编写代码..."
        case .contentCreate, .contentRewrite:
            return "正在撰写内容..."
        case .conversationHistory:
            return "正在读取历史对话..."
        case .memoryRecall:
            return "正在读取 Memory..."
        case .memoryRemember:
            return "正在写入 Memory..."
        case .memoryClear:
            return "正在清空 Memory..."
        case .memoryTree:
            return "正在构建记忆文件树..."
        case .sessionList:
            return "正在读取会话列表..."
        default:
            return "执行中..."
        }
    }
    
    private var statusColorForExecuting: Color {
        guard let intent else { return .cyan }
        switch intent.action {
        case .findFile: return .orange
        case .launchApp, .systemCommand: return .blue
        case .codeWrite, .codeDebug, .scriptExec: return .green
        case .knowledgeQuery, .translateText, .webSearch: return .cyan
        case .contentCreate, .contentRewrite: return .mint
        case .conversationHistory, .memoryRecall, .memoryRemember, .memoryClear,
             .memoryTree, .sessionList: return .mint
        default: return .secondary
        }
    }
    
    private func copyActionRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            Spacer()
            
            Text("↵ 复制")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.7))
            
            Button(action: { copyToClipboard(text) }) {
                Label("复制", systemImage: "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(TerminalTheme.chipBG)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundColor(.primary)
            .help("复制结果到剪贴板")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
    
    private func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
    
    // MARK: - 执行结果
    
    private func resultView(_ result: ExecutionResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result.output ?? "完成")
                .font(.system(size: 13))
                .foregroundColor(result.isSuccess ? .green : .red)
                .textSelection(.enabled)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
        }
    }
    
    private func aiResultView(_ result: ExecutionResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            aiCard {
                formattedAIResponse(result.output ?? "完成")
            }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
        }
    }
    
    // MARK: - AI 富文本格式化
    
    @ViewBuilder
    private func aiCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            // Matrix rain background
            if isMatrixStyle {
                MatrixRainBackground(columnCount: 25)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .opacity(0.15)
            }
            
            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(aiCardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isMatrixStyle ? Color.green.opacity(0.45) : TerminalTheme.line, lineWidth: 0.8)
        )
        .modifier(ConditionalMatrixGlowModifier(isMatrix: isMatrixStyle))
        .overlay {
            if isMatrixStyle {
                AnimatedMatrixScanlineOverlay()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .shadow(color: isMatrixStyle ? Color.green.opacity(0.20) : .clear, radius: isMatrixStyle ? 8 : 0)
    }
    
    @ViewBuilder
    private func formattedAIResponse(_ text: String) -> some View {
        let prepared = normalizedAITextForDisplay(text)
        if richAIFormatting,
           let attributed = try? AttributedString(
               markdown: prepared,
               options: AttributedString.MarkdownParsingOptions(
                   interpretedSyntax: .full,
                   failurePolicy: .returnPartiallyParsedIfPossible
               )
           ) {
            Text(attributed)
                .font(isMatrixStyle ? .system(size: 14, design: .monospaced) : .system(size: 14))
                .foregroundColor(isMatrixStyle ? .green.opacity(0.95) : .primary)
                .lineSpacing(isMatrixStyle ? 7 : 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        } else {
            Text(prepared)
                .font(isMatrixStyle ? .system(size: 14, design: .monospaced) : .system(size: 14))
                .foregroundColor(isMatrixStyle ? .green.opacity(0.95) : .primary)
                .lineSpacing(isMatrixStyle ? 7 : 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func normalizedAITextForDisplay(_ text: String) -> String {
        var output = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !output.isEmpty else { return output }

        let hasMarkdownStructure = output.contains("\n#") || output.contains("- ") || output.contains("1.")
        if !hasMarkdownStructure {
            output = output.replacingOccurrences(
                of: #"(?<![#\n])(结论|要点|建议|步骤|风险|总结|说明)\s*[:：]?"#,
                with: "\n## $1\n",
                options: .regularExpression
            )
            output = output.replacingOccurrences(
                of: #"(?<!\n)(\d+[\.、])\s*"#,
                with: "\n$1 ",
                options: .regularExpression
            )
            output = output.replacingOccurrences(
                of: #"([。！？])\s*(?=[^\n])"#,
                with: "$1\n\n",
                options: .regularExpression
            )
        }

        output = output.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)

        if isMatrixStyle {
            // Generate dynamic Matrix-style headers
            let signalStrength = Int.random(in: 85...100)
            let decryptionStatus = ["COMPLETE", "VERIFIED", "SECURED"].randomElement() ?? "COMPLETE"
            let accessStatus = ["GRANTED", "AUTHORIZED", "ACTIVE"].randomElement() ?? "GRANTED"
            
            let header = """
## MATRIX::OUTPUT
> ACCESS_GRANTED: \(accessStatus)
> SIGNAL_STRENGTH: \(signalStrength)%
> DECRYPTION: \(decryptionStatus)
> NEURAL_LINK: ONLINE
> TIMESTAMP: \(formatMatrixTimestamp())

"""
            
            if !output.hasPrefix("## MATRIX::OUTPUT") {
                output = header + output
            }
        }

        return output
    }
    
    private func formatMatrixTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }

    private var isMatrixStyle: Bool {
        aiVisualStyle.lowercased() == "matrix"
    }

    private var aiCardFill: AnyShapeStyle {
        if isMatrixStyle {
            return AnyShapeStyle(matrixCardFill)
        }
        return AnyShapeStyle(TerminalTheme.cardFill)
    }

    private var matrixCardFill: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.03, green: 0.08, blue: 0.04),
                Color(red: 0.02, green: 0.06, blue: 0.03),
                Color(red: 0.01, green: 0.04, blue: 0.02),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    @ViewBuilder
    private func aiBlockView(_ block: AIBlock) -> some View {
        switch block {
        case .heading(let title):
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.accentColor)
                .textSelection(.enabled)
        case .bullet(let text):
            HStack(alignment: .top, spacing: 7) {
                Text("•")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.secondary)
                markdownText(text, font: .system(size: 14), color: .primary)
            }
        case .numbered(let index, let text):
            HStack(alignment: .top, spacing: 7) {
                Text("\(index).")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                markdownText(text, font: .system(size: 14), color: .primary)
            }
        case .paragraph(let text):
            markdownText(text, font: .system(size: 14), color: .primary)
        case .code(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(TerminalTheme.line, lineWidth: 0.7)
            )
        case .divider:
            Rectangle()
                .fill(TerminalTheme.line)
                .frame(height: 1)
        }
    }
    
    private func parseAIBlocks(_ text: String) -> [AIBlock] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var blocks: [AIBlock] = []
        var insideCode = false
        var codeLines: [String] = []
        
        for rawLine in normalized.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmed.hasPrefix("```") {
                if insideCode {
                    if !codeLines.isEmpty {
                        blocks.append(.code(codeLines.joined(separator: "\n")))
                        codeLines.removeAll()
                    }
                    insideCode = false
                } else {
                    insideCode = true
                }
                continue
            }
            
            if insideCode {
                codeLines.append(rawLine)
                continue
            }
            
            if trimmed.isEmpty {
                continue
            }
            
            if ["---", "——", "___"].contains(trimmed) {
                blocks.append(.divider)
                continue
            }
            
            if isSemanticHeading(trimmed) {
                blocks.append(.heading(trimmed))
                continue
            }
            
            if trimmed.hasPrefix("#") {
                let title = trimmed.replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
                blocks.append(.heading(title))
                continue
            }
            
            if let bullet = parseBulletLine(trimmed) {
                blocks.append(.bullet(bullet))
                continue
            }
            
            if let numbered = parseNumberedLine(trimmed) {
                blocks.append(.numbered(index: numbered.index, text: numbered.text))
                continue
            }
            
            blocks.append(.paragraph(trimmed))
        }
        
        if insideCode, !codeLines.isEmpty {
            blocks.append(.code(codeLines.joined(separator: "\n")))
        }
        return blocks.isEmpty ? [.paragraph(text)] : blocks
    }
    
    private func parseBulletLine(_ line: String) -> String? {
        let prefixes = ["- ", "* ", "• ", "· "]
        for prefix in prefixes where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
    
    private func parseNumberedLine(_ line: String) -> (index: String, text: String)? {
        let chars = Array(line)
        var i = 0
        var digits = ""
        
        while i < chars.count, chars[i].isNumber {
            digits.append(chars[i])
            i += 1
        }
        
        guard !digits.isEmpty, i < chars.count else { return nil }
        let separator = chars[i]
        guard separator == "." || separator == "、" || separator == ")" else { return nil }
        i += 1
        
        while i < chars.count, chars[i].isWhitespace {
            i += 1
        }
        
        guard i < chars.count else { return nil }
        let text = String(chars[i...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : (digits, text)
    }
    
    @ViewBuilder
    private func markdownText(_ text: String, font: Font, color: Color) -> some View {
        if richAIFormatting,
           let attributed = try? AttributedString(
               markdown: text,
               options: AttributedString.MarkdownParsingOptions(
                   interpretedSyntax: .inlineOnlyPreservingWhitespace,
                   failurePolicy: .returnPartiallyParsedIfPossible
               )
           ) {
            Text(attributed)
                .font(font)
                .foregroundColor(color)
                .textSelection(.enabled)
        } else {
            Text(text)
                .font(font)
                .foregroundColor(color)
                .textSelection(.enabled)
        }
    }
    
    private func isSemanticHeading(_ line: String) -> Bool {
        let normalized = line
            .replacingOccurrences(of: "：", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ["结论", "要点", "总结", "步骤", "建议", "风险", "说明", "原因"].contains(normalized)
    }
}

// MatrixScanlineOverlay has been replaced with AnimatedMatrixScanlineOverlay in TerminalTheme.swift

private struct ConditionalMatrixGlowModifier: ViewModifier {
    let isMatrix: Bool
    
    func body(content: Content) -> some View {
        if isMatrix {
            content.matrixGlowPulseBorder()
        } else {
            content
        }
    }
}

private struct GlowingBrainIndicator: View {
    let color: Color
    @State private var glowing = false
    
    var body: some View {
        ZStack {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .scaleEffect(glowing ? 1.08 : 0.94)
                .shadow(color: color.opacity(glowing ? 0.80 : 0.20), radius: glowing ? 7 : 1)
            
            Image(systemName: "brain.head.profile")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .scaleEffect(glowing ? 1.22 : 1.02)
                .opacity(glowing ? 0.20 : 0.05)
                .blur(radius: glowing ? 3 : 0)
        }
        .frame(width: 22, height: 22)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                glowing = true
            }
        }
    }
}
