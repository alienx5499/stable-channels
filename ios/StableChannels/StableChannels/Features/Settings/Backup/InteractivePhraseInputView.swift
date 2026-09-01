import SwiftUI

struct InteractivePhraseInputView: View {
    @Binding var committedWords: [String]
    @Binding var currentInput: String
    @FocusState private var isFieldFocused: Bool
    let onCommitPhrase: ([String]) -> Void
    let onPaste: () -> Void
    let onClearAll: () -> Void

    private var isInvalidPrefix: Bool {
        let trimmed = currentInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return false }
        return !BIP39WordList.hasPrefixMatch(trimmed)
    }

    private var suggestions: [String] {
        let trimmed = currentInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !isInvalidPrefix else { return [] }
        return BIP39WordList.suggestions(for: trimmed, limit: 5)
    }

    private var isFull24: Bool {
        committedWords.count == 24 && currentInput.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Main Input Container (Obsidian card)
            ZStack(alignment: .topLeading) {
                // Background Box
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                isInvalidPrefix ? Color
                                    .red : (isFieldFocused ? Color.white.opacity(0.24) : Color.white.opacity(0.08)),
                                lineWidth: isInvalidPrefix ? 1.5 : 1
                            )
                    )

                if committedWords.isEmpty {
                    // Initial Clean Text Input with Placeholder
                    TextField(
                        String(
                            localized: "restore_placeholder_metamask",
                            defaultValue: "Add a space between each word and make sure no one is watching"
                        ),
                        text: $currentInput,
                        axis: .vertical
                    )
                    .focused($isFieldFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .lineSpacing(5)
                    .padding(20)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            keyboardSuggestionsBar
                        }
                    }
                    .onChange(of: currentInput) { _, newValue in
                        handleInputChanged(newValue)
                    }
                    .onSubmit {
                        handleReturnPressed()
                    }
                } else {
                    // Word Blocks Flow Layout with Active Input Field (allows continuing to 24 words)
                    wordBlocksFlowLayout
                        .padding(16)
                }
            }
            .frame(minHeight: committedWords.count >= 12 ? 240 : 170)
            .contentShape(Rectangle())
            .onTapGesture {
                if !isFull24 {
                    isFieldFocused = true
                }
            }

            // Below Box Actions (Paste / Clear all)
            HStack {
                // Word counter helper
                if !committedWords.isEmpty {
                    Text("\(committedWords.count) / \(committedWords.count <= 12 ? 12 : 24) words")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(white: 0.5))
                }

                Spacer()

                if committedWords.isEmpty && currentInput.isEmpty {
                    Button {
                        onPaste()
                    } label: {
                        Text(String(localized: "button_paste", defaultValue: "Paste"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                } else {
                    Button {
                        onClearAll()
                        currentInput = ""
                        isFieldFocused = true
                    } label: {
                        Text(String(localized: "button_clear_all", defaultValue: "Clear all"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.horizontal, 4)

            // Spelling / Invalid Prefix Error Notice
            if isInvalidPrefix {
                Text(String(
                    localized: "restore_error_invalid_prefix",
                    defaultValue: "Use only lowercase letters, check your spelling, and put the words in the original order."
                ))
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 1.0, green: 0.35, blue: 0.35))
                .lineSpacing(2)
                .padding(.top, 2)
                .transition(.opacity)
            }
        }
    }

    // MARK: - Word Blocks Flow

    private var wordBlocksFlowLayout: some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(committedWords.enumerated()), id: \.offset) { index, word in
                HStack(spacing: 6) {
                    Text("\(index + 1).")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(white: 0.5))

                    Text(word)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .onTapGesture {
                    removeWord(at: index)
                }
            }

            // Currently Active Word Input Box (active up to 24 words)
            if committedWords.count < 24 {
                HStack(spacing: 6) {
                    Text("\(committedWords.count + 1).")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(isInvalidPrefix ? Color.red : Color.stablePrimary)

                    TextField("", text: $currentInput)
                        .focused($isFieldFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(minWidth: 54)
                        .fixedSize(horizontal: true, vertical: false)
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                keyboardSuggestionsBar
                            }
                        }
                        .onChange(of: currentInput) { _, newValue in
                            handleInputChanged(newValue)
                        }
                        .onSubmit {
                            handleReturnPressed()
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isInvalidPrefix ? Color.red : Color.stablePrimary,
                            lineWidth: 1.5
                        )
                )
                .onTapGesture {
                    isFieldFocused = true
                }
            }
        }
    }

    // MARK: - Keyboard Suggestions Bar

    @ViewBuilder
    private var keyboardSuggestionsBar: some View {
        if !suggestions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            commitWord(suggestion)
                        } label: {
                            Text(suggestion)
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Color(white: 0.2))
                                .clipShape(RoundedRectangle(
                                    cornerRadius: 8,
                                    style: .continuous
                                ))
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Actions

    private func handleInputChanged(_ newValue: String) {
        if newValue.contains(" ") || newValue.contains("\n") || newValue.contains("\t") {
            let words = newValue
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
            guard !words.isEmpty else {
                currentInput = ""
                return
            }
            if words.count > 1 || (words.count == 1 && BIP39WordList.isValidWord(words[0])) {
                for word in words {
                    let clean = word.lowercased()
                    if BIP39WordList.isValidWord(clean) && committedWords.count < 24 {
                        committedWords.append(clean)
                    }
                }
                currentInput = ""
                onCommitPhrase(committedWords)
                if isFull24 {
                    isFieldFocused = false
                }
            } else if words.count == 1 {
                currentInput = words[0].lowercased()
            }
        }
    }

    private func handleReturnPressed() {
        let trimmed = currentInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if BIP39WordList.isValidWord(trimmed) {
            commitWord(trimmed)
        } else if let firstSuggestion = suggestions.first {
            commitWord(firstSuggestion)
        }
    }

    private func commitWord(_ word: String) {
        guard committedWords.count < 24 else { return }
        committedWords.append(word)
        currentInput = ""
        onCommitPhrase(committedWords)
        if isFull24 {
            isFieldFocused = false
        }
    }

    private func removeWord(at index: Int) {
        guard index >= 0 && index < committedWords.count else { return }
        let removed = committedWords.remove(at: index)
        if currentInput.isEmpty {
            currentInput = removed
        }
        onCommitPhrase(committedWords)
        isFieldFocused = true
    }
}

// MARK: - Flow Layout Helper

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                proposal: .unspecified
            )
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var points: [CGPoint] = []

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            points.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return (CGSize(width: maxWidth, height: currentY + lineHeight), points)
    }
}
