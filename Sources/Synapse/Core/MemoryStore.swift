import Foundation

struct MemoryItem: Codable, Identifiable {
    let id: UUID
    let text: String
    let source: String
    let timestamp: Date
    var category: String  // preferences, facts, identity, goals, skills, general
    var uri: String       // synapse://user/memories/{category}/{id}
    
    init(id: UUID, text: String, source: String, timestamp: Date, category: String? = nil, uri: String? = nil) {
        self.id = id
        self.text = text
        self.source = source
        self.timestamp = timestamp
        self.category = category ?? MemoryStore.categorize(text)
        self.uri = uri ?? MemoryStore.generateURI(category: self.category, id: id)
    }
    
    // Custom decoding for backward compatibility
    enum CodingKeys: String, CodingKey {
        case id, text, source, timestamp, category, uri
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        source = try container.decode(String.self, forKey: .source)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        
        // Handle missing category/uri in old files
        category = (try? container.decode(String.self, forKey: .category)) ?? MemoryStore.categorize(text)
        uri = (try? container.decode(String.self, forKey: .uri)) ?? MemoryStore.generateURI(category: category, id: id)
    }
}

enum ContextLevel {
    case L0  // Abstract/one-liner
    case L1  // Overview
    case L2  // Full details
}

final class MemoryStore {
    static let shared = MemoryStore()
    
    // Category definitions
    static let categories = ["preferences", "facts", "identity", "goals", "skills", "general"]
    static let userMemoryBase = "synapse://user/memories"
    static let agentSkillsBase = "synapse://agent/skills"

    private let queue = DispatchQueue(label: "synapse.memory.store", qos: .utility)
    private let maxItems = 500
    private var items: [MemoryItem] = []
    private let fileURL: URL

    private init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = support.appendingPathComponent("Synapse", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("memory.json")
        load()
    }

    // MARK: - Automatic Categorization
    
    static func categorize(_ text: String) -> String {
        let lower = text.lowercased()
        
        // Preferences: likes, dislikes, preferences, favorite, prefer, want, don't like
        if lower.contains("prefer") || lower.contains("like") || lower.contains("dislike") ||
           lower.contains("favorite") || lower.contains("favourite") || lower.contains("want") ||
           lower.contains("don't like") || lower.contains("hate") || lower.contains("love") {
            return "preferences"
        }
        
        // Facts: factual statements, information, data
        if lower.contains("is ") || lower.contains("are ") || lower.contains("was ") ||
           lower.contains("were ") || lower.contains("fact") || lower.contains("information") ||
           lower.contains("data") || lower.contains("according to") || lower.contains("research") {
            return "facts"
        }
        
        // Identity: who I am, my name, my role, I am, I'm
        if lower.contains("i am") || lower.contains("i'm ") || lower.contains("my name") ||
           lower.contains("i work") || lower.contains("i do") || lower.contains("my role") ||
           lower.contains("i'm a") || lower.contains("i'm an") || lower.hasPrefix("i ") {
            return "identity"
        }
        
        // Goals: want to, goal, objective, plan, target, achieve
        if lower.contains("goal") || lower.contains("objective") || lower.contains("plan") ||
           lower.contains("target") || lower.contains("achieve") || lower.contains("want to") ||
           lower.contains("need to") || lower.contains("should") || lower.contains("will do") {
            return "goals"
        }
        
        // Skills: can, know how, skill, ability, expertise, learned
        if lower.contains("skill") || lower.contains("can ") || lower.contains("know how") ||
           lower.contains("ability") || lower.contains("expertise") || lower.contains("learned") ||
           lower.contains("master") || lower.contains("proficient") {
            return "skills"
        }
        
        return "general"
    }
    
    static func generateURI(category: String, id: UUID) -> String {
        if category == "skills" {
            return "\(agentSkillsBase)/\(id.uuidString)"
        }
        return "\(userMemoryBase)/\(category)/\(id.uuidString)"
    }

    // MARK: - Existing API (maintained for compatibility)

