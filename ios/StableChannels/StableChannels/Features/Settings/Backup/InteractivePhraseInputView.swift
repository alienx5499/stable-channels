import SwiftUI

struct InteractivePhraseInputView: View {
    @Binding var committedWords: [String]
    @Binding var currentInput: String
    @FocusState private var isFieldFocused: Bool
    let onCommitPhrase: ([String]) -> Void
    let onPaste: () -> Void
    let onClearAll: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    private var isInvalidPrefix: Bool {
        let trimmed = currentInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return false }
        return !BIP39WordList.hasPrefixMatch(trimmed)
    }

    private var isInvalidChecksum: Bool {
        guard currentInput.isEmpty else { return false }
        if committedWords.count == 12 || committedWords.count == 24 {
            let phrase = committedWords.joined(separator: " ")
            return !BIP39.isValid(phrase)
        }
        return false
    }

    private var hasError: Bool {
        isInvalidPrefix || isInvalidChecksum
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
            // Main Input Container
            ZStack(alignment: .topLeading) {
                // Background Obsidian Box
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                hasError ? Color
                                    .red : (isFieldFocused ? Color.white.opacity(0.24) : Color.white.opacity(0.08)),
                                lineWidth: hasError ? 1.5 : 1
                            )
                    )

                if committedWords.isEmpty && currentInput.isEmpty && !isFieldFocused {
                    // Initial Clean Text Input Placeholder
                    Text(String(
                        localized: "restore_placeholder_metamask",
                        defaultValue: "Add a space between each word and make sure no one is watching"
                    ))
                    .font(.system(size: 15))
                    .foregroundStyle(Color(white: 0.55))
                    .lineSpacing(5)
                    .padding(20)
                    .allowsHitTesting(false)
                } else if committedWords.isEmpty && !isFieldFocused {
                    // Unfocused text preview
                    Text(currentInput)
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .padding(20)
                        .allowsHitTesting(false)
                }

                // 3 Equal-Sized Boxes Grid Layout (3 words per row)
                LazyVGrid(columns: columns, spacing: 8) {
                    // Committed Word Boxes
                    ForEach(Array(committedWords.enumerated()), id: \.offset) { index, word in
                        HStack(spacing: 4) {
                            Text("\(index + 1).")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(isInvalidChecksum ? Color.red.opacity(0.8) : Color(white: 0.5))
                                .fixedSize()

                            Text(word)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .frame(height: 38)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(
                                    isInvalidChecksum ? Color.red.opacity(0.6) : Color.white.opacity(0.12),
                                    lineWidth: 1
                                )
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            removeWord(at: index)
                        }
                    }

                    // Active Typing Equal-Sized Box
                    if committedWords.count < 24 {
                        HStack(spacing: 4) {
                            Text("\(committedWords.count + 1).")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(isInvalidPrefix ? Color.red : Color.stablePrimary)
                                .fixedSize()

                            TextField("", text: $currentInput)
                                .focused($isFieldFocused)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
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
                        .padding(.horizontal, 8)
                        .frame(height: 38)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(
                                    isInvalidPrefix ? Color.red : Color.stablePrimary,
                                    lineWidth: 1.5
                                )
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isFieldFocused = true
                        }
                    }
                }
                .padding(14)
                .opacity((committedWords.isEmpty && currentInput.isEmpty && !isFieldFocused) ? 0 : 1)
            }
            .frame(minHeight: committedWords.count >= 12 ? 240 : 170)
            .contentShape(Rectangle())
            .onTapGesture {
                if !isFull24 {
                    isFieldFocused = true
                }
            }

            // Below Box Actions (Paste / Clear all & Word Count)
            HStack {
                if !committedWords.isEmpty {
                    Text("\(committedWords.count) / \(committedWords.count <= 12 ? 12 : 24) words")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(isInvalidChecksum ? Color.red : Color(white: 0.5))
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

            // Spelling / Invalid Prefix or Checksum Error Notice
            if isInvalidPrefix || isInvalidChecksum {
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
