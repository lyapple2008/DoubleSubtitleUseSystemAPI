# 系统数据流图

```mermaid
flowchart TB
    subgraph 用户交互
        UI["ContentView / UI层"]
        PICKER["RPSystemBroadcastPickerView\n系统录屏选择器"]
    end

    subgraph 音频捕获模块
        AC["AudioCaptureManager"]
        EXT["AudioCaptureExtension\nBroadcast Upload Extension"]
        SHARED["App Group 共享存储\ncaptured_audio.pcm"]
    end

    subgraph 语音识别模块
        SR["SpeechRecognitionManager\nSFSpeechRecognizer"]
        SEG["SpeechSentenceSegmenter\n断句处理器"]
    end

    subgraph 翻译模块
        TM["TranslationManager\n系统翻译API"]
    end

    subgraph 字幕显示模块
        OVERLAY["SubtitleOverlayManager\nPiP画中画管理"]
        PIP["AVPictureInPicture\n画中画视图"]
    end

    %% 用户交互流程
    UI -->|"点击开始识别"| PICKER
    PICKER -->|"用户点击开始直播"| EXT

    %% 音频捕获流程
    EXT -->|"写入PCM音频"| SHARED
    SHARED -->|"轮询读取PCM"| AC
    AC -->|"AVAudioPCMBuffer"| SR

    %% 语音识别流程
    SR -->|"识别结果文本"| SEG
    SEG -->|"断句结果"| UI

    %% 翻译流程
    SEG -->|"原始文本"| TM
    TM -->|"翻译文本"| UI

    %% 字幕显示流程
    UI -->|"更新字幕"| OVERLAY
    OVERLAY -->|"显示双语字幕"| PIP

    %% 样式定义
    classDef module fill:#e1f5fe,stroke:#01579b,stroke-width:2px;
    classDef storage fill:#fff3e0,stroke:#e65100,stroke-width:2px;
    classDef user fill:#e8f5e9,stroke:#1b5e20,stroke-width:2px;

    class AC,SR,SEG,TM,OVERLAY module;
    class SHARED storage;
    class UI,PICKER user;
```

## 数据流说明

1. **用户触发**: 用户点击"开始识别"按钮，弹出系统 RPSystemBroadcastPickerView
2. **音频捕获**: 用户在系统界面点击"开始直播"，Extension 开始捕获系统音频，写入共享 PCM 文件
3. **音频读取**: 主 App 通过 AudioCaptureManager 轮询读取共享文件，转换为 AVAudioPCMBuffer
4. **语音识别**: SpeechRecognitionManager 接收音频缓冲区，进行实时语音识别
5. **断句处理**: SpeechSentenceSegmenter 对识别结果进行断句处理
6. **翻译**: 断句后的文本进入翻译队列，由 TranslationManager 调用系统翻译 API
7. **显示**: 最终的原文和译文通过 SubtitleOverlayManager 在画中画中显示
