// MARK: - Models/Intent.swift
// 意图数据模型

import Foundation

/// 意图领域
enum IntentDomain: String, Codable {
    case systemOperation = "系统操作"
    case aiCapability = "AI能力"
}

/// 意图动作
enum IntentAction: String, Codable {
    // 系统操作
    case launchApp = "启动App"
    case closeApp = "关闭App"
    case findFile = "查找文件"
    case systemSetting = "系统设置"
    case windowManage = "窗口管理"
    case processControl = "进程控制"
    case systemCommand = "系统命令"
    case webSearch = "联网搜索"
    case conversationHistory = "历史对话"
    case memoryRecall = "记忆召回"
    case memoryRemember = "记住信息"
    case memoryClear = "清空记忆"
    case memoryTree = "记忆树"
    case sessionList = "会话列表"
    
    // 内联结果
    case inlineResult = "内联结果"
    
    // AI 能力
    case codeWrite = "编写代码"
    case codeDebug = "代码调试"
    case knowledgeQuery = "知识查询"
    case translateText = "文本翻译"
    case contentCreate = "文案创作"
    case contentRewrite = "内容改写"
    case logicReason = "逻辑推理"
    case planDesign = "方案设计"
    case scriptExec = "脚本执行"
    case unknown = "未知"
}

/// 识别后的意图
struct RecognizedIntent {
    let domain: IntentDomain
    let action: IntentAction
    let confidence: Double
    let parameters: [String: String]
    let rawQuery: String
    let matchedApp: AppInfo?
    
    /// 显示标题
    var displayTitle: String {
        switch action {
        case .inlineResult:
            let type = parameters["type"] ?? ""
            switch type {
            case "calculator": return "🔢 计算结果"
            case "unit": return "📐 单位换算"
            case "color": return "🎨 颜色信息"
            case "emoji": return "😀 Emoji"
            case "dictionary": return "📖 词典"
            case "clipboard": return "📋 剪贴板"
            case "fallback": return "💡 帮助"
            default: return "📝 结果"
            }
        case .systemCommand: return parameters["command"] ?? "系统命令"
        case .webSearch:
            let target = cleanedEntity(parameters["query"], fallback: "关键词")
            return "🌐 联网搜索\(target)"
        case .conversationHistory:
            return "🕘 历史对话"
        case .memoryRecall:
            return "🧠 Memory"
        case .memoryRemember:
            return "🧠 记住这条信息"
        case .memoryClear:
            return "🧼 清空记忆"
        case .memoryTree:
            return "🌳 记忆文件树"
        case .sessionList:
            return "📋 会话列表"
        case .launchApp:
            let name = cleanedEntity(parameters["appName"], fallback: "程序")
            return "🚀 启动\(name)"
        case .closeApp:
            let name = cleanedEntity(parameters["appName"], fallback: "程序")
            return "⛔ 关闭\(name)"
        case .findFile:
            let target = cleanedEntity(parameters["query"], fallback: "文件")
            return "🔍 查找「\(target)」"
        case .systemSetting: return "⚙️ 系统设置"
        case .windowManage: return "🪟 窗口管理"
        case .processControl: return "📊 进程控制"
        case .codeWrite, .codeDebug, .scriptExec: return "💻 代码生成"
        case .knowledgeQuery: return "📚 知识查询  ↵执行"
        case .translateText: return "🌐 AI 翻译  ↵执行"
        case .contentCreate, .contentRewrite: return "✍️ 写作助手  ↵执行"
        default: return action.rawValue
        }
    }
    
    /// 是否为内联显示（不跳转外部 App）
    var isInline: Bool {
        switch action {
        case .inlineResult, .findFile, .systemCommand, .windowManage, .processControl,
             .closeApp, .codeWrite, .codeDebug, .knowledgeQuery, .translateText, .contentCreate,
             .webSearch, .conversationHistory, .memoryRecall, .memoryRemember, .memoryClear,
             .memoryTree, .sessionList:
            return true
        case .launchApp, .systemSetting:
            return false
        default:
            return true
        }
    }

    private func cleanedEntity(_ raw: String?, fallback: String) -> String {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let uselessTokens: Set<String> = ["打开", "启动", "运行", "关闭", "退出", "查找", "搜索", "找", "find", "open", "quit"]
        guard !value.isEmpty else { return fallback }
        if uselessTokens.contains(value.lowercased()) || uselessTokens.contains(value) {
            return fallback
        }
        return " \(value)"
    }
}
