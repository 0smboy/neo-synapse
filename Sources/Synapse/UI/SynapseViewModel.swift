// MARK: - UI/SynapseViewModel.swift
// 主视图模型 — 内联结果 + AI 功能 + 斜杠命令

import SwiftUI
import Combine

@MainActor
final class SynapseViewModel: ObservableObject {
    private struct SlashCommand {
        let key: String
        let aliases: [String]
        let requiresArgument: Bool
        let transform: (String) -> String
    }
    
    @Published var query: String = "" {
        didSet {
            if query == oldValue { return }
            onQueryChanged()
        }
    }
    @Published var currentIntent: RecognizedIntent?
    @Published var executionResult: ExecutionResult?
    @Published var isProcessing: Bool = false
    @Published var isExecuting: Bool = false
    @Published var matchedApps: [AppInfo] = []
    @Published var showHelp: Bool = false
    @Published var showConfig: Bool = false
    @Published var inlineText: String = ""
    @Published var selectedAppIndex: Int = 0
    @Published var selectedHelpIndex: Int = 0
    @Published var voiceListening: Bool = false
    @Published var voiceStatusText: String = ""
    
    private let engine = IntentEngine()
    private let executor = IntentExecutor()
    private let appIndexer = AppIndexer.shared
    private let voiceAssistant = VoiceAssistantService.shared
    private var liveKnowledgeTask: Task<Void, Never>?
    private var settingsObserver: NSObjectProtocol?
    private var cancellables: Set<AnyCancellable> = []
    
    private let slashCommands: [SlashCommand] = [
        SlashCommand(key: "/open", aliases: ["o"], requiresArgument: true, transform: { "打开 \($0)" }),
        SlashCommand(key: "/find", aliases: ["f"], requiresArgument: true, transform: { "查找 \($0)" }),
        SlashCommand(key: "/setting", aliases: ["settings"], requiresArgument: false, transform: { _ in "系统设置" }),
        SlashCommand(key: "/calc", aliases: ["c"], requiresArgument: true, transform: { "calc \($0)" }),
        SlashCommand(key: "/color", aliases: ["palette"], requiresArgument: true, transform: { "color \($0)" }),
        SlashCommand(key: "/emoji", aliases: ["em"], requiresArgument: true, transform: { "emoji \($0)" }),
        SlashCommand(key: "/define", aliases: ["dict"], requiresArgument: true, transform: { "define \($0)" }),
        SlashCommand(key: "/close", aliases: ["cl"], requiresArgument: true, transform: { "关闭 \($0)" }),
        SlashCommand(key: "/quit", aliases: ["q", "exit"], requiresArgument: false, transform: { _ in "退出synapse" }),
        SlashCommand(key: "/clipboard", aliases: ["clip"], requiresArgument: false, transform: { _ in "剪贴板" }),
        SlashCommand(key: "/ip", aliases: [], requiresArgument: false, transform: { _ in "ip" }),
        SlashCommand(key: "/battery", aliases: ["power"], requiresArgument: false, transform: { _ in "battery" }),
        SlashCommand(key: "/date", aliases: ["time"], requiresArgument: false, transform: { _ in "今天日期" }),
        SlashCommand(key: "/lock", aliases: [], requiresArgument: false, transform: { _ in "锁屏" }),
        SlashCommand(key: "/screenshot", aliases: ["shot"], requiresArgument: false, transform: { _ in "截图" }),
        SlashCommand(key: "/darkmode", aliases: ["dark"], requiresArgument: false, transform: { _ in "暗黑模式" }),
        SlashCommand(key: "/trash", aliases: ["bin"], requiresArgument: false, transform: { _ in "清空废纸篓" }),
        SlashCommand(key: "/config", aliases: ["cfg"], requiresArgument: false, transform: { _ in "/config" }),
        SlashCommand(key: "/code", aliases: ["dev"], requiresArgument: true, transform: { "写代码 \($0)" }),
        SlashCommand(key: "/ask", aliases: ["qa"], requiresArgument: true, transform: { "什么是 \($0)" }),
        SlashCommand(key: "/web", aliases: ["net", "online"], requiresArgument: true, transform: { "联网搜索 \($0)" }),
        SlashCommand(key: "/write", aliases: ["draft"], requiresArgument: true, transform: { "写文章 \($0)" }),
        SlashCommand(key: "/translate", aliases: ["trans", "tr"], requiresArgument: true, transform: { "翻译 \($0)" }),
        SlashCommand(key: "/history", aliases: ["his"], requiresArgument: false, transform: { arg in
            let trimmed = arg.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "历史对话" : "历史对话 \(trimmed)"
        }),
        SlashCommand(key: "/memory", aliases: ["mem"], requiresArgument: false, transform: { arg in
            let trimmed = arg.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "memory" : "memory \(trimmed)"
        }),
        SlashCommand(key: "/remember", aliases: ["memo"], requiresArgument: true, transform: { "记住 \($0)" }),
        SlashCommand(key: "/forget", aliases: ["clear-memory"], requiresArgument: false, transform: { _ in "清空记忆" }),
        SlashCommand(key: "/sessions", aliases: ["sess"], requiresArgument: false, transform: { _ in "会话列表" }),
        SlashCommand(key: "/tree", aliases: ["mtree"], requiresArgument: false, transform: { _ in "memory tree" }),
    ]

