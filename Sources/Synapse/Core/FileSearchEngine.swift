// MARK: - Core/FileSearchEngine.swift
// 高性能文件搜索引擎：fd 快速路径 + fts_open 深度扫描后备

@preconcurrency import Foundation
import AppKit

// MARK: - 数据模型

/// 搜索结果
struct FileSearchResult: Identifiable {
    let id = UUID()
    let path: String
    let name: String
    let size: Int64
    let modifiedDate: Date
    let fileType: FileType
    let inode: UInt64
    let matchScore: Double
    
    /// 简洁路径显示
    var displayPath: String {
        return path
    }
    
    var sizeString: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    var icon: String {
        fileType.icon
    }
}

/// 文件类型分类
enum FileType: String {
    case directory, document, spreadsheet, presentation
    case image, video, audio, archive, code, app, disk, pdf, other
    
    var icon: String {
        switch self {
        case .directory:    return "📁"
        case .pdf:          return "📕"
        case .document:     return "📘"
        case .spreadsheet:  return "📗"
        case .presentation: return "📙"
        case .image:        return "🖼"
        case .video:        return "🎬"
        case .audio:        return "🎵"
        case .archive:      return "📦"
        case .code:         return "💻"
        case .app:          return "📱"
        case .disk:         return "💿"
        case .other:        return "📄"
        }
    }
    
    static func from(extension ext: String) -> FileType {
        switch ext.lowercased() {
        case "pdf":                                                 return .pdf
        case "doc", "docx", "txt", "rtf", "md", "pages":           return .document
        case "xls", "xlsx", "csv", "numbers":                      return .spreadsheet
        case "ppt", "pptx", "key", "keynote":                      return .presentation
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "svg",
             "tiff", "bmp", "ico":                                  return .image
        case "mp4", "mov", "avi", "mkv", "wmv", "flv", "webm":     return .video
        case "mp3", "wav", "m4a", "flac", "aac", "ogg", "wma":     return .audio
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "dmg":  return .archive
        case "swift", "py", "js", "ts", "go", "rs", "java", "c",
             "cpp", "h", "m", "rb", "php", "sh", "lua", "json",
             "yaml", "yml", "toml", "xml", "html", "css":          return .code
        case "app":                                                 return .app
        default:                                                    return .other
        }
    }
}

/// 搜索过滤器
struct FileSearchFilter {
    var extensions: [String]?       // 限制文件类型
    var minSize: Int64?             // 最小字节
    var maxSize: Int64?             // 最大字节
    var modifiedAfter: Date?        // 从什么时候之后修改
    var modifiedBefore: Date?       // 到什么时候之前修改
    var isDirectory: Bool?          // 是否只搜目录
    var searchPaths: [String]?      // 指定搜索路径
    
    static let none = FileSearchFilter()
}

// MARK: - 搜索引擎

final class FileSearchEngine: @unchecked Sendable {
    
    static let shared = FileSearchEngine()
    
    private let fdCandidatePaths = [
        "/opt/homebrew/bin/fd", // Apple Silicon Homebrew
        "/usr/local/bin/fd",    // Intel Homebrew
        "/opt/local/bin/fd"     // MacPorts
    ]
    private let maxResults = 20
    private lazy var fdExecutablePath: String? = Self.resolveFdExecutablePath(candidatePaths: fdCandidatePaths)
    
    private static func resolveFdExecutablePath(candidatePaths: [String]) -> String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let expandedCandidates = candidatePaths + [
            "\(home)/.local/bin/fd",
            "\(home)/.cargo/bin/fd",
            "\(home)/.nix-profile/bin/fd",
            "\(home)/bin/fd",
            "\(home)/.local/bin/fdfind",
            "\(home)/bin/fdfind",
        ]
        
        for path in expandedCandidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v fd || command -v fdfind"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !output.isEmpty,
                  fm.isExecutableFile(atPath: output) else {
                return nil
            }
            
