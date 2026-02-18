// MARK: - Core/IntentEngine.swift
// 意图识别引擎 — 优先内联模块，然后规则引擎

import Foundation

/// 意图识别引擎
final class IntentEngine {
    
    // 内联模块
    let calculator = CalculatorModule()
    let dictionary = DictionaryModule()
    let systemCommands = SystemCommandModule()
    let unitConverter = UnitConverterModule()
    let emoji = EmojiModule()
    let color = ColorModule()
    let fileSearch = FileSearchModule()
    
    // MARK: - 关键词表
    
    private let launchKeywords = ["打开", "启动", "运行", "open", "launch", "run", "start"]
    private let closeKeywords  = ["关闭", "close", "kill", "结束"]
    private let findKeywords   = ["查找", "搜索", "找", "find", "search", "locate", "文件"]
    private let settingKeywords = ["设置", "配置", "setting", "preference", "偏好"]
    private let windowKeywords = ["窗口", "全屏", "最小化", "分屏", "window", "fullscreen", "minimize",
                                  "左半屏", "右半屏", "最大化", "maximize", "tile"]
    private let clipboardKeywords = ["剪贴板", "clipboard", "粘贴历史", "paste history"]
    private let historyKeywords = ["历史对话", "对话历史", "聊天记录", "history", "conversation history"]
    private let sessionKeywords = ["会话列表", "sessions", "对话列表", "session list"]
    private let memoryTreeKeywords = ["memory tree", "记忆树", "memory 树"]
    private let memoryShowKeywords = ["memory", "记忆", "记住了什么", "我的记忆", "memory list"]
    private let memoryRememberKeywords = ["记住", "记一下", "remember", "加入记忆", "存到memory"]
    private let memoryClearKeywords = ["清空记忆", "清空memory", "forget all memory", "clear memory"]
    private let webSearchKeywords = ["联网搜索", "上网查", "web search", "搜一下网页", "online search"]
    
    // AI 意图关键词
    private let codeKeywords = ["写代码", "代码", "编写", "code", "写一个", "函数", "function",
                                "脚本", "script", "实现", "implement", "写个", "编程",
                                "swift", "python", "javascript", "java", "go", "rust",
                                "排序", "sort", "http", "请求", "api", "json", "timer", "hello"]
    private let knowledgeKeywords = ["什么是", "是什么", "解释", "介绍", "知识", "百科", "知道",
                                     "what is", "explain", "tell me about", "how does",
                                     "为什么", "why", "how", "怎么", "如何", "谁是", "who is",
                                     "历史", "原理", "概念", "定义"]
    private let translateKeywords = ["翻译", "译成", "翻成", "translate", "translation", "中译英", "英译中"]
    private let writeKeywords = ["写文章", "写作", "文案", "写一篇", "创作", "write article",
                                "邮件", "email", "简历", "resume", "文章", "内容",
                                "写一封", "草稿", "draft", "compose"]
    
    // MARK: - 主识别入口
    
    func recognize(_ query: String) -> RecognizedIntent {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .empty(query)
        }
        
        // 0. 计算器（最高优先级 — 数学表达式即时求值）
        if calculator.canHandle(trimmed) {
            if let result = calculator.evaluate(trimmed) {
                return RecognizedIntent(
                    domain: .systemOperation, action: .inlineResult,
                    confidence: 0.99,
                    parameters: ["result": "🔢 = \(result)", "type": "calculator"],
                    rawQuery: trimmed, matchedApp: nil
                )
            }
        }
        
        // 1. 颜色解析
        if color.canHandle(trimmed) {
            if let result = color.parse(trimmed) {
                return RecognizedIntent(
                    domain: .systemOperation, action: .inlineResult,
                    confidence: 0.99,
                    parameters: ["result": result, "type": "color"],
                    rawQuery: trimmed, matchedApp: nil
                )
            }
        }
        
        // 2. 单位换算
        if unitConverter.canHandle(trimmed) {
            if let result = unitConverter.convert(trimmed) {
                return RecognizedIntent(
                    domain: .systemOperation, action: .inlineResult,
                    confidence: 0.95,
                    parameters: ["result": result, "type": "unit"],
                    rawQuery: trimmed, matchedApp: nil
                )
            }
        }
        
        // 3. Emoji 搜索
        if emoji.canHandle(trimmed) {
            let result = emoji.search(trimmed)
            return RecognizedIntent(
                domain: .systemOperation, action: .inlineResult,
                confidence: 0.95,
                parameters: ["result": result, "type": "emoji"],
                rawQuery: trimmed, matchedApp: nil
            )
        }
        
        // 4. 词典查询（有明确触发词）
        if dictionary.canHandle(trimmed) {
            let word = dictionary.extractWord(from: trimmed)
            let definition = dictionary.lookup(word) ?? "未找到词典释义，可尝试英文单词或更精确短语。"
            return RecognizedIntent(
                domain: .systemOperation, action: .inlineResult,
                confidence: 0.90,
                parameters: ["result": "📖 \(word)\n\n\(definition)", "type": "dictionary"],
                rawQuery: trimmed, matchedApp: nil
            )
        }
        