    init() {
        if appIndexer.apps.isEmpty {
            _ = appIndexer.loadCache()
        }
        bindVoice()
        observeSettings()
        syncVoiceFromSettings()
    }
    
    // MARK: - 计算属性
    
    var showResults: Bool {
        !query.isEmpty && (
            showConfig ||
            !inlineText.isEmpty ||
            currentIntent != nil ||
            executionResult != nil ||
            isExecuting ||
            !matchedApps.isEmpty
        )
    }
    
    var statusColor: Color {
        guard let intent = currentIntent else { return .green }
        let type = intent.parameters["type"] ?? ""
        switch type {
        case "calculator": return .orange
        case "unit": return .cyan
        case "color": return .pink
        case "emoji": return .yellow
        case "dictionary": return .blue
        case "clipboard": return .purple
        default:
            switch intent.action {
            case .codeWrite, .codeDebug, .scriptExec: return .green
            case .knowledgeQuery, .translateText: return .blue
            case .contentCreate, .contentRewrite: return .purple
            case .webSearch: return .cyan
            case .memoryRecall, .memoryRemember, .memoryClear, .conversationHistory, .memoryTree, .sessionList: return .mint
            case .findFile: return .orange
            default:
                switch intent.domain {
                case .systemOperation: return .blue
                case .aiCapability: return .purple
                }
            }
        }
    }
    
    var slashFilter: String {
        guard query.hasPrefix("/") else { return "" }
        let body = String(query.dropFirst())
        if let firstToken = body.split(separator: " ").first {
            return String(firstToken)
        }
        return body
    }

    var filteredHelpCommands: [HelpCommand] {
        HelpMenuView.filteredCommands(for: slashFilter)
    }
    
    // MARK: - 输入变化
    
