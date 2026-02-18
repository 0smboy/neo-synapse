// MARK: - Modules/ColorModule.swift
// 颜色预览模块 - 解析 hex/rgb/hsl 颜色值

import AppKit

/// 颜色模块
final class ColorModule {
    private let namedColors: [String: String] = [
        "red": "FF3B30", "红": "FF3B30", "红色": "FF3B30",
        "orange": "FF9500", "橙": "FF9500", "橙色": "FF9500",
        "yellow": "FFCC00", "黄": "FFCC00", "黄色": "FFCC00",
        "green": "34C759", "绿": "34C759", "绿色": "34C759",
        "mint": "00C7BE", "薄荷": "00C7BE",
        "cyan": "32ADE6", "青": "32ADE6", "青色": "32ADE6",
        "blue": "007AFF", "蓝": "007AFF", "蓝色": "007AFF",
        "indigo": "5856D6", "靛蓝": "5856D6",
        "purple": "AF52DE", "紫": "AF52DE", "紫色": "AF52DE",
        "pink": "FF2D55", "粉": "FF2D55", "粉色": "FF2D55",
        "brown": "A2845E", "棕": "A2845E", "棕色": "A2845E",
        "black": "000000", "黑": "000000", "黑色": "000000",
        "white": "FFFFFF", "白": "FFFFFF", "白色": "FFFFFF",
        "gray": "8E8E93", "grey": "8E8E93", "灰": "8E8E93", "灰色": "8E8E93"
    ]
    
    func canHandle(_ query: String) -> Bool {
        let lower = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // #hex 格式
        if lower.hasPrefix("#") && lower.count >= 4 { return true }
        // rgb(...) 格式
        if lower.contains("rgb(") || lower.contains("rgba(") { return true }
        // 颜色关键词
        if lower.hasPrefix("color ") || lower.hasPrefix("颜色 ") { return true }
        if namedColors[lower] != nil { return true }
        
        return false
    }
    
    func parse(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // #hex
        if trimmed.hasPrefix("#") {
            return parseHex(String(trimmed.dropFirst()))
        }
        
        // rgb(r, g, b)
        let lower = trimmed.lowercased()
        if lower.contains("rgb") {
            return parseRGB(trimmed)
        }
        
        // 关键词
        if lower.hasPrefix("color ") || lower.hasPrefix("颜色 ") {
            let colorStr = trimmed.components(separatedBy: " ").last ?? ""
            if colorStr.hasPrefix("#") {
                return parseHex(String(colorStr.dropFirst()))
            }
            if let hex = namedColors[colorStr.lowercased()] {
                return parseHex(hex)
            }
            return parseHex(colorStr)
        }

        if let hex = namedColors[lower] {
            return parseHex(hex)
        }
        
        return nil
    }
    
    private func parseHex(_ hex: String) -> String? {
        var cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        
        // 3位简写 → 6位
        if cleanHex.count == 3 {
            cleanHex = cleanHex.map { "\($0)\($0)" }.joined()
        }
        
        guard cleanHex.count == 6, let val = UInt64(cleanHex, radix: 16) else { return nil }
        
        let r = Int((val >> 16) & 0xFF)
        let g = Int((val >> 8) & 0xFF)
        let b = Int(val & 0xFF)
        
        return formatColor(r: r, g: g, b: b, hex: cleanHex)
    }
    
    private func parseRGB(_ input: String) -> String? {
        let pattern = #"(\d+)\s*,\s*(\d+)\s*,\s*(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) else {
            return nil
        }
        
        guard let rRange = Range(match.range(at: 1), in: input),
              let gRange = Range(match.range(at: 2), in: input),
              let bRange = Range(match.range(at: 3), in: input),
              let r = Int(input[rRange]),
              let g = Int(input[gRange]),
              let b = Int(input[bRange]) else { return nil }
        
        let hex = String(format: "%02X%02X%02X", r, g, b)
        return formatColor(r: r, g: g, b: b, hex: hex)
    }
    
    private func formatColor(r: Int, g: Int, b: Int, hex: String) -> String {
        // HSL 转换
        let rf = Double(r) / 255, gf = Double(g) / 255, bf = Double(b) / 255
        let maxC = max(rf, gf, bf), minC = min(rf, gf, bf)
        let l = (maxC + minC) / 2
        var h = 0.0, s = 0.0
        
        if maxC != minC {
            let d = maxC - minC
            s = l > 0.5 ? d / (2 - maxC - minC) : d / (maxC + minC)
            switch maxC {
            case rf: h = (gf - bf) / d + (gf < bf ? 6 : 0)
            case gf: h = (bf - rf) / d + 2
            default: h = (rf - gf) / d + 4
            }
            h *= 60
        }
        
        return """
        🎨 颜色信息
        
        HEX:  #\(hex)
        RGB:  rgb(\(r), \(g), \(b))
        HSL:  hsl(\(Int(h))°, \(Int(s * 100))%, \(Int(l * 100))%)
        """
    }
}
