import Foundation

/// 自动 Memory 抽取器（轻量规则版）
/// 目标：像聊天产品一样自动记住“用户画像 + 偏好 + 长期约束”，无需手动 /remember。
final class MemoryAutoManager {
    static let shared = MemoryAutoManager()

    private init() {}

    func ingest(user: String, assistant: String, action: IntentAction) {
        guard SynapseSettings.autoMemoryEnabled else { return }

        let userText = normalized(user)
        guard !userText.isEmpty else { return }

        var candidates = extractFromUser(userText)
        candidates.append(contentsOf: extractFromAssistant(assistant))

        let unique = Array(Set(candidates)).sorted()
        for item in unique where isMemoryWorthy(item) {
            _ = MemoryStore.shared.remember(item, source: "auto:\(action.rawValue)")
        }
    }

    private func extractFromUser(_ text: String) -> [String] {
        var notes: [String] = []
        let lower = text.lowercased()

        // 显式记忆指令
        let explicitPrefixes = ["记住", "记一下", "remember", "请记住", "帮我记住"]
        if let prefix = explicitPrefixes.first(where: { lower.hasPrefix($0) }) {
            let raw = text.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.isEmpty { notes.append("用户要求记忆：\(raw)") }
        }

        // 偏好/约束
        let preferenceSignals = ["请用", "希望", "偏好", "喜欢", "不要", "尽量", "最好", "回答用", "回答请"]
        if preferenceSignals.contains(where: { text.contains($0) || lower.contains($0) }) {
            notes.append("用户偏好：\(text)")
        }

        // 常见身份与背景
        if let name = firstCapture(
            pattern: #"(?:(?:我叫|我的名字是|i am|i'm)\s*([A-Za-z0-9_\u4e00-\u9fa5·]{1,32}))"#,
            in: text
        ) {
            notes.append("用户姓名：\(name)")
        }
        if let role = firstCapture(
            pattern: #"(?:(?:我是|我在做|我的职业是|我的工作是)\s*([^，。；\n]{2,40}))"#,
            in: text
        ) {
            notes.append("用户身份：\(role)")
        }
        if let city = firstCapture(
            pattern: #"(?:(?:我在|我住在|我来自)\s*([^，。；\n]{2,30}))"#,
            in: text
        ) {
            notes.append("用户地点：\(city)")
        }

        // 目标/计划
        if let goal = firstCapture(
            pattern: #"(?:(?:我的目标是|我想要|我计划|我正在)\s*([^。；\n]{4,80}))"#,
            in: text
        ) {
            notes.append("用户目标：\(goal)")
        }

        return notes
    }

    private func extractFromAssistant(_ text: String) -> [String] {
        // 当前版本只从 assistant 抽取“明确约束回显”，避免误记。
        let cleaned = normalized(text)
        guard !cleaned.isEmpty else { return [] }
        if cleaned.contains("我会用中文回答") || cleaned.contains("将使用中文回答") {
            return ["用户偏好：中文输出"]
        }
        return []
    }

    private func isMemoryWorthy(_ text: String) -> Bool {
        let length = text.count
        guard length >= 4, length <= 120 else { return false }
        let noisy = ["command not found", "Codex 查询失败", "MCP startup", "session id:"]
        return !noisy.contains(where: { text.localizedCaseInsensitiveContains($0) })
    }

    private func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: text) else { return nil }
        let value = String(text[captured]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func normalized(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}

