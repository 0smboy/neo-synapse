import Foundation
import AppKit

private struct VoiceHistoryEntry: Codable {
    let role: String
    let text: String
    let timestamp: Date
}

private struct ScheduledTask: Codable {
    let id: String
    let time: Date
    let task: String
    let completed: Bool
}

private struct WatchedFile: Codable {
    let path: String
    let lastModified: Date
    let callback: String?
}

private final class VoiceStore {
    static let shared = VoiceStore()

    private let fm = FileManager.default
    private let root: URL
    private let memoryURL: URL
    private let historyURL: URL
    private let personalityURL: URL
    private let scheduleURL: URL
    private let watchURL: URL

    private init() {
        let home = fm.homeDirectoryForCurrentUser
        root = home.appendingPathComponent(".synapse-voice", isDirectory: true)
        memoryURL = root.appendingPathComponent("memory.md")
        historyURL = root.appendingPathComponent("history.json")
        personalityURL = root.appendingPathComponent("personality.md")
        scheduleURL = root.appendingPathComponent("schedule.json")
        watchURL = root.appendingPathComponent("watch.json")
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: memoryURL.path) {
            try? "# SynapseVoice Memory\n\n".data(using: .utf8)?.write(to: memoryURL)
        }
        if !fm.fileExists(atPath: historyURL.path) {
            try? "[]".data(using: .utf8)?.write(to: historyURL)
        }
        if !fm.fileExists(atPath: personalityURL.path) {
            let defaultPersonality = """
            # Neo - SynapseVoice Personality

            Name: Neo
            Type: Friendly AI Assistant with a hint of sarcasm
            Style: Helpful, witty, slightly sarcastic but always professional
            Tone: Conversational, confident, occasionally playful
            Response Format: Direct answers with occasional dry humor
            """
            try? defaultPersonality.data(using: .utf8)?.write(to: personalityURL)
        }
        if !fm.fileExists(atPath: scheduleURL.path) {
            try? "[]".data(using: .utf8)?.write(to: scheduleURL)
        }
        if !fm.fileExists(atPath: watchURL.path) {
            try? "[]".data(using: .utf8)?.write(to: watchURL)
        }
    }

    func appendMemory(_ text: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "Memory 内容为空。" }
        let line = "- \(cleaned)\n"
        if let data = line.data(using: .utf8),
           let handle = try? FileHandle(forWritingTo: memoryURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
        return "已写入 Memory。"
    }

    func readMemory(maxChars: Int = 1200) -> String {
        guard let text = try? String(contentsOf: memoryURL, encoding: .utf8) else {
            return ""
        }
        if text.count <= maxChars { return text }
        return String(text.suffix(maxChars))
    }

    func appendHistory(role: String, text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        var history = loadHistory()
        history.append(VoiceHistoryEntry(role: role, text: cleaned, timestamp: Date()))
        // Keep last 200 entries for storage, but use last 20 for context
        if history.count > 200 {
            history = Array(history.suffix(200))
        }
        saveHistory(history)
    }

    func recentHistory(limit: Int = 20) -> String {
        let history = Array(loadHistory().suffix(max(1, limit)))
        guard !history.isEmpty else { return "" }
        return history.map { "\($0.role.uppercased()): \($0.text)" }.joined(separator: "\n")
    }

    func getConversationContext() -> String {
        let history = loadHistory()
        let recent = Array(history.suffix(20))
        guard !recent.isEmpty else { return "" }
        return recent.map { "\($0.role.uppercased()): \($0.text)" }.joined(separator: "\n")
    }

    func getHistoryCount() -> Int {
        loadHistory().count
    }

    func summarizeOldConversations() {
        let history = loadHistory()
        guard history.count > 50 else { return }
        // Keep last 20 detailed, summarize older ones
        let oldEntries = Array(history.prefix(history.count - 20))
        let summary = "Previous conversation summary: \(oldEntries.count) exchanges covering various topics."
        // Could implement actual summarization here
    }

    func getPersonality() -> String {
        guard let text = try? String(contentsOf: personalityURL, encoding: .utf8) else {
            return "Name: Neo\nType: Friendly AI Assistant\nStyle: Helpful, witty, slightly sarcastic"
        }
        return text
    }

    func savePersonality(_ content: String) -> String {
        do {
            try content.write(to: personalityURL, atomically: true, encoding: .utf8)
            return "Personality updated."
        } catch {
            return "Failed to save personality: \(error.localizedDescription)"
        }
    }

    func addSchedule(time: Date, task: String) -> String {
        var schedules = loadSchedules()
        let id = UUID().uuidString
        schedules.append(ScheduledTask(id: id, time: time, task: task, completed: false))
        saveSchedules(schedules)
        return "Scheduled task '\(task)' for \(formatDate(time))"
    }

    func getPendingSchedules() -> [ScheduledTask] {
        let schedules = loadSchedules()
        let now = Date()
        return schedules.filter { !$0.completed && $0.time <= now }
    }

    func completeSchedule(id: String) {
        var schedules = loadSchedules()
        for i in 0..<schedules.count {
            if schedules[i].id == id {
                schedules[i] = ScheduledTask(id: schedules[i].id, time: schedules[i].time, task: schedules[i].task, completed: true)
                break
            }
        }
        saveSchedules(schedules)
    }

    func addWatch(path: String, callback: String? = nil) -> String {
        var watches = loadWatches()
        let expandedPath = (path as NSString).expandingTildeInPath
        watches.append(WatchedFile(path: expandedPath, lastModified: Date(), callback: callback))
        saveWatches(watches)
        return "Watching \(expandedPath)"
    }

    func getWatches() -> [WatchedFile] {
        loadWatches()
    }

    func updateWatchLastModified(path: String, date: Date) {
        var watches = loadWatches()
        for i in 0..<watches.count {
            if watches[i].path == path {
                watches[i] = WatchedFile(path: watches[i].path, lastModified: date, callback: watches[i].callback)
                break
            }
        }
        saveWatches(watches)
    }

    private func loadHistory() -> [VoiceHistoryEntry] {
        guard let data = try? Data(contentsOf: historyURL),
              let decoded = try? JSONDecoder().decode([VoiceHistoryEntry].self, from: data) else {
            return []
        }
        return decoded
    }

    private func saveHistory(_ history: [VoiceHistoryEntry]) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        try? data.write(to: historyURL, options: .atomic)
    }

    private func loadSchedules() -> [ScheduledTask] {
        guard let data = try? Data(contentsOf: scheduleURL),
              let decoded = try? JSONDecoder().decode([ScheduledTask].self, from: data) else {
            return []
        }
        return decoded
    }

    private func saveSchedules(_ schedules: [ScheduledTask]) {
        guard let data = try? JSONEncoder().encode(schedules) else { return }
        try? data.write(to: scheduleURL, options: .atomic)
    }

    private func loadWatches() -> [WatchedFile] {
        guard let data = try? Data(contentsOf: watchURL),
              let decoded = try? JSONDecoder().decode([WatchedFile].self, from: data) else {
            return []
        }
        return decoded
    }

    private func saveWatches(_ watches: [WatchedFile]) {
        guard let data = try? JSONEncoder().encode(watches) else { return }
        try? data.write(to: watchURL, options: .atomic)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private final class PiAgentCore {
    func read(path: String) -> String {
        let p = expand(path)
        guard let text = try? String(contentsOfFile: p, encoding: .utf8) else {
            return "read 失败：无法读取 \(p)"
        }
        return text
    }

    func write(path: String, content: String) -> String {
        let p = expand(path)
        let url = URL(fileURLWithPath: p)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return "write 成功：\(p)"
        } catch {
            return "write 失败：\(error.localizedDescription)"
        }
    }

    func edit(path: String, find: String, replace: String) -> String {
        let p = expand(path)
        guard let original = try? String(contentsOfFile: p, encoding: .utf8) else {
            return "edit 失败：无法读取 \(p)"
        }
        let updated = original.replacingOccurrences(of: find, with: replace)
        do {
            try updated.write(toFile: p, atomically: true, encoding: .utf8)
            return "edit 成功：\(p)"
        } catch {
            return "edit 失败：\(error.localizedDescription)"
        }
    }

    func bash(command: String) -> String {
        let process = Process()
        let out = Pipe()
        let err = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
            process.waitUntilExit()
            let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return [stdout, stderr].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return "bash 失败：\(error.localizedDescription)"
        }
    }

    private func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}