    private func onQueryChanged() {
        liveKnowledgeTask?.cancel()
        liveKnowledgeTask = nil
        executionResult = nil
        showConfig = false
        
        // 帮助菜单
        if query == "/" {
            showHelp = true
            currentIntent = nil
            isProcessing = false
            matchedApps = []
            selectedAppIndex = 0
            selectedHelpIndex = 0
            inlineText = ""
            return
        }
        showHelp = false
        selectedHelpIndex = 0
        
        let normalized = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let synapseConfigAliases: Set<String> = [
            "/config", "config", "配置", "synapse配置", "synapse config",
            "synapse设置", "synapse setting", "synapse 偏好", "synapse 偏好设置"
        ]
        if synapseConfigAliases.contains(normalized) {
            showConfig = true
            currentIntent = nil
            isProcessing = false
            matchedApps = []
            selectedAppIndex = 0
            selectedHelpIndex = 0
            inlineText = ""
            return
        }
        
        // 斜杠命令
        if query.hasPrefix("/") && query.count > 1 {
            handleSlashCommand()
            return
        }
        
        guard !query.isEmpty else {
            currentIntent = nil
            isProcessing = false
            matchedApps = []
            selectedAppIndex = 0
            inlineText = ""
            return
        }
        
        isProcessing = true
        
        // 识别意图
        let intent = engine.recognize(query)
        self.currentIntent = intent
        
        // 即时内联结果（计算器、单位换算、颜色、Emoji、词典、剪贴板 — 无需回车）
        if intent.action == .inlineResult {
            inlineText = intent.parameters["result"] ?? ""
            isProcessing = false
            matchedApps = []
            selectedAppIndex = 0
            return
        }
        
        // 非即时 — 显示意图预览
        inlineText = ""
        updateAppMatches(for: intent)
        
        // 知识查询：输入后自动快速预览（类似 menubar 快速响应）
        if intent.action == .knowledgeQuery {
            startLiveKnowledgeQuery(intent)
            return
        }
        
        isProcessing = false
    }
    
    // MARK: - 斜杠命令
    
    private func handleSlashCommand() {
        let lower = query.lowercased()

        if lower == "/help" {
            query = "/"
            showHelp = true
            return
        }
        
        if lower == "/config" || lower == "/cfg" {
            showHelp = false
            showConfig = true
            currentIntent = nil
            isProcessing = false
            matchedApps = []
            selectedAppIndex = 0
            selectedHelpIndex = 0
            inlineText = ""
            executionResult = nil
            return
        }

        let body = String(query.dropFirst())
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else {
            showHelp = true
            showConfig = false
            isProcessing = false
            currentIntent = nil
            matchedApps = []
            selectedAppIndex = 0
            selectedHelpIndex = 0
            inlineText = ""
            return
        }

        let parts = trimmedBody.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let token = parts.first.map(String.init)?.lowercased() ?? ""
        let argument = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""

        if "help".hasPrefix(token) || token == "?" {
            query = "/"
            showHelp = true
            return
        }

        if let exact = slashCommands.first(where: { slashCommandMatchesExactly($0, token: token) }) {
            applySlashCommand(exact, argument: argument)
            return
        }

        if let fuzzy = fuzzyMatchSlashCommand(token: token) {
            applySlashCommand(fuzzy, argument: argument)
            return
        }

        // / 命令匹配失败时，回退到自然语言识别（最终兜底知识查询）
        recognizeNaturalLanguage(trimmedBody)
    }
    
    private func setSlashPreviewState(for cmd: SlashCommand, argument: String) {
        currentIntent = previewIntentForSlashCommand(cmd, argument: argument)
        isProcessing = false
        updateAppMatches(for: currentIntent)
        inlineText = ""
        showHelp = true
        selectedHelpIndex = 0
        showConfig = false
    }

    private func applySlashCommand(_ cmd: SlashCommand, argument: String) {
        if cmd.requiresArgument {
            if argument.isEmpty {
                if query != cmd.key + " " {
                    query = cmd.key + " "
                }
                setSlashPreviewState(for: cmd, argument: "")
                return
            }
            query = cmd.transform(argument)
            return
        }

        query = cmd.transform(argument)
    }

    private func slashCommandMatchesExactly(_ cmd: SlashCommand, token: String) -> Bool {
        let canonical = String(cmd.key.dropFirst()).lowercased()
        if token == canonical { return true }
        return cmd.aliases.contains { $0.lowercased() == token }
    }

