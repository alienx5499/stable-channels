import SwiftUI

struct InteractivePhraseInputView: View {
    @Binding var committedWords: [String]
    @Binding var currentInput: String
    @FocusState private var focusedBox: Int?
    let onCommitPhrase: ([String]) -> Void
    let onPaste: () -> Void
    let onClearAll: () -> Void

    @State private var editingIndex: Int? = nil
    @State private var editingText: String = ""

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    private var activeText: String {
        if editingIndex != nil {
            return editingText
        }
        return currentInput
    }

    private var isInvalidPrefix: Bool {
        let trimmed = activeText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return false }
        return !BIP39WordList.hasPrefixMatch(trimmed)
    }

    private var isInvalidChecksum: Bool {
        guard currentInput.isEmpty, editingIndex == nil else { return false }
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
        let trimmed = activeText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !isInvalidPrefix else { return [] }
        return BIP39WordList.suggestions(for: trimmed, limit: 5)
    }

    private var isFull24: Bool {
        committedWords.count == 24 && currentInput.isEmpty && editingIndex == nil
    }

    private var isAnyFieldFocused: Bool {
        focusedBox != nil
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
                                    .red : (isAnyFieldFocused ? Color.white.opacity(0.24) : Color.white.opacity(0.08)),
                                lineWidth: hasError ? 1.5 : 1
                            )
                    )

                if committedWords.isEmpty && currentInput.isEmpty && !isAnyFieldFocused {
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
                }

                // 3 Equal-Sized Boxes Grid Layout (3 words per row)
                LazyVGrid(columns: columns, spacing: 8) {
                    // Committed Word Boxes (tap any box to edit it directly in-place)
                    ForEach(Array(committedWords.indices), id: \.self) { index in
                        if editingIndex == index {
                            // Active In-Place Editor for this specific box
                            HStack(spacing: 4) {
                                Text("\(index + 1).")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundStyle(isInvalidPrefix ? Color.red : Color.stablePrimary)
                                    .fixedSize()

                                TextField("", text: $editingText)
                                    .focused($focusedBox, equals: index)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .onChange(of: editingText) { _, newValue in
                                        handleEditingTextChanged(newValue, at: index)
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
                        } else {
                            // Display Box (tapping starts editing this exact box)
                            HStack(spacing: 4) {
                                Text("\(index + 1).")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundStyle(isInvalidChecksum ? Color.red.opacity(0.8) : Color(white: 0.5))
                                    .fixedSize()

                                Text(committedWords[index])
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
                                startEditing(at: index)
                            }
                        }
                    }

                    // Active Typing Slot for the NEXT new word (visible when not editing an earlier box)
                    if committedWords.count < 24 && editingIndex == nil {
                        HStack(spacing: 4) {
                            Text("\(committedWords.count + 1).")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(isInvalidPrefix ? Color.red : Color.stablePrimary)
                                .fixedSize()

                            TextField("", text: $currentInput)
                                .focused($focusedBox, equals: committedWords.count)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .onChange(of: currentInput) { _, newValue in
                                    handleAppendInputChanged(newValue)
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
                            focusedBox = committedWords.count
                        }
                    }
                }
                .padding(14)
                .opacity((committedWords.isEmpty && currentInput.isEmpty && !isAnyFieldFocused) ? 0 : 1)
            }
            .frame(minHeight: committedWords.count >= 12 ? 240 : 170)
            .contentShape(Rectangle())
            .onTapGesture {
                if !isFull24 && editingIndex == nil {
                    focusedBox = committedWords.count
                }
            }

            // Inline Autocomplete Suggestions Bar (appears smoothly while typing)
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                commitWord(suggestion)
                            } label: {
                                Text(suggestion)
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Color(white: 0.16))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .transition(.opacity)
            }

            // Below Box Actions (Paste / Clear all & Word Count)
            HStack {
                if !committedWords.isEmpty {
                    Text("\(committedWords.count) / \(committedWords.count <= 12 ? 12 : 24) words")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(isInvalidChecksum ? Color.red : Color(white: 0.5))
                }

                Spacer()

                if committedWords.isEmpty && currentInput.isEmpty && editingIndex == nil {
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
                        editingIndex = nil
                        editingText = ""
                        focusedBox = 0
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

    // MARK: - In-Place Editing Actions

    private func startEditing(at index: Int) {
        guard index >= 0 && index < committedWords.count else { return }
        editingIndex = index
        editingText = committedWords[index]
        focusedBox = index
    }

    private func handleEditingTextChanged(_ newValue: String, at index: Int) {
        if newValue.contains(" ") || newValue.contains("\n") || newValue.contains("\t") {
            let words = newValue
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
            guard !words.isEmpty else {
                // If emptied, remove this specific word
                committedWords.remove(at: index)
                editingIndex = nil
                editingText = ""
                onCommitPhrase(committedWords)
                focusedBox = committedWords.count
                return
            }
            let firstWord = words[0].lowercased()
            if BIP39WordList.isValidWord(firstWord) {
                committedWords[index] = firstWord
                editingIndex = nil
                editingText = ""
                onCommitPhrase(committedWords)
                // Move focus to next box or append slot
                if index + 1 < committedWords.count {
                    startEditing(at: index + 1)
                } else if committedWords.count < 24 {
                    focusedBox = committedWords.count
                } else {
                    focusedBox = nil
                }
            } else {
                editingText = firstWord
            }
        }
    }

    private func handleAppendInputChanged(_ newValue: String) {
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
                if committedWords.count >= 24 {
                    focusedBox = nil
                } else {
                    focusedBox = committedWords.count
                }
            } else if words.count == 1 {
                currentInput = words[0].lowercased()
            }
        }
    }

    private func handleReturnPressed() {
        let trimmed = activeText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if BIP39WordList.isValidWord(trimmed) {
            commitWord(trimmed)
        } else if let firstSuggestion = suggestions.first {
            commitWord(firstSuggestion)
        }
    }

    private func commitWord(_ word: String) {
        if let editIdx = editingIndex, editIdx < committedWords.count {
            committedWords[editIdx] = word
            editingIndex = nil
            editingText = ""
            onCommitPhrase(committedWords)
            if editIdx + 1 < committedWords.count {
                startEditing(at: editIdx + 1)
            } else if committedWords.count < 24 {
                focusedBox = committedWords.count
            } else {
                focusedBox = nil
            }
        } else if committedWords.count < 24 {
            committedWords.append(word)
            currentInput = ""
            onCommitPhrase(committedWords)
            if committedWords.count >= 24 {
                focusedBox = nil
            } else {
                focusedBox = committedWords.count
            }
        }
    }
}

