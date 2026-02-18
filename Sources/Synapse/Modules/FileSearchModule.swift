// MARK: - Modules/FileSearchModule.swift
// 文件搜索模块 — IntentEngine 接口层

import Foundation

/// 文件搜索模块
final class FileSearchModule {
    
    // MARK: - 关键词
    
    private let searchKeywords = [
        "查找", "搜索", "找", "文件", "find", "search", "locate",
        "where is", "在哪", "打开文件"
    ]
    
    private let filterKeywords = [
        "大文件", "图片", "照片", "视频", "文档", "音乐", "音频",
        "swift文件", "最近", "今天", "本周", "本月",
        "pdf", "代码文件"
    ]
    
    // MARK: - 意图判断
    
    /// 判断是否为文件搜索意图
    func canHandle(_ query: String) -> Bool {
        let lower = query.lowercased()
        // 直接包含搜索关键词
        if searchKeywords.contains(where: { lower.contains($0) }) { return true }
        // 包含过滤关键词
        if filterKeywords.contains(where: { lower.contains($0) }) { return true }
        return false
    }
    
    /// 从原始查询中提取搜索关键词
    func extractSearchQuery(_ rawQuery: String) -> String {
        var query = rawQuery
        
        // 移除搜索前缀关键词
        let prefixes = ["查找", "搜索", "找一下", "找到", "找", "search", "find", "locate", "打开文件"]
        for prefix in prefixes {
            if query.lowercased().hasPrefix(prefix) {
                query = String(query.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        
        return query
    }
    
    /// 异步搜索
    func search(_ rawQuery: String) async -> [FileSearchResult] {
        let cleanQuery = extractSearchQuery(rawQuery)
        let (query, filter) = FileSearchEngine.parseQuery(cleanQuery)
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return await FileSearchEngine.shared.search(
            query: normalizedQuery,
            filter: filter,
            allowBroadMatch: normalizedQuery.isEmpty
        )
    }
}
