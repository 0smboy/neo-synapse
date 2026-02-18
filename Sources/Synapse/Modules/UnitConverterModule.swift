// MARK: - Modules/UnitConverterModule.swift
// 单位与货币换算

import Foundation

/// 单位换算模块
final class UnitConverterModule {
    
    // MARK: - 单位换算规则
    
    struct ConversionRule {
        let pattern: String       // 正则匹配模式
        let convert: (Double) -> (value: Double, unit: String)
        let reverseUnit: String   // 源单位名
    }
    
    /// 判断是否能处理
    func canHandle(_ query: String) -> Bool {
        let lower = query.lowercased()
        let unitKeywords = ["转", "换算", "convert", "to", "等于多少",
                           "km", "mi", "kg", "lb", "lbs", "°c", "°f", "℃", "℉",
                           "厘米", "英寸", "公里", "英里", "千克", "磅",
                           "摄氏", "华氏", "celsius", "fahrenheit",
                           "升", "加仑", "盎司", "ml", "oz", "gallon",
                           "米", "英尺", "foot", "feet", "inch",
                           "rmb", "usd", "cny", "eur", "jpy", "gbp", "美元", "人民币", "欧元", "日元", "英镑",
                           "字节", "mb", "gb", "tb", "kb", "byte"]
        
        let hasNumber = query.contains(where: { $0.isNumber })
        let hasUnit = unitKeywords.contains(where: { lower.contains($0) })
        return hasNumber && hasUnit
    }
    
    /// 执行换算
    func convert(_ query: String) -> String? {
        let lower = query.lowercased()
        
        // 提取数字
        guard let number = extractNumber(from: query) else { return nil }
        
        // 温度
        if matches(lower, ["°c", "℃", "摄氏", "celsius"]) {
            let f = number * 9.0 / 5.0 + 32
            let k = number + 273.15
            return "🌡 温度换算\n\n\(fmt(number))°C = \(fmt(f))°F = \(fmt(k))K"
        }
        if matches(lower, ["°f", "℉", "华氏", "fahrenheit"]) {
            let c = (number - 32) * 5.0 / 9.0
            let k = c + 273.15
            return "🌡 温度换算\n\n\(fmt(number))°F = \(fmt(c))°C = \(fmt(k))K"
        }
        
        // 长度
        if matches(lower, ["km", "公里", "千米"]) {
            return "📏 长度换算\n\n\(fmt(number)) km = \(fmt(number * 0.621371)) mi = \(fmt(number * 1000)) m"
        }
        if matches(lower, ["mi", "英里", "mile"]) {
            return "📏 长度换算\n\n\(fmt(number)) mi = \(fmt(number * 1.60934)) km = \(fmt(number * 5280)) ft"
        }
        if matches(lower, ["cm", "厘米"]) {
            return "📏 长度换算\n\n\(fmt(number)) cm = \(fmt(number / 2.54)) in = \(fmt(number / 100)) m"
        }
        if matches(lower, ["inch", "英寸", "in", "寸"]) && !lower.contains("min") {
            return "📏 长度换算\n\n\(fmt(number)) in = \(fmt(number * 2.54)) cm = \(fmt(number / 12)) ft"
        }
        if matches(lower, ["m", "米"]) && !matches(lower, ["km", "cm", "mm", "mi", "mb"]) {
            return "📏 长度换算\n\n\(fmt(number)) m = \(fmt(number * 3.28084)) ft = \(fmt(number * 100)) cm"
        }
        if matches(lower, ["feet", "foot", "ft", "英尺"]) {
            return "📏 长度换算\n\n\(fmt(number)) ft = \(fmt(number * 0.3048)) m = \(fmt(number * 12)) in"
        }
        
        // 重量
        if matches(lower, ["kg", "千克", "公斤"]) {
            return "⚖️ 重量换算\n\n\(fmt(number)) kg = \(fmt(number * 2.20462)) lb = \(fmt(number * 1000)) g"
        }
        if matches(lower, ["lb", "lbs", "磅"]) {
            return "⚖️ 重量换算\n\n\(fmt(number)) lb = \(fmt(number * 0.453592)) kg = \(fmt(number * 16)) oz"
        }
        
        // 容量
        if matches(lower, ["gallon", "加仑"]) {
            return "🥛 容量换算\n\n\(fmt(number)) gal = \(fmt(number * 3.78541)) L = \(fmt(number * 3785.41)) mL"
        }
        if matches(lower, ["升", "liter", "l"]) && !matches(lower, ["ml"]) {
            return "🥛 容量换算\n\n\(fmt(number)) L = \(fmt(number * 0.264172)) gal = \(fmt(number * 1000)) mL"
        }
        
        // 数据大小
        if matches(lower, ["tb"]) {
            return "💾 数据大小\n\n\(fmt(number)) TB = \(fmt(number * 1024)) GB = \(fmt(number * 1048576)) MB"
        }
        if matches(lower, ["gb"]) {
            return "💾 数据大小\n\n\(fmt(number)) GB = \(fmt(number / 1024)) TB = \(fmt(number * 1024)) MB"
        }
        if matches(lower, ["mb"]) && !matches(lower, ["rmb"]) {
            return "💾 数据大小\n\n\(fmt(number)) MB = \(fmt(number / 1024)) GB = \(fmt(number * 1024)) KB"
        }
        
        // 货币（静态汇率近似值）
        if matches(lower, ["usd", "美元"]) {
            return "💱 汇率换算 (近似)\n\n$\(fmt(number)) USD ≈ ¥\(fmt(number * 7.25)) CNY ≈ €\(fmt(number * 0.92)) EUR ≈ ¥\(fmt(number * 149.5)) JPY"
        }
        if matches(lower, ["rmb", "cny", "人民币", "元"]) {
            return "💱 汇率换算 (近似)\n\n¥\(fmt(number)) CNY ≈ $\(fmt(number / 7.25)) USD ≈ €\(fmt(number / 7.88)) EUR ≈ ¥\(fmt(number * 20.6)) JPY"
        }
        if matches(lower, ["eur", "欧元"]) {
            return "💱 汇率换算 (近似)\n\n€\(fmt(number)) EUR ≈ $\(fmt(number * 1.09)) USD ≈ ¥\(fmt(number * 7.88)) CNY"
        }
        if matches(lower, ["jpy", "日元"]) {
            return "💱 汇率换算 (近似)\n\n¥\(fmt(number)) JPY ≈ $\(fmt(number / 149.5)) USD ≈ ¥\(fmt(number * 0.0485)) CNY"
        }
        
        return nil
    }
    
    // MARK: - 辅助
    
    private func extractNumber(from query: String) -> Double? {
        let pattern = #"[\d]+\.?[\d]*"#
        guard let range = query.range(of: pattern, options: .regularExpression) else { return nil }
        return Double(query[range])
    }
    
    private func matches(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains(where: { text.contains($0) })
    }
    
    private func fmt(_ n: Double) -> String {
        if n == floor(n) && abs(n) < 1e15 { return String(format: "%.0f", n) }
        if abs(n) < 0.01 { return String(format: "%.4f", n) }
        return String(format: "%.2f", n)
    }
}
