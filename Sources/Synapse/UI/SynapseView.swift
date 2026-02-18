// MARK: - UI/SynapseView.swift
// 主视图

import SwiftUI
import Combine

/// 高度通知
final class HeightNotifier: ObservableObject {
    let heightSubject = PassthroughSubject<CGFloat, Never>()
    let widthSubject = PassthroughSubject<CGFloat, Never>()
    var publisher: AnyPublisher<CGFloat, Never> {
        heightSubject.eraseToAnyPublisher()
    }
    var widthPublisher: AnyPublisher<CGFloat, Never> {
        widthSubject.eraseToAnyPublisher()
    }
}

struct SynapseView: View {
    @StateObject private var viewModel = SynapseViewModel()
    @State private var lastPublishedHeight: CGFloat = 64
    let heightNotifier: HeightNotifier
    
    private let inputBarHeight: CGFloat = 64
    private let maxAutoHeight: CGFloat = 640
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                TerminalBackgroundView()
                
                VStack(spacing: 0) {
                    // 搜索栏
                    SearchBarView(
                        query: $viewModel.query,
                        isProcessing: $viewModel.isProcessing,
                        statusColor: viewModel.statusColor,
                        voiceListening: viewModel.voiceListening,
                        voiceStatusText: viewModel.voiceStatusText,
                        onSubmit: { viewModel.executeCurrentIntent() },
                        onEscape: { viewModel.quitApplication() },
                        onMoveUp: { viewModel.moveSelectionUp() },
                        onMoveDown: { viewModel.moveSelectionDown() },
                        onToggleVoice: { viewModel.toggleVoice() }
                    )
                    .frame(height: 58)
                    
                    // /help 菜单
                    if viewModel.showHelp {
                        Divider()
                        ScrollView(.vertical, showsIndicators: false) {
                            HelpMenuView(
                                filter: viewModel.slashFilter,
                                selectedIndex: viewModel.selectedHelpIndex,
                                onSelect: { cmd in
                                    viewModel.query = cmd.insertionText
                            })
                        }
                        .frame(maxHeight: min(helpSectionHeight, 420))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    if viewModel.showConfig {
                        Divider()
                        SynapseSettingsView(embedded: true, onClose: { viewModel.query = "" })
                        .frame(maxHeight: 420)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    // 结果区
                    if viewModel.showResults && !viewModel.showConfig {
                        Divider()
                        
                        ScrollView(.vertical, showsIndicators: false) {
                            ResultListView(
                                intent: viewModel.currentIntent,
                                executionResult: viewModel.executionResult,
                                isExecuting: viewModel.isExecuting,
                                matchedApps: viewModel.matchedApps,
                                selectedAppIndex: viewModel.selectedAppIndex,
                                inlineText: viewModel.inlineText,
                                onSelect: { app in viewModel.launchApp(app) }
                            )
                        }
                        .frame(maxHeight: min(resultSectionHeight, 400))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(TerminalTheme.line, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 14, x: 0, y: 8)
        }
        .frame(maxWidth: .infinity)
        .background(
            Color.clear
                .onChange(of: desiredPanelHeight) { _, newHeight in
                    let clamped = min(maxAutoHeight, max(inputBarHeight, ceil(newHeight)))
                    guard abs(clamped - lastPublishedHeight) > 0.5 else { return }
                    lastPublishedHeight = clamped
                    heightNotifier.heightSubject.send(clamped)
                }
                .onChange(of: preferredPanelWidth) { _, newWidth in
                    heightNotifier.widthSubject.send(newWidth)
                }
                .onAppear {
                    lastPublishedHeight = desiredPanelHeight
                    heightNotifier.heightSubject.send(desiredPanelHeight)
                    heightNotifier.widthSubject.send(preferredPanelWidth)
                }
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: viewModel.showResults)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: viewModel.showHelp)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: viewModel.showConfig)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: viewModel.inlineText.isEmpty)
    }
    
    private var preferredPanelWidth: CGFloat {
        if viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return 560
        }
        
        var base: CGFloat = 640
        
        if viewModel.showHelp { base = 820 }
        if viewModel.showConfig { base = 860 }
        
        if viewModel.showResults && !viewModel.showConfig {
            if viewModel.currentIntent?.action == .findFile {
                base = 960
            } else if viewModel.currentIntent?.domain == .aiCapability {
                base = 900
            } else {
                base = 780
            }
        }
        
        let queryBoost = min(CGFloat(max(0, viewModel.query.count - 18)) * 2.8, 140)
        return min(1180, max(520, base + queryBoost))
    }
    
    private var desiredPanelHeight: CGFloat {
        var height = inputBarHeight
        
        if viewModel.showHelp {
            height += 1 + helpSectionHeight
        }
        
        if viewModel.showConfig {
            height += 1 + 420
        } else if viewModel.showResults {
            height += 1 + resultSectionHeight
        }
        
        return min(maxAutoHeight, max(inputBarHeight, height))
    }
    
    private var helpSectionHeight: CGFloat {
        if viewModel.query == "/" { return 420 }
        let filterLength = viewModel.slashFilter.count
        if filterLength <= 1 { return 380 }
        if filterLength <= 3 { return 320 }
        return 250
    }
    
    private var resultSectionHeight: CGFloat {
        if viewModel.isExecuting { return 88 }
        
        if let fileResults = viewModel.executionResult?.fileResults, !fileResults.isEmpty {
            return 360
        }
        
        if !viewModel.matchedApps.isEmpty {
            let count = CGFloat(min(5, max(1, viewModel.matchedApps.count)))
            return 26 + count * 44
        }
        
        if !viewModel.inlineText.isEmpty {
            let lineCount = viewModel.inlineText.components(separatedBy: .newlines).count
            return min(360, max(110, CGFloat(lineCount) * 22 + 34))
        }
        
        if viewModel.executionResult != nil { return 132 }
        if viewModel.currentIntent != nil { return 92 }
        return 92
    }
}
