import SwiftUI

struct SynapseSettingsView: View {
    let embedded: Bool
    let onClose: (() -> Void)?

    @AppStorage(SynapseSettings.Keys.fastModel) private var fastModel = SynapseSettings.defaultFastModel
    @AppStorage(SynapseSettings.Keys.thinkModel) private var thinkModel = SynapseSettings.defaultThinkModel
    @AppStorage(SynapseSettings.Keys.deepResearchModel) private var deepResearchModel = SynapseSettings.defaultDeepResearchModel

    @AppStorage(SynapseSettings.Keys.fastReasoningEffort)
    private var fastReasoningEffort = SynapseSettings.defaultFastReasoningEffort
    @AppStorage(SynapseSettings.Keys.thinkReasoningEffort)
    private var thinkReasoningEffort = SynapseSettings.defaultThinkReasoningEffort
    @AppStorage(SynapseSettings.Keys.deepResearchReasoningEffort)
    private var deepResearchReasoningEffort = SynapseSettings.defaultDeepResearchReasoningEffort

    @AppStorage(SynapseSettings.Keys.responseMode) private var responseMode = SynapseSettings.defaultResponseMode
    @AppStorage(SynapseSettings.Keys.knowledgeTimeout) private var knowledgeTimeout = SynapseSettings.defaultKnowledgeTimeout
    @AppStorage(SynapseSettings.Keys.codeTimeout) private var codeTimeout = SynapseSettings.defaultCodeTimeout
    @AppStorage(SynapseSettings.Keys.writingTimeout) private var writingTimeout = SynapseSettings.defaultWritingTimeout
    @AppStorage(SynapseSettings.Keys.disableMCPServers) private var disableMCPServers = SynapseSettings.defaultDisableMCPServers
    @AppStorage(SynapseSettings.Keys.richAIFormatting) private var richAIFormatting = SynapseSettings.defaultRichAIFormatting
    @AppStorage(SynapseSettings.Keys.autoMemoryEnabled) private var autoMemoryEnabled = SynapseSettings.defaultAutoMemoryEnabled
    @AppStorage(SynapseSettings.Keys.enableWebSearch) private var enableWebSearch = SynapseSettings.defaultEnableWebSearch
    @AppStorage(SynapseSettings.Keys.aiVisualStyle) private var aiVisualStyle = SynapseSettings.defaultAIVisualStyle
    @AppStorage(SynapseSettings.Keys.voiceEnabled) private var voiceEnabled = SynapseSettings.defaultVoiceEnabled
    @AppStorage(SynapseSettings.Keys.voiceAutoExecute) private var voiceAutoExecute = SynapseSettings.defaultVoiceAutoExecute
    @AppStorage(SynapseSettings.Keys.voiceSpeakResponse) private var voiceSpeakResponse = SynapseSettings.defaultVoiceSpeakResponse
    @AppStorage(SynapseSettings.Keys.voiceWakeWord) private var voiceWakeWord = SynapseSettings.defaultVoiceWakeWord
    @AppStorage(SynapseSettings.Keys.voiceLocale) private var voiceLocale = SynapseSettings.defaultVoiceLocale
    @AppStorage(SynapseSettings.Keys.hotkeyPreset) private var hotkeyPreset = SynapseSettings.defaultHotkeyPreset

