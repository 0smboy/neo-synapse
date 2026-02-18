// MARK: - Core/IntentExecutor.swift
// 执行决策分发器 — 所有结果内联显示（除 launchApp/systemSetting）

@preconcurrency import AppKit

/// 执行器
final class IntentExecutor {
    
    private let systemCommands = SystemCommandModule()
    private let webSearchModule = WebSearchModule()
    
    func execute(_ intent: RecognizedIntent, recordConversation: Bool = true) async -> ExecutionResult {
        print("🚀 执行: \(intent.action.rawValue) | 置信度: \(String(format: "%.0f%%", intent.confidence * 100))")
        
        switch intent.action {
            
        // 内联结果（计算器、单位、颜色、Emoji、词典、剪贴板）
        case .inlineResult:
            let result = intent.parameters["result"] ?? "无结果"
            return .success(result)
            
        // 系统命令（锁屏、截图等）
        case .systemCommand:
            if let cmd = systemCommands.findCommand(intent.rawQuery) {
                return await Task.detached(priority: .userInitiated, operation: {
                    cmd.action()
                }).value
            }
            return .failure("未找到系统命令")
        
        // 启动 App（唯一跳转外部的操作）
        case .launchApp:
            return await executeLaunchApp(intent)
            
        // 关闭 App（内联结果）
        case .closeApp:
            return executeCloseApp(intent)
            
        // 文件搜索（高性能混合引擎 — 内联结果）
        case .findFile:
            return await executeFindFile(intent)
            
        // 系统设置（跳转）
        case .systemSetting:
            return SystemAdapter.openSettings(query: intent.parameters["query"] ?? "")
            
        // 窗口管理（内联结果）
        case .windowManage:
            return executeWindowManage(intent)
            
        // 进程控制（内联结果）
        case .processControl:
            return SystemAdapter.listProcesses(top: 8)
            
        // ========== AI 能力（全部内联） ==========
            
        // 代码生成
        case .codeWrite, .codeDebug, .scriptExec:
            let query = intent.parameters["query"] ?? intent.rawQuery
            let result = await Task.detached(priority: .userInitiated, operation: {
                await AIInlineModule().generateCode(query)
            }).value
            if recordConversation {
                ConversationHistoryStore.shared.appendExchange(user: query, assistant: result, action: .codeWrite)
                MemoryAutoManager.shared.ingest(user: query, assistant: result, action: intent.action)
            }
            return .success(result)
            
        // 知识查询
        case .knowledgeQuery:
            let query = intent.parameters["query"] ?? intent.rawQuery
            let result = await Task.detached(priority: .userInitiated, operation: {
                await AIInlineModule().queryKnowledge(query)
            }).value
            if recordConversation {
                ConversationHistoryStore.shared.appendExchange(user: query, assistant: result, action: .knowledgeQuery)
                MemoryAutoManager.shared.ingest(user: query, assistant: result, action: intent.action)
            }
            return .success(result)

        // AI 翻译
        case .translateText:
            let query = intent.parameters["query"] ?? intent.rawQuery
            let result = await Task.detached(priority: .userInitiated, operation: {
                await AIInlineModule().translateText(query)
            }).value
            if recordConversation {
                ConversationHistoryStore.shared.appendExchange(user: query, assistant: result, action: .translateText)
                MemoryAutoManager.shared.ingest(user: query, assistant: result, action: intent.action)
            }
            return .success(result)
            
        // 文案创作
        case .contentCreate, .contentRewrite:
            let query = intent.parameters["query"] ?? intent.rawQuery
            let result = await Task.detached(priority: .userInitiated, operation: {
                await AIInlineModule().generateContent(query)
            }).value
            if recordConversation {
                ConversationHistoryStore.shared.appendExchange(user: query, assistant: result, action: .contentCreate)
                MemoryAutoManager.shared.ingest(user: query, assistant: result, action: intent.action)
            }
            return .success(result)

        case .webSearch:
            let query = intent.parameters["query"] ?? intent.rawQuery
            let result = await webSearchModule.search(query)
            if recordConversation {
                ConversationHistoryStore.shared.appendExchange(user: query, assistant: result, action: .webSearch)
                MemoryAutoManager.shared.ingest(user: query, assistant: result, action: intent.action)
            }
            return .success(result)

        case .conversationHistory:
            let keyword = intent.parameters["query"]
            let subcommand = intent.parameters["subcommand"] ?? ""
            if subcommand == "sessions" {
                return .success(ConversationHistoryStore.shared.formatSessionList())
            }
            return .success(ConversationHistoryStore.shared.formatHistory(keyword: keyword))

        case .memoryRecall:
            let query = (intent.parameters["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if query == "tree" || query.hasPrefix("synapse://") {
                return .success(MemoryStore.shared.formatMemoryTree())
            }
            let categories = MemoryStore.shared.listCategories()
            if !query.isEmpty, categories.contains(query) {
                let items = MemoryStore.shared.browseCategory(query)
                if items.isEmpty {
                    return .success("该分类下暂无记忆。")
                }
                let rows = items.map { "• [\($0.category)] \($0.text)" }
                return .success("# 分类：\(query)\n\n\(rows.joined(separator: "\n"))")
            }
            return .success(MemoryStore.shared.formatMemories(keyword: intent.parameters["query"]))

        case .memoryRemember:
            let text = (intent.parameters["text"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return .failure("请输入要记住的内容") }
            _ = MemoryStore.shared.remember(text)
            return .success("✅ 已记住：\(text)")

        case .memoryClear:
            let count = MemoryStore.shared.clear()
            return .success("🧼 Memory 已清空（\(count) 条）")

        case .memoryTree:
            return .success(MemoryStore.shared.formatMemoryTree())

        case .sessionList:
            return .success(ConversationHistoryStore.shared.formatSessionList())

        default:
            return .success("💡 暂不支持此操作\n\n输入 / 查看可用命令")
        }
    }
    
    // MARK: - 启动 App
    
    private func executeLaunchApp(_ intent: RecognizedIntent) async -> ExecutionResult {
        let rawName = (intent.parameters["appName"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !rawName.isEmpty else {
            return .failure("请提供要启动的应用名称")
        }

        return await Task.detached(priority: .userInitiated, operation: {
            let bestMatch = AppIndexer.shared.bestMatch(query: rawName)
            let preferredPath = bestMatch?.path
            let preferredName = bestMatch?.name ?? rawName

            let task = Process()
            let errorPipe = Pipe()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            if let preferredPath {
                task.arguments = [preferredPath]
            } else {
                task.arguments = ["-a", rawName]
            }
            task.standardError = errorPipe
            task.standardOutput = FileHandle.nullDevice
            
            do {
                try task.run()
                task.waitUntilExit()
                
                if task.terminationStatus == 0 {
                    if let bestMatch, bestMatch.name.caseInsensitiveCompare(rawName) != .orderedSame {
                        return .success("✅ 已启动 \(preferredName)\n匹配：\(rawName) → \(preferredName)")
                    }
                    return .success("✅ 已启动 \(preferredName)")
                }
                
                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorText = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if errorText.isEmpty {
                    return .failure("未找到或无法启动应用「\(rawName)」")
                }
                return .failure("启动失败: \(errorText)")
            } catch {
                return .failure("启动失败: \(error.localizedDescription)")
            }
        }).value
    }
    
    // MARK: - 关闭 App
    
    private func executeCloseApp(_ intent: RecognizedIntent) -> ExecutionResult {
        let appName = (intent.parameters["appName"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appName.isEmpty else { return .failure("请提供要关闭的应用名称") }

        if let bestMatch = AppIndexer.shared.bestMatch(query: appName) {
            return SystemAdapter.killProcess(name: bestMatch.name, bundleIdentifier: bestMatch.bundleId)
        }
        return SystemAdapter.killProcess(name: appName)
    }
    
    // MARK: - 文件搜索（高性能混合引擎: Spotlight + fts 并发）
    
    private func executeFindFile(_ intent: RecognizedIntent) async -> ExecutionResult {
        let rawQuery = intent.parameters["query"] ?? intent.rawQuery
        guard !rawQuery.isEmpty else { return .failure("请输入搜索关键词") }
        
        let results = await Task.detached(priority: .userInitiated, operation: {
            await FileSearchModule().search(rawQuery)
        }).value
        
        if results.isEmpty {
            return .failure("未找到与「\(rawQuery)」相关的文件")
        }
        
        return .success(FileSearchEngine.formatResults(results), fileResults: results)
    }
    
    // MARK: - 窗口管理（内联结果）
    
    private func executeWindowManage(_ intent: RecognizedIntent) -> ExecutionResult {
        let query = intent.parameters["query"]?.lowercased() ?? ""
        let ax = AccessibilityManager.shared
        
        guard ax.hasPermission else {
            ax.requestPermission()
            return .failure("⚠️ 需要辅助功能权限\n\n请前往: 系统设置 > 隐私与安全 > 辅助功能\n授权后重试")
        }
        
        if query.contains("最小化") || query.contains("minimize") {
            return ax.minimizeFrontWindow() ? .success("✅ 已最小化窗口") : .failure("操作失败")
        }
        if query.contains("全屏") || query.contains("fullscreen") {
            return ax.toggleFullscreen() ? .success("✅ 已切换全屏") : .failure("操作失败")
        }
        if query.contains("左") || query.contains("left") {
            return ax.tileLeft() ? .success("✅ 窗口已移到左半屏") : .failure("操作失败")
        }
        if query.contains("右") || query.contains("right") {
            return ax.tileRight() ? .success("✅ 窗口已移到右半屏") : .failure("操作失败")
        }
        if query.contains("最大化") || query.contains("maximize") {
            return ax.maximizeWindow() ? .success("✅ 窗口已最大化") : .failure("操作失败")
        }
        
        return .success("🪟 窗口管理\n\n支持: 最小化 / 全屏 / 左半屏 / 右半屏 / 最大化")
    }
}
