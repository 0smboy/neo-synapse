// MARK: - Core/AppIndexer.swift
// App 扫描与缓存

import AppKit

/// App 扫描器 - 扫描系统中安装的所有应用并建立能力索引
final class AppIndexer {
    static let shared = AppIndexer()
    
    private(set) var apps: [AppInfo] = []
    private let fileManager = FileManager.default
    
    // 预定义的 App 能力标签映射
    private let knownCapabilities: [String: [String]] = [
        "com.apple.Safari":        ["浏览器", "网页", "上网", "搜索"],
        "com.apple.finder":        ["文件", "文件夹", "访达", "查找"],
        "com.apple.Terminal":      ["终端", "命令行", "脚本", "shell"],
        "com.apple.TextEdit":      ["文本", "编辑", "记事本"],
        "com.apple.Notes":         ["备忘录", "笔记", "记录"],
        "com.apple.Calculator":    ["计算器", "计算"],
        "com.apple.Preview":       ["预览", "图片", "PDF"],
        "com.apple.mail":          ["邮件", "邮箱", "email"],
        "com.apple.iCal":          ["日历", "日程", "提醒"],
        "com.apple.MusicApp":      ["音乐", "播放"],
        "com.apple.systempreferences": ["系统设置", "偏好设置", "设置"],
        "com.apple.ActivityMonitor": ["活动监视器", "进程", "CPU", "内存"],
        
        // 第三方
        "com.todesktop.230313mzl4w4u92": ["cursor", "代码", "编程", "ide", "开发"],
        "com.microsoft.VSCode":    ["vscode", "代码", "编程", "ide", "开发"],
        "com.google.Chrome":       ["chrome", "浏览器", "网页"],
        "md.obsidian":             ["obsidian", "笔记", "知识库", "markdown"],
        "notion.id":               ["notion", "知识库", "笔记", "协作"],
        "com.openai.chat":         ["chatgpt", "ai", "对话", "问答"],
    ]
    
    /// 扫描所有 App 目录
    func indexAll() async {
        let knownCapabilities = self.knownCapabilities
        let result = await Task.detached(priority: .utility, operation: {
            Self.scanInstalledApps(knownCapabilities: knownCapabilities)
        }).value
        
        self.apps = result
        print("✅ 已索引 \(result.count) 个应用")
        
        // 持久化缓存
        saveCache()
    }
    
    private static func scanInstalledApps(knownCapabilities: [String: [String]]) -> [AppInfo] {
        let fileManager = FileManager.default
        var result: [AppInfo] = []
        
        let directories = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
        ]
        
        let userApps = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications")
        
        for dir in directories {
            scanDirectory(
                URL(fileURLWithPath: dir),
                fileManager: fileManager,
                knownCapabilities: knownCapabilities,
                into: &result
            )
        }
        scanDirectory(
            userApps,
            fileManager: fileManager,
            knownCapabilities: knownCapabilities,
            into: &result
        )
        
        // 去重 + 稳定排序
        var seen = Set<String>()
        result = result.filter { seen.insert($0.id).inserted }
        result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        
        return result
    }
    
    private static func scanDirectory(
        _ url: URL,
        fileManager: FileManager,
        knownCapabilities: [String: [String]],
        into results: inout [AppInfo]
    ) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        
        let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.nameKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "app" else { continue }
            if let info = makeAppInfo(from: fileURL, knownCapabilities: knownCapabilities) {
                results.append(info)
            }
        }
    }
    
    private static func makeAppInfo(from url: URL, knownCapabilities: [String: [String]]) -> AppInfo? {
        let bundle = Bundle(url: url)
        let name = (bundle?.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle?.infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        
        let bundleId = bundle?.bundleIdentifier
        
        // 查找已知能力标签, 或根据名称自动生成
        var caps: [String]
        if let bid = bundleId, let known = knownCapabilities[bid] {
            caps = known
        } else {
            caps = [name.lowercased()]
        }
        
        return AppInfo(
            name: name,
            path: url.path,
            bundleId: bundleId,
            capabilities: caps
        )
    }
    
    // MARK: - 搜索
    
    /// 模糊搜索 App
    func search(query: String) -> [AppInfo] {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }

        let queryTokens = query
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { normalize($0) }
            .filter { !$0.isEmpty }

        let scored = apps.compactMap { app -> (app: AppInfo, score: Int)? in
            let score = score(app: app, query: normalizedQuery, tokens: queryTokens)
            guard score > 0 else { return nil }
            return (app, score)
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.app.name.localizedCaseInsensitiveCompare(rhs.app.name) == .orderedAscending
            }
            .map(\.app)
    }

    func bestMatch(query: String) -> AppInfo? {
        search(query: query).first
    }
    
    // MARK: - 缓存
    
    private var cacheURL: URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Synapse")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("app_cache.json")
    }
    
    private func saveCache() {
        do {
            let data = try JSONEncoder().encode(apps)
            try data.write(to: cacheURL)
        } catch {
            print("⚠️ 缓存保存失败: \(error)")
        }
    }
    
    func loadCache() -> Bool {
        guard let data = try? Data(contentsOf: cacheURL),
              let cached = try? JSONDecoder().decode([AppInfo].self, from: data) else {
            return false
        }
        self.apps = cached
        print("📦 从缓存加载 \(cached.count) 个应用")
        return true
    }

    private func score(app: AppInfo, query: String, tokens: [String]) -> Int {
        let normalizedName = normalize(app.name)
        let normalizedBundle = normalize(app.bundleId ?? "")
        let normalizedCapabilities = app.capabilities.map(normalize)

        var score = 0
        if normalizedName == query { score = max(score, 1200) }
        if normalizedName.hasPrefix(query) { score = max(score, 1020) }
        if normalizedName.contains(query) { score = max(score, 920) }
        if normalizedBundle.contains(query) { score = max(score, 840) }
        if normalizedCapabilities.contains(where: { $0.contains(query) }) { score = max(score, 780) }
        if isSubsequence(query, in: normalizedName) { score = max(score, 720) }

        if !tokens.isEmpty {
            let coverage = tokens.reduce(into: 0) { partial, token in
                if normalizedName.contains(token) || normalizedBundle.contains(token) {
                    partial += 1
                } else if normalizedCapabilities.contains(where: { $0.contains(token) }) {
                    partial += 1
                }
            }
            if coverage > 0 {
                score += coverage * 25
            }
        }

        return score
    }

    private func normalize(_ raw: String) -> String {
        let folded = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: .current)
        return folded.replacingOccurrences(
            of: #"[^a-z0-9\u4e00-\u9fa5]+"#,
            with: "",
            options: .regularExpression
        )
    }

    private func isSubsequence(_ pattern: String, in target: String) -> Bool {
        guard !pattern.isEmpty else { return false }
        var idx = target.startIndex
        for ch in pattern {
            guard let found = target[idx...].firstIndex(of: ch) else { return false }
            idx = target.index(after: found)
        }
        return true
    }
}