    init(embedded: Bool = false, onClose: (() -> Void)? = nil) {
        self.embedded = embedded
        self.onClose = onClose
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("运行配置")
                        .font(.system(size: embedded ? 14 : 18, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    if embedded {
                        Button("关闭") { onClose?() }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("响应模式")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: $responseMode) {
                                Text("Fast").tag("fast")
                                Text("Think").tag("think")
                                Text("Deep Research").tag("deep_research")
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 360)
                        }

                        modelPickerRow("模型（\(modeTitle)）", selection: currentModelBinding, options: modelOptionsForCurrentMode)

                        HStack {
                            Text("推理强度（\(modeTitle)）")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: currentReasoningEffortBinding) {
                                ForEach(SynapseSettings.reasoningEffortOptions, id: \.self) { level in
                                    Text(level).tag(level)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 300)
                        }

                        if normalizedMode == "deep_research" {
                            Text("Deep Research 强制启用 Web Search；Fast/Think 可通过“行为开关”控制联网搜索。")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                } label: {
                    Text("Codex 模型")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12, weight: .semibold))
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("唤醒快捷键")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: $hotkeyPreset) {
                                ForEach(SynapseSettings.hotkeyPresetOptions, id: \.id) { item in
                                    Text(item.title).tag(item.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 260)
                        }

                        Text("修改后立即生效")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 6)
                } label: {
                    Text("快捷键")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12, weight: .semibold))
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        timeoutRow("知识查询", value: $knowledgeTimeout)
                        timeoutRow("代码生成", value: $codeTimeout)
                        timeoutRow("写作生成", value: $writingTimeout)
                    }
                    .padding(.vertical, 6)
                } label: {
                    Text("超时阈值")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12, weight: .semibold))
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("自动管理 Memory（推荐）", isOn: $autoMemoryEnabled)
                        Toggle("启用联网搜索（优先使用 Web Search）", isOn: $enableWebSearch)
                        Toggle("禁用 MCP 启动（推荐）", isOn: $disableMCPServers)
                        Toggle("AI 输出富文本格式化", isOn: $richAIFormatting)

                        HStack {
                            Text("AI 视觉风格")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: $aiVisualStyle) {
                                Text("Matrix").tag("matrix")
                                Text("Native").tag("native")
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 220)
                        }
                    }
                    .toggleStyle(.switch)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.vertical, 6)
                } label: {
                    Text("行为开关")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12, weight: .semibold))
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("启用语音输入（实时 ASR）", isOn: $voiceEnabled)
                        Toggle("识别后自动执行", isOn: $voiceAutoExecute)
                        Toggle("语音播报执行结果", isOn: $voiceSpeakResponse)

                        HStack {
                            Text("唤醒词")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            TextField("synapse", text: $voiceWakeWord)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200)
                        }

                        HStack {
                            Text("识别语言")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: $voiceLocale) {
                                ForEach(SynapseSettings.voiceLocaleOptions, id: \.self) { locale in
                                    Text(locale).tag(locale)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 200)
                        }
                    }
                    .toggleStyle(.switch)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.vertical, 6)
                } label: {
                    Text("语音链路")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12, weight: .semibold))
                }

                HStack {
                    Button("恢复默认") { SynapseSettings.resetToDefaults() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.orange)

                    Spacer()

                    Text("修改后立即生效")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(embedded ? 14 : 20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { normalizeSelection() }
        .onChange(of: responseMode) { _, _ in normalizeSelection() }
        .onChange(of: fastModel) { _, _ in normalizeSelection() }
        .onChange(of: thinkModel) { _, _ in normalizeSelection() }
        .onChange(of: deepResearchModel) { _, _ in normalizeSelection() }
        .onChange(of: fastReasoningEffort) { _, _ in normalizeSelection() }
        .onChange(of: thinkReasoningEffort) { _, _ in normalizeSelection() }
        .onChange(of: deepResearchReasoningEffort) { _, _ in normalizeSelection() }
        .onChange(of: hotkeyPreset) { _, _ in normalizeSelection() }
        .onChange(of: voiceWakeWord) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            voiceWakeWord = trimmed.isEmpty ? SynapseSettings.defaultVoiceWakeWord : trimmed
        }
    }

    private var normalizedMode: String {
        SynapseSettings.normalizedMode(responseMode)
    }

    private var modeTitle: String {
        switch normalizedMode {
        case "think": return "Think"
        case "deep_research": return "Deep Research"
        default: return "Fast"
        }
    }

    private var modelOptionsForCurrentMode: [String] {
        SynapseSettings.modelOptions(for: normalizedMode)
    }

    private var currentModelBinding: Binding<String> {
        switch normalizedMode {
        case "think":
            return $thinkModel
        case "deep_research":
            return $deepResearchModel
        default:
            return $fastModel
        }
    }

    private var currentReasoningEffortBinding: Binding<String> {
        switch normalizedMode {
        case "think":
            return $thinkReasoningEffort
        case "deep_research":
            return $deepResearchReasoningEffort
        default:
            return $fastReasoningEffort
        }
    }

    private func timeoutRow(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
            Stepper(value: value, in: 3...60, step: 1) {
                Text("\(Int(value.wrappedValue))s")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(TerminalTheme.textPrimary)
            }
            .frame(width: 120)
        }
    }

    private func modelPickerRow(_ title: String, selection: Binding<String>, options: [String]) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 240)
        }
    }

    private func normalizeSelection() {
        responseMode = normalizedMode

        if !SynapseSettings.fastModelOptions.contains(fastModel) {
            fastModel = SynapseSettings.defaultFastModel
        }
        if !SynapseSettings.thinkModelOptions.contains(thinkModel) {
            thinkModel = SynapseSettings.defaultThinkModel
        }
        if !SynapseSettings.deepResearchModelOptions.contains(deepResearchModel) {
            deepResearchModel = SynapseSettings.defaultDeepResearchModel
        }

        if !SynapseSettings.reasoningEffortOptions.contains(fastReasoningEffort.lowercased()) {
            fastReasoningEffort = SynapseSettings.defaultFastReasoningEffort
        } else {
            fastReasoningEffort = fastReasoningEffort.lowercased()
        }
        if !SynapseSettings.reasoningEffortOptions.contains(thinkReasoningEffort.lowercased()) {
            thinkReasoningEffort = SynapseSettings.defaultThinkReasoningEffort
        } else {
            thinkReasoningEffort = thinkReasoningEffort.lowercased()
        }
        if !SynapseSettings.reasoningEffortOptions.contains(deepResearchReasoningEffort.lowercased()) {
            deepResearchReasoningEffort = SynapseSettings.defaultDeepResearchReasoningEffort
        } else {
            deepResearchReasoningEffort = deepResearchReasoningEffort.lowercased()
        }

        if !SynapseSettings.hotkeyPresetOptions.contains(where: { $0.id == hotkeyPreset }) {
            hotkeyPreset = SynapseSettings.defaultHotkeyPreset
        }

        if !SynapseSettings.aiVisualStyleOptions.contains(aiVisualStyle.lowercased()) {
            aiVisualStyle = SynapseSettings.defaultAIVisualStyle
        } else {
            aiVisualStyle = aiVisualStyle.lowercased()
        }

        if !SynapseSettings.voiceLocaleOptions.contains(voiceLocale) {
            voiceLocale = SynapseSettings.defaultVoiceLocale
        }
        let trimmedWakeWord = voiceWakeWord.trimmingCharacters(in: .whitespacesAndNewlines)
        voiceWakeWord = trimmedWakeWord.isEmpty ? SynapseSettings.defaultVoiceWakeWord : trimmedWakeWord
    }
}