    @discardableResult
    func remember(_ text: String, source: String = "manual") -> Bool {
        let clean = normalize(text)
        guard !clean.isEmpty else { return false }

        return queue.sync {
            if let idx = items.firstIndex(where: { $0.text.caseInsensitiveCompare(clean) == .orderedSame }) {
                let category = Self.categorize(clean)
                let uri = Self.generateURI(category: category, id: items[idx].id)
                items[idx] = MemoryItem(
                    id: items[idx].id,
                    text: clean,
                    source: source,
                    timestamp: Date(),
                    category: category,
                    uri: uri
                )
                saveLocked()
                return true
            }

            let id = UUID()
            let category = Self.categorize(clean)
            let uri = Self.generateURI(category: category, id: id)
            items.append(MemoryItem(
                id: id,
                text: clean,
                source: source,
                timestamp: Date(),
                category: category,
                uri: uri
            ))
            if items.count > maxItems {
                items = Array(items.suffix(maxItems))
            }
            saveLocked()
            return true
        }
    }

    func list(limit: Int = 30) -> [MemoryItem] {
        queue.sync {
            Array(items.reversed().prefix(max(1, limit)))
        }
    }

    func clear() -> Int {
        queue.sync {
            let count = items.count
            items.removeAll()
            saveLocked()
            return count
        }
    }

    func contextSnippet(limit: Int = 8, maxChars: Int = 800) -> String {
        let notes = list(limit: limit).map { "- \($0.text)" }
        guard !notes.isEmpty else { return "" }
        var text = notes.joined(separator: "\n")
        if text.count > maxChars {
            text = String(text.prefix(maxChars))
        }
        return text
    }

