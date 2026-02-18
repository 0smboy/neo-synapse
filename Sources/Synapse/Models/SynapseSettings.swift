import Foundation

enum SynapseSettings {
    enum Keys {
        static let fastModel = "synapse.codex.fastModel"
        static let thinkModel = "synapse.codex.thinkModel"
        static let deepResearchModel = "synapse.codex.deepResearchModel"

        static let fastReasoningEffort = "synapse.codex.fastReasoningEffort"
        static let thinkReasoningEffort = "synapse.codex.thinkReasoningEffort"
        static let deepResearchReasoningEffort = "synapse.codex.deepResearchReasoningEffort"

        static let responseMode = "synapse.codex.responseMode"
        static let knowledgeTimeout = "synapse.codex.knowledgeTimeout"
        static let codeTimeout = "synapse.codex.codeTimeout"
        static let writingTimeout = "synapse.codex.writingTimeout"
        static let disableMCPServers = "synapse.codex.disableMCPServers"
        static let richAIFormatting = "synapse.ui.richAIFormatting"
        static let autoMemoryEnabled = "synapse.ai.autoMemoryEnabled"
        static let enableWebSearch = "synapse.ai.enableWebSearch"
        static let aiVisualStyle = "synapse.ai.visualStyle"
        static let voiceEnabled = "synapse.voice.enabled"
        static let voiceAutoExecute = "synapse.voice.autoExecute"
        static let voiceSpeakResponse = "synapse.voice.speakResponse"
        static let voiceWakeWord = "synapse.voice.wakeWord"
        static let voiceLocale = "synapse.voice.locale"
        static let rayEnabled = "synapse.ray.enabled"
        static let rayWakeWords = "synapse.ray.wakeWords"
        static let rayAutoSpeak = "synapse.ray.autoSpeak"
        static let rayPosition = "synapse.ray.position"
        static let panelWidth = "synapse.ui.panelWidth"
        static let hotkeyPreset = "synapse.ui.hotkeyPreset"
    }

    // 仅保留当前 Codex CLI 可用模型，并按模式做推荐分组
    static let defaultFastModel = "gpt-5.1-codex-mini"
    static let defaultThinkModel = "gpt-5.1-codex-max"
    static let defaultDeepResearchModel = "gpt-5.2"

    static let defaultFastReasoningEffort = "medium"
    static let defaultThinkReasoningEffort = "high"
    static let defaultDeepResearchReasoningEffort = "xhigh"

    static let defaultResponseMode = "fast"
    static let defaultKnowledgeTimeout = 12.0
    static let defaultCodeTimeout = 18.0
    static let defaultWritingTimeout = 12.0
    static let defaultDisableMCPServers = true
    static let defaultRichAIFormatting = true
    static let defaultAutoMemoryEnabled = true
    static let defaultEnableWebSearch = true
    static let defaultAIVisualStyle = "matrix"
    static let defaultVoiceEnabled = false
    static let defaultVoiceAutoExecute = true
    static let defaultVoiceSpeakResponse = true
    static let defaultVoiceWakeWord = "synapse"
    static let defaultVoiceLocale = "zh-CN"
    static let defaultRayEnabled = true
    static let defaultRayWakeWords = "hi ray,hey ray"
    static let defaultRayAutoSpeak = true
    static let defaultRayPosition = "bottom_right"
    static let defaultPanelWidth = 900.0
    static let defaultHotkeyPreset = "option_space"

    static let fastModelOptions = [
        "gpt-5.1-codex-mini",
        "gpt-5.2-codex",
        "gpt-5.3-codex",
        "gpt-5.2",
    ]
    static let thinkModelOptions = [
        "gpt-5.1-codex-max",
        "gpt-5.3-codex",
        "gpt-5.2-codex",
        "gpt-5.2",
    ]
    static let deepResearchModelOptions = [
        "gpt-5.2",
        "gpt-5.3-codex",
        "gpt-5.1-codex-max",
        "gpt-5.2-codex",
    ]
    static let reasoningEffortOptions = ["low", "medium", "high", "xhigh"]
    static let aiVisualStyleOptions = ["matrix", "native"]
    static let voiceLocaleOptions = ["zh-CN", "en-US"]

    static let hotkeyPresetOptions: [(id: String, title: String)] = [
        ("option_space", "Option + Space"),
        ("control_space", "Control + Space"),
        ("command_shift_space", "Command + Shift + Space"),
        ("option_command_k", "Option + Command + K"),
    ]

    private static let store = UserDefaults.standard

