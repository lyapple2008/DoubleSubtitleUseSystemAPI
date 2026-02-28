import SwiftUI

/// Subtitle display component showing original and translated text
struct SubtitleDisplayView: View {
    let currentSubtitle: SubtitleItem?
    let historySubtitles: [SubtitleItem]
    private var historyByNewestFirst: [SubtitleItem] {
        historySubtitles.sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Current (live) subtitle
            if let subtitle = currentSubtitle {
                VStack(alignment: .leading, spacing: 8) {
                    Text("原文")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(subtitle.originalText)
                        .font(.body)
                        .foregroundColor(subtitle.isFinal ? .primary : .orange)
                        .animation(.easeInOut(duration: 0.2), value: subtitle.originalText)

                    Text("译文")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)

                    Text(subtitle.translatedText)
                        .font(.body)
                        .foregroundColor(subtitle.isFinal ? .primary : .orange)
                        .animation(.easeInOut(duration: 0.2), value: subtitle.translatedText)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                Divider()
                    .padding(.vertical, 8)
            }

            // History subtitles
            if !historySubtitles.isEmpty {
                Text("历史记录")
                    .font(.headline)
                    .foregroundColor(.secondary)

                ScrollView {
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
                }
                .frame(maxHeight: 200)
            }

            // Empty state
            if currentSubtitle == nil && historySubtitles.isEmpty {
                VStack {
                    Spacer()
                    Text("点击「开始识别」启动双语字幕")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
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
