//
//  AIResponseRenderer.swift
//  Synapse
//
//  Renders AI response text (markdown) with clean native macOS styling.
//

import SwiftUI
import AppKit

// MARK: - Block Types

enum AIResponseBlock: Equatable {
    case heading(level: Int, text: String)
    case codeBlock(language: String, code: String)
    case bullet(text: String)
    case numbered(index: String, text: String)
    case blockquote(text: String)
    case divider
    case paragraph(text: String)
}

// MARK: - Parser

struct AIResponseParser {
    static func parse(_ text: String) -> [AIResponseBlock] {
        var blocks: [AIResponseBlock] = []
        var lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Empty line - skip (don't add as paragraph)
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1
                continue
            }

            // Code block start
            if line.hasPrefix("```") {
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    if lines[i].hasPrefix("```") {
                        i += 1
                        break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(language: language, code: codeLines.joined(separator: "\n")))
                continue
            }

            // Divider
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "___" {
                blocks.append(.divider)
                i += 1
                continue
            }

            // Heading
            if let headingMatch = parseHeading(line) {
                blocks.append(.heading(level: headingMatch.level, text: headingMatch.text))
                i += 1
                continue
            }

            // Blockquote
            if line.hasPrefix(">") {
                let quoteText = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                blocks.append(.blockquote(text: quoteText))
                i += 1
                continue
            }

            // Bullet
            if let bulletMatch = parseBullet(line) {
                blocks.append(.bullet(text: bulletMatch))
                i += 1
                continue
            }

            // Numbered
            if let numberedMatch = parseNumbered(line) {
                blocks.append(.numbered(index: numberedMatch.index, text: numberedMatch.text))
                i += 1
                continue
            }

            // Paragraph (everything else)
            blocks.append(.paragraph(text: line))
            i += 1
        }

        return blocks
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        var level = 0
        for c in trimmed {
            if c == "#" { level += 1 }
            else { break }
        }
        guard level >= 1, level <= 6 else { return nil }
        let text = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
        return (level, text)
    }

    private static func parseBullet(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("- ") {
            return String(trimmed.dropFirst(2))
        }
        if trimmed.hasPrefix("* ") {
            return String(trimmed.dropFirst(2))
        }
        if trimmed.hasPrefix("• ") {
            return String(trimmed.dropFirst(2))
        }
        return nil
    }

    private static func parseNumbered(_ line: String) -> (index: String, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let pattern = #"^(\d+)\.\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let indexRange = Range(match.range(at: 1), in: trimmed),
              let textRange = Range(match.range(at: 2), in: trimmed) else {
            return nil
        }
        return (String(trimmed[indexRange]), String(trimmed[textRange]))
    }
}

// MARK: - Inline Markdown Helper

struct InlineMarkdownText: View {
    let text: String

    var body: some View {
        Text(attributedContent)
    }

    private var attributedContent: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

// MARK: - AIResponseRenderer

struct AIResponseRenderer: View {
    let text: String

    private var blocks: [AIResponseBlock] {
        AIResponseParser.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(for: block)
            }
        }
    }

    @ViewBuilder
    private func blockView(for block: AIResponseBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            headingView(level: level, text: text)
        case .codeBlock(let language, let code):
            codeBlockView(language: language, code: code)
        case .bullet(let text):
            bulletView(text: text)
        case .numbered(let index, let text):
            numberedView(index: index, text: text)
        case .blockquote(let text):
            blockquoteView(text: text)
        case .divider:
            dividerView()
        case .paragraph(let text):
            paragraphView(text: text)
        }
    }

    private func headingView(level: Int, text: String) -> some View {
        let (font, padding): (Font, CGFloat) = switch level {
        case 1: (.system(size: 18, weight: .semibold), 12)
        case 2: (.system(size: 16, weight: .semibold), 8)
        default: (.system(size: 14, weight: .medium), 6)
        }
        let color: Color = level <= 2 ? .primary : .secondary
        return InlineMarkdownText(text: text)
            .font(font)
            .foregroundStyle(color)
            .padding(.bottom, padding)
    }

    private func paragraphView(text: String) -> some View {
        InlineMarkdownText(text: text)
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(.primary)
            .lineSpacing(1.4 * 14 - 14) // 1.4 line spacing
            .textSelection(.enabled)
    }

    private func codeBlockView(language: String, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private func bulletView(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color.secondary)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            InlineMarkdownText(text: text)
                .font(.system(size: 13.5, weight: .regular))
                .foregroundStyle(.primary)
        }
        .padding(.leading, 20)
    }

    private func numberedView(index: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(index)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
            InlineMarkdownText(text: text)
                .font(.system(size: 13.5, weight: .regular))
                .foregroundStyle(.primary)
        }
        .padding(.leading, 20)
    }

    private func blockquoteView(text: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 3)
            InlineMarkdownText(text: text)
                .font(.system(size: 13.5, weight: .regular))
                .italic()
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
        }
    }

    private func dividerView() -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 1)
            .padding(.vertical, 12)
    }
}

