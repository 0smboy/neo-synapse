import SwiftUI
import AppKit

enum TerminalTheme {
    static let line = Color.primary.opacity(0.14)
    static let accent = Color.accentColor
    static let accentSoft = Color.accentColor.opacity(0.82)
    static let warning = Color.orange
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let chipBG = Color.primary.opacity(0.06)
    static let cardFill = Color.primary.opacity(0.05)
}

struct TerminalBackgroundView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .windowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 16
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Matrix Theme System

enum MatrixTheme {
    // Core colors
    static let primaryGreen = Color(red: 0.0, green: 1.0, blue: 0.4)
    static let brightGreen = Color(red: 0.2, green: 1.0, blue: 0.6)
    static let dimGreen = Color(red: 0.0, green: 0.6, blue: 0.2)
    static let darkGreen = Color(red: 0.0, green: 0.3, blue: 0.1)
    static let black = Color(red: 0.0, green: 0.0, blue: 0.0)
    static let nearBlack = Color(red: 0.05, green: 0.05, blue: 0.05)
    
    // Text colors
    static let textPrimary = primaryGreen.opacity(0.95)
    static let textSecondary = dimGreen.opacity(0.75)
    static let textDim = darkGreen.opacity(0.5)
    
    // Glow effects
    static let glowStrong = primaryGreen.opacity(0.6)
    static let glowMedium = primaryGreen.opacity(0.3)
    static let glowSoft = primaryGreen.opacity(0.15)
    static let glowSubtle = primaryGreen.opacity(0.08)
    
    // Scanline colors
    static let scanlineBright = primaryGreen.opacity(0.12)
    static let scanlineDim = primaryGreen.opacity(0.04)
    static let scanlineSubtle = primaryGreen.opacity(0.02)
    
    // Background gradients
    static let cardGradient = LinearGradient(
        colors: [
            Color(red: 0.03, green: 0.08, blue: 0.04),
            Color(red: 0.02, green: 0.06, blue: 0.03),
            Color(red: 0.01, green: 0.04, blue: 0.02),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.02, green: 0.04, blue: 0.02),
            Color(red: 0.01, green: 0.02, blue: 0.01),
            Color(red: 0.0, green: 0.01, blue: 0.0),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Matrix Rain Animation

struct MatrixRainBackground: View {
    @State private var animationTime: Double = 0
    @State private var columns: [MatrixColumn] = []
    
    private let columnCount: Int
    private let characterSet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZアイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン"
    
    init(columnCount: Int = 25) {
        self.columnCount = columnCount
    }
    
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                for column in columns {
                    drawColumn(column, in: context, size: size)
                }
            }
            .onAppear {
                setupColumns(width: geometry.size.width, height: geometry.size.height)
                startAnimation()
            }
            .onChange(of: geometry.size) { newSize in
                setupColumns(width: newSize.width, height: newSize.height)
            }
        }
        .allowsHitTesting(false)
    }
    
    private func setupColumns(width: CGFloat, height: CGFloat) {
        let columnWidth = width / CGFloat(columnCount)
        columns = (0..<columnCount).map { index in
            MatrixColumn(
                x: CGFloat(index) * columnWidth,
                width: columnWidth,
                height: height,
                speed: Double.random(in: 0.4...0.9),
                delay: Double.random(in: 0...3.0),
                characterCount: Int(height / 16) + 20
            )
        }
    }
    
    private func drawColumn(_ column: MatrixColumn, in context: GraphicsContext, size: CGSize) {
        let charHeight: CGFloat = 16
        let totalCharHeight = CGFloat(column.characterCount) * charHeight
        
        // Calculate vertical offset for this column
        let offset = (animationTime * column.speed * 30 + column.delay * 30)
            .truncatingRemainder(dividingBy: totalCharHeight + size.height)
        
        var y = -offset
        var charIndex = 0
        
        while y < size.height + 50 && charIndex < column.characterCount {
            let char = characterSet.randomElement() ?? "0"
            let normalizedY = max(0, min(1, (y + offset) / size.height))
            let opacity = calculateOpacity(normalizedY: normalizedY)
            let color = MatrixTheme.primaryGreen.opacity(opacity)
            
            // Use resolved text for Canvas
            let text = Text(String(char))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(color)
            
            let resolved = context.resolve(text)
            context.draw(resolved, at: CGPoint(x: column.x + column.width / 2, y: y))
            
            y += charHeight
            charIndex += 1
        }
    }
    
    private func calculateOpacity(normalizedY: Double) -> Double {
        if normalizedY < 0.15 {
            return Double(normalizedY / 0.15) * 0.35 + 0.1
        } else if normalizedY < 0.35 {
            return 0.45
        } else if normalizedY < 0.75 {
            return 0.25
        } else {
            return max(0.06, 0.25 * (1.0 - (normalizedY - 0.75) / 0.25))
        }
    }
    
    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            animationTime += 0.05
        }
    }
}

