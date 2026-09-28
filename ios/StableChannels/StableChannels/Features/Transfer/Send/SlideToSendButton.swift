import SwiftUI
import UIKit

/// Interactive swipe-to-confirm button inspired by high-security wallet patterns.
/// Prevents accidental payment broadcasts while providing tactile feedback.
struct SlideToSendButton: View {
    let title: String
    let isSending: Bool
    let onConfirmed: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var hasTriggered = false

    private let handleSize: CGFloat = 52
    private let trackHeight: CGFloat = 58
    private let cornerRadius: CGFloat = 14

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let maxDrag = max(0, totalWidth - handleSize - 6)

            ZStack(alignment: .leading) {
                // Background Track
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(height: trackHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color(uiColor: .separator).opacity(0.4), lineWidth: 0.5)
                    )

                // Track Progress Fill
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.sendBlue.opacity(0.20))
                    .frame(width: max(0, dragOffset + handleSize + 3), height: trackHeight)

                // Center Label
                HStack {
                    Spacer()
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .opacity(1.0 - Double(dragOffset / max(1, maxDrag)))
                    Spacer()
                }

                // Draggable Handle
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
                        .frame(width: handleSize, height: handleSize)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .padding(.leading, 3)
                .offset(x: dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            guard !hasTriggered else { return }
                            let newOffset = min(max(0, value.translation.width), maxDrag)
                            if abs(newOffset - dragOffset) > 12 {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                            dragOffset = newOffset

                            if dragOffset >= maxDrag * 0.88 {
                                hasTriggered = true
                                dragOffset = maxDrag
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                onConfirmed()
                            }
                        }
                        .onEnded { _ in
                            guard !hasTriggered else { return }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                dragOffset = 0
                            }
                        }
                )
            }
            .frame(height: trackHeight)
        }
        .frame(height: trackHeight)
        .disabled(isSending)
        .onChange(of: isSending) { _, sending in
            if !sending {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    dragOffset = 0
                    hasTriggered = false
                }
            }
        }
    }
}