// MARK: - BIP-39 Word List Autocomplete & Binary Search Helpers

extension BIP39WordList {
    private static let englishSet: Set<String> = Set(english)

    /// Check if a given string is a valid BIP-39 word in O(1)
    static func isValidWord(_ word: String) -> Bool {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return englishSet.contains(trimmed)
    }

    /// Check if there is any BIP-39 word starting with the given prefix using O(log N) binary search
    static func hasPrefixMatch(_ prefix: String) -> Bool {
        let p = prefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !p.isEmpty else { return true }
        var low = 0
        var high = english.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let word = english[mid]
            if word.hasPrefix(p) {
                return true
            } else if word < p {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return false
    }

    /// Get up to `limit` autocomplete suggestions for a given typed prefix using O(log N) binary search
    static func suggestions(for prefix: String, limit: Int = 5) -> [String] {
        let p = prefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !p.isEmpty else { return [] }

        var low = 0
        var high = english.count
        while low < high {
            let mid = (low + high) / 2
            if english[mid] < p && !english[mid].hasPrefix(p) {
                low = mid + 1
            } else {
                high = mid
            }
        }

        var result: [String] = []
        var index = low
        while index < english.count && result.count < limit {
            let word = english[index]
            if word.hasPrefix(p) {
                result.append(word)
                index += 1
            } else {
                break
            }
        }
        return result
    }
}
