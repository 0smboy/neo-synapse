// MARK: - Modules/EmojiModule.swift
// Emoji 搜索模块

import Foundation

/// Emoji 搜索
final class EmojiModule {
    
    private let emojiMap: [(keywords: [String], emoji: String, name: String)] = [
        // 笑脸
        (["笑", "开心", "happy", "smile", "高兴"], "😊", "微笑"),
        (["大笑", "laugh", "哈哈"], "😂", "大笑"),
        (["哭", "cry", "sad", "难过", "伤心"], "😢", "哭"),
        (["大哭", "sob", "嚎啕"], "😭", "大哭"),
        (["愤怒", "angry", "生气"], "😡", "愤怒"),
        (["爱", "love", "心", "heart"], "❤️", "爱心"),
        (["眼心", "love eyes"], "😍", "花痴"),
        (["思考", "think", "想"], "🤔", "思考"),
        (["鼓掌", "clap", "掌声"], "👏", "鼓掌"),
        (["拇指", "赞", "good", "ok", "thumb"], "👍", "赞"),
        (["火", "fire", "热", "hot"], "🔥", "火"),
        (["party", "庆祝", "派对"], "🎉", "庆祝"),
        (["星", "star", "闪亮"], "⭐", "星"),
        (["太阳", "sun", "阳光"], "☀️", "太阳"),
        (["月亮", "moon", "晚安"], "🌙", "月亮"),
        (["彩虹", "rainbow"], "🌈", "彩虹"),
        (["闪电", "lightning", "雷"], "⚡", "闪电"),
        (["雪", "snow", "冷"], "❄️", "雪花"),
        (["咖啡", "coffee"], "☕", "咖啡"),
        (["啤酒", "beer", "干杯"], "🍺", "啤酒"),
        (["蛋糕", "cake", "生日"], "🎂", "蛋糕"),
        (["钱", "money", "美元", "dollar"], "💰", "钱"),
        (["电脑", "computer", "mac"], "💻", "电脑"),
        (["手机", "phone", "iphone"], "📱", "手机"),
        (["火箭", "rocket", "发射"], "🚀", "火箭"),
        (["闹钟", "alarm", "clock", "时钟"], "⏰", "闹钟"),
        (["书", "book", "阅读", "read"], "📚", "书"),
        (["音乐", "music", "歌"], "🎵", "音乐"),
        (["狗", "dog", "汪"], "🐶", "狗"),
        (["猫", "cat", "喵"], "🐱", "猫"),
        (["花", "flower", "玫瑰"], "🌹", "玫瑰"),
        (["树", "tree", "植物"], "🌳", "树"),
        (["海", "ocean", "wave", "浪"], "🌊", "海浪"),
        (["眼睛", "eye", "看"], "👀", "眼睛"),
        (["肌肉", "muscle", "strong", "力量"], "💪", "力量"),
        (["对勾", "check", "完成", "done"], "✅", "完成"),
        (["叉", "cross", "错", "wrong"], "❌", "错误"),
        (["警告", "warning", "注意"], "⚠️", "警告"),
        (["灯泡", "bulb", "idea", "想法", "灵感"], "💡", "灵感"),
        (["钥匙", "key", "密码"], "🔑", "钥匙"),
        (["指向", "point", "手指"], "👉", "指向"),
        (["握手", "handshake", "合作"], "🤝", "握手"),
        (["祈祷", "pray", "谢谢", "thank"], "🙏", "感谢"),
    ]
    
    func canHandle(_ query: String) -> Bool {
        let lower = query.lowercased()
        return lower.hasPrefix("emoji") || lower.hasPrefix("表情")
    }
    
    func search(_ query: String) -> String {
        let searchTerm = query
            .replacingOccurrences(of: "emoji", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "表情", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        
        let results: [(String, String)]
        if searchTerm.isEmpty {
            results = emojiMap.prefix(20).map { ($0.emoji, $0.name) }
        } else {
            results = emojiMap.filter { entry in
                entry.keywords.contains(where: { $0.contains(searchTerm) || searchTerm.contains($0) }) ||
                entry.name.contains(searchTerm)
            }.map { ($0.emoji, $0.name) }
        }
        
        if results.isEmpty {
            return "未找到相关 Emoji"
        }
        
        return results.map { "\($0.0)  \($0.1)" }.joined(separator: "\n")
    }
}
