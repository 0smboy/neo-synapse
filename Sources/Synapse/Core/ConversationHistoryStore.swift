import Foundation

struct ConversationHistoryEntry: Codable, Identifiable {
    let id: UUID
    let role: String
    let action: String
    let text: String
    let timestamp: Date
    let sessionId: UUID? // Optional for backward compatibility
    
    init(id: UUID, role: String, action: String, text: String, timestamp: Date, sessionId: UUID? = nil) {
        self.id = id
        self.role = role
        self.action = action
        self.text = text
        self.timestamp = timestamp
        self.sessionId = sessionId
    }
}

struct ConversationSession: Codable, Identifiable {
    let id: UUID
    var startTime: Date
    var endTime: Date?
    var messageCount: Int
    var title: String
    var lastActivity: Date
    
    init(id: UUID, startTime: Date, endTime: Date? = nil, messageCount: Int = 0, title: String = "", lastActivity: Date? = nil) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.messageCount = messageCount
        self.title = title
        self.lastActivity = lastActivity ?? startTime
    }
}

final class ConversationHistoryStore {
    static let shared = ConversationHistoryStore()
    
    // Session management
    private(set) var currentSessionId: UUID?
    private var sessions: [UUID: ConversationSession] = [:]
    private var lastActivityTime: Date = Date()
    private let sessionIdleTimeout: TimeInterval = 30 * 60 // 30 minutes
    
    private let queue = DispatchQueue(label: "synapse.conversation.history", qos: .utility)
    private let maxEntries = 500 // Increased from 300
    private var entries: [ConversationHistoryEntry] = []
    private let fileURL: URL
    private let sessionsFileURL: URL
    
    private init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = support.appendingPathComponent("Synapse", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("conversation_history.json")
        sessionsFileURL = dir.appendingPathComponent("conversation_sessions.json")
        load()
        // Always start a new session on app launch
        startNewSession()
    }
    
    // MARK: - Session Management
    
    private func startNewSession() {
        queue.sync {
            // End previous session if exists
            if let previousSessionId = currentSessionId,
               var previousSession = sessions[previousSessionId] {
                previousSession.endTime = Date()
                sessions[previousSessionId] = previousSession
            }
            
            // Create new session
            let newSessionId = UUID()
            currentSessionId = newSessionId
            lastActivityTime = Date()
            
            let newSession = ConversationSession(
                id: newSessionId,
                startTime: Date(),
                messageCount: 0,
                title: "",
                lastActivity: Date()
            )
            sessions[newSessionId] = newSession
            saveSessionsLocked()
        }
    }
    
    private func checkAndRenewSessionIfNeeded() {
        queue.sync {
            let now = Date()
            let timeSinceLastActivity = now.timeIntervalSince(lastActivityTime)
            
            if timeSinceLastActivity > sessionIdleTimeout {
                startNewSession()
            } else {
                lastActivityTime = now
                // Update last activity for current session
                if let sessionId = currentSessionId,
                   var session = sessions[sessionId] {
                    session.lastActivity = now
                    sessions[sessionId] = session
                }
            }
        }
    }
    
    func getSession(id: UUID) -> ConversationSession? {
        queue.sync {
            sessions[id]
        }
    }
    
    func getAllSessions() -> [ConversationSession] {
        queue.sync {
            Array(sessions.values).sorted { $0.startTime > $1.startTime }
        }
    }
    
    // MARK: - Entry Management
    
    func appendExchange(user: String, assistant: String, action: IntentAction) {
        let cleanUser = sanitize(user)
        let cleanAssistant = sanitize(assistant)
        guard !cleanUser.isEmpty, !cleanAssistant.isEmpty else { return }
        
        checkAndRenewSessionIfNeeded()
        
        queue.sync {
            guard let sessionId = currentSessionId else {
                startNewSession()
                return
            }
            
            let now = Date()
            
            // Add user message
            entries.append(
                ConversationHistoryEntry(
                    id: UUID(),
                    role: "user",
                    action: action.rawValue,
                    text: cleanUser,
                    timestamp: now,
                    sessionId: sessionId
                )
            )
            
            // Add assistant message
            entries.append(
                ConversationHistoryEntry(
                    id: UUID(),
                    role: "assistant",
                    action: action.rawValue,
                    text: cleanAssistant,
                    timestamp: now,
                    sessionId: sessionId
                )
            )
            
            // Update session
            if var session = sessions[sessionId] {
                session.messageCount += 2
                session.lastActivity = now
                
                // Auto-generate title if empty and we have enough content
                if session.title.isEmpty && session.messageCount >= 2 {
                    session.title = generateSessionTitle(userText: cleanUser, assistantText: cleanAssistant)
                }
                
                sessions[sessionId] = session
            }
            
            // Trim entries if needed
            if entries.count > maxEntries {
                let toRemove = entries.count - maxEntries
                entries = Array(entries.suffix(maxEntries))
                
                // Clean up sessions that no longer have entries
                let remainingSessionIds = Set(entries.compactMap { $0.sessionId })
                sessions = sessions.filter { remainingSessionIds.contains($0.key) }
            }
            
            saveLocked()
            saveSessionsLocked()
        }
    }
    
