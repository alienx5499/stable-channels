import SwiftUI
import PhotosUI

/// Step 1: Destination input, QR scanning, and real-time protocol recognition.
struct SendRecipientStepView: View {
    @Bindable var model: SendFlowModel
    @Environment(AppState.self) private var appState

    @State private var showScanner = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 20) {
            sourceBalancePill

            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "header_recipient", defaultValue: "Recipient"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                recipientCard
            }

            SendDestinationBadgeView(classification: model.classification)

            Spacer(minLength: 20)

            actionButtons
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .sheet(isPresented: $showScanner) {
            InvoiceScanView(
                onScan: { scanned in
                    model.inputText = QRCodeExtractor.sanitizePaymentInput(scanned)
                    showScanner = false
                },
                onCancel: { showScanner = false }
            )
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let item = newItem else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   let code = QRCodeExtractor.extract(from: image) {
                    await MainActor.run {
                        model.inputText = QRCodeExtractor.sanitizePaymentInput(code)
                    }
                }
                await MainActor.run { selectedPhotoItem = nil }
            }
        }
    }

    private var sourceBalancePill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
            let readyChannel = appState.nodeService.channels.first(where: \.isChannelReady)
            if readyChannel != nil {
                Text(String(localized: "label_lightning_ready", defaultValue: "Lightning Ready"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                Text(String(localized: "label_onchain_only", defaultValue: "Onchain Wallet"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if appState.btcPrice > 0 {
                let usd = Double(appState.totalBalanceSats) / Double(Constants.satsInBTC) * appState.btcPrice
                Text("Balance: \(usd.usdFormatted)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(white: 0.12), in: Capsule())
    }

    private var recipientCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                TextField(
                    String(
                        localized: "placeholder_send_destination",
                        defaultValue: "Invoice, address, or name@domain.com"
                    ),
                    text: $model.inputText,
                    axis: .vertical
                )
                .font(.system(.body, design: .monospaced))
                .lineLimit(3...5)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.trailing, 28)

                if !model.inputText.isEmpty {
                    Button {
                        model.inputText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider().overlay(Color.white.opacity(0.1))

            HStack {
                Button {
                    if let clipboard = UIPasteboard.general.string {
                        model.inputText = QRCodeExtractor.sanitizePaymentInput(clipboard)
                    }
                } label: {
                    Label(String(localized: "button_paste", defaultValue: "Paste"), systemImage: "doc.on.clipboard")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(.secondary)

                Spacer()

                Button {
                    showScanner = true
                } label: {
                    Label(
                        String(localized: "button_scan_qr", defaultValue: "Scan QR"),
                        systemImage: "qrcode.viewfinder"
                    )
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(.cyan)

                Button {
                    showPhotoPicker = true
                } label: {
                    Image(systemName: "photo")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            }
        }
        .padding(16)
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 16))
    }

    private var actionButtons: some View {
        Button {
            Task { await model.proceedFromRecipient(appState: appState) }
        } label: {
            if model.isFetchingLNURL {
                ProgressView().tint(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                Text(String(localized: "button_next", defaultValue: "Next"))
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
        }
        .background(
            model.destination != nil ? Color.cyan : Color.gray.opacity(0.3),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .disabled(model.destination == nil || model.isFetchingLNURL)
        .padding(.bottom, 16)
    }
}