    private func fuzzyMatchSlashCommand(token: String) -> SlashCommand? {
        guard !token.isEmpty else { return nil }

        let scored = slashCommands.compactMap { cmd -> (SlashCommand, Int)? in
            let canonical = String(cmd.key.dropFirst()).lowercased()
            let variants = [canonical] + cmd.aliases.map { $0.lowercased() }
            let score = variants.map { slashMatchScore(token: token, candidate: $0) }.max() ?? 0
            guard score > 0 else { return nil }
            return (cmd, score)
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.key < rhs.0.key
            }
            .first?
            .0
    }

    private func slashMatchScore(token: String, candidate: String) -> Int {
        guard !token.isEmpty else { return 0 }
        if token == candidate { return 240 }
        if candidate.hasPrefix(token) { return 180 - min(40, max(0, candidate.count - token.count) * 4) }
        if candidate.contains(token) { return 120 }
        if isSubsequence(token, in: candidate) { return 90 }
        return 0
    }

    private func isSubsequence(_ needle: String, in haystack: String) -> Bool {
        guard !needle.isEmpty else { return false }
        var index = haystack.startIndex
        for char in needle {
            guard let found = haystack[index...].firstIndex(of: char) else { return false }
            index = haystack.index(after: found)
        }
        return true
    }
    
    private func previewIntentForSlashCommand(_ cmd: SlashCommand, argument: String) -> RecognizedIntent? {
        guard cmd.requiresArgument else { return nil }
        
        switch cmd.key {
        case "/open":
            return RecognizedIntent(
                domain: .systemOperation,
                action: .launchApp,
                confidence: 0.92,
                parameters: ["appName": argument],
                rawQuery: query,
                matchedApp: nil
            )
        case "/find":
            return RecognizedIntent(
                domain: .systemOperation,
                action: .findFile,
                confidence: 0.92,
                parameters: ["query": argument],
                rawQuery: query,
                matchedApp: nil
            )
        case "/close":
            return RecognizedIntent(
                domain: .systemOperation,
                action: .closeApp,
                confidence: 0.92,
                parameters: ["appName": argument],
                rawQuery: query,
                matchedApp: nil
            )
        case "/code":
            return RecognizedIntent(
                domain: .aiCapability,
                action: .codeWrite,
                confidence: 0.85,
                parameters: ["query": argument],
                rawQuery: query,
                matchedApp: nil
            )
        case "/ask":
            return RecognizedIntent(
                domain: .aiCapability,
                action: .knowledgeQuery,
                confidence: 0.85,
                parameters: ["query": argument],
                rawQuery: query,
                matchedApp: nil
            )
        case "/web":
            return RecognizedIntent(
                domain: .aiCapability,
                action: .webSearch,
                confidence: 0.85,
                parameters: ["query": argument],
                rawQuery: query,
                matchedApp: nil
            )
        case "/write":
            return RecognizedIntent(
                domain: .aiCapability,
                action: .contentCreate,
                confidence: 0.85,
                parameters: ["query": argument],
                rawQuery: query,
                matchedApp: nil
            )
        case "/translate":
            return RecognizedIntent(
                domain: .aiCapability,
                action: .translateText,
                confidence: 0.9,
                parameters: ["query": argument],
                rawQuery: query,
                matchedApp: nil
            )
        case "/remember":
            return RecognizedIntent(
                domain: .aiCapability,
                action: .memoryRemember,
                confidence: 0.9,
                parameters: ["text": argument],
                rawQuery: query,
                matchedApp: nil
            )
        default:
            return nil
        }
    }

    private func recognizeNaturalLanguage(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isProcessing = true
        showHelp = false
        selectedHelpIndex = 0
        showConfig = false

        let intent = engine.recognize(trimmed)
        currentIntent = intent

        if intent.action == .inlineResult {
            inlineText = intent.parameters["result"] ?? ""
            matchedApps = []
            selectedAppIndex = 0
            isProcessing = false
            return
        }

        inlineText = ""
        updateAppMatches(for: intent)

        if intent.action == .knowledgeQuery {
            startLiveKnowledgeQuery(intent)
            return
        }

        isProcessing = false
    }

