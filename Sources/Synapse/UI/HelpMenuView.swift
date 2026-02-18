// MARK: - UI/HelpMenuView.swift
// 斜杠命令帮助菜单

import SwiftUI

struct HelpCommand: Identifiable, Equatable {
    let id = UUID()
    let command: String
    let description: String
    let icon: String
    let color: Color
    let requiresArgument: Bool

    var insertionText: String {
        command + (requiresArgument ? " " : "")
    }
}

struct HelpMenuView: View {
    let filter: String
    let selectedIndex: Int
    let onSelect: (HelpCommand) -> Void

    static let allCommands: [HelpCommand] = [
        // 系统操作
        HelpCommand(command: "/open", description: "启动程序", icon: "arrow.up.forward.app", color: .cyan, requiresArgument: true),
        HelpCommand(command: "/find", description: "查找文件", icon: "doc.text.magnifyingglass", color: .orange, requiresArgument: true),
        HelpCommand(command: "/setting", description: "系统设置", icon: "gearshape", color: .gray, requiresArgument: false),
        HelpCommand(command: "/config", description: "Synapse 配置", icon: "slider.horizontal.3", color: .mint, requiresArgument: false),
        HelpCommand(command: "/close", description: "关闭程序", icon: "xmark.app", color: .red, requiresArgument: true),
        HelpCommand(command: "/quit", description: "退出 Synapse", icon: "xmark.circle", color: .red, requiresArgument: false),
        // AI 能力
        HelpCommand(command: "/code", description: "代码生成", icon: "curlybraces", color: .green, requiresArgument: true),
        HelpCommand(command: "/ask", description: "知识查询", icon: "brain.head.profile", color: .white, requiresArgument: true),
        HelpCommand(command: "/web", description: "联网搜索", icon: "network", color: .cyan, requiresArgument: true),
        HelpCommand(command: "/translate", description: "AI翻译", icon: "globe", color: .cyan, requiresArgument: true),
        HelpCommand(command: "/write", description: "写作助手", icon: "pencil.line", color: .mint, requiresArgument: true),
        HelpCommand(command: "/history", description: "历史对话", icon: "clock.arrow.circlepath", color: .mint, requiresArgument: false),
        HelpCommand(command: "/memory", description: "查看记忆", icon: "brain", color: .mint, requiresArgument: false),
        HelpCommand(command: "/remember", description: "记住信息", icon: "bookmark", color: .mint, requiresArgument: true),
        HelpCommand(command: "/forget", description: "清空记忆", icon: "trash.slash", color: .orange, requiresArgument: false),
        HelpCommand(command: "/sessions", description: "会话列表", icon: "list.bullet.rectangle", color: .mint, requiresArgument: false),
        HelpCommand(command: "/tree", description: "记忆文件树", icon: "folder.badge.gearshape", color: .mint, requiresArgument: false),
        // 工具
        HelpCommand(command: "/calc", description: "计算器", icon: "function", color: .orange, requiresArgument: true),
        HelpCommand(command: "/define", description: "词典查询", icon: "book", color: .blue, requiresArgument: true),
        HelpCommand(command: "/color", description: "颜色解析", icon: "paintpalette", color: .pink, requiresArgument: true),
        HelpCommand(command: "/emoji", description: "表情搜索", icon: "face.smiling", color: .yellow, requiresArgument: true),
        HelpCommand(command: "/clipboard", description: "剪贴板历史", icon: "doc.on.clipboard", color: .purple, requiresArgument: false),
        // 系统命令
        HelpCommand(command: "/lock", description: "锁屏", icon: "lock", color: .gray, requiresArgument: false),
        HelpCommand(command: "/screenshot", description: "截图", icon: "camera", color: .green, requiresArgument: false),
        HelpCommand(command: "/darkmode", description: "深色模式", icon: "moon", color: .indigo, requiresArgument: false),
        HelpCommand(command: "/ip", description: "IP 地址", icon: "network", color: .cyan, requiresArgument: false),
        HelpCommand(command: "/battery", description: "电池状态", icon: "battery.100", color: .green, requiresArgument: false),
        HelpCommand(command: "/date", description: "日期时间", icon: "calendar", color: .red, requiresArgument: false),
        HelpCommand(command: "/trash", description: "清废纸篓", icon: "trash", color: .red, requiresArgument: false),
        HelpCommand(command: "/help", description: "显示命令菜单", icon: "questionmark.circle", color: .gray, requiresArgument: false),
    ]

    static func filteredCommands(for filter: String) -> [HelpCommand] {
        let key = filter.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return allCommands }

        let normalized = key.hasPrefix("/") ? key : "/\(key)"
        return allCommands.filter { cmd in
            cmd.command.lowercased().hasPrefix(normalized)
            || cmd.command.lowercased().contains(normalized)
            || cmd.description.lowercased().contains(key)
        }
    }

    private var filteredCommands: [HelpCommand] {
        Self.filteredCommands(for: filter)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("命令列表")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 4)
            
            if filteredCommands.isEmpty {
                Text("未找到匹配命令")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
            
            VStack(spacing: 0) {
                ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { idx, cmd in
                    Button(action: { onSelect(cmd) }) {
                        HStack(spacing: 12) {
                            Image(systemName: cmd.icon)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(cmd.color)
                                .frame(width: 18)
                            
                            Text(cmd.command)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(.primary)
                                .frame(width: 108, alignment: .leading)
                            
                            Text(cmd.description)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(idx == selectedIndex ? Color.accentColor.opacity(0.18) : .clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    if idx < filteredCommands.count - 1 {
                        Divider().padding(.leading, 20)
                    }
                }
            }
            .background(TerminalTheme.cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
        .padding(.bottom, 10)
    }
}