        // 5. 剪贴板历史
        let lower = trimmed.lowercased()
        if clipboardKeywords.contains(where: { lower.contains($0) }) {
            let history = ClipboardModule.shared.formatHistory()
            return RecognizedIntent(
                domain: .systemOperation, action: .inlineResult,
                confidence: 0.95,
                parameters: ["result": history, "type": "clipboard"],
                rawQuery: trimmed, matchedApp: nil
            )
        }

        // 5.1 Memory 指令
        if let memoryIntent = detectMemoryIntent(trimmed) {
            return memoryIntent
        }

        // 5.15 会话列表
        if let sessionIntent = detectSessionIntent(trimmed) {
            return sessionIntent
        }

        // 5.2 历史对话
        if let historyIntent = detectHistoryIntent(trimmed) {
            return historyIntent
        }

        // 5.3 联网搜索
        if let webIntent = detectWebIntent(trimmed) {
            return webIntent
        }
        
        // 6. 系统命令（锁屏、截图等）
        if let cmd = systemCommands.findCommand(trimmed) {
            return RecognizedIntent(
                domain: .systemOperation, action: .systemCommand,
                confidence: 0.95,
                parameters: ["command": cmd.title, "query": trimmed, "commandID": cmd.id],
                rawQuery: trimmed, matchedApp: nil
            )
        }
        
        // 7. L1 规则引擎（启动/关闭/窗口/文件搜索/设置）
        if let result = l1RuleEngine(trimmed) { return result }
        
        // 8. AI 意图检测（代码/知识/写作）
        if let result = detectAIIntent(trimmed) { return result }
        
        // 9. 尝试词典（无关键词也试一下）
        if trimmed.count <= 30 {
            if let definition = dictionary.lookup(trimmed) {
                return RecognizedIntent(
                    domain: .systemOperation, action: .inlineResult,
                    confidence: 0.60,
                    parameters: ["result": "📖 \(trimmed)\n\n\(definition)", "type": "dictionary"],
                    rawQuery: trimmed, matchedApp: nil
                )
            }
        }
        