    private func generateSessionTitle(userText: String, assistantText: String) -> String {
        // Extract first meaningful sentence or phrase from user's first message
        let text = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try to extract first sentence
        if let sentenceEnd = text.firstIndex(of: ".") ?? text.firstIndex(of: "?") ?? text.firstIndex(of: "!") {
            let sentence = String(text[..<sentenceEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            if sentence.count > 5 && sentence.count <= 60 {
                return sentence
            }
        }
        
        // Fallback: take first 50 characters
        if text.count <= 50 {
            return text
        }
        
        let truncated = String(text.prefix(47)) + "..."
        return truncated
    }
    
    func recent(limit: Int = 16) -> [ConversationHistoryEntry] {
        queue.sync {
            Array(entries.suffix(max(1, limit)))
        }
    }
    
    func recent(limit: Int = 16, sessionId: UUID) -> [ConversationHistoryEntry] {
        queue.sync {
            Array(entries.filter { $0.sessionId == sessionId }.suffix(max(1, limit)))
        }
    }
    
    func contextSnippet(limit: Int = 8, maxChars: Int = 1200) -> String {
        let recentItems = recent(limit: limit)
        guard !recentItems.isEmpty else { return "" }
        
        let lines = recentItems.map { item in
            let role = item.role == "assistant" ? "A" : "U"
            let compact = item.text.replacingOccurrences(of: "\n", with: " ")
            return "\(role): \(compact)"
        }
        
        var text = lines.joined(separator: "\n")
        if text.count > maxChars {
            text = String(text.suffix(maxChars))
        }
        return text
    }
    
    func formatHistory(keyword: String? = nil, limit: Int = 24) -> String {
        let key = (keyword ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let list = queue.sync { () -> [ConversationHistoryEntry] in
            let reversed = entries.reversed()
            if key.isEmpty {
                return Array(reversed.prefix(max(1, limit)))
            }
            return Array(
                reversed
                    .filter { $0.text.lowercased().contains(key) }
                    .prefix(max(1, limit))
            )
        }
        
        guard !list.isEmpty else {
            return key.isEmpty ? "暂无历史对话。" : "未找到包含「\(keyword ?? "")」的历史对话。"
        }
        
        let iso = ISO8601DateFormatter()
        let lines = list.map { item in
            let marker = item.role == "assistant" ? "🤖" : "👤"
            let timestamp = iso.string(from: item.timestamp)
            let compact = item.text.replacingOccurrences(of: "\n", with: " ")
            
            // Highlight keyword if provided
            var highlightedText = compact
            if !key.isEmpty {
                highlightedText = highlightKeyword(compact, keyword: keyword ?? "")
            }
            
            return "\(marker) [\(timestamp)] \(highlightedText)"
        }
        
        return """
        # 历史对话
        
        \(lines.joined(separator: "\n"))
        """
    }
    
    func formatHistory(keyword: String? = nil, limit: Int = 24, sessionId: UUID) -> String {
        let key = (keyword ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let list = queue.sync { () -> [ConversationHistoryEntry] in
            let sessionEntries = entries.filter { $0.sessionId == sessionId }
            let reversed = sessionEntries.reversed()
            if key.isEmpty {
                return Array(reversed.prefix(max(1, limit)))
            }
            return Array(
                reversed
                    .filter { $0.text.lowercased().contains(key) }
                    .prefix(max(1, limit))
            )
        }
        
        guard !list.isEmpty else {
            return key.isEmpty ? "暂无该会话的历史对话。" : "未找到该会话中包含「\(keyword ?? "")」的历史对话。"
        }
        
        let iso = ISO8601DateFormatter()
        let lines = list.map { item in
            let marker = item.role == "assistant" ? "🤖" : "👤"
            let timestamp = iso.string(from: item.timestamp)
            let compact = item.text.replacingOccurrences(of: "\n", with: " ")
            
            // Highlight keyword if provided
            var highlightedText = compact
            if !key.isEmpty {
                highlightedText = highlightKeyword(compact, keyword: keyword ?? "")
            }
            
            return "\(marker) [\(timestamp)] \(highlightedText)"
        }
        
        return """
        # 历史对话
        
        \(lines.joined(separator: "\n"))
        """
    }
    
    // MARK: - Search
    
    func search(keyword: String, limit: Int = 50) -> [ConversationHistoryEntry] {
        let key = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return [] }
        
        return queue.sync {
            entries
                .filter { $0.text.lowercased().contains(key) }
                .suffix(limit)
                .reversed()
        }
    }
    
    func search(keyword: String, sessionId: UUID, limit: Int = 50) -> [ConversationHistoryEntry] {
        let key = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return [] }
        
        return queue.sync {
            entries
                .filter { $0.sessionId == sessionId && $0.text.lowercased().contains(key) }
                .suffix(limit)
                .reversed()
        }
    }
    
    private func highlightKeyword(_ text: String, keyword: String) -> String {
        guard !keyword.isEmpty else { return text }
        
        // Find all match ranges first (case-insensitive)
        let lowerText = text.lowercased()
        let lowerKeyword = keyword.lowercased()
        var matchRanges: [Range<String.Index>] = []
        var searchStart = lowerText.startIndex
        
        while searchStart < lowerText.endIndex,
              let range = lowerText.range(of: lowerKeyword, range: searchStart..<lowerText.endIndex) {
            matchRanges.append(range)
            searchStart = range.upperBound
        }
        
        // Build result string by replacing matches (from end to start to preserve indices)
        var result = text
        for range in matchRanges.reversed() {
            let matchedText = String(text[range])
            result.replaceSubrange(range, with: "**\(matchedText)**")
        }
        
        return result
    }
    
    // MARK: - Session List Formatting
    
    func formatSessionList(limit: Int = 20) -> String {
        let allSessions = getAllSessions()
        let recentSessions = Array(allSessions.prefix(limit))
        
        guard !recentSessions.isEmpty else {
            return "暂无会话记录。"
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        let isoFormatter = ISO8601DateFormatter()
        
        let lines = recentSessions.map { session in
            let startTimeStr = dateFormatter.string(from: session.startTime)
            let endTimeStr = session.endTime.map { dateFormatter.string(from: $0) } ?? "进行中"
            let title = session.title.isEmpty ? "未命名会话" : session.title
            let isCurrent = session.id == currentSessionId ? " (当前)" : ""
            
            return """
            - **\(title)**\(isCurrent)
              ID: \(session.id.uuidString.prefix(8))
              开始: \(startTimeStr) | 结束: \(endTimeStr)
              消息数: \(session.messageCount)
            """
        }
        
        return """
        # 会话列表
        
        \(lines.joined(separator: "\n\n"))
        """
    }
    
    func getEntriesForSession(_ sessionId: UUID) -> [ConversationHistoryEntry] {
        queue.sync {
            entries.filter { $0.sessionId == sessionId }
        }
    }
    
    // MARK: - Private Helpers
    
    private func sanitize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func load() {
        queue.sync {
            // Load entries (with backward compatibility)
            if let data = try? Data(contentsOf: fileURL),
               let decoded = try? JSONDecoder().decode([ConversationHistoryEntry].self, from: data) {
                entries = decoded
            } else {
                entries = []
            }
            
            // Load sessions
            if let data = try? Data(contentsOf: sessionsFileURL),
               let decoded = try? JSONDecoder().decode([UUID: ConversationSession].self, from: data) {
                sessions = decoded
                
                // Rebuild session metadata from entries if needed
                rebuildSessionMetadata()
            } else {
                // If no sessions file exists, create sessions from existing entries
                rebuildSessionMetadata()
            }
        }
    }
    
    private func rebuildSessionMetadata() {
        // Group entries by sessionId (or create legacy session for entries without sessionId)
        var sessionGroups: [UUID: [ConversationHistoryEntry]] = [:]
        var legacySessionId: UUID?
        
        for entry in entries {
            let sessionId: UUID
            if let existingSessionId = entry.sessionId {
                sessionId = existingSessionId
            } else {
                // All legacy entries go into a single legacy session
                if legacySessionId == nil {
                    legacySessionId = UUID()
                }
                sessionId = legacySessionId!
            }
            
            if sessionGroups[sessionId] == nil {
                sessionGroups[sessionId] = []
            }
            sessionGroups[sessionId]?.append(entry)
        }
        
        // Create or update sessions
        for (sessionId, sessionEntries) in sessionGroups {
            if sessions[sessionId] == nil {
                let sortedEntries = sessionEntries.sorted { $0.timestamp < $1.timestamp }
                let startTime = sortedEntries.first?.timestamp ?? Date()
                let endTime = sortedEntries.last?.timestamp
                let title = generateSessionTitle(
                    userText: sortedEntries.first(where: { $0.role == "user" })?.text ?? "",
                    assistantText: sortedEntries.first(where: { $0.role == "assistant" })?.text ?? ""
                )
                
                sessions[sessionId] = ConversationSession(
                    id: sessionId,
                    startTime: startTime,
                    endTime: endTime,
                    messageCount: sessionEntries.count,
                    title: title,
                    lastActivity: endTime ?? startTime
                )
            } else {
                // Update existing session metadata
                var session = sessions[sessionId]!
                let sortedEntries = sessionEntries.sorted { $0.timestamp < $1.timestamp }
                session.messageCount = sessionEntries.count
                session.lastActivity = sortedEntries.last?.timestamp ?? session.lastActivity
                if session.title.isEmpty && !sessionEntries.isEmpty {
                    session.title = generateSessionTitle(
                        userText: sessionEntries.first(where: { $0.role == "user" })?.text ?? "",
                        assistantText: sessionEntries.first(where: { $0.role == "assistant" })?.text ?? ""
                    )
                }
                sessions[sessionId] = session
            }
        }
    }
    
    private func saveLocked() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
    
    private func saveSessionsLocked() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? data.write(to: sessionsFileURL, options: .atomic)
    }
}
