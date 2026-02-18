// MARK: - Modules/DictionaryModule.swift
// 词典模块 - macOS 内置词典查询

import Foundation
import CoreServices

/// 词典查询（使用 macOS 内置词典）
final class DictionaryModule {
    
    /// 查询词典定义
    func lookup(_ word: String) -> String? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        let nsWord = trimmed as NSString
        let range = CFRange(location: 0, length: nsWord.length)
        
        guard let definition = DCSCopyTextDefinition(nil,
                                                      nsWord as CFString,
                                                      range)?.takeRetainedValue() as String? else {
            return nil
        }
        
        // 截取前 500 字符，避免过长
        let maxLen = 500
        if definition.count > maxLen {
            let idx = definition.index(definition.startIndex, offsetBy: maxLen)
            return String(definition[..<idx]) + "..."
        }
        
        return definition
    }
    
    /// 是否可以处理（单词或短语查询）
    func canHandle(_ query: String) -> Bool {
        let lower = query.lowercased()
        let triggers = ["定义", "含义", "什么意思", "define", "meaning", "词典", "dictionary"]
        return triggers.contains(where: { lower.contains($0) })
    }
    
    /// 从查询中提取要查的词
    func extractWord(from query: String) -> String {
        let removals = ["定义", "含义", "什么意思", "是什么", "define", "meaning of", "meaning", "词典", "dictionary", "的"]
        var result = query
        for r in removals {
            result = result.replacingOccurrences(of: r, with: "", options: .caseInsensitive)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
