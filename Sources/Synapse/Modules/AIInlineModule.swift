// MARK: - Modules/AIInlineModule.swift
// AI 内联模块 — 知识查询 + 代码生成 + 文案写作
// 统一使用 Codex CLI

import Foundation

/// AI 内联功能
final class AIInlineModule {
    
    private struct CLIRunResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }
    
    private static var responseMode: String {
        let mode = ProcessInfo.processInfo.environment["SYNAPSE_CODEX_RESPONSE_MODE"] ?? SynapseSettings.responseMode
        return SynapseSettings.normalizedMode(mode)
    }

    private static var selectedModel: String {
        let env = ProcessInfo.processInfo.environment
        switch responseMode {
        case "think":
            return env["SYNAPSE_CODEX_THINK_MODEL"] ?? SynapseSettings.thinkModel
        case "deep_research":
            return env["SYNAPSE_CODEX_DEEP_RESEARCH_MODEL"] ?? SynapseSettings.deepResearchModel
        default:
            return env["SYNAPSE_CODEX_FAST_MODEL"] ?? SynapseSettings.fastModel
        }
    }

    private static var effectiveReasoningEffort: String {
        let env = ProcessInfo.processInfo.environment
        switch responseMode {
        case "think":
            return env["SYNAPSE_CODEX_THINK_REASONING_EFFORT"] ?? SynapseSettings.thinkReasoningEffort
        case "deep_research":
            return env["SYNAPSE_CODEX_DEEP_RESEARCH_REASONING_EFFORT"] ?? SynapseSettings.deepResearchReasoningEffort
        default:
            return env["SYNAPSE_CODEX_FAST_REASONING_EFFORT"] ?? SynapseSettings.fastReasoningEffort
        }
    }

    private static var useWebSearchInKnowledge: Bool {
        if responseMode == "deep_research" { return true }
        return SynapseSettings.enableWebSearch
    }

    private static var aiVisualStyle: String {
        SynapseSettings.aiVisualStyle
    }
    
    private static var responseModeLabel: String {
        switch responseMode {
        case "think": return "Think"
        case "deep_research": return "Deep Research"
        default: return "Fast"
        }
    }

    private static var codexExecutableCandidates: [String] {
        var paths: [String] = []
        if let configured = ProcessInfo.processInfo.environment["SYNAPSE_CODEX_BIN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty {
            paths.append(configured)
        }
        paths.append(contentsOf: [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex",
            "/bin/codex",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/share/mise/shims/codex",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/codex",
        ])
        return paths
    }
    
    private static func adjustedTimeout(_ base: TimeInterval) -> TimeInterval {
        switch responseMode {
        case "think": return max(3, base * 1.6)
        case "deep_research": return max(3, base * 2.4)
        default: return max(3, base)
        }
    }
    
    // MARK: - 知识查询（Codex CLI）
    
    func queryKnowledge(_ query: String) async -> String {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return "请输入问题" }
        
        let runResult = await Task.detached(priority: .utility, operation: {
            Self.runCodexKnowledgeSync(normalizedQuery, webSearch: Self.useWebSearchInKnowledge)
        }).value
        
        let output = Self.sanitizeCLIText(runResult.stdout)
        if runResult.status == 0 && !output.isEmpty {
            return """
            # 知识回答
            
            **问题**：\(normalizedQuery)
            
            \(output)
            """
        }

        if Self.useWebSearchInKnowledge {
            let webFallback = await WebSearchModule().search(normalizedQuery)
            if !webFallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !webFallback.contains("未检索到可用结果") {
                return """
                # 知识回答（联网兜底）

                **问题**：\(normalizedQuery)

                Codex 当前不可用，已自动切换为联网搜索结果：

                \(webFallback)
                """
            }
        }
        
        let errorOutput = Self.extractCodexError(runResult.stderr)
        let diagnosis = errorOutput.isEmpty ? "Codex CLI 未返回可用内容" : errorOutput
        return """
        # ⚠️ Codex 查询失败
        
        **问题**：\(normalizedQuery)
        **诊断**：\(diagnosis)
        **模型**：\(Self.selectedModel)
        **模式**：\(Self.responseModeLabel)
        **推理强度**：\(Self.effectiveReasoningEffort)
        **可执行**：\(Self.resolvedCodexExecutable())
        
        请先在终端确认：
        `codex exec -m \(Self.selectedModel) \(Self.useWebSearchInKnowledge ? "--search " : "")"你好"`
        """
    }

    // MARK: - AI 翻译

    func translateText(_ query: String) async -> String {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return "请输入要翻译的内容" }

        let runResult = await Task.detached(priority: .utility, operation: {
            Self.runCodexTranslationSync(normalizedQuery)
        }).value

        let output = Self.sanitizeCLIText(runResult.stdout)
        if runResult.status == 0 && !output.isEmpty {
            return """
            # 翻译结果

            **输入**：\(normalizedQuery)

            \(output)
            """
        }

        let errorOutput = Self.extractCodexError(runResult.stderr)
        let diagnosis = errorOutput.isEmpty ? "Codex CLI 未返回可用内容" : errorOutput
        return """
        # ⚠️ Codex 翻译失败

        **输入**：\(normalizedQuery)
        **诊断**：\(diagnosis)
        **模型**：\(Self.selectedModel)
        **模式**：\(Self.responseModeLabel)
        **推理强度**：\(Self.effectiveReasoningEffort)

        请先在终端确认：
        `codex exec -m \(Self.selectedModel) "把 hello 翻译成中文"`
        """
    }

    private static func runCodexKnowledgeSync(_ query: String, webSearch: Bool) -> CLIRunResult {
        let modeRequirement: String = {
            switch responseMode {
            case "think":
                return "5) 开启 Think 模式：给出更充分的依据与边界条件分析。"
            case "deep_research":
                return """
                5) 开启 Deep Research 模式：优先使用最新公开信息，给出 2-4 条可访问来源链接。
                6) 明确区分“已知事实”和“推断”。
                """
            default:
                return "5) 开启 Fast 模式：优先响应速度，保证结论清晰。"
            }
        }()

        let styleRule = matrixStyleRule()
        let context = contextPreamble()
        
        let prompt = """
        你是中文知识助手。请对用户问题给出准确、简洁、结构化回答。
        要求：
        1) 全文中文。
        2) 使用 Markdown 输出。
        3) 按这个结构：
           ## 结论
           （1-2 句）
           ## 要点
           - 要点 1
           - 要点 2
           - 要点 3
        4) 总长度控制在 220-420 字。
        \(styleRule)
        \(modeRequirement)
        
        \(context)
        
        问题：\(query)
        """
        return runCodex(prompt: prompt, timeout: adjustedTimeout(SynapseSettings.knowledgeTimeout), allowWebSearch: webSearch)
    }

    private static func runCodexTranslationSync(_ query: String) -> CLIRunResult {
        let styleRule = matrixStyleRule()
        let context = contextPreamble()
        let prompt = """
        你是专业翻译助手。请按以下规则翻译用户输入：
        1) 自动判断源语言与目标语言；若用户明确指定目标语言，按用户指定执行。
        2) 先给“译文”，再给“术语说明”（最多 3 条）。
        3) 保留专有名词、代码、URL、数字与单位准确性。
        4) 输出使用 Markdown。
        \(styleRule)
        
        \(context)

        用户输入：\(query)
        """
        return runCodex(prompt: prompt, timeout: adjustedTimeout(SynapseSettings.knowledgeTimeout), allowWebSearch: false)
    }
    
    private static func runCodexWritingSync(_ query: String) -> CLIRunResult {
        let styleRule = matrixStyleRule()
        let context = contextPreamble()
        let prompt = """
        你是中文写作助手。请根据用户需求直接给出可用内容。
        要求：
        1) 输出最终稿，不要解释过程。
        2) 使用 Markdown 排版（标题/小节/列表）。
        3) 语气自然，结构清晰。
        4) 若需求不完整，做合理补全并明确分段。
        \(styleRule)
        
        \(context)
        
        需求：\(query)
        """
        return runCodex(prompt: prompt, timeout: adjustedTimeout(SynapseSettings.writingTimeout), allowWebSearch: false)
    }
    
    private static func runCodexSync(query: String, language: String) -> CLIRunResult {
        let styleRule = matrixStyleRule()
        let context = contextPreamble()
        let prompt = """
        你是资深工程师。请根据需求生成可运行的\(language)代码。
        规则：
        1) 直接给最终答案，不要解释性段落。
        2) 仅输出一个 Markdown 代码块。
        3) 代码尽量简洁并可直接执行。
        4) 不要输出任何运行日志、前后缀说明或额外标题。
        \(styleRule)
        
        \(context)
        
        需求：\(query)
        """
        return runCodex(prompt: prompt, timeout: adjustedTimeout(SynapseSettings.codeTimeout), allowWebSearch: false)
    }
    
    private static func runCodex(prompt: String, timeout: TimeInterval, allowWebSearch: Bool) -> CLIRunResult {
        let model = selectedModel
        var lastResult = CLIRunResult(status: -1, stdout: "", stderr: "Codex CLI 未执行")

        let searchCandidates: [Bool] = allowWebSearch ? [true, false] : [false]
        for searchEnabled in searchCandidates {
            let attempts: [TimeInterval] = [timeout, max(timeout * 2.2, timeout + 8)]
            for (index, attemptTimeout) in attempts.enumerated() {
                let outputPath = (NSTemporaryDirectory() as NSString)
                    .appendingPathComponent("synapse-codex-\(UUID().uuidString).txt")
                let command = buildCodexCommand(
                    prompt: prompt,
                    outputPath: outputPath,
                    model: model,
                    searchEnabled: searchEnabled
                )
                let run = runCommand(command, timeout: attemptTimeout)
                
                let captured = (try? String(contentsOfFile: outputPath, encoding: .utf8)) ?? ""
                try? FileManager.default.removeItem(atPath: outputPath)
                
                let mergedStdout = captured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? run.stdout : captured
                let mergedResult = CLIRunResult(status: run.status, stdout: mergedStdout, stderr: run.stderr)
                lastResult = mergedResult
                
                let cleaned = sanitizeCLIText(mergedStdout)
                if run.status == 0 && !cleaned.isEmpty {
                    return mergedResult
                }
                
                let lowerError = mergedResult.stderr.lowercased()
                if searchEnabled && lowerError.contains("unexpected argument '--search'") {
                    break
                }
                
                let needsRetry = index == 0 && shouldRetry(run: mergedResult)
                if needsRetry { continue }
                break
            }
        }

        return lastResult
    }
    
    private static func shouldRetry(run: CLIRunResult) -> Bool {
        let stdout = sanitizeCLIText(run.stdout)
        let stderr = sanitizeCLIText(run.stderr)
        if run.status == 0 && !stdout.isEmpty { return false }
        
        let lowerError = stderr.lowercased()
        let retrySignals = [
            "timed out",
            "timeout",
            "mcp startup",
            "handshaking with mcp server failed",
            "connection closed",
        ]
        if retrySignals.contains(where: { lowerError.contains($0) }) {
            return true
        }

        let stopSignals = [
            "unexpected argument '--search'",
            "not supported when using codex with a chatgpt account",
            "invalid model",
            "unknown model",
        ]
        if stopSignals.contains(where: { lowerError.contains($0) }) {
            return false
        }
        
        if run.status != 0 && stdout.isEmpty {
            return true
        }
        return false
    }
    
    private static func buildCodexCommand(
        prompt: String,
        outputPath: String,
        model: String,
        searchEnabled: Bool
    ) -> String {
        let reasoningConfig = "model_reasoning_effort=\"\(effectiveReasoningEffort)\""
        let codexExecutable = shellQuote(resolvedCodexExecutable())
        var parts = [
            "\(codexExecutable) exec",
            "--skip-git-repo-check",
            "--color never",
            "-m \(shellQuote(model))",
            "-c \(shellQuote(reasoningConfig))",
        ]
        if searchEnabled {
            parts.append("--search")
        }
        if SynapseSettings.disableMCPServers {
            parts.append("-c mcp_servers.playwright.enabled=false")
            parts.append("-c mcp_servers.figma.enabled=false")
        }
        parts.append("--output-last-message \(shellQuote(outputPath))")
        parts.append(shellQuote(prompt))
        return parts.joined(separator: " ")
    }

    private static func contextPreamble() -> String {
        let memory = MemoryStore.shared.contextSnippet()
        let history = ConversationHistoryStore.shared.contextSnippet()
        var blocks: [String] = []

        if !memory.isEmpty {
            blocks.append("""
            ### Memory（长期偏好/事实）
            \(memory)
            """)
        }

        if !history.isEmpty {
            blocks.append("""
            ### Recent Conversation（最近对话）
            \(history)
            """)
        }

        guard !blocks.isEmpty else { return "" }
        return """
        你可参考以下上下文（若与当前问题冲突，以当前问题为准）：
        \(blocks.joined(separator: "\n\n"))
        """
    }

    private static func matrixStyleRule() -> String {
        guard aiVisualStyle == "matrix" else { return "" }
        return """
        额外风格要求：采用“Matrix 终端”风格的简洁表达，标题可使用如「## [MATRIX] 结论」，避免花哨 emoji。
        """
    }
    
    private static func runCommand(_ command: String, timeout: TimeInterval) -> CLIRunResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.environment = cliEnvironment()
        
        do {
            try process.run()
            
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { process.terminate() }
            }
            
            process.waitUntilExit()
            
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            
            return CLIRunResult(
                status: process.terminationStatus,
                stdout: stdout,
                stderr: stderr
            )
        } catch {
            return CLIRunResult(
                status: -1,
                stdout: "",
                stderr: error.localizedDescription
            )
        }
    }
    
    private static func shellQuote(_ input: String) -> String {
        let escaped = input.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    private static func cliEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let basePath = [
            environment["PATH"] ?? "",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "\(home)/.local/share/mise/shims",
            "\(home)/.local/bin",
            "\(home)/.npm-global/bin",
        ]
        environment["PATH"] = uniquePathComponents(basePath).joined(separator: ":")
        environment["HOME"] = home
        return environment
    }

    private static func uniquePathComponents(_ pathItems: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for item in pathItems {
            let segments = item
                .split(separator: ":")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            for segment in segments where !segment.isEmpty {
                guard !seen.contains(segment) else { continue }
                seen.insert(segment)
                ordered.append(segment)
            }
        }
        return ordered
    }

    private static func resolvedCodexExecutable() -> String {
        for candidate in codexExecutableCandidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }

        let pathDirs = uniquePathComponents([
            ProcessInfo.processInfo.environment["PATH"] ?? "",
            "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        ])
        for dir in pathDirs {
            let candidate = (dir as NSString).appendingPathComponent("codex")
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return "codex"
    }
    
    private static func sanitizeCLIText(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        
        let withoutANSI = text.replacingOccurrences(
            of: #"\u{001B}\[[0-9;]*[A-Za-z]"#,
            with: "",
            options: .regularExpression
        )
        
        let lines = withoutANSI.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        let cleaned = lines.filter { line in
            !line.isEmpty &&
            !isCodexRuntimeNoise(line) &&
            !line.contains("Loaded cached credentials") &&
            !line.contains("Hook registry initialized") &&
            !line.contains("Loading") &&
            !line.hasPrefix("DEBUG") &&
            !line.hasPrefix("INFO")
        }
        
        return cleaned.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func isCodexRuntimeNoise(_ line: String) -> Bool {
        let lower = line.lowercased()
        if line == "--------" || lower == "user" || lower == "codex" { return true }
        
        let prefixes = [
            "openai codex",
            "workdir:",
            "model:",
            "provider:",
            "approval:",
            "sandbox:",
            "reasoning effort:",
            "reasoning summaries:",
            "session id:",
            "mcp startup:",
            "tokens used",
            "warning: no last agent message",
        ]
        if prefixes.contains(where: { lower.hasPrefix($0) }) { return true }
        
        if lower.hasPrefix("mcp: ") { return true }
        return false
    }
    
    private static func extractCodexError(_ stderr: String) -> String {
        let lowerRaw = stderr.lowercased()
        if lowerRaw.contains("command not found: codex") {
            return "未找到 codex CLI。请安装 Codex，并确认 \(resolvedCodexExecutable()) 在可执行路径中。"
        }

        let cleaned = sanitizeCLIText(stderr)
        guard !cleaned.isEmpty else { return "" }
        
        let lines = cleaned.components(separatedBy: .newlines)
        if let explicit = lines.first(where: { $0.localizedCaseInsensitiveContains("error:") }) {
            return explicit.replacingOccurrences(of: "ERROR:", with: "")
                .replacingOccurrences(of: "error:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        if let unsupported = lines.first(where: { $0.localizedCaseInsensitiveContains("not supported") }) {
            return unsupported
        }
        
        return Array(lines.prefix(3)).joined(separator: "\n")
    }
    
    /// Legacy fallback（当前不用于 AI 主链路）
    private func fetchDuckDuckGo(_ query: String) async -> String? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_html=1&skip_disambig=1") else {
            return nil
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            
            // Abstract（主要摘要）
            if let abstract = json["Abstract"] as? String, !abstract.isEmpty {
                let source = json["AbstractSource"] as? String ?? "DuckDuckGo"
                let abstractURL = json["AbstractURL"] as? String ?? ""
                return "📚 \(query)\n\n\(abstract)\n\n— \(source)\n🔗 \(abstractURL)"
            }
            
            // Answer（直接回答）
            if let answer = json["Answer"] as? String, !answer.isEmpty {
                return "💡 \(query)\n\n\(answer)"
            }
            
            // Definition
            if let definition = json["Definition"] as? String, !definition.isEmpty {
                let source = json["DefinitionSource"] as? String ?? ""
                return "📖 \(query)\n\n\(definition)\n\n— \(source)"
            }
            
            // Related Topics（前 5 个相关主题）
            if let topics = json["RelatedTopics"] as? [[String: Any]], !topics.isEmpty {
                var result = "🔗 \(query) — 相关主题\n"
                for topic in topics.prefix(5) {
                    if let text = topic["Text"] as? String, !text.isEmpty {
                        let preview = String(text.prefix(100))
                        result += "\n• \(preview)"
                    }
                }
                if result.count > 30 { return result }
            }
            
            return nil
        } catch {
            return nil
        }
    }
    
    /// Legacy fallback（当前不用于 AI 主链路）
    private func fetchWikipedia(_ query: String) async -> String? {
        // 尝试中文 Wikipedia
        let wikis = [
            ("zh", "https://zh.wikipedia.org/api/rest_v1/page/summary/"),
            ("en", "https://en.wikipedia.org/api/rest_v1/page/summary/")
        ]
        
        for (lang, baseURL) in wikis {
            guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let url = URL(string: baseURL + encoded) else { continue }
            
            do {
                var request = URLRequest(url: url)
                request.setValue("Synapse/1.0", forHTTPHeaderField: "User-Agent")
                request.timeoutInterval = 5
                
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { continue }
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                
                let title = json["title"] as? String ?? query
                let extract = json["extract"] as? String ?? ""
                let pageURL = (json["content_urls"] as? [String: Any])?["desktop"] as? [String: Any]
                let link = pageURL?["page"] as? String ?? ""
                
                if !extract.isEmpty {
                    let langLabel = lang == "zh" ? "维基百科" : "Wikipedia"
                    return "📚 \(title)\n\n\(extract)\n\n— \(langLabel)\n🔗 \(link)"
                }
            } catch {
                continue
            }
        }
        
        return nil
    }
    
    // MARK: - 代码生成
    
    func generateCode(_ query: String) async -> String {
        let lower = query.lowercased()
        
        // 提取语言和需求
        let language = detectLanguage(lower)
        let task = extractCodeTask(query)
        let normalizedTask = task.isEmpty ? query : task
        
        // 优先交给 Codex CLI
        let codexResult = await Task.detached(priority: .userInitiated, operation: {
            Self.runCodexSync(query: normalizedTask, language: language)
        }).value
        
        let codexOutput = Self.sanitizeCLIText(codexResult.stdout)
        if codexResult.status == 0, !codexOutput.isEmpty {
            return """
            💻 Codex \(language) 代码
            
            \(codexOutput)
            
            ↵ 按回车复制代码
            """
        }
        
        let diagnostic = Self.sanitizeCLIText(codexResult.stderr)
        let detail = diagnostic.isEmpty ? "无可用诊断信息" : diagnostic
        return """
        ⚠️ Codex 代码生成失败
        需求: \(normalizedTask)
        诊断: \(detail)
        
        请先在终端确认:
        codex exec "写一段 Python 代码打印 hello"
        """
    }
    
    private func detectLanguage(_ query: String) -> String {
        let langs: [(keywords: [String], name: String)] = [
            (["swift", "swiftui", "ios", "macos"], "Swift"),
            (["python", "py"], "Python"),
            (["javascript", "js", "node", "react", "vue"], "JavaScript"),
            (["typescript", "ts"], "TypeScript"),
            (["java", "spring"], "Java"),
            (["go", "golang"], "Go"),
            (["rust"], "Rust"),
            (["c++", "cpp"], "C++"),
            (["c#", "csharp", "dotnet"], "C#"),
            (["ruby", "rails"], "Ruby"),
            (["php"], "PHP"),
            (["sql", "mysql", "postgres"], "SQL"),
            (["html", "css"], "HTML/CSS"),
            (["bash", "shell", "sh", "zsh"], "Shell"),
        ]
        
        for lang in langs {
            if lang.keywords.contains(where: { query.contains($0) }) {
                return lang.name
            }
        }
        return "Python" // 默认 Python
    }
    
    private func extractCodeTask(_ query: String) -> String {
        let removals = ["写", "编写", "生成", "代码", "code", "write", "create", "generate",
                       "一个", "帮我", "请", "用", "实现", "函数", "方法", "程序"]
        var result = query
        for r in removals {
            result = result.replacingOccurrences(of: r, with: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func generateTemplate(task: String, language: String) -> String {
        let lower = task.lowercased()
        
        // 常见代码模板
        if lower.contains("sort") || lower.contains("排序") {
            return codeBlock(language, sortTemplate(language))
        }
        if lower.contains("http") || lower.contains("请求") || lower.contains("api") || lower.contains("fetch") {
            return codeBlock(language, httpTemplate(language))
        }
        if lower.contains("file") || lower.contains("文件") || lower.contains("读") || lower.contains("写") {
            return codeBlock(language, fileTemplate(language))
        }
        if lower.contains("json") || lower.contains("解析") || lower.contains("parse") {
            return codeBlock(language, jsonTemplate(language))
        }
        if lower.contains("timer") || lower.contains("定时") || lower.contains("计时") {
            return codeBlock(language, timerTemplate(language))
        }
        if lower.contains("hello") || lower.contains("你好") {
            return codeBlock(language, helloTemplate(language))
        }
        
        // 通用模板
        return """
        💻 代码生成 [\(language)]
        
        需求: \(task.isEmpty ? "未指定" : task)
        
        \(codeBlock(language, helloTemplate(language)))
        
        💡 提示: 可以更具体描述需求，如：
        • "写一个 Python HTTP 请求"
        • "Swift 排序算法"
        • "JavaScript 读取 JSON 文件"
        """
    }
    
    private func codeBlock(_ lang: String, _ code: String) -> String {
        return "💻 \(lang) 代码\n\n```\n\(code)\n```\n\n↵ 按回车复制代码"
    }
    
    // MARK: - 代码模板库
    
    private func helloTemplate(_ lang: String) -> String {
        switch lang {
        case "Swift": return "import Foundation\n\nprint(\"Hello, World!\")"
        case "Python": return "def main():\n    print(\"Hello, World!\")\n\nif __name__ == \"__main__\":\n    main()"
        case "JavaScript": return "console.log('Hello, World!');"
        case "TypeScript": return "const greeting: string = 'Hello, World!';\nconsole.log(greeting);"
        case "Go": return "package main\n\nimport \"fmt\"\n\nfunc main() {\n    fmt.Println(\"Hello, World!\")\n}"
        case "Rust": return "fn main() {\n    println!(\"Hello, World!\");\n}"
        case "Java": return "public class Main {\n    public static void main(String[] args) {\n        System.out.println(\"Hello, World!\");\n    }\n}"
        case "Shell": return "#!/bin/bash\necho \"Hello, World!\""
        default: return "print(\"Hello, World!\")"
        }
    }
    
    private func sortTemplate(_ lang: String) -> String {
        switch lang {
        case "Swift":
            return """
            // 快速排序
            func quickSort<T: Comparable>(_ arr: [T]) -> [T] {
                guard arr.count > 1 else { return arr }
                let pivot = arr[arr.count / 2]
                let left = arr.filter { $0 < pivot }
                let middle = arr.filter { $0 == pivot }
                let right = arr.filter { $0 > pivot }
                return quickSort(left) + middle + quickSort(right)
            }
            
            let sorted = quickSort([3, 6, 8, 10, 1, 2, 1])
            print(sorted)
            """
        case "Python":
            return """
            def quick_sort(arr):
                if len(arr) <= 1:
                    return arr
                pivot = arr[len(arr) // 2]
                left = [x for x in arr if x < pivot]
                middle = [x for x in arr if x == pivot]
                right = [x for x in arr if x > pivot]
                return quick_sort(left) + middle + quick_sort(right)
            
            print(quick_sort([3, 6, 8, 10, 1, 2, 1]))
            """
        case "JavaScript":
            return """
            function quickSort(arr) {
                if (arr.length <= 1) return arr;
                const pivot = arr[Math.floor(arr.length / 2)];
                const left = arr.filter(x => x < pivot);
                const middle = arr.filter(x => x === pivot);
                const right = arr.filter(x => x > pivot);
                return [...quickSort(left), ...middle, ...quickSort(right)];
            }
            
            console.log(quickSort([3, 6, 8, 10, 1, 2, 1]));
            """
        default: return "# \(lang) 排序算法\n# 请参考该语言的标准库排序方法"
        }
    }
    
    private func httpTemplate(_ lang: String) -> String {
        switch lang {
        case "Swift":
            return """
            import Foundation
            
            func fetchData(from urlString: String) async throws -> Data {
                guard let url = URL(string: urlString) else {
                    throw URLError(.badURL)
                }
                let (data, _) = try await URLSession.shared.data(from: url)
                return data
            }
            
            // 使用
            // let data = try await fetchData(from: "https://api.example.com/data")
            """
        case "Python":
            return """
            import requests
            
            def fetch_data(url):
                response = requests.get(url)
                response.raise_for_status()
                return response.json()
            
            # 使用
            # data = fetch_data("https://api.example.com/data")
            # print(data)
            """
        case "JavaScript":
            return """
            async function fetchData(url) {
                const response = await fetch(url);
                if (!response.ok) throw new Error(`HTTP ${response.status}`);
                return await response.json();
            }
            
            // 使用
            // const data = await fetchData('https://api.example.com/data');
            """
        default: return "# \(lang) HTTP 请求\n# 请使用该语言的 HTTP 库"
        }
    }
    
    private func fileTemplate(_ lang: String) -> String {
        switch lang {
        case "Swift":
            return """
            import Foundation
            
            // 读取文件
            func readFile(_ path: String) throws -> String {
                return try String(contentsOfFile: path, encoding: .utf8)
            }
            
            // 写入文件
            func writeFile(_ path: String, content: String) throws {
                try content.write(toFile: path, atomically: true, encoding: .utf8)
            }
            """
        case "Python":
            return """
            # 读取文件
            def read_file(path):
                with open(path, 'r', encoding='utf-8') as f:
                    return f.read()
            
            # 写入文件
            def write_file(path, content):
                with open(path, 'w', encoding='utf-8') as f:
                    f.write(content)
            """
        case "JavaScript":
            return """
            const fs = require('fs').promises;
            
            // 读取文件
            async function readFile(path) {
                return await fs.readFile(path, 'utf8');
            }
            
            // 写入文件
            async function writeFile(path, content) {
                await fs.writeFile(path, content, 'utf8');
            }
            """
        default: return "# \(lang) 文件操作\n# 请参考该语言的文件 I/O API"
        }
    }
    
    private func jsonTemplate(_ lang: String) -> String {
        switch lang {
        case "Swift":
            return """
            import Foundation
            
            struct User: Codable {
                let name: String
                let age: Int
            }
            
            // JSON → 对象
            let jsonStr = #"{"name": "Alice", "age": 30}"#
            let user = try JSONDecoder().decode(User.self, from: jsonStr.data(using: .utf8)!)
            
            // 对象 → JSON
            let data = try JSONEncoder().encode(user)
            let output = String(data: data, encoding: .utf8)!
            """
        case "Python":
            return """
            import json
            
            # JSON → 字典
            json_str = '{"name": "Alice", "age": 30}'
            data = json.loads(json_str)
            print(data["name"])
            
            # 字典 → JSON
            output = json.dumps(data, ensure_ascii=False, indent=2)
            print(output)
            """
        case "JavaScript":
            return """
            // JSON → 对象
            const jsonStr = '{"name": "Alice", "age": 30}';
            const data = JSON.parse(jsonStr);
            console.log(data.name);
            
            // 对象 → JSON
            const output = JSON.stringify(data, null, 2);
            console.log(output);
            """
        default: return "# \(lang) JSON 解析\n# 请参考该语言的 JSON 库"
        }
    }
    
    private func timerTemplate(_ lang: String) -> String {
        switch lang {
        case "Swift":
            return """
            import Foundation
            
            // 定时器（每秒执行）
            let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                print("Tick: \\(Date())")
            }
            
            // 延迟执行
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                print("3 秒后执行")
                timer.invalidate()
            }
            """
        case "Python":
            return """
            import time
            import threading
            
            # 定时器
            def tick():
                print(f"Tick: {time.strftime('%H:%M:%S')}")
                threading.Timer(1.0, tick).start()
            
            # 延迟执行
            def delayed():
                time.sleep(3)
                print("3 秒后执行")
            
            tick()
            """
        case "JavaScript":
            return """
            // 定时器（每秒执行）
            const timer = setInterval(() => {
                console.log('Tick:', new Date().toLocaleTimeString());
            }, 1000);
            
            // 延迟执行
            setTimeout(() => {
                console.log('3 秒后执行');
                clearInterval(timer);
            }, 3000);
            """
        default: return "# \(lang) 定时器\n# 请参考该语言的定时器 API"
        }
    }
    
    // MARK: - 文案写作
    
    func generateContent(_ query: String) async -> String {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return "请输入写作需求" }
        
        let runResult = await Task.detached(priority: .utility, operation: {
            Self.runCodexWritingSync(normalizedQuery)
        }).value
        
        let output = Self.sanitizeCLIText(runResult.stdout)
        if runResult.status == 0 && !output.isEmpty {
            return "✍️ \(normalizedQuery)\n\n\(output)"
        }
        
        let errorOutput = Self.sanitizeCLIText(runResult.stderr)
        let diagnosis = errorOutput.isEmpty ? "Codex CLI 未返回可用内容" : errorOutput
        return """
        ⚠️ Codex 写作失败
        
        需求: \(normalizedQuery)
        诊断: \(diagnosis)
        
        请先在终端确认:
        codex exec "写一封简短的请假邮件"
        """
    }
    
    private func extractWritingTopic(_ query: String) -> String {
        let removals = ["写", "创作", "生成", "文案", "文章", "内容", "一篇", "一封", "帮我", "请", "关于",
                       "write", "create", "generate", "content", "article", "about"]
        var result = query
        for r in removals {
            result = result.replacingOccurrences(of: r, with: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func emailTemplate(_ topic: String) -> String {
        return """
        ✉️ 邮件模板
        
        主题: Re: \(topic.isEmpty ? "[主题]" : topic)
        
        ---
        
        尊敬的 [收件人姓名]：
        
        您好！
        
        [正文内容]
        
        期待您的回复。
        
        此致
        敬礼
        
        [您的姓名]
        [日期]
        
        ---
        
        ↵ 按回车复制模板
        """
    }
    
    private func resumeTemplate() -> String {
        return """
        📄 简历模板
        
        ━━━━━━━━━━━━━━━━━━━
        [姓名]
        [电话] | [邮箱] | [城市]
        ━━━━━━━━━━━━━━━━━━━
        
        📌 个人简介
        [2-3句概括你的核心竞争力]
        
        💼 工作经历
        ┌ [公司名] — [职位]  [时间]
        │ • [成就1：用数据量化]
        │ • [成就2]
        └
        
        🎓 教育背景
        [学校] — [学位] [专业]  [时间]
        
        🛠 技能
        [技能1] | [技能2] | [技能3]
        
        ━━━━━━━━━━━━━━━━━━━
        
        ↵ 按回车复制模板
        """
    }
}