        // 10. 兜底 → 知识查询（所有无法识别的意图走知识搜索）
        return RecognizedIntent(
            domain: .aiCapability, action: .knowledgeQuery,
            confidence: 0.5,
            parameters: ["query": trimmed],
            rawQuery: trimmed, matchedApp: nil
        )
    }
    
    // MARK: - L1 规则引擎
    
    private func l1RuleEngine(_ query: String) -> RecognizedIntent? {
        let lower = query.lowercased()
        
        // 启动 App
        for kw in launchKeywords {
            if lower.hasPrefix(kw) || lower.hasPrefix(kw + " ") {
                let appName = extractTarget(from: query, keyword: kw)
                return RecognizedIntent(
                    domain: .systemOperation, action: .launchApp,
                    confidence: 0.95, parameters: ["appName": appName],
                    rawQuery: query, matchedApp: nil
                )
            }
        }
        
        // 关闭 App
        for kw in closeKeywords {
            if lower.hasPrefix(kw) || lower.hasPrefix(kw + " ") {
                let appName = extractTarget(from: query, keyword: kw)
                return RecognizedIntent(
                    domain: .systemOperation, action: .closeApp,
                    confidence: 0.95, parameters: ["appName": appName],
                    rawQuery: query, matchedApp: nil
                )
            }
        }
        
        // 窗口管理
        if windowKeywords.contains(where: { lower.contains($0) }) {
            return RecognizedIntent(
                domain: .systemOperation, action: .windowManage,
                confidence: 0.90, parameters: ["query": query],
                rawQuery: query, matchedApp: nil
            )
        }
        
        // 查找文件 → 内联（支持过滤关键词触发）
        if fileSearch.canHandle(lower) {
            let target = fileSearch.extractSearchQuery(query)
            return RecognizedIntent(
                domain: .systemOperation, action: .findFile,
                confidence: 0.90, parameters: ["query": target.isEmpty ? query : target],
                rawQuery: query, matchedApp: nil
            )
        }
        
        // 系统设置
        for kw in settingKeywords {
            if lower.contains(kw) {
                return RecognizedIntent(
                    domain: .systemOperation, action: .systemSetting,
                    confidence: 0.90, parameters: ["query": query],
                    rawQuery: query, matchedApp: nil
                )
            }
        }
        
        return nil
    }
    
    // MARK: - AI 意图检测
    
    private func detectAIIntent(_ query: String) -> RecognizedIntent? {
        let lower = query.lowercased()
        
        // AI 翻译
        if translateKeywords.contains(where: { lower.contains($0) }) {
            return RecognizedIntent(
                domain: .aiCapability, action: .translateText,
                confidence: 0.9, parameters: ["query": query],
                rawQuery: query, matchedApp: nil
            )
        }

        // 写代码
        if codeKeywords.contains(where: { lower.contains($0) }) {
            return RecognizedIntent(
                domain: .aiCapability, action: .codeWrite,
                confidence: 0.85, parameters: ["query": query],
                rawQuery: query, matchedApp: nil
            )
        }
        
        // 知识查询
        if knowledgeKeywords.contains(where: { lower.contains($0) }) {
            return RecognizedIntent(
                domain: .aiCapability, action: .knowledgeQuery,
                confidence: 0.85, parameters: ["query": query],
                rawQuery: query, matchedApp: nil
            )
        }
        
        // 文案写作
        if writeKeywords.contains(where: { lower.contains($0) }) {
            return RecognizedIntent(
                domain: .aiCapability, action: .contentCreate,
                confidence: 0.85, parameters: ["query": query],
                rawQuery: query, matchedApp: nil
            )
        }
        
        return nil
    }
    
    // MARK: - 辅助
    
    private func extractTarget(from query: String, keyword: String) -> String {
        if let range = query.range(
            of: keyword,
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        ) {
            return query[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private func detectHistoryIntent(_ query: String) -> RecognizedIntent? {
        let lower = query.lowercased()
        guard historyKeywords.contains(where: { lower.hasPrefix($0) || lower == $0 }) else {
            return nil
        }

        let keyword = historyKeywords.first(where: { lower.hasPrefix($0) || lower == $0 }) ?? "历史对话"
        let target = extractTarget(from: query, keyword: keyword)
        return RecognizedIntent(
            domain: .aiCapability,
            action: .conversationHistory,
            confidence: 0.95,
            parameters: ["query": target],
            rawQuery: query,
            matchedApp: nil
        )
    }

    private func detectMemoryIntent(_ query: String) -> RecognizedIntent? {
        let lower = query.lowercased()

        if memoryTreeKeywords.contains(where: { lower.hasPrefix($0) || lower == $0 }) {
            return RecognizedIntent(
                domain: .aiCapability,
                action: .memoryTree,
                confidence: 0.96,
                parameters: [:],
                rawQuery: query,
                matchedApp: nil
            )
        }

        if memoryClearKeywords.contains(where: { lower.hasPrefix($0) || lower == $0 }) {
            return RecognizedIntent(
                domain: .aiCapability,
                action: .memoryClear,
                confidence: 0.96,
                parameters: [:],
                rawQuery: query,
                matchedApp: nil
            )
        }

        if let rememberKey = memoryRememberKeywords.first(where: { lower.hasPrefix($0) }) {
            let target = extractTarget(from: query, keyword: rememberKey)
            return RecognizedIntent(
                domain: .aiCapability,
                action: .memoryRemember,
                confidence: 0.95,
                parameters: ["text": target],
                rawQuery: query,
                matchedApp: nil
            )
        }

        if memoryShowKeywords.contains(where: { lower == $0 || lower.hasPrefix($0) }) {
            let key = memoryShowKeywords.first(where: { lower.hasPrefix($0) || lower == $0 }) ?? "memory"
            let target = extractTarget(from: query, keyword: key)
            return RecognizedIntent(
                domain: .aiCapability,
                action: .memoryRecall,
                confidence: 0.9,
                parameters: ["query": target],
                rawQuery: query,
                matchedApp: nil
            )
        }

        return nil
    }

    private func detectSessionIntent(_ query: String) -> RecognizedIntent? {
        let lower = query.lowercased()
        guard sessionKeywords.contains(where: { lower.hasPrefix($0) || lower == $0 }) else {
            return nil
        }
        return RecognizedIntent(
            domain: .aiCapability,
            action: .conversationHistory,
            confidence: 0.95,
            parameters: ["query": "", "subcommand": "sessions"],
            rawQuery: query,
            matchedApp: nil
        )
    }

    private func detectWebIntent(_ query: String) -> RecognizedIntent? {
        let lower = query.lowercased()
        guard let keyword = webSearchKeywords.first(where: { lower.hasPrefix($0) || lower.contains($0) }) else {
            return nil
        }
        let target = extractTarget(from: query, keyword: keyword)
        let finalQuery = target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? query : target
        return RecognizedIntent(
            domain: .aiCapability,
            action: .webSearch,
            confidence: 0.9,
            parameters: ["query": finalQuery],
            rawQuery: query,
            matchedApp: nil
        )
    }

}

// MARK: - RecognizedIntent helpers
extension RecognizedIntent {
    static func empty(_ query: String) -> RecognizedIntent {
        RecognizedIntent(domain: .systemOperation, action: .unknown, confidence: 0,
                        parameters: [:], rawQuery: query, matchedApp: nil)
    }
}
