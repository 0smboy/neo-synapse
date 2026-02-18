//
//  RayBubbleView.swift
//  Synapse
//
//  Main visual for the Ray voice pet - a Siri/Apple Intelligence style glowing bubble.
//

import SwiftUI
import AppKit

// MARK: - RippleRing

/// A circle that scales from 1.0 to 2.5 while fading from 0.4 to 0.0, repeating.
struct RippleRing: View {
    let delay: Double
    let color: Color

    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.4

    var body: some View {
        Circle()
            .stroke(color, lineWidth: 2)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(
                    .easeOut(duration: 0.8)
                    .repeatForever(autoreverses: false)
                    .delay(delay)
                ) {
                    scale = 2.5
                    opacity = 0.0
                }
            }
    }
}

// MARK: - GlowOrb

/// The main orb with radial gradient, shadow, and optional "R" text.
struct GlowOrb: View {
    let size: CGFloat
    let showLetter: Bool
    let gradientColors: [Color]
    let glowIntensity: Double

    init(
        size: CGFloat,
        showLetter: Bool = true,
        gradientColors: [Color] = [Color.accentColor, Color.accentColor.opacity(0.6)],
        glowIntensity: Double = 0.8
    ) {
        self.size = size
        self.showLetter = showLetter
        self.gradientColors = gradientColors
        self.glowIntensity = glowIntensity
    }

    var body: some View {
        ZStack {
            // Glow / shadow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            gradientColors[0].opacity(glowIntensity),
                            gradientColors[0].opacity(0.3),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.8
                    )
                )
                .frame(width: size * 1.6, height: size * 1.6)
                .blur(radius: 12)

            // Main orb
            Circle()
                .fill(
                    RadialGradient(
                        colors: gradientColors,
                        center: .center,
                        startRadius: 0,
                        endRadius: size / 2
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: gradientColors[0].opacity(0.5), radius: 8, x: 0, y: 2)

            if showLetter {
                Text("R")
                    .font(.system(size: size * 0.35, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - RayBubbleView

/// Main visual for the Ray voice pet. Observes RayVoiceEngine and renders different states.
struct RayBubbleView: View {
    @ObservedObject var engine: RayVoiceEngine
    var onDismiss: (() -> Void)?

    private let springAnimation = Animation.spring(response: 0.4, dampingFraction: 0.75)

    // Gradient palettes
    private var idleGradient: [Color] {
        [Color.accentColor, Color.accentColor.opacity(0.65)]
    }

    private var listeningGradient: [Color] {
        [
            Color(red: 0.35, green: 0.55, blue: 1.0),
            Color(red: 0.5, green: 0.4, blue: 0.95)
        ]
    }

    private var thinkingGradient: [Color] {
        [
            Color(red: 0.4, green: 0.5, blue: 1.0),
            Color(red: 0.55, green: 0.45, blue: 0.98)
        ]
    }

    var body: some View {
        content
            .animation(springAnimation, value: engine.state)
            .frame(maxWidth: 360)
    }

    @ViewBuilder
    private var content: some View {
        switch engine.state {
        case .idle:
            idleView
        case .listening:
            listeningView
        case .thinking:
            thinkingView
        case .responding(let text):
            respondingView(resultText: text)
        }
    }

    // MARK: - Idle

    private var idleView: some View {
        IdleOrbView()
    }

    // MARK: - Listening

    private var listeningView: some View {
        VStack(spacing: 12) {
            ZStack {
                // Ripple rings (3 rings, staggered by 0.25s)
                RippleRing(delay: 0, color: listeningGradient[0].opacity(0.5))
                RippleRing(delay: 0.25, color: listeningGradient[0].opacity(0.5))
                RippleRing(delay: 0.5, color: listeningGradient[0].opacity(0.5))

                HStack(spacing: 8) {
                    GlowOrb(
                        size: 60,
                        showLetter: true,
                        gradientColors: listeningGradient,
                        glowIntensity: 0.9
                    )

                    Image(systemName: "mic.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(listeningGradient[0])
                }
            }

            if !engine.liveTranscript.isEmpty {
                Text(engine.liveTranscript)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
        }
        .padding()
    }

    // MARK: - Thinking

    private var thinkingView: some View {
        VStack(spacing: 12) {
            ThinkingOrbView()

            Text("Thinking...")
                .font(.system(size: 12, weight: .regular))
                .italic()
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - Responding

    private func respondingView(resultText: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                GlowOrb(
                    size: 40,
                    showLetter: true,
                    gradientColors: idleGradient,
                    glowIntensity: 0.7
                )

                Spacer()

                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView {
                AIResponseRenderer(text: resultText)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
            .frame(maxHeight: 340)
        }
        .frame(maxWidth: 340, maxHeight: 400)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 8)
    }
}

// MARK: - IdleOrbView

private struct IdleOrbView: View {
    @State private var pulseScale: CGFloat = 0.95
    @State private var pulseOpacity: Double = 0.6

    private let baseSize: CGFloat = 50

    var body: some View {
        GlowOrb(
            size: baseSize * pulseScale,
            showLetter: true,
            gradientColors: [Color.accentColor, Color.accentColor.opacity(0.65)],
            glowIntensity: pulseOpacity
        )
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.2)
                .repeatForever(autoreverses: true)
            ) {
                pulseScale = 1.05
                pulseOpacity = 0.9
            }
        }
        .onDisappear {
            pulseScale = 0.95
            pulseOpacity = 0.6
        }
    }
}

// MARK: - ThinkingOrbView

private struct ThinkingOrbView: View {
    @State private var rotation: Double = 0

    private let size: CGFloat = 60
    private let gradientColors: [Color] = [
        Color(red: 0.4, green: 0.5, blue: 1.0),
        Color(red: 0.55, green: 0.45, blue: 0.98)
    ]

    var body: some View {
        ZStack {
            // Rotating gradient
            Circle()
                .fill(
                    AngularGradient(
                        colors: gradientColors + [gradientColors[0]],
                        center: .center
                    )
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(rotation))
                .overlay(
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    gradientColors[0].opacity(0.9),
                                    gradientColors[1].opacity(0.8)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: size / 2
                            )
                        )
                        .frame(width: size - 4, height: size - 4)
                        .overlay(
                            Text("R")
                                .font(.system(size: size * 0.35, weight: .semibold))
                                .foregroundStyle(.white)
                        )
                )

            // Pulsing glow
            Circle()
                .fill(gradientColors[0].opacity(0.3))
                .frame(width: size * 1.4, height: size * 1.4)
                .blur(radius: 10)
        }
        .onAppear {
            withAnimation(
                .linear(duration: 2.0)
                .repeatForever(autoreverses: false)
            ) {
                rotation = 360
            }
        }
    }
}
