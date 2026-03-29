# 翻译队列图

```mermaid
flowchart TB
    subgraph 翻译任务提交
        SEG["断句片段\nSegmentedSentence"]
        VALID["内容验证\n- 非空\n- 有效字符≥2\n- 非重复"]
        SUBMIT["提交翻译任务"]
    end

    subgraph 翻译队列
        QUEUE["translationQueue\n[TranslationJob]"]
        JOB1["Job 1"]
        JOB2["Job 2"]
        JOB3["Job N"]
        QUEUE -.->|"按序取出"| JOB1
        QUEUE -.->|"等待"| JOB2
    end

    subgraph 队列处理
        RUNNING{"isTranslation\nQueueRunning"}
        PROCESS["处理翻译任务"]
        CHECK["检查sessionID"]
        SKIP{"job.sessionID\n== currentSessionID"}
    end

    subgraph 翻译执行
        TM["TranslationManager"]
        API{"调用系统翻译API\n(iOS 26+)"}
        SUCCESS["翻译成功\n更新字幕"]
        FAIL["翻译失败\n显示错误"]
    end

    subgraph 状态同步
        UPDATE["更新historySubtitles"]
        SYNC["同步到PiP显示"]
        NEXT["处理下一个任务"]
    end

    %% 流程连接
    SEG --> VALID
    VALID -->|"验证通过"| SUBMIT
    SUBMIT -->|"enqueueTranslation"| QUEUE
    QUEUE -->|"processNextTranslationIfNeeded"| RUNNING

    RUNNING -->|"false & 队列非空"| PROCESS
    PROCESS -->|"取出队首"| JOB1
    JOB1 --> CHECK
    CHECK --> SKIP

    SKIP -->|"是"| API
    SKIP -->|"否 → session已切换"| NEXT

    API -->|"成功"| SUCCESS
    API -->|"失败"| FAIL

    SUCCESS --> UPDATE
    UPDATE --> SYNC
    SYNC --> NEXT
    FAIL --> UPDATE

    NEXT --> RUNNING

    %% 样式
    classDef input fill:#fff3e0,stroke:#e65100,stroke-width:2px;
    classDef queue fill:#e8eaf6,stroke:#3f51b5,stroke-width:2px;
    classDef process fill:#e3f2fd,stroke:#1565c0,stroke-width:2px;
    classDef api fill:#fce4ec,stroke:#c2185b,stroke-width:2px;
    classDef output fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px;

    class SEG,VALID,SUBMIT input;
    class QUEUE,JOB1,JOB2,JOB3 queue;
    class RUNNING,PROCESS,CHECK,SKIP process;
    class TM,API,SUCCESS,FAIL api;
    class UPDATE,SYNC,NEXT output;
```

## 翻译队列处理机制

### 1. 任务入队
- 断句完成后，通过 `enqueueTranslation()` 添加到队列
- 每个任务包含：`subtitleID`, `text`, `sessionID`

### 2. 队列处理逻辑
- 使用 `isTranslationQueueRunning` 标志防止并发
- 每次只处理一个翻译任务
- 任务完成后自动处理下一个

### 3. Session 隔离
- 每次新识别会话生成新的 `translationSessionID`
- 新会话开始时清空队列并取消正在进行的翻译
- 处理时检查 `job.sessionID == translationSessionID`，不匹配则跳过

### 4. 错误处理
- 翻译成功: 更新 `historySubtitles` 中对应字幕的翻译文本
- 翻译失败: 显示"翻译失败"占位符
- 无论成功失败，都会继续处理队列中的下一个任务

### 5. 显示同步
- 翻译完成后:
  1. 更新 `historySubtitles` 数组中的字幕项
  2. 调用 `syncPiPTranslatedTextFromCurrentSession()` 同步到画中画显示
  3. 将当前会话所有已翻译文本合并显示在译文区域
