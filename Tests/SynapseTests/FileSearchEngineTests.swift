import Foundation
import Testing
@testable import Synapse

struct FileSearchEngineTests {
    
    @Test
    func parseQueryWithOnlyFiltersKeepsEmptyKeyword() {
        let parsed = FileSearchEngine.parseQuery("最近 pdf")
        
        #expect(parsed.query == "")
        #expect(parsed.filter.extensions == ["pdf"])
        #expect(parsed.filter.modifiedAfter != nil)
    }
    
    @Test
    func fuzzyScoreRanksPrefixHigherThanSubsequence() {
        let engine = FileSearchEngine.shared
        
        let prefixScore = engine.fuzzyScore(query: "syn", target: "synapse.swift")
        let subsequenceScore = engine.fuzzyScore(query: "snp", target: "synapse.swift")
        
        #expect(prefixScore > subsequenceScore)
        #expect(engine.fuzzyScore(query: "synapse", target: "synapse") == 1.0)
    }
    
    @Test
    func broadMatchSearchReturnsFilteredFiles() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("synapse-test-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        
        let markdownFile = root.appendingPathComponent("notes.md")
        let textFile = root.appendingPathComponent("plain.txt")
        try "# title".write(to: markdownFile, atomically: true, encoding: .utf8)
        try "hello".write(to: textFile, atomically: true, encoding: .utf8)
        
        var filter = FileSearchFilter.none
        filter.extensions = ["md"]
        filter.searchPaths = [root.path]
        
        let results = await FileSearchEngine.shared.search(
            query: "",
            filter: filter,
            allowBroadMatch: true
        )
        
        #expect(results.contains(where: { $0.name == "notes.md" }))
        #expect(!results.contains(where: { $0.name == "plain.txt" }))
    }
    
    @Test
    func literalFilenameSearchMatchesExactFile() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("synapse-test-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        
        let exactFile = root.appendingPathComponent("me2.jpg")
        let distractorA = root.appendingPathComponent("track-22663608.jpg")
        let distractorB = root.appendingPathComponent("track-569028.jpg")
        try Data([0x01]).write(to: exactFile)
        try Data([0x02]).write(to: distractorA)
        try Data([0x03]).write(to: distractorB)
        
        var filter = FileSearchFilter.none
        filter.searchPaths = [root.path]
        
        let results = await FileSearchEngine.shared.search(
            query: "me2.jpg",
            filter: filter
        )
        
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.name.localizedCaseInsensitiveContains("me2.jpg") })
    }
}
