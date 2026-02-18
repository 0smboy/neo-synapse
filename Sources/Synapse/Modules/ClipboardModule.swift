// MARK: - Modules/ClipboardModule.swift
// 剪贴板历史模块

import AppKit

/// 剪贴板历史管理器
final class ClipboardModule {
    
    static let shared = ClipboardModule()
    
    struct ClipboardItem: Identifiable {
        let id = UUID()
        let content: String
        let timestamp: Date
        let type: ContentType
        
        enum ContentType {
            case text
            case url
            case code
        }
    }
    
    private(set) var history: [ClipboardItem] = []
    private var lastChangeCount: Int = 0
    private var timer: Timer?
    private let maxItems = 50
    
    private init() {}
    
    /// 启动监控
    func startMonitoring() {
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }
    
    /// 停止监控
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    /// 检查剪贴板变化
    private func checkClipboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        
        guard let str = pb.string(forType: .string), !str.isEmpty else { return }
        
        // 去重（和上一条相同则不添加）
        if let last = history.first, last.content == str { return }
        
        let type: ClipboardItem.ContentType
        if str.hasPrefix("http://") || str.hasPrefix("https://") {
            type = .url
        } else if str.contains("{") || str.contains("func ") || str.contains("def ") ||
                  str.contains("class ") || str.contains("import ") {
            type = .code
        } else {
            type = .text
        }
        
        let item = ClipboardItem(content: str, timestamp: Date(), type: type)
        history.insert(item, at: 0)
        
        if history.count > maxItems {
            history = Array(history.prefix(maxItems))
        }
    }
    
    /// 获取历史（最近 N 条）
    func getRecent(count: Int = 10) -> [ClipboardItem] {
        return Array(history.prefix(count))
    }
    
    /// 格式化显示
    func formatHistory(count: Int = 10) -> String {
        let items = getRecent(count: count)
        if items.isEmpty { return "📋 剪贴板历史为空" }
        
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        
        var output = "📋 剪贴板历史 (最近 \(items.count) 条)\n"
        for (i, item) in items.enumerated() {
            let icon: String
            switch item.type {
            case .text: icon = "📝"
            case .url: icon = "🔗"
            case .code: icon = "💻"
            }
            let preview = item.content.prefix(60).replacingOccurrences(of: "\n", with: " ")
            let suffix = item.content.count > 60 ? "..." : ""
            output += "\n\(icon) \(i + 1). \(preview)\(suffix)  [\(fmt.string(from: item.timestamp))]"
        }
        return output
    }
    
    /// 复制指定项到剪贴板
    func copyItem(at index: Int) -> Bool {
        guard index >= 0, index < history.count else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(history[index].content, forType: .string)
        return true
    }
}