            return output
        } catch {
            return nil
        }
    }
    
    // MARK: - 主搜索入口
    
    /// 使用 fd 搜索文件（优先 ~ 目录）
    func search(
        query: String,
        filter: FileSearchFilter = .none,
        allowBroadMatch: Bool = false
    ) async -> [FileSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let isBroadMatch = allowBroadMatch && trimmed.isEmpty
        guard !trimmed.isEmpty || isBroadMatch else { return [] }
        
        // 用 fd 搜索
        let results = await fdSearch(query: trimmed, filter: filter, isBroadMatch: isBroadMatch)
        
        if !results.isEmpty {
            return Array(results.prefix(maxResults))
        }
        
        // fd 无结果时，fts 深度扫描后备
        let deepResults = await deepSearch(
            query: trimmed,
            filter: filter,
            excluding: Set(results.map(\.path)),
            isBroadMatch: isBroadMatch
        )
        return Array(deepResults.prefix(maxResults))
    }
    
    // MARK: - 快速路径: fd
    
    private func fdSearch(query: String, filter: FileSearchFilter, isBroadMatch: Bool) async -> [FileSearchResult] {
        guard let fdPath = fdExecutablePath else { return [] }
        
        var args: [String] = []
        
        // 颜色关闭，方便解析
        args.append("--color=never")
        
        // 类型过滤
        if let isDir = filter.isDirectory, isDir {
            args.append(contentsOf: ["-t", "d"])
        }
        
        // 扩展名过滤
        if let exts = filter.extensions, !exts.isEmpty {
            for ext in exts {
                args.append(contentsOf: ["-e", ext])
            }
        }
        
        // 大小过滤
        if let minSize = filter.minSize {
            args.append(contentsOf: ["-S", "+\(formatSizeForFd(minSize))"])
        }
        if let maxSize = filter.maxSize {
            args.append(contentsOf: ["-S", "-\(formatSizeForFd(maxSize))"])
        }
        
        // 时间过滤（fd 支持 --changed-within）
        if let after = filter.modifiedAfter {
            let seconds = Int(Date().timeIntervalSince(after))
            if seconds > 0 {
                args.append(contentsOf: ["--changed-within", "\(seconds)sec"])
            }
        }
        
        // 固定字符串匹配（. 不再当正则通配符）
        if !isBroadMatch {
            args.append("--fixed-strings")
        }
        
        // 输出绝对路径
        args.append("--absolute-path")
        
        // 搜索模式
        // broad match 时使用正则匹配所有文件名，便于“只有过滤条件”的查询。
        args.append(isBroadMatch ? ".*" : query)
        
        // 搜索目录：默认 ~，支持多个搜索路径
        let searchDirs = (filter.searchPaths?.isEmpty == false) ? (filter.searchPaths ?? []) : [NSHomeDirectory()]
        args.append(contentsOf: searchDirs)
        
        // 执行 fd
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: fdPath)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            
            // 超时 5 秒
            DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) {
                if process.isRunning { process.terminate() }
            }
            
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return [] }
            
            let paths = output.components(separatedBy: "\n").filter { !$0.isEmpty }
            let queryLower = query.lowercased()
            
            var results: [FileSearchResult] = []
            for path in paths.prefix(50) {
                let fullPath = path // 已经是绝对路径（--absolute-path）
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath) else { continue }
                
                let name = (fullPath as NSString).lastPathComponent
                let size = attrs[.size] as? Int64 ?? 0
                let modDate = attrs[.modificationDate] as? Date ?? Date.distantPast
                let inode = attrs[.systemFileNumber] as? UInt64 ?? 0
                let isDir = attrs[.type] as? FileAttributeType == .typeDirectory
                
                let ext = (name as NSString).pathExtension
                let fileType: FileType = isDir ? .directory : FileType.from(extension: ext)
                let score = isBroadMatch ? 0.5 : fuzzyScore(query: queryLower, target: name.lowercased())
                
                results.append(FileSearchResult(
                    path: fullPath, name: name, size: size,
                    modifiedDate: modDate, fileType: fileType,
                    inode: inode, matchScore: max(score, 0.5)
                ))
            }
            
            if isBroadMatch {
                results.sort {
                    if $0.modifiedDate != $1.modifiedDate { return $0.modifiedDate > $1.modifiedDate }
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            } else {
                results.sort { $0.matchScore > $1.matchScore }
            }
            return results
        } catch {
            return []
        }
    }
    
    /// 格式化字节为 fd 可识别的大小字符串
    private func formatSizeForFd(_ bytes: Int64) -> String {
        if bytes >= 1024 * 1024 * 1024 { return "\(bytes / (1024 * 1024 * 1024))g" }
        if bytes >= 1024 * 1024 { return "\(bytes / (1024 * 1024))m" }
        if bytes >= 1024 { return "\(bytes / 1024)k" }
        return "\(bytes)b"
    }
    
    // MARK: - 深度后备: fts_open + Swift Concurrency
    
    private func deepSearch(
        query: String,
        filter: FileSearchFilter,
        excluding: Set<String>,
        isBroadMatch: Bool
    ) async -> [FileSearchResult] {
        let searchPaths = filter.searchPaths ?? [NSHomeDirectory()]
        let queryLower = query.lowercased()
        
        return await withTaskGroup(of: [FileSearchResult].self) { group in
            for rootPath in searchPaths {
                group.addTask { [self] in
                    return self.ftsWalk(
                        rootPath: rootPath,
                        query: queryLower,
                        filter: filter,
                        excluding: excluding,
                        isBroadMatch: isBroadMatch
                    )
                }
            }
            
            var allResults: [FileSearchResult] = []
            for await batch in group {
                allResults.append(contentsOf: batch)
                if allResults.count >= maxResults * 2 { break }
            }
            return allResults
        }
    }
    
    /// fts_open/fts_read 底层遍历
    private func ftsWalk(
        rootPath: String,
        query: String,
        filter: FileSearchFilter,
        excluding: Set<String>,
        isBroadMatch: Bool
    ) -> [FileSearchResult] {
        var results: [FileSearchResult] = []
        
        let skipDirs: Set<String> = [
            ".git", ".svn", "node_modules", ".build", ".Trash",
            "Library", ".cache", "DerivedData", "Pods"
        ]
        
        let cPath = rootPath.withCString { strdup($0) }
        defer { free(cPath) }
        guard let cPath = cPath else { return [] }
        
        var paths: [UnsafeMutablePointer<Int8>?] = [cPath, nil]
        
        guard let stream = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else {
            return []
        }
        defer { fts_close(stream) }
        
        while let entry = fts_read(stream) {
            if results.count >= maxResults { break }
            
            let info = entry.pointee
            let fullPath = String(cString: info.fts_path)
            let entryName = (fullPath as NSString).lastPathComponent
            
            if info.fts_info == FTS_D {
                if entryName.hasPrefix(".") || skipDirs.contains(entryName) {
                    fts_set(stream, entry, FTS_SKIP)
                    continue
                }
                if info.fts_level > 8 {
                    fts_set(stream, entry, FTS_SKIP)
                    continue
                }
            }
            
            guard info.fts_info == FTS_F || info.fts_info == FTS_D else { continue }
            if excluding.contains(fullPath) { continue }
            
            let nameLower = entryName.lowercased()
            let score: Double
            if isBroadMatch {
                score = 0.5
            } else {
                if requiresLiteralMatch(query: query) {
                    guard nameLower.contains(query) else { continue }
                    score = nameLower == query ? 1.0 : 0.96
                } else {
                    score = fuzzyScore(query: query, target: nameLower)
                    guard score > 0.1 else { continue }
                }
            }
            
            let inode = UInt64(info.fts_statp.pointee.st_ino)
            let fileSize = Int64(info.fts_statp.pointee.st_size)
            let modTime = Date(timeIntervalSince1970: TimeInterval(info.fts_statp.pointee.st_mtimespec.tv_sec))
            
            if let minSize = filter.minSize, fileSize < minSize { continue }
            if let maxSize = filter.maxSize, fileSize > maxSize { continue }
            if let after = filter.modifiedAfter, modTime < after { continue }
            if let before = filter.modifiedBefore, modTime > before { continue }
            
            let ext = (entryName as NSString).pathExtension.lowercased()
            if let exts = filter.extensions, !exts.isEmpty {
                if !exts.contains(ext) { continue }
            }
            
            if let isDir = filter.isDirectory {
                let entryIsDir = info.fts_info == FTS_D
                if isDir != entryIsDir { continue }
            }
            
            let fileType: FileType = info.fts_info == FTS_D ? .directory : FileType.from(extension: ext)
            
            results.append(FileSearchResult(
                path: fullPath, name: entryName, size: fileSize,
                modifiedDate: modTime, fileType: fileType,
                inode: inode, matchScore: score
            ))
        }
        
        if isBroadMatch {
            results.sort {
                if $0.modifiedDate != $1.modifiedDate { return $0.modifiedDate > $1.modifiedDate }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        } else {
            results.sort { $0.matchScore > $1.matchScore }
        }
        
        return results
    }
    
    private func requiresLiteralMatch(query: String) -> Bool {
        if query.contains("/") || query.contains(".") { return true }
        if query.rangeOfCharacter(from: .decimalDigits) != nil && query.count >= 4 { return true }
        return false
    }
    
    // MARK: - 模糊匹配算法
    
    func fuzzyScore(query: String, target: String) -> Double {
        if query.isEmpty || target.isEmpty { return 0 }
        if target == query { return 1.0 }
        if target.contains(query) { return 0.95 }
        if target.hasPrefix(query) { return 0.98 }
        
        let targetBase = (target as NSString).deletingPathExtension.lowercased()
        if targetBase == query { return 0.97 }
        if targetBase.contains(query) { return 0.93 }
        
        var score = subsequenceScore(query: query, target: target)
        
        let queryTokens = tokenize(query)
        let targetTokens = tokenize(target)
        
        if queryTokens.count > 1 {
            let tokenScore = tokenMatchScore(queryTokens: queryTokens, targetTokens: targetTokens)
            score = max(score, tokenScore)
        }
        
        return score
    }
    
    private func subsequenceScore(query: String, target: String) -> Double {
        let qChars = Array(query)
        let tChars = Array(target)
        
        var qi = 0
        var matchPositions: [Int] = []
        
        for (ti, tc) in tChars.enumerated() {
            if qi < qChars.count && tc == qChars[qi] {
                matchPositions.append(ti)
                qi += 1
            }
        }
        
        guard qi == qChars.count else { return 0 }
        
        let baseScore = Double(qChars.count) / Double(tChars.count) * 0.6
        
        var continuousBonus = 0.0
        for i in 1..<matchPositions.count {
            if matchPositions[i] == matchPositions[i - 1] + 1 {
                continuousBonus += 0.05
            }
        }
        
        let positionBonus = matchPositions.first == 0 ? 0.1 : 0.0
        
        return min(baseScore + continuousBonus + positionBonus, 0.89)
    }
    
    private func tokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        
        for (i, char) in input.enumerated() {
            if char == " " || char == "_" || char == "-" || char == "." {
                if !current.isEmpty {
                    tokens.append(current.lowercased())
                    current = ""
                }
            } else if char.isUppercase && i > 0 {
                if !current.isEmpty {
                    tokens.append(current.lowercased())
                    current = ""
                }
                current.append(char)
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            tokens.append(current.lowercased())
        }
        return tokens
    }
    
    private func tokenMatchScore(queryTokens: [String], targetTokens: [String]) -> Double {
        guard !queryTokens.isEmpty else { return 0 }
        
        var matched = 0
        for qt in queryTokens {
            if targetTokens.contains(where: { $0.contains(qt) }) {
                matched += 1
            }
        }
        
        return Double(matched) / Double(queryTokens.count) * 0.85
    }
    
    // MARK: - 查询解析
    
    static func parseQuery(_ rawQuery: String) -> (query: String, filter: FileSearchFilter) {
        var filter = FileSearchFilter()
        var queryParts: [String] = []
        let extensionKeywords: [String: [String]] = [
            "pdf": ["pdf"],
            "md": ["md"],
            "markdown": ["md"],
            "txt": ["txt"],
            "doc": ["doc", "docx"],
            "docx": ["docx"],
            "swift": ["swift"],
            "py": ["py"],
            "js": ["js"],
            "ts": ["ts"],
            "json": ["json"],
            "xml": ["xml"],
            "html": ["html"],
            "css": ["css"],
            "jpg": ["jpg", "jpeg"],
            "jpeg": ["jpg", "jpeg"],
            "png": ["png"],
            "gif": ["gif"],
            "webp": ["webp"],
            "heic": ["heic"],
            "mp4": ["mp4"],
            "mov": ["mov"],
            "avi": ["avi"],
            "mkv": ["mkv"],
            "mp3": ["mp3"],
            "wav": ["wav"],
            "m4a": ["m4a"],
            "zip": ["zip"],
            "rar": ["rar"],
        ]
        
        let parts = rawQuery.components(separatedBy: " ")
        var i = 0
        
        while i < parts.count {
            let part = parts[i].lowercased()
            
            switch part {
            case "-size", "--size":
                if i + 1 < parts.count {
                    i += 1
                    let sizeStr = parts[i].lowercased()
                    if sizeStr.hasPrefix(">") {
                        filter.minSize = parseSize(String(sizeStr.dropFirst()))
                    } else if sizeStr.hasPrefix("<") {
                        filter.maxSize = parseSize(String(sizeStr.dropFirst()))
                    }
                }
                
            case "-time", "--time", "-t":
                if i + 1 < parts.count {
                    i += 1
                    let timeStr = parts[i].lowercased()
                    if let days = parseDays(timeStr) {
                        filter.modifiedAfter = Calendar.current.date(byAdding: .day, value: -days, to: Date())
                    }
                }
                
            case "-ext", "--ext", "-e":
                if i + 1 < parts.count {
                    i += 1
                    filter.extensions = parts[i].components(separatedBy: ",")
                }
                
            case "-dir", "--dir":
                filter.isDirectory = true
                
            case "-in", "--in":
                if i + 1 < parts.count {
                    i += 1
                    let searchPath = parts[i]
                    let expanded = (searchPath as NSString).expandingTildeInPath
                    filter.searchPaths = [expanded]
                }
                
            default:
                // 中文过滤关键词
                if part.contains("大文件") {
                    filter.minSize = 100 * 1024 * 1024
                } else if part.contains("swift文件") || part.contains("swift 文件") {
                    filter.extensions = ["swift"]
                } else if part.contains("图片") || part.contains("照片") {
                    filter.extensions = ["jpg", "jpeg", "png", "gif", "webp", "heic"]
                } else if part.contains("视频") {
                    filter.extensions = ["mp4", "mov", "avi", "mkv"]
                } else if part.contains("文档") {
                    filter.extensions = ["pdf", "doc", "docx", "txt", "md", "pages"]
                } else if part.contains("音乐") || part.contains("音频") {
                    filter.extensions = ["mp3", "wav", "m4a", "flac"]
                } else if part.contains("最近") || part.contains("今天") {
                    filter.modifiedAfter = Calendar.current.date(byAdding: .day, value: -1, to: Date())
                } else if part.contains("本周") {
                    filter.modifiedAfter = Calendar.current.date(byAdding: .day, value: -7, to: Date())
                } else if part.contains("本月") {
                    filter.modifiedAfter = Calendar.current.date(byAdding: .month, value: -1, to: Date())
                } else if let mappedExtensions = extensionKeywords[part] {
                    filter.extensions = mergeExtensions(existing: filter.extensions, adding: mappedExtensions)
                } else if part.contains("代码") || part == "code" {
                    filter.extensions = mergeExtensions(
                        existing: filter.extensions,
                        adding: ["swift", "py", "js", "ts", "java", "go", "rs", "c", "cpp", "h", "m"]
                    )
                } else {
                    queryParts.append(parts[i])
                }
            }
            
            i += 1
        }
        
        return (queryParts.joined(separator: " "), filter)
    }
    
    private static func parseSize(_ str: String) -> Int64? {
        let lower = str.lowercased()
        let multipliers: [(String, Int64)] = [
            ("gb", 1024 * 1024 * 1024),
            ("mb", 1024 * 1024),
            ("kb", 1024),
            ("b", 1)
        ]
        
        for (suffix, mult) in multipliers {
            if lower.hasSuffix(suffix) {
                let numStr = String(lower.dropLast(suffix.count))
                if let num = Double(numStr) {
                    return Int64(num * Double(mult))
                }
            }
        }
        
        return Int64(str)
    }
    
    private static func parseDays(_ str: String) -> Int? {
        let lower = str.lowercased()
        if lower.hasSuffix("d") { return Int(String(lower.dropLast())) }
        if lower.hasSuffix("w") { return (Int(String(lower.dropLast())) ?? 0) * 7 }
        if lower.hasSuffix("m") { return (Int(String(lower.dropLast())) ?? 0) * 30 }
        return Int(str)
    }
    
    private static func mergeExtensions(existing: [String]?, adding: [String]) -> [String] {
        let merged = Set((existing ?? []) + adding.map { $0.lowercased() })
        return merged.sorted()
    }
    
    // MARK: - 结果格式化
    
    static func formatResults(_ results: [FileSearchResult]) -> String {
        if results.isEmpty {
            return "未找到匹配文件"
        }
        
        var lines: [String] = []
        for r in results {
            lines.append("\(r.icon) \(r.name)  \(r.sizeString)\n   \(r.displayPath)")
        }
        
        return "🔍 找到 \(results.count) 个结果\n\n" + lines.joined(separator: "\n\n")
    }
}