private struct MatrixColumn: Identifiable {
    let id = UUID()
    let x: CGFloat
    let width: CGFloat
    let height: CGFloat
    let speed: Double
    let delay: Double
    let characterCount: Int
}

// MARK: - Matrix Glow Text Modifier

struct MatrixGlowText: ViewModifier {
    let glowIntensity: Double
    let glowRadius: CGFloat
    
    init(intensity: Double = 0.4, radius: CGFloat = 8) {
        self.glowIntensity = intensity
        self.glowRadius = radius
    }
    
    func body(content: Content) -> some View {
        content
            .shadow(color: MatrixTheme.glowStrong.opacity(glowIntensity), radius: glowRadius)
            .shadow(color: MatrixTheme.glowMedium.opacity(glowIntensity * 0.6), radius: glowRadius * 1.5)
            .shadow(color: MatrixTheme.glowSoft.opacity(glowIntensity * 0.3), radius: glowRadius * 2.5)
    }
}

extension View {
    func matrixGlow(intensity: Double = 0.4, radius: CGFloat = 8) -> some View {
        modifier(MatrixGlowText(intensity: intensity, radius: radius))
    }
}

// MARK: - Matrix Typing Effect

struct MatrixTypingEffect: View {
    let text: String
    let speed: TimeInterval
    @State private var displayedText: String = ""
    @State private var currentIndex: Int = 0
    
    init(text: String, speed: TimeInterval = 0.03) {
        self.text = text
        self.speed = speed
    }
    
    var body: some View {
        Text(displayedText)
            .font(.system(size: 14, design: .monospaced))
            .foregroundColor(MatrixTheme.textPrimary)
            .onAppear {
                startTyping()
            }
            .onChange(of: text) { _, newText in
                displayedText = ""
                currentIndex = 0
                startTyping()
            }
    }
    
    private func startTyping() {
        guard currentIndex < text.count else { return }
        
        let char = text[text.index(text.startIndex, offsetBy: currentIndex)]
        displayedText.append(char)
        currentIndex += 1
        
        DispatchQueue.main.asyncAfter(deadline: .now() + speed) {
            startTyping()
        }
    }
}

// MARK: - Animated Matrix Scanline Overlay

struct AnimatedMatrixScanlineOverlay: View {
    @State private var offset: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                var path = Path()
                var y: CGFloat = offset.truncatingRemainder(dividingBy: 8)
                
                while y < size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += 4
                }
                
                context.stroke(path, with: .color(MatrixTheme.scanlineBright), lineWidth: 0.6)
                
                // Add secondary scanlines
                var path2 = Path()
                var y2: CGFloat = (offset + 2).truncatingRemainder(dividingBy: 8)
                while y2 < size.height {
                    path2.move(to: CGPoint(x: 0, y: y2))
                    path2.addLine(to: CGPoint(x: size.width, y: y2))
                    y2 += 4
                }
                context.stroke(path2, with: .color(MatrixTheme.scanlineDim), lineWidth: 0.4)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onAppear {
                withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                    offset = 8
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Matrix Glow Pulse Border

struct MatrixGlowPulseBorder: ViewModifier {
    @State private var pulsePhase: Double = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                MatrixTheme.primaryGreen.opacity(0.3 + sin(pulsePhase) * 0.2),
                                MatrixTheme.brightGreen.opacity(0.2 + sin(pulsePhase + .pi / 2) * 0.15),
                                MatrixTheme.primaryGreen.opacity(0.3 + sin(pulsePhase) * 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
                    .shadow(color: MatrixTheme.glowMedium.opacity(0.4 + sin(pulsePhase) * 0.2), radius: 4)
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                    pulsePhase = .pi * 2
                }
            }
    }
}

extension View {
    func matrixGlowPulseBorder() -> some View {
        modifier(MatrixGlowPulseBorder())
    }
}
