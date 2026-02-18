// MARK: - Models/ExecutionResult.swift
// 执行结果模型

import Foundation

struct ExecutionResult {
    enum Status {
        case success
        case failure(String)
        case pending
    }
    
    let status: Status
    let output: String?
    let fileResults: [FileSearchResult]?
    let timestamp: Date
    
    var isSuccess: Bool {
        if case .success = status { return true }
        return false
    }
    
    static func success(_ output: String? = nil, fileResults: [FileSearchResult]? = nil) -> ExecutionResult {
        ExecutionResult(status: .success, output: output, fileResults: fileResults, timestamp: Date())
    }
    
    static func failure(_ error: String) -> ExecutionResult {
        ExecutionResult(status: .failure(error), output: nil, fileResults: nil, timestamp: Date())
    }
}