private final class VoiceOutput {
    private let enabled: Bool

    init(enabled: Bool) {
        self.enabled = enabled
    }

    func speak(_ text: String) {
        guard enabled else { return }
        let clean = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        task.arguments = ["-v", "Tingting", clean]
        try? task.run()
    }
}

private final class MatrixOutput {
    static func printBanner() {
        let banner = """
        
        ╔═══════════════════════════════════════════════════════════╗
        ║                                                           ║
        ║     ███████╗██╗   ██╗███╗   ██╗ █████╗ ███████╗███████╗ ║
        ║     ██╔════╝╚██╗ ██╔╝████╗  ██║██╔══██╗██╔════╝██╔════╝ ║
        ║     ███████╗ ╚████╔╝ ██╔██╗ ██║███████║███████╗█████╗   ║
        ║     ╚════██║  ╚██╔╝  ██║╚██╗██║██╔══██║╚════██║██╔══╝   ║
        ║     ███████║   ██║   ██║ ╚████║██║  ██║███████║███████╗ ║
        ║     ╚══════╝   ╚═╝   ╚═╝  ╚═══╝╚═╝  ╚═╝╚══════╝╚══════╝ ║
        ║                                                           ║
        ║              V O I C E   P E T   R O B O T                ║
        ║                                                           ║
        ╚═══════════════════════════════════════════════════════════╝
        
        """
        printGreen(banner)
    }

