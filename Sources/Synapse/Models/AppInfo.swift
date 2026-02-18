// MARK: - Models/AppInfo.swift
// App 数据模型

import AppKit

struct AppInfo: Identifiable, Hashable, Codable {
    var id: String { bundleId ?? path }
    let name: String
    let path: String
    let bundleId: String?
    let capabilities: [String]  // 能力标签
    
    // Non-codable, runtime only
    var icon: NSImage? {
        NSWorkspace.shared.icon(forFile: path)
    }
    
    enum CodingKeys: String, CodingKey {
        case name, path, bundleId, capabilities
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
        lhs.id == rhs.id
    }
}
