import SwiftUI

/// Subtitle display component showing original and translated text
struct SubtitleDisplayView: View {
    let currentSubtitle: SubtitleItem?
    let historySubtitles: [SubtitleItem]
    private let currentSectionHeight: CGFloat = 170

    private var historyByNewestFirst: [SubtitleItem] {
        historySubtitles.sorted { $0.timestamp > $1.timestamp }
    }

    private var currentOriginalText: String {
        guard let text = currentSubtitle?.originalText, !text.isEmpty else { return "等待识别中..." }
        return text
    }

    private var currentTranslatedText: String {
        guard let text = currentSubtitle?.translatedText, !text.isEmpty else { return "等待翻译中..." }
        return text
    }

    private var currentSubtitleColor: Color {
        guard currentSubtitle != nil else { return .secondary }
        return currentSubtitle?.isFinal == true ? .primary : .orange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("当前字幕")
                .font(.headline)
                .foregroundColor(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("原文")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(currentOriginalText)
                        .font(.body)
                        .foregroundColor(currentSubtitleColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(.easeInOut(duration: 0.2), value: currentOriginalText)

                    Text("译文")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)

                    Text(currentTranslatedText)
                        .font(.body)
                        .foregroundColor(currentSubtitleColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(.easeInOut(duration: 0.2), value: currentTranslatedText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: currentSectionHeight)
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(12)

            Text("历史记录")
                .font(.headline)
                .foregroundColor(.secondary)

            ScrollView {
                if historySubtitles.isEmpty {
                    Text("暂无历史字幕")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(historyByNewestFirst) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.originalText)
                                    .font(.caption)
                                    .foregroundColor(.primary)

                                Text(item.translatedText)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray5))
                            .cornerRadius(8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: .infinity)
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .padding()
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

#Preview {
    SubtitleDisplayView(
        currentSubtitle: SubtitleItem(
            originalText: "Hello, how are you?",
            translatedText: "你好，你怎么样？",
            isFinal: false
        ),
        historySubtitles: [
            SubtitleItem(
                originalText: "Good morning",
                translatedText: "早上好",
                isFinal: true
            )
        ]
    )
    .frame(height: 400)
}
