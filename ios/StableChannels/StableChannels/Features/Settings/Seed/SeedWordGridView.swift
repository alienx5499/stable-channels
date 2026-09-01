import SwiftUI

struct SeedWordGridView: View {
    let wordFields: [String]
    let isReadOnly: Bool
    let isDisabled: Bool
    let wordCount: Int
    var onWordChanged: ((Int, String) -> Void)?

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(0..<wordCount, id: \.self) { index in
                wordCell(index: index)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: wordCount)
    }

    private func wordCell(index: Int) -> some View {
        let isFilled = index < wordFields.count && !wordFields[index].trimmingCharacters(in: .whitespaces).isEmpty
        let word = index < wordFields.count ? wordFields[index] : ""

        return HStack(spacing: 8) {
            Text(String(format: "%02d", index + 1))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(isFilled ? Color.stablePrimary : Color.secondary.opacity(0.7))
                .frame(width: 22, alignment: .leading)

            if isReadOnly || isDisabled {
                Text(word.isEmpty ? "—" : word)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(word.isEmpty ? Color.secondary.opacity(0.4) : Color.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(
                    "",
                    text: Binding(
                        get: { index < wordFields.count ? wordFields[index] : "" },
                        set: { onWordChanged?(index, $0) }
                    )
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isFilled ? Color.stablePrimary.opacity(0.35) : Color.white.opacity(0.06),
                    lineWidth: 1
                )
        )
    }
}
