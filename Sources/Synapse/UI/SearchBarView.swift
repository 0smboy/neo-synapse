// MARK: - UI/SearchBarView.swift
// 主搜索栏视图

import SwiftUI
import AppKit

struct SearchBarView: View {
    @Binding var query: String
    @Binding var isProcessing: Bool
    let statusColor: Color
    let voiceListening: Bool
    let voiceStatusText: String
    let onSubmit: () -> Void
    let onEscape: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onToggleVoice: () -> Void
    
    @FocusState private var isFocused: Bool
    @State private var keyMonitor: Any?
    
    var body: some View {
        HStack(spacing: 10) {
            // 搜索图标
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.secondary)
            
            // 输入框
            TextField("输入命令或问题", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .regular))
                .foregroundColor(TerminalTheme.textPrimary)
                .focused($isFocused)
                .onSubmit { onSubmit() }
            
            Spacer()

            Button(action: onToggleVoice) {
                Image(systemName: voiceListening ? "mic.fill" : "mic")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(voiceListening ? .red : .secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill((voiceListening ? Color.red : Color.white).opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .help(voiceStatusText.isEmpty ? "语音输入" : voiceStatusText)

            // 状态指示器
            if isProcessing {
                PulsingDot(color: statusColor)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .onAppear {
            isFocused = true
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onReceive(NotificationCenter.default.publisher(for: .synapseFocus)) { _ in
            isFocused = true
        }
        .onMoveCommand { direction in
            switch direction {
            case .up:
                onMoveUp()
            case .down:
                onMoveDown()
            default:
                break
            }
        }
        .onExitCommand { onEscape() }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isFocused else { return event }

            switch event.keyCode {
            case 126: // up
                onMoveUp()
                return nil
            case 125: // down
                onMoveDown()
                return nil
            case 53: // esc
                onEscape()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }
}

// MARK: - 脉冲指示器
struct PulsingDot: View {
    let color: Color
    @State private var animating = false
    
    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 16, height: 16)
                .scaleEffect(animating ? 1.5 : 0.8)
                .opacity(animating ? 0 : 0.6)
            
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                animating = true
            }
        }
    }
}