    func formatMemories(keyword: String? = nil, limit: Int = 30) -> String {
        let key = (keyword ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let notes: [MemoryItem]
        if key.isEmpty {
            notes = list(limit: limit)
        } else {
            notes = queue.sync {
                Array(
                    items
                        .reversed()
                        .filter { $0.text.lowercased().contains(key) }
                        .prefix(max(1, limit))
                )
            }
        }
        guard !notes.isEmpty else { return "Memory 为空，先用 /remember 添加一条。" }

        let iso = ISO8601DateFormatter()
        let rows = notes.map { item in
            "• [\(iso.string(from: item.timestamp))] [\(item.category)] \(item.text)"
        }
        return """
        # Memory

        \(rows.joined(separator: "\n"))
        """
    }

    // MARK: - New OpenViking-inspired Features

    /// Returns context appropriate for the specified level
    /// - L0: Abstract one-liners (very brief summaries)
    /// - L1: Overview (concise summaries)
    /// - L2: Full details (complete memory text)
    func contextForPrompt(level: ContextLevel, maxTokens: Int = 2000) -> String {
        return queue.sync {
            let allItems = items.reversed()
            var result: [String] = []
            var currentLength = 0
            let maxChars = maxTokens * 4 // Rough estimate: 4 chars per token
            
            switch level {
            case .L0:
                // Abstract: First sentence or first 50 chars
                for item in allItems {
                    let abstract = abstractMemory(item.text)
                    if currentLength + abstract.count + 10 > maxChars { break }
                    result.append("• \(abstract)")
                    currentLength += abstract.count + 10
                }
                
            case .L1:
                // Overview: First 100-150 chars or first two sentences
                for item in allItems {
                    let overview = overviewMemory(item.text)
                    if currentLength + overview.count + 10 > maxChars { break }
                    result.append("• [\(item.category)] \(overview)")
                    currentLength += overview.count + 10
                }
                
            case .L2:
                // Full: Complete memory text
                for item in allItems {
                    let full = item.text
                    if currentLength + full.count + item.category.count + 20 > maxChars { break }
                    result.append("• [\(item.category)] \(full)")
                    currentLength += full.count + item.category.count + 20
                }
            }
            
            return result.joined(separator: "\n")
        }
    }
    
    private func abstractMemory(_ text: String) -> String {
        // Extract first sentence or first 50 chars
        if let sentenceEnd = text.firstIndex(where: { ".!?".contains($0) }) {
            let sentence = String(text[..<sentenceEnd])
            return sentence.count <= 50 ? sentence : String(sentence.prefix(50)) + "..."
        }
        return text.count <= 50 ? text : String(text.prefix(50)) + "..."
    }
    
    private func overviewMemory(_ text: String) -> String {
        // Extract first two sentences or first 150 chars
        var sentences: [String] = []
        var current = text.startIndex
        var sentenceCount = 0
        
        while current < text.endIndex && sentenceCount < 2 {
            if let end = text[current...].firstIndex(where: { ".!?".contains($0) }) {
                let sentence = String(text[current...end]).trimmingCharacters(in: .whitespaces)
                if !sentence.isEmpty {
                    sentences.append(sentence)
                    sentenceCount += 1
                }
                current = text.index(after: end)
            } else {
                break
            }
        }
        
        if !sentences.isEmpty {
            let overview = sentences.joined(separator: " ")
            return overview.count <= 150 ? overview : String(overview.prefix(150)) + "..."
        }
        
        return text.count <= 150 ? text : String(text.prefix(150)) + "..."
    }

    /// Browse memories by category (directory-like browsing)
    func browseCategory(_ category: String) -> [MemoryItem] {
        return queue.sync {
            Array(items.reversed().filter { $0.category == category })
        }
    }
    
    /// Get all available categories
    func listCategories() -> [String] {
        return queue.sync {
            Array(Set(items.map { $0.category })).sorted()
        }
    }
    
    /// Format memories as a filesystem-like tree view
    func formatMemoryTree() -> String {
        return queue.sync {
            var tree: [String: [MemoryItem]] = [:]
            
            // Group by category
            for item in items {
                if tree[item.category] == nil {
                    tree[item.category] = []
                }
                tree[item.category]?.append(item)
            }
            
            var lines: [String] = []
            lines.append("synapse://")
            
            // User memories
            lines.append("├── user/")
            lines.append("│   └── memories/")
            
            let userCategories = Self.categories.filter { $0 != "skills" }
            for (idx, category) in userCategories.enumerated() {
                let items = tree[category] ?? []
                let isLast = idx == userCategories.count - 1
                let prefix = isLast ? "    └── " : "    ├── "
                lines.append("│\(prefix)\(category)/ (\(items.count) items)")
                
                // Show first few items as files
                let displayItems = Array(items.reversed().prefix(3))
                for (itemIdx, item) in displayItems.enumerated() {
                    let isLastItem = itemIdx == displayItems.count - 1 && items.count <= 3
                    let itemPrefix = isLast ? "    " : "    │"
                    let filePrefix = isLastItem ? "        └── " : "        ├── "
                    let shortId = String(item.id.uuidString.prefix(8))
                    let shortText = item.text.count > 40 ? String(item.text.prefix(40)) + "..." : item.text
                    lines.append("\(itemPrefix)\(filePrefix)\(shortId).mem: \(shortText)")
                }
                
                if items.count > 3 {
                    let remaining = items.count - 3
                    let prefix = isLast ? "    " : "    │"
                    lines.append("\(prefix)        └── ... (\(remaining) more)")
                }
            }
            
            // Agent skills
            let skills = tree["skills"] ?? []
            lines.append("└── agent/")
            lines.append("    └── skills/ (\(skills.count) items)")
            
            let displaySkills = Array(skills.reversed().prefix(3))
            for (idx, item) in displaySkills.enumerated() {
                let isLast = idx == displaySkills.count - 1 && skills.count <= 3
                let prefix = isLast ? "        └── " : "        ├── "
                let shortId = String(item.id.uuidString.prefix(8))
                let shortText = item.text.count > 40 ? String(item.text.prefix(40)) + "..." : item.text
                lines.append("    \(prefix)\(shortId).mem: \(shortText)")
            }
            
            if skills.count > 3 {
                let remaining = skills.count - 3
                lines.append("        └── ... (\(remaining) more)")
            }
            
            return lines.joined(separator: "\n")
        }
    }
    
    /// Get memory by URI
    func getMemory(uri: String) -> MemoryItem? {
        return queue.sync {
            items.first { $0.uri == uri }
        }
    }
    
    /// List memories by URI prefix (directory-like)
    func listMemories(uriPrefix: String) -> [MemoryItem] {
        return queue.sync {
            Array(items.reversed().filter { $0.uri.hasPrefix(uriPrefix) })
        }
    }

    // MARK: - Private Helpers

    private func normalize(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func load() {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL),
                  let decoded = try? JSONDecoder().decode([MemoryItem].self, from: data) else {
                items = []
                return
            }
            
            // Migrate old items without category/uri
            items = decoded.map { item in
                if item.category.isEmpty || item.uri.isEmpty {
                    let category = Self.categorize(item.text)
                    let uri = Self.generateURI(category: category, id: item.id)
                    return MemoryItem(
                        id: item.id,
                        text: item.text,
                        source: item.source,
                        timestamp: item.timestamp,
                        category: category,
                        uri: uri
                    )
                }
                return item
            }
        }
    }

    private func saveLocked() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