    private func updateAppMatches(for intent: RecognizedIntent?) {
        guard let intent else {
            matchedApps = []
            selectedAppIndex = 0
            return
        }

        switch intent.action {
        case .launchApp, .closeApp:
            let appName = (intent.parameters["appName"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if appName.isEmpty {
                matchedApps = Array(appIndexer.apps.prefix(5))
                selectedAppIndex = matchedApps.isEmpty ? 0 : min(selectedAppIndex, matchedApps.count - 1)
                return
            }
            matchedApps = Array(appIndexer.search(query: appName).prefix(5))
            selectedAppIndex = matchedApps.isEmpty ? 0 : min(selectedAppIndex, matchedApps.count - 1)
        default:
            matchedApps = []
            selectedAppIndex = 0
        }
    }
    
    // MARK: - 按回车执行
    
    func executeCurrentIntent() {
        if showHelp, applySelectedHelpCommand() {
            return
        }

        guard let intent = currentIntent else { return }
        liveKnowledgeTask?.cancel()
        liveKnowledgeTask = nil
        
        // 内联结果 → 回车复制到剪贴板
        if intent.action == .inlineResult {
            if !inlineText.isEmpty {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(inlineText, forType: .string)
                executionResult = .success("✅ 已复制到剪贴板")
            }
            return
        }
        
        // 已有内联结果 → 回车复制
        if !inlineText.isEmpty && !(intent.action == .knowledgeQuery && inlineText.hasPrefix("正在通过 Codex 快速查询")) {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(inlineText, forType: .string)
            executionResult = .success("✅ 已复制到剪贴板")
            return
        }
        
        // 需要执行的操作（文件搜索、系统命令、AI 意图等）
        isExecuting = true
        executionResult = nil

        var executionIntent = intent
        if (intent.action == .launchApp || intent.action == .closeApp), !matchedApps.isEmpty {
            let safeIndex = max(0, min(selectedAppIndex, matchedApps.count - 1))
            let selectedApp = matchedApps[safeIndex]
            var params = intent.parameters
            params["appName"] = selectedApp.name
            executionIntent = RecognizedIntent(
                domain: intent.domain,
                action: intent.action,
                confidence: intent.confidence,
                parameters: params,
                rawQuery: intent.rawQuery,
                matchedApp: selectedApp
            )
        }
        
        Task {
            let result = await executor.execute(executionIntent, recordConversation: true)
            
            // 内联展示结果
            if executionIntent.isInline {
                self.inlineText = result.output ?? (result.isSuccess ? "✅ 完成" : "❌ 失败")
            }
            
            self.executionResult = result
            self.isExecuting = false
            self.isProcessing = false
            self.readResultIfNeeded(result)
            
            print("📋 执行结果: \(result.isSuccess ? "成功" : "失败")")
        }
    }
    
    func launchApp(_ app: AppInfo) {
        let intent = RecognizedIntent(
            domain: .systemOperation, action: .launchApp,
            confidence: 1.0, parameters: ["appName": app.name],
            rawQuery: "打开 \(app.name)", matchedApp: app
        )
        
        currentIntent = intent
        isExecuting = true
        
        Task {
            let result = await executor.execute(intent, recordConversation: false)
            self.executionResult = result
            self.isExecuting = false
            self.readResultIfNeeded(result)
        }
    }

    func moveAppSelectionUp() {
        guard !matchedApps.isEmpty else { return }
        selectedAppIndex = (selectedAppIndex - 1 + matchedApps.count) % matchedApps.count
    }

    func moveAppSelectionDown() {
        guard !matchedApps.isEmpty else { return }
        selectedAppIndex = (selectedAppIndex + 1) % matchedApps.count
    }

    func moveSelectionUp() {
        if showHelp {
            moveHelpSelectionUp()
        } else {
            moveAppSelectionUp()
        }
    }

    func moveSelectionDown() {
        if showHelp {
            moveHelpSelectionDown()
        } else {
            moveAppSelectionDown()
        }
    }

    private func moveHelpSelectionUp() {
        let commands = filteredHelpCommands
        guard !commands.isEmpty else { return }
        selectedHelpIndex = (selectedHelpIndex - 1 + commands.count) % commands.count
    }

    private func moveHelpSelectionDown() {
        let commands = filteredHelpCommands
        guard !commands.isEmpty else { return }
        selectedHelpIndex = (selectedHelpIndex + 1) % commands.count
    }

    @discardableResult
    private func applySelectedHelpCommand() -> Bool {
        guard showHelp else { return false }
        let commands = filteredHelpCommands
        guard !commands.isEmpty else { return false }

        let idx = max(0, min(selectedHelpIndex, commands.count - 1))
        let selected = commands[idx]
        query = selected.insertionText
        selectedHelpIndex = idx
        return true
    }
    
    func dismiss() {
        NotificationCenter.default.post(name: .synapseDismiss, object: nil)
        resetState()
    }
    
    func quitApplication() {
        ClipboardModule.shared.stopMonitoring()
        NSApp.terminate(nil)
    }
    
    func openConfig() {
        query = "/config"
    }
    
    func resetState() {
        liveKnowledgeTask?.cancel()
        liveKnowledgeTask = nil
        query = ""
        currentIntent = nil
        executionResult = nil
        isProcessing = false
        isExecuting = false
        matchedApps = []
        selectedAppIndex = 0
        selectedHelpIndex = 0
        showHelp = false
        showConfig = false
        inlineText = ""
    }
    
    private func startLiveKnowledgeQuery(_ intent: RecognizedIntent) {
        inlineText = "正在通过 Codex 快速查询..."
        isProcessing = true
        isExecuting = false
        
        let inputSnapshot = query
        liveKnowledgeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !Task.isCancelled else { return }
            guard self.query == inputSnapshot else { return }
            
            let result = await self.executor.execute(intent, recordConversation: false)
            guard !Task.isCancelled else { return }
            
            self.inlineText = result.output ?? "⚠️ 未返回结果"
            self.executionResult = result
            self.isProcessing = false
            self.isExecuting = false
            self.readResultIfNeeded(result)
        }
    }

    private func bindVoice() {
        voiceAssistant.$isListening
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.voiceListening = value
            }
            .store(in: &cancellables)

        voiceAssistant.$statusText
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                self?.voiceStatusText = text
            }
            .store(in: &cancellables)

        voiceAssistant.onCommand = { [weak self] command in
            guard let self else { return }
            self.handleVoiceCommand(command)
        }
    }

    private func observeSettings() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncVoiceFromSettings()
            }
        }
    }

    private func syncVoiceFromSettings() {
        if SynapseSettings.voiceEnabled {
            voiceAssistant.start()
        } else {
            voiceAssistant.stop()
        }
    }

    private func handleVoiceCommand(_ raw: String) {
        let command = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        query = command
        if SynapseSettings.voiceAutoExecute {
            executeCurrentIntent()
        }
    }

    func toggleVoice() {
        SynapseSettings.voiceEnabled.toggle()
        syncVoiceFromSettings()
    }

    private func readResultIfNeeded(_ result: ExecutionResult) {
        guard SynapseSettings.voiceEnabled, SynapseSettings.voiceSpeakResponse else { return }
        let text = (result.output ?? (result.isSuccess ? "执行完成" : "执行失败"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        voiceAssistant.speak(text)
    }

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }
}

// MARK: - 通知
extension Notification.Name {
    static let synapseDismiss = Notification.Name("synapseDismiss")
}
