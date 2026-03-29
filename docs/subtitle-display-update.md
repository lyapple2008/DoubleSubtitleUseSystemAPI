# 字幕显示更新图

```mermaid
flowchart TB
    subgraph 识别阶段
        RAW["原始识别结果\nResult String"]
        SEG["断句处理器\nSentenceSegmenter"]
        STABLE["稳定片段\nStable Segments"]
        CURRENT["当前识别中\nCurrent Preview"]
    end

    subgraph 字幕数据结构
        ITEM["SubtitleItem\n- originalText\n- translatedText\n- isFinal\n- timestamp"]
        HISTORY["历史字幕列表\n[SubtitleItem]"]
    end

    subgraph 显示层
        APP_UI["App内字幕视图\nSubtitleDisplayView"]
        PIP["画中画字幕\nPiP Overlay"]
    end

    %% 识别流程
    RAW -->|"实时输入"| SEG
    SEG -->|"检测到断句边界"| STABLE
    SEG -->|"持续更新"| CURRENT

    %% 字幕项创建
    STABLE -->|"提交片段"| ITEM
    CURRENT -->|"预览文本"| ITEM

    ITEM -->|"添加"| HISTORY
    ITEM -->|"当前字幕"| APP_UI
    ITEM -->|"当前字幕"| PIP

    %% 翻译更新
    TM["TranslationManager"] -.->|"翻译完成"| ITEM

    APP_UI -->|"原文 + 译文"| 用户1["用户"]
    PIP -->|"双语字幕"| 用户2["用户"]

    %% 样式
    classDef process fill:#e3f2fd,stroke:#1565c0,stroke-width:2px;
    classDef data fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px;
    classDef display fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px;

    class RAW,SEG,STABLE,CURRENT,TM process;
    class ITEM,HISTORY data;
    class APP_UI,PIP display;
```

## 字幕更新机制

### 1. 实时识别阶段
- 语音识别持续输出原始文本
- `SpeechSentenceSegmenter` 实时分析文本，检测稳定断句边界
- 未断句的部分作为"当前预览"显示

### 2. 字幕项状态
- **isFinal = false**: 正在识别中，文字可能还会变化（显示橙色）
- **isFinal = true**: 已完成识别，文字稳定（显示黑色）
- **translatedText**: 初始为"翻译中..."，翻译完成后更新

### 3. 显示分区
- **上半部分 (原文)**: 显示 SpeechRecognitionManager 识别的原始文本
- **下半部分 (译文)**: 显示 TranslationManager 翻译后的文本
- **历史记录**: 已完成的字幕项添加到历史列表

### 4. 画中画显示
- 当前会话的所有已翻译文本合并显示在译文区域
- 原文区域显示当前正在识别的内容
