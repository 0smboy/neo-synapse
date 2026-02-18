import Testing
@testable import Synapse

struct IntentEngineTests {
    
    @Test
    func recognizeEnglishLaunchCommandExtractsTargetSafely() {
        let engine = IntentEngine()
        let intent = engine.recognize("Open Safari")
        
        #expect(intent.action == .launchApp)
        #expect(intent.parameters["appName"] == "Safari")
    }
    
    @Test
    func recognizeChineseLaunchCommandExtractsTargetSafely() {
        let engine = IntentEngine()
        let intent = engine.recognize("打开 微信")
        
        #expect(intent.action == .launchApp)
        #expect(intent.parameters["appName"] == "微信")
    }
    
    @Test
    func recognizeCodeQueryShouldNotBeHijackedByFileSearch() {
        let engine = IntentEngine()
        let intent = engine.recognize("写代码 一个 swift 排序函数")
        
        #expect(intent.action == .codeWrite)
    }
    
    @Test
    func recognizeExplicitDictionaryQueryShouldStayDictionaryEvenWhenMissing() {
        let engine = IntentEngine()
        let intent = engine.recognize("define qwertyuiopasdfgh")
        
        #expect(intent.action == .inlineResult)
        #expect(intent.parameters["type"] == "dictionary")
    }
    
    @Test
    func recognizeCalcPrefixShouldReturnInlineCalculatorResult() {
        let engine = IntentEngine()
        let intent = engine.recognize("calc 2+3*4")
        
        #expect(intent.action == .inlineResult)
        #expect(intent.parameters["type"] == "calculator")
    }
    
    @Test
    func recognizeColorNameShouldReturnInlineColorResult() {
        let engine = IntentEngine()
        let intent = engine.recognize("color blue")
        
        #expect(intent.action == .inlineResult)
        #expect(intent.parameters["type"] == "color")
    }

    @Test
    func recognizeTranslateQueryShouldRouteToTranslateAction() {
        let engine = IntentEngine()
        let intent = engine.recognize("把 hello world 翻译成中文")

        #expect(intent.action == .translateText)
        #expect(intent.parameters["query"] == "把 hello world 翻译成中文")
    }

    @Test
    func recognizeLaunchKeywordWithoutAppNameShouldKeepEmptyTarget() {
        let engine = IntentEngine()
        let intent = engine.recognize("打开")

        #expect(intent.action == .launchApp)
        #expect(intent.parameters["appName"] == "")
    }

    @Test
    func recognizeWebSearchIntent() {
        let engine = IntentEngine()
        let intent = engine.recognize("联网搜索 SwiftData 教程")

        #expect(intent.action == .webSearch)
        #expect(intent.parameters["query"] == "SwiftData 教程")
    }

    @Test
    func recognizeMemoryRememberIntent() {
        let engine = IntentEngine()
        let intent = engine.recognize("记住 我喜欢简洁回答")

        #expect(intent.action == .memoryRemember)
        #expect(intent.parameters["text"] == "我喜欢简洁回答")
    }

    @Test
    func recognizeConversationHistoryIntent() {
        let engine = IntentEngine()
        let intent = engine.recognize("历史对话 产品发布")

        #expect(intent.action == .conversationHistory)
        #expect(intent.parameters["query"] == "产品发布")
    }

    @Test
    func autoMemoryShouldCaptureUserPreferenceWithoutManualRemember() {
        _ = MemoryStore.shared.clear()
        SynapseSettings.autoMemoryEnabled = true

        MemoryAutoManager.shared.ingest(
            user: "请用中文并尽量简洁回答我。",
            assistant: "好的，我会用中文并保持简洁。",
            action: .knowledgeQuery
        )

        let items = MemoryStore.shared.list(limit: 10)
        #expect(items.contains(where: { $0.text.contains("用户偏好：") }))

        _ = MemoryStore.shared.clear()
    }
}
