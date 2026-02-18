// MARK: - Modules/CalculatorModule.swift
// 计算器 - 数学表达式 + 进制转换 + 常量

import Foundation
import JavaScriptCore

/// 内联计算器
final class CalculatorModule {
    
    private let jsContext: JSContext = {
        let ctx = JSContext()!
        // 注入数学常量和函数
        ctx.evaluateScript("""
            var PI = Math.PI;
            var E = Math.E;
            var pi = Math.PI;
            var e = Math.E;
            var sqrt = Math.sqrt;
            var abs = Math.abs;
            var pow = Math.pow;
            var log = Math.log;
            var log2 = Math.log2;
            var log10 = Math.log10;
            var sin = Math.sin;
            var cos = Math.cos;
            var tan = Math.tan;
            var ceil = Math.ceil;
            var floor = Math.floor;
            var round = Math.round;
            var max = Math.max;
            var min = Math.min;
            var random = Math.random;
        """)
        return ctx
    }()
    
    /// 判断是否是数学表达式
    func canHandle(_ query: String) -> Bool {
        let trimmed = normalizedExpression(from: query)
        if trimmed.isEmpty { return false }
        
        // 包含数字和运算符
        let mathPattern = #"[\d\.\+\-\*\/\%\(\)\^]"#
        let hasMath = trimmed.range(of: mathPattern, options: .regularExpression) != nil
        let hasDigit = trimmed.contains(where: { $0.isNumber })
        
        // 进制转换
        if trimmed.lowercased().hasPrefix("0x") || trimmed.lowercased().hasPrefix("0b") ||
           trimmed.lowercased().hasPrefix("0o") { return true }
        
        // 包含数学函数
        let mathFuncs = ["sqrt", "pow", "log", "sin", "cos", "tan", "abs", "ceil", "floor", "round", "pi", "PI"]
        if mathFuncs.contains(where: { trimmed.lowercased().contains($0.lowercased()) }) && hasDigit { return true }
        
        return hasMath && hasDigit
    }
    
    /// 计算表达式
    func evaluate(_ query: String) -> String? {
        var expr = normalizedExpression(from: query)
        if expr.isEmpty { return nil }
        
        // 预处理
        expr = expr.replacingOccurrences(of: "×", with: "*")
        expr = expr.replacingOccurrences(of: "÷", with: "/")
        expr = expr.replacingOccurrences(of: "^", with: "**")
        expr = expr.replacingOccurrences(of: "，", with: ",")
        expr = expr.replacingOccurrences(of: "=", with: "")
        
        // 进制转换
        let lower = expr.lowercased()
        if lower.hasPrefix("0x"), let val = UInt64(String(lower.dropFirst(2)), radix: 16) {
            return formatConversion(val, fromBase: "十六进制")
        }
        if lower.hasPrefix("0b"), let val = UInt64(String(lower.dropFirst(2)), radix: 2) {
            return formatConversion(val, fromBase: "二进制")
        }
        if lower.hasPrefix("0o"), let val = UInt64(String(lower.dropFirst(2)), radix: 8) {
            return formatConversion(val, fromBase: "八进制")
        }
        
        // JavaScript 执行
        jsContext.exception = nil
        guard let result = jsContext.evaluateScript(expr) else { return nil }
        
        if result.isUndefined || result.isNull { return nil }
        if jsContext.exception != nil {
            jsContext.exception = nil
            return nil
        }
        
        if result.isNumber {
            let num = result.toDouble()
            if num.isNaN || num.isInfinite { return nil }
            
            // 整数结果不需要小数点
            if num == floor(num) && abs(num) < 1e15 {
                return formatNumber(Int64(num))
            }
            return formatDecimal(num)
        }
        
        return result.toString()
    }
    
    // MARK: - 格式化
    
    private func formatNumber(_ n: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: n)) ?? String(n)
    }
    
    private func formatDecimal(_ n: Double) -> String {
        if abs(n) < 0.0001 || abs(n) > 1e10 {
            return String(format: "%.6e", n)
        }
        // 去掉尾部的零
        let str = String(format: "%.10f", n)
        var result = str
        while result.hasSuffix("0") { result = String(result.dropLast()) }
        if result.hasSuffix(".") { result = String(result.dropLast()) }
        return result
    }
    
    private func formatConversion(_ val: UInt64, fromBase: String) -> String {
        return """
        \(fromBase) → 十进制: \(val)
        十六进制: 0x\(String(val, radix: 16, uppercase: true))
        二进制: 0b\(String(val, radix: 2))
        八进制: 0o\(String(val, radix: 8))
        """
    }

    private func normalizedExpression(from query: String) -> String {
        var expr = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["calc ", "calculator ", "计算 ", "算一下 ", "算 "]
        for prefix in prefixes where expr.lowercased().hasPrefix(prefix) {
            expr = String(expr.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        return expr
    }
}
