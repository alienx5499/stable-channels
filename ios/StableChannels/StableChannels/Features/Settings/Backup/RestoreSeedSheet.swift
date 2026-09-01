import SwiftUI

struct RestoreSeedSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @Binding var restoreMnemonic: String
    @Binding var wordFields: [String]
    @Binding var isWordFieldsReadOnly: Bool
    @Binding var isImportingSeed: Bool
    @Binding var isRestoring: Bool
    @Binding var restoreError: String?
    let onCancel: () -> Void
    let onSuccess: () -> Void

    @State private var committedWords: [String] = []
    @State private var currentInput: String = ""
    @State private var showForceCloseConfirm = false
    @State private var showGuardUnavailableConfirm = false
    @State private var showLearnMoreSheet = false

    private var restoreValid: Bool {
        (committedWords.count == SeedConstants.wordCount12 || committedWords.count == SeedConstants.wordCount24) &&
            currentInput.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 20) {
                            // Header
                            VStack(alignment: .leading, spacing: 6) {
                                Text(String(localized: "title_restore_seed", defaultValue: "Restore from Seed"))
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(.white)

                                HStack(spacing: 6) {
                                    Text(String(
                                        localized: "instruction_restore",
                                        defaultValue: "Enter your 12 or 24-word seed phrase."
                                    ))
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color(uiColor: .lightGray))

                                    Button {
                                        showLearnMoreSheet = true
                                    } label: {
                                        Image(systemName: "info.circle")
                                            .font(.system(size: 15))
                                            .foregroundStyle(Color(white: 0.6))
                                    }
                                }
                            }
                            .padding(.top, 12)

                            // Warning Notice
                            warningCard

                            // Interactive Recovery Phrase Input View
                            InteractivePhraseInputView(
                                committedWords: $committedWords,
                                currentInput: $currentInput,
                                onCommitPhrase: { words in
                                    syncFields(from: words)
                                },
                                onPaste: {
                                    pasteFromClipboard()
                                },
                                onClearAll: {
                                    clearAll()
                                }
                            )

                            if let error = restoreError {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.system(size: 13))
                                    Text(error)
                                        .font(.system(size: 13))
                                }
                                .foregroundStyle(.red)
                                .padding(.top, 4)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }

                    // Bottom Action Button
                    Button {
                        Task { await restoreWallet() }
                    } label: {
                        if isRestoring {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .tint(.black)
                                Text(String(localized: "restoring", defaultValue: "Restoring..."))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.black)
                            }
                        } else {
                            Text(String(localized: "button_restore", defaultValue: "Restore"))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(restoreValid ? .black : Color.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(restoreValid ? Color.white : Color(white: 0.18))
                    .clipShape(Capsule())
                    .disabled(!restoreValid || isRestoring)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onCancel()
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .sheet(isPresented: $showLearnMoreSheet) {
                RevealQuizLearnMoreSheet()
            }
            .alert(
                String(localized: "title_open_channel_detected", defaultValue: "Open Channel Detected"),
                isPresented: $showForceCloseConfirm
            ) {
                Button(String(localized: "button_cancel", defaultValue: "Cancel"), role: .cancel) {}
                Button(
                    String(localized: "button_restore_anyway", defaultValue: "Restore Anyway"),
                    role: .destructive
                ) {
                    Task { await restoreWallet(acknowledgeForceClose: true) }
                }
            } message: {
                Text(String(
                    localized: "message_restore_force_close",
                    defaultValue: "This wallet still has an open Lightning channel with the LSP. Restoring from seed alone cannot restore the channel and it will be force-closed on-chain; funds return after a timelock. Only continue if this is your only way back into the wallet."
                ))
            }
            .alert(
                String(localized: "title_channel_check_unavailable", defaultValue: "Couldn't Verify Channel Status"),
                isPresented: $showGuardUnavailableConfirm
            ) {
                Button(String(localized: "button_cancel", defaultValue: "Cancel"), role: .cancel) {}
                Button(
                    String(localized: "button_continue_anyway", defaultValue: "Continue Anyway"),
                    role: .destructive
                ) {
                    Task { await restoreWallet(acknowledgeForceClose: true) }
                }
            } message: {
                Text(String(
                    localized: "message_channel_check_unavailable",
                    defaultValue: "The server couldn't be reached to check whether this wallet still has an open Lightning channel. If it does, restoring from seed alone will force-close it on-chain. Continue only if you're sure, or try again with a network connection."
                ))
            }
            .onAppear {
                initFromBindings()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private var warningCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.orange)

                Text(String(localized: "warning_partial_recovery", defaultValue: "Onchain Recovery Notice"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text(String(
                localized: "warning_restore_desc",
                defaultValue: "Restoring from seed recovers onchain funds. Active Lightning channels cannot be recovered via seed alone and will require LSP settlement."
            ))
            .font(.system(size: 13))
            .foregroundStyle(Color(white: 0.72))
            .lineSpacing(2.5)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.24), lineWidth: 1)
        )
    }

    // MARK: - Synchronization & Actions

    private func initFromBindings() {
        if !restoreMnemonic.isEmpty {
            let parsed = MnemonicUtils.parseMnemonic(restoreMnemonic)
            if !parsed.isEmpty {
                committedWords = parsed
            }
        } else {
            let existing = wordFields.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            if !existing.isEmpty {
                committedWords = existing
            }
        }
    }

    private func syncFields(from words: [String]) {
        restoreMnemonic = words.joined(separator: " ")
        wordFields = MnemonicUtils.wordsToFields(words)
        isWordFieldsReadOnly = false
    }

    private func pasteFromClipboard() {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return
        }
        let parsed = MnemonicUtils.parseMnemonic(text)
        guard !parsed.isEmpty else { return }
        committedWords = Array(parsed.prefix(24))
        currentInput = ""
        syncFields(from: committedWords)
    }

    private func clearAll() {
        committedWords = []
        currentInput = ""
        restoreMnemonic = ""
        wordFields = Array(repeating: "", count: SeedConstants.maxWordCount)
        restoreError = nil
    }

    private func restoreWallet(acknowledgeForceClose: Bool = false) async {
        isRestoring = true
        restoreError = nil

        let input = restoreMnemonic.trimmingCharacters(in: .whitespacesAndNewlines)

        guard MnemonicUtils.isValidWordCount(input) else {
            isRestoring = false
            restoreError = String(localized: "error_seed_word_count", defaultValue: "Please enter 12 or 24 words.")
            return
        }

        guard MnemonicUtils.isValidMnemonic(input) else {
            isRestoring = false
            restoreError = String(
                localized: "error_invalid_seed_phrase",
                defaultValue: "Invalid Secret Recovery Phrase. Please check word spelling and order."
            )
            return
        }

        do {
            try await appState.restoreWalletFromMnemonic(
                input,
                acknowledgeForceClose: acknowledgeForceClose
            )
            clearAll()
            isRestoring = false
            onSuccess()
            dismiss()
        } catch AppState.WalletRestoreError.activeChannelDetected {
            isRestoring = false
            showForceCloseConfirm = true
        } catch AppState.WalletRestoreError.channelCheckUnavailable {
            isRestoring = false
            showGuardUnavailableConfirm = true
        } catch AppState.WalletRestoreError.invalidMnemonic {
            isRestoring = false
            restoreError = String(
                localized: "error_invalid_seed_phrase",
                defaultValue: "Invalid Secret Recovery Phrase. Please check word spelling and order."
            )
        } catch {
            restoreError = String(localized: "error_restore_failed") + error.localizedDescription
            isRestoring = false
        }
    }
}