    static func printGreen(_ text: String, animated: Bool = false) {
        if animated {
            printTypingAnimation(text)
        } else {
            print("\u{001B}[32m\(text)\u{001B}[0m")
        }
    }

    static func printPrompt() {
        print("\u{001B}[32mneo> \u{001B}[0m", terminator: "")
    }

    private static func printTypingAnimation(_ text: String) {
        let chars = Array(text)
        for char in chars {
            print("\u{001B}[32m\(char)\u{001B}[0m", terminator: "")
            fflush(stdout)
            usleep(10000) // 10ms delay for typing effect
        }
        print()
    }
}

private enum ParsedIntent {
    case read(String)
    case write(path: String, content: String)
    case edit(path: String, find: String, replace: String)
    case bash(String)
    case remember(String)
    case memory
    case history
    case ask(String)
    case help
    case quit
    case status
    case search(String)
    case open(String)
    case weather
    case schedule(time: String, task: String)
    case watch(path: String, callback: String?)
    case agent(String)
    case personality
    case setPersonality(String)
}

private func parseIntent(_ input: String) -> ParsedIntent {
    let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if raw.isEmpty { return .help }
    if raw == "quit" || raw == "exit" || raw == ":q" { return .quit }
    if raw == "help" || raw == ":help" { return .help }
    if raw == "memory" { return .memory }
    if raw == "history" { return .history }
    if raw == "status" { return .status }
    if raw == "weather" { return .weather }
    if raw == "personality" { return .personality }
    if raw.lowercased().hasPrefix("remember ") {
        return .remember(String(raw.dropFirst("remember ".count)))
    }
    if raw.lowercased().hasPrefix("search ") {
        return .search(String(raw.dropFirst("search ".count)))
    }
    if raw.lowercased().hasPrefix("open ") {
        return .open(String(raw.dropFirst("open ".count)))
    }
    if raw.lowercased().hasPrefix("schedule ") {
        let rest = String(raw.dropFirst("schedule ".count))
        if let spaceIndex = rest.firstIndex(of: " ") {
            let timeStr = String(rest[..<spaceIndex])
            let task = String(rest[rest.index(after: spaceIndex)...])
            return .schedule(time: timeStr, task: task)
        }
    }
    if raw.lowercased().hasPrefix("watch ") {
        let rest = String(raw.dropFirst("watch ".count))
        if let spaceIndex = rest.firstIndex(of: " ") {
            let path = String(rest[..<spaceIndex])
            let callback = String(rest[rest.index(after: spaceIndex)...])
            return .watch(path: path, callback: callback.isEmpty ? nil : callback)
        } else {
            return .watch(path: rest, callback: nil)
        }
    }
    if raw.lowercased().hasPrefix("agent ") {
        return .agent(String(raw.dropFirst("agent ".count)))
    }
    if raw.lowercased().hasPrefix("set-personality ") {
        return .setPersonality(String(raw.dropFirst("set-personality ".count)))
    }

    if raw.lowercased().hasPrefix("read ") {
        return .read(String(raw.dropFirst("read ".count)))
    }

    if raw.lowercased().hasPrefix("bash ") {
        return .bash(String(raw.dropFirst("bash ".count)))
    }

    if raw.lowercased().hasPrefix("write "),
       let range = raw.range(of: "<<<") {
        let prefix = raw[raw.index(raw.startIndex, offsetBy: "write ".count)..<range.lowerBound]
        let content = raw[range.upperBound...]
        return .write(path: String(prefix).trimmingCharacters(in: .whitespacesAndNewlines),
                      content: String(content).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    if raw.lowercased().hasPrefix("edit "),
       let pipe = raw.range(of: "|"),
       let arrow = raw.range(of: "=>") {
        let path = raw[raw.index(raw.startIndex, offsetBy: "edit ".count)..<pipe.lowerBound]
        let find = raw[pipe.upperBound..<arrow.lowerBound]
        let replace = raw[arrow.upperBound...]
        return .edit(
            path: String(path).trimmingCharacters(in: .whitespacesAndNewlines),
            find: String(find).trimmingCharacters(in: .whitespacesAndNewlines),
            replace: String(replace).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    return .ask(raw)
}

private func parseTime(_ timeStr: String) -> Date? {
    let now = Date()
    let calendar = Calendar.current
    
    // Try parsing as "HH:MM" or "HHMM"
    let cleaned = timeStr.replacingOccurrences(of: ":", with: "")
    if cleaned.count == 4, let hour = Int(String(cleaned.prefix(2))), let minute = Int(String(cleaned.suffix(2))) {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        if let date = calendar.date(from: components) {
            // If time has passed today, schedule for tomorrow
            if date < now {
                return calendar.date(byAdding: .day, value: 1, to: date)
            }
            return date
        }
    }
    
    // Try parsing as relative time like "30m", "2h", "1d"
    if let value = Int(String(timeStr.dropLast())), timeStr.count > 1 {
        let unit = String(timeStr.suffix(1))
        switch unit.lowercased() {
        case "m":
            return calendar.date(byAdding: .minute, value: value, to: now)
        case "h":
            return calendar.date(byAdding: .hour, value: value, to: now)
        case "d":
            return calendar.date(byAdding: .day, value: value, to: now)
        default:
            break
        }
    }
    
    return nil
}

private func runCodex(query: String, personality: String, context: String, mute: Bool = false) -> String {
    let memory = VoiceStore.shared.readMemory()
    let history = VoiceStore.shared.recentHistory(limit: 20)
    
    let prompt = """
    你是 SynapseVoice（Headless AI Native 助手），一个具有个性的语音宠物机器人。
    
    [personality]
    \(personality)
    
    回答规则：
    1) 根据你的个性风格回答，体现你的性格特点。
    2) 先给结论，再给 3-5 条要点。
    3) 简洁、可执行，中文输出。
    4) 可引用下面的 memory 与 recent history，但若冲突以当前问题优先。
    5) 保持对话的连贯性和上下文理解。

    [memory]
    \(memory)

    [conversation_context]
    \(context)

    [recent_history]
    \(history)

    [user_query]
    \(query)
    """

    let escaped = prompt.replacingOccurrences(of: "'", with: "'\\''")
    let muteFlag = mute ? "--mute" : ""
    let command = "codex exec --skip-git-repo-check --color never \(muteFlag) -m gpt-5.3-codex '\(escaped)'"
    let process = Process()
    let out = Pipe()
    let err = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-lc", command]
    process.standardOutput = out
    process.standardError = err
    do {
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let content = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !content.isEmpty { return content }
        return "Codex 失败：\(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
    } catch {
        return "执行失败：\(error.localizedDescription)"
    }
}

private func executeAgentTask(_ task: String, core: PiAgentCore) -> String {
    // Autonomous multi-step task execution
    let query = """
    我需要执行以下任务：\(task)
    
    请分析任务并生成一个执行计划，使用以下工具：
    - read <path> - 读取文件
    - write <path> <<< <content> - 写入文件
    - edit <path> | <find> => <replace> - 编辑文件
    - bash <command> - 执行shell命令
    
    请以JSON格式返回执行计划，格式：
    {
      "steps": [
        {"action": "read|write|edit|bash", "params": {...}, "description": "..."}
      ]
    }
    """
    
    let planJson = runCodex(query: query, personality: VoiceStore.shared.getPersonality(), context: VoiceStore.shared.getConversationContext(), mute: true)
    
    // Parse and execute plan (simplified - in production would parse JSON properly)
    // For now, let Codex handle it directly with tool calls
    return runCodex(query: "执行任务：\(task)\n\n使用 read/write/edit/bash 工具完成。", personality: VoiceStore.shared.getPersonality(), context: VoiceStore.shared.getConversationContext(), mute: true)
}

private func checkScheduledTasks(core: PiAgentCore) {
    let pending = VoiceStore.shared.getPendingSchedules()
    for task in pending {
        MatrixOutput.printGreen("🔔 Scheduled reminder: \(task.task)")
        executeAgentTask(task.task, core: core)
        VoiceStore.shared.completeSchedule(id: task.id)
    }
}

private func checkWatchedFiles(core: PiAgentCore) {
    let watches = VoiceStore.shared.getWatches()
    let fm = FileManager.default
    
    for watch in watches {
        guard fm.fileExists(atPath: watch.path) else { continue }
        guard let attrs = try? fm.attributesOfItem(atPath: watch.path),
              let modified = attrs[.modificationDate] as? Date else { continue }
        
        if modified > watch.lastModified {
            MatrixOutput.printGreen("📝 File changed: \(watch.path)")
            if let callback = watch.callback, !callback.isEmpty {
                _ = core.bash(command: callback)
            }
            VoiceStore.shared.updateWatchLastModified(path: watch.path, date: modified)
        }
    }
}

@main
struct SynapseVoiceMain {
    static func main() {
        let mute = CommandLine.arguments.contains("--mute")
        let customPersonality = CommandLine.arguments.contains("--personality")
        let voice = VoiceOutput(enabled: !mute)
        let core = PiAgentCore()
        let store = VoiceStore.shared

        // Show banner
        MatrixOutput.printBanner()
        
        // Load personality
        let personality = store.getPersonality()
        if customPersonality {
            MatrixOutput.printGreen("Loaded custom personality from ~/.synapse-voice/personality.md")
        }

        MatrixOutput.printGreen("""
        SynapseVoice (Voice Pet Robot)
        Core tools: read/write/edit/bash
        Extra: memory/history/ask/status/search/open/weather
        Proactive: schedule/watch/agent
        Personality: Active
        
        输入 help 查看示例，输入 quit 退出。
        """, animated: true)

        // Background task checker
        var lastCheck = Date()
        let checkInterval: TimeInterval = 30.0 // Check every 30 seconds

        while true {
            // Check scheduled tasks and watched files periodically
            let now = Date()
            if now.timeIntervalSince(lastCheck) >= checkInterval {
                checkScheduledTasks(core: core)
                checkWatchedFiles(core: core)
                lastCheck = now
            }

            MatrixOutput.printPrompt()
            guard let line = readLine() else { break }

            let intent = parseIntent(line)
            let response: String
            switch intent {
            case .read(let path):
                response = core.read(path: path)
            case .write(let path, let content):
                response = core.write(path: path, content: content)
            case .edit(let path, let find, let replace):
                response = core.edit(path: path, find: find, replace: replace)
            case .bash(let cmd):
                response = core.bash(command: cmd)
            case .remember(let text):
                response = store.appendMemory(text)
            case .memory:
                response = store.readMemory()
            case .history:
                let rows = store.recentHistory(limit: 30)
                response = rows.isEmpty ? "暂无历史。" : rows
            case .status:
                let battery = core.bash(command: "pmset -g batt | grep -E '\\d+%' | awk '{print $3}' | sed 's/;//'")
                let disk = core.bash(command: "df -h / | tail -1 | awk '{print $5}'")
                let network = core.bash(command: "ifconfig | grep 'inet ' | grep -v 127.0.0.1 | head -1 | awk '{print $2}'")
                response = """
                System Status:
                Battery: \(battery.isEmpty ? "N/A" : battery)
                Disk Usage: \(disk.isEmpty ? "N/A" : disk)
                Network IP: \(network.isEmpty ? "N/A" : network)
                """
            case .search(let query):
                let results = core.bash(command: "find ~ -type f -name '*\(query)*' 2>/dev/null | head -20")
                response = results.isEmpty ? "No files found matching '\(query)'" : results
            case .open(let app):
                let result = core.bash(command: "open -a '\(app)'")
                response = result.isEmpty ? "Opened \(app)" : result
            case .weather:
                let weather = core.bash(command: "curl -s 'wttr.in?format=3'")
                response = weather.isEmpty ? "Weather service unavailable" : weather
            case .schedule(let timeStr, let task):
                if let time = parseTime(timeStr) {
                    response = store.addSchedule(time: time, task: task)
                } else {
                    response = "Invalid time format. Use HH:MM or relative time like 30m, 2h, 1d"
                }
            case .watch(let path, let callback):
                response = store.addWatch(path: path, callback: callback)
            case .agent(let task):
                store.appendHistory(role: "user", text: "agent: \(task)")
                response = executeAgentTask(task, core: core)
                store.appendHistory(role: "assistant", text: response)
            case .personality:
                response = store.getPersonality()
            case .setPersonality(let content):
                response = store.savePersonality(content)
            case .ask(let query):
                store.appendHistory(role: "user", text: query)
                let context = store.getConversationContext()
                let answer = runCodex(query: query, personality: personality, context: context, mute: mute)
                store.appendHistory(role: "assistant", text: answer)
                response = answer
            case .help:
                response = """
                用法:
                Core Tools:
                - read <path>
                - write <path> <<< <content>
                - edit <path> | <find> => <replace>
                - bash <command>
                
                Memory & History:
                - remember <text>
                - memory
                - history
                
                Built-in Commands:
                - status - 系统状态
                - search <query> - 搜索文件
                - open <app> - 启动应用
                - weather - 天气信息
                
                Proactive Features:
                - schedule <time> <task> - 安排提醒 (时间格式: HH:MM 或 30m/2h/1d)
                - watch <path> [callback] - 监控文件变化
                - agent <task> - 自主执行多步骤任务
                
                Personality:
                - personality - 查看当前个性
                - set-personality <content> - 设置个性
                
                Other:
                - <任意自然语言问题>  (会走 Codex)
                - quit
                """
            case .quit:
                MatrixOutput.printGreen("See you later, human. 👋")
                return
            }

            MatrixOutput.printGreen(response, animated: true)
            voice.speak(response)
            
            // Auto-summarize old conversations periodically
            if store.getHistoryCount() > 50 {
                store.summarizeOldConversations()
            }
        }
    }
}