    static var fastModel: String {
        get { normalizedModel(string(for: Keys.fastModel, defaultValue: defaultFastModel), mode: "fast") }
        set { store.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.fastModel) }
    }

    static var thinkModel: String {
        get { normalizedModel(string(for: Keys.thinkModel, defaultValue: defaultThinkModel), mode: "think") }
        set { store.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.thinkModel) }
    }

    static var deepResearchModel: String {
        get {
            normalizedModel(
                string(for: Keys.deepResearchModel, defaultValue: defaultDeepResearchModel),
                mode: "deep_research"
            )
        }
        set { store.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.deepResearchModel) }
    }

    static var fastReasoningEffort: String {
        get {
            normalizedReasoningEffort(
                string(for: Keys.fastReasoningEffort, defaultValue: defaultFastReasoningEffort),
                fallback: defaultFastReasoningEffort
            )
        }
        set { store.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.fastReasoningEffort) }
    }

    static var thinkReasoningEffort: String {
        get {
            normalizedReasoningEffort(
                string(for: Keys.thinkReasoningEffort, defaultValue: defaultThinkReasoningEffort),
                fallback: defaultThinkReasoningEffort
            )
        }
        set { store.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.thinkReasoningEffort) }
    }

    static var deepResearchReasoningEffort: String {
        get {
            normalizedReasoningEffort(
                string(for: Keys.deepResearchReasoningEffort, defaultValue: defaultDeepResearchReasoningEffort),
                fallback: defaultDeepResearchReasoningEffort
            )
        }
        set {
            store.set(
                newValue.trimmingCharacters(in: .whitespacesAndNewlines),
                forKey: Keys.deepResearchReasoningEffort
            )
        }
    }

    static var responseMode: String {
        get { normalizedMode(string(for: Keys.responseMode, defaultValue: defaultResponseMode)) }
        set { store.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.responseMode) }
    }

    static var knowledgeTimeout: Double {
        get { double(for: Keys.knowledgeTimeout, defaultValue: defaultKnowledgeTimeout) }
        set { store.set(max(3, newValue), forKey: Keys.knowledgeTimeout) }
    }

    static var codeTimeout: Double {
        get { double(for: Keys.codeTimeout, defaultValue: defaultCodeTimeout) }
        set { store.set(max(3, newValue), forKey: Keys.codeTimeout) }
    }

    static var writingTimeout: Double {
        get { double(for: Keys.writingTimeout, defaultValue: defaultWritingTimeout) }
        set { store.set(max(3, newValue), forKey: Keys.writingTimeout) }
    }

    static var disableMCPServers: Bool {
        get { bool(for: Keys.disableMCPServers, defaultValue: defaultDisableMCPServers) }
        set { store.set(newValue, forKey: Keys.disableMCPServers) }
    }

    static var richAIFormatting: Bool {
        get { bool(for: Keys.richAIFormatting, defaultValue: defaultRichAIFormatting) }
        set { store.set(newValue, forKey: Keys.richAIFormatting) }
    }

    static var autoMemoryEnabled: Bool {
        get { bool(for: Keys.autoMemoryEnabled, defaultValue: defaultAutoMemoryEnabled) }
        set { store.set(newValue, forKey: Keys.autoMemoryEnabled) }
    }

    static var enableWebSearch: Bool {
        get { bool(for: Keys.enableWebSearch, defaultValue: defaultEnableWebSearch) }
        set { store.set(newValue, forKey: Keys.enableWebSearch) }
    }

    static var aiVisualStyle: String {
        get {
            let style = string(for: Keys.aiVisualStyle, defaultValue: defaultAIVisualStyle).lowercased()
            return aiVisualStyleOptions.contains(style) ? style : defaultAIVisualStyle
        }
        set { store.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), forKey: Keys.aiVisualStyle) }
    }

    static var voiceEnabled: Bool {
        get { bool(for: Keys.voiceEnabled, defaultValue: defaultVoiceEnabled) }
        set { store.set(newValue, forKey: Keys.voiceEnabled) }
    }

    static var voiceAutoExecute: Bool {
        get { bool(for: Keys.voiceAutoExecute, defaultValue: defaultVoiceAutoExecute) }
        set { store.set(newValue, forKey: Keys.voiceAutoExecute) }
    }

    static var voiceSpeakResponse: Bool {
        get { bool(for: Keys.voiceSpeakResponse, defaultValue: defaultVoiceSpeakResponse) }
        set { store.set(newValue, forKey: Keys.voiceSpeakResponse) }
    }

    static var voiceWakeWord: String {
        get {
            let text = string(for: Keys.voiceWakeWord, defaultValue: defaultVoiceWakeWord)
            return text.isEmpty ? defaultVoiceWakeWord : text
        }
        set { store.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.voiceWakeWord) }
    }

    static var voiceLocale: String {
        get {
            let value = string(for: Keys.voiceLocale, defaultValue: defaultVoiceLocale)
            return voiceLocaleOptions.contains(value) ? value : defaultVoiceLocale
        }
        set { store.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.voiceLocale) }
    }

    static var rayEnabled: Bool {
        get { bool(for: Keys.rayEnabled, defaultValue: defaultRayEnabled) }
        set { store.set(newValue, forKey: Keys.rayEnabled) }
    }

    static var rayWakeWords: String {
        get { string(for: Keys.rayWakeWords, defaultValue: defaultRayWakeWords) }
        set { store.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.rayWakeWords) }
    }

    static var rayAutoSpeak: Bool {
        get { bool(for: Keys.rayAutoSpeak, defaultValue: defaultRayAutoSpeak) }
        set { store.set(newValue, forKey: Keys.rayAutoSpeak) }
    }

    static var rayPosition: String {
        get {
            let value = string(for: Keys.rayPosition, defaultValue: defaultRayPosition).lowercased()
            let valid = ["bottom_right", "bottom_left", "top_right", "top_left"]
            return valid.contains(value) ? value : defaultRayPosition
        }
        set { store.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), forKey: Keys.rayPosition) }
    }

    static var panelWidth: Double {
        get { double(for: Keys.panelWidth, defaultValue: defaultPanelWidth) }
        set { store.set(min(1600, max(680, newValue)), forKey: Keys.panelWidth) }
    }

    static var hotkeyPreset: String {
        get { normalizedHotkeyPreset(string(for: Keys.hotkeyPreset, defaultValue: defaultHotkeyPreset)) }
        set { store.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.hotkeyPreset) }
    }

    static func selectedModel(for mode: String) -> String {
        switch normalizedMode(mode) {
        case "think": return thinkModel
        case "deep_research": return deepResearchModel
        default: return fastModel
        }
    }

    static func setSelectedModel(_ model: String, for mode: String) {
        switch normalizedMode(mode) {
        case "think": thinkModel = model
        case "deep_research": deepResearchModel = model
        default: fastModel = model
        }
    }

    static func reasoningEffort(for mode: String) -> String {
        switch normalizedMode(mode) {
        case "think": return thinkReasoningEffort
        case "deep_research": return deepResearchReasoningEffort
        default: return fastReasoningEffort
        }
    }

    static func setReasoningEffort(_ effort: String, for mode: String) {
        switch normalizedMode(mode) {
        case "think": thinkReasoningEffort = effort
        case "deep_research": deepResearchReasoningEffort = effort
        default: fastReasoningEffort = effort
        }
    }

    static func modelOptions(for mode: String) -> [String] {
        switch normalizedMode(mode) {
        case "think": return thinkModelOptions
        case "deep_research": return deepResearchModelOptions
        default: return fastModelOptions
        }
    }

    static func resetToDefaults() {
        fastModel = defaultFastModel
        thinkModel = defaultThinkModel
        deepResearchModel = defaultDeepResearchModel
        fastReasoningEffort = defaultFastReasoningEffort
        thinkReasoningEffort = defaultThinkReasoningEffort
        deepResearchReasoningEffort = defaultDeepResearchReasoningEffort
        responseMode = defaultResponseMode
        knowledgeTimeout = defaultKnowledgeTimeout
        codeTimeout = defaultCodeTimeout
        writingTimeout = defaultWritingTimeout
        disableMCPServers = defaultDisableMCPServers
        richAIFormatting = defaultRichAIFormatting
        autoMemoryEnabled = defaultAutoMemoryEnabled
        enableWebSearch = defaultEnableWebSearch
        aiVisualStyle = defaultAIVisualStyle
        voiceEnabled = defaultVoiceEnabled
        voiceAutoExecute = defaultVoiceAutoExecute
        voiceSpeakResponse = defaultVoiceSpeakResponse
        voiceWakeWord = defaultVoiceWakeWord
        voiceLocale = defaultVoiceLocale
        rayEnabled = defaultRayEnabled
        rayWakeWords = defaultRayWakeWords
        rayAutoSpeak = defaultRayAutoSpeak
        rayPosition = defaultRayPosition
        panelWidth = defaultPanelWidth
        hotkeyPreset = defaultHotkeyPreset
    }

    static func normalizedMode(_ value: String) -> String {
        let mode = value.lowercased()
        if mode == "think" || mode == "deep_research" { return mode }
        return "fast"
    }

    private static func normalizedModel(_ model: String, mode: String) -> String {
        let options = modelOptions(for: mode)
        return options.contains(model) ? model : (options.first ?? model)
    }

    private static func normalizedReasoningEffort(_ value: String, fallback: String) -> String {
        let lower = value.lowercased()
        return reasoningEffortOptions.contains(lower) ? lower : fallback
    }

    private static func normalizedHotkeyPreset(_ value: String) -> String {
        let normalized = value.lowercased()
        if hotkeyPresetOptions.contains(where: { $0.id == normalized }) {
            return normalized
        }
        return defaultHotkeyPreset
    }

    private static func string(for key: String, defaultValue: String) -> String {
        let raw = store.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? defaultValue : raw
    }

    private static func double(for key: String, defaultValue: Double) -> Double {
        if store.object(forKey: key) == nil { return defaultValue }
        let value = store.double(forKey: key)
        return value > 0 ? value : defaultValue
    }

    private static func bool(for key: String, defaultValue: Bool) -> Bool {
        if store.object(forKey: key) == nil { return defaultValue }
        return store.bool(forKey: key)
    }
}
