import SwiftUI

/// Language selector component
struct LanguageSelectorView: View {
    @Binding var sourceLanguage: LanguageOption
    @Binding var targetLanguage: LanguageOption

    var body: some View {
        VStack(spacing: 16) {
            // Source language selector
            HStack {
                Text("源语言")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Spacer()

                Picker("源语言", selection: $sourceLanguage) {
                    ForEach(LanguageOption.sourceLanguages) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.menu)
            }

            // Target language selector
            HStack {
                Text("目标语言")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Spacer()

                Picker("目标语言", selection: $targetLanguage) {
                    ForEach(LanguageOption.targetLanguages) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

#Preview {
    LanguageSelectorView(
        sourceLanguage: .constant(.defaultSource),
        targetLanguage: .constant(.defaultTarget)
    )
    .padding()
}
