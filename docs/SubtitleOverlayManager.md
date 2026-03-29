# SubtitleOverlayManager.swift 代码详解

这是一份面向 Swift/iOS 开发小白的完整指南。

---

## 一、Swift 语法基础

### 1. `final` - 禁止继承

```swift
final class SubtitleOverlayManager: NSObject, ObservableObject {
```

- `final` 修饰符表示这个类**不能被其他类继承**
- 类似于 Java 的 `final class`
- 编译器可以对此进行优化

### 2. `static let` - 单例模式

```swift
static let shared = SubtitleOverlayManager()
```

- `static` 属于类本身，而非实例
- 整个应用只有一个 `SubtitleOverlayManager.shared` 实例
- 这是 iOS 开发中常用的**单例模式**，用于全局共享状态

### 3. `@Published` - 可观察属性

```swift
@Published var isPiPActive = false
@Published var currentSubtitle: SubtitleItem?
```

- 修饰 `ObservableObject` 类的属性
- 当值改变时，自动通知观察者（SwiftUI 视图）
- 类似于 Android 的 LiveData

### 4. `private(set)` - 只读属性

```swift
@Published private(set) var currentOriginalText = ""
```

- 外部**只能读取**，不能直接修改
- 只能在类内部修改值
- 保证数据封装性

### 5. `guard` - 条件守卫

```swift
guard AVPictureInPictureController.isPictureInPictureSupported() else {
    isPiPPossible = false
    return
}
```

- 条件不满足时执行 `else` 分支并**提前返回**
- 类似于 if-else，但更简洁，强制要求 return
- 用于提前检查并处理错误情况

### 6. `??` - 空值合并运算符

```swift
pipController?.isPictureInPictureActive ?? false
```

- 如果 `pipController` 为 nil，返回 `false`
- 类似于 Kotlin 的 `?:` 操作符

### 7. `Any` 类型

```swift
func pictureInPictureController(_ controller: AVPictureInPictureController,
                                failedToStartPictureInPictureWithError error: any Error)
```

- `any` 表示任意类型的 Error
- Swift 5.6+ 需要显式标记

### 8. 尾随闭包语法

```swift
NSLayoutConstraint.activate([
    hostingController.view.leadingAnchor.constraint(equalTo: contentController.view.leadingAnchor),
    // ...
])
```

- 如果函数最后一个参数是闭包，可以放在括号外
- 这是 Swift 的常用简写语法

---

## 二、iOS 画中画 (Picture-in-Picture) 使用指南

### 1. 什么是画中画？

画中画（PiP）是一种在屏幕上同时显示两个应用的技术：
- 主屏幕显示一个应用
- 另一个小窗口同时播放视频或显示内容

在 iOS 中，PiP 常用于：
- 视频播放时切换到其他应用
- 视频通话时显示悬浮字幕

### 2. 画中画的前置条件

```swift
guard AVPictureInPictureController.isPictureInPictureSupported() else {
    isPiPPossible = false
    return
}
```

- 并非所有设备都支持 PiP
- 需要检查 `isPictureInPictureSupported()`

### 3. 画中画的创建流程

```
┌─────────────────────────────────────────────────────────────┐
│                    PiP 创建流程                              │
├─────────────────────────────────────────────────────────────┤
│ 1. 检查设备支持                                             │
│    AVPictureInPictureController.isPictureInPictureSupported│
│                                                             │
│ 2. 创建源视图 (sourceView)                                   │
│    - 作为 PiP 显示内容的来源                                 │
│    - 通常是一个透明的小视图                                  │
│                                                             │
│ 3. 创建内容视图控制器                                        │
│    - AVPictureInPictureVideoCallViewController            │
│    - 用于显示字幕内容                                        │
│                                                             │
│ 4. 创建 SwiftUI 托管控制器                                   │
│    - UIHostingController 包装 SwiftUI 视图                  │
│    - 将字幕 UI 嵌入到 PiP 中                                │
│                                                             │
│ 5. 创建内容源并初始化 PiP 控制器                              │
│    - AVPictureInPictureController.ContentSource           │
│    - 关联源视图和内容控制器                                  │
│                                                             │
│ 6. 设置代理并启动                                           │
│    - delegate = self                                        │
│    - canStartPictureInPictureAutomaticallyFromInline = true│
└─────────────────────────────────────────────────────────────┘
```

### 4. 核心 API 说明

| API | 作用 |
|-----|------|
| `AVPictureInPictureController.isPictureInPictureSupported()` | 检查设备是否支持 PiP |
| `AVPictureInPictureVideoCallViewController` | 视频通话风格的 PiP 容器 |
| `UIHostingController` | 将 SwiftUI 视图嵌入 UIKit |
| `startPictureInPicture()` | 启动画中画 |
| `stopPictureInPicture()` | 停止画中画 |
| `isPictureInPictureActive` | 当前是否正在显示 PiP |

### 5. SourceView（源视图）详解

SourceView 是画中画功能的核心组件之一，它作为 PiP 的"视频源"。

```swift
private weak var pipSourceView: UIView?  // 源视图引用

private func ensurePiPSourceView() -> UIView? {
    // 获取当前窗口
    let windows = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
    guard let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first else {
        return nil
    }

    // 计算源视图大小（16:9 比例，最小 240x135）
    let sourceFrame = preferredSourceFrame(in: window.bounds)

    // 创建透明源视图
    let sourceView = UIView(frame: sourceFrame)
    sourceView.backgroundColor = .clear
    sourceView.isUserInteractionEnabled = false
    sourceView.alpha = 0.01  // 必须非零，否则系统不接受
    window.addSubview(sourceView)
    pipSourceView = sourceView
    return sourceView
}

private func preferredSourceFrame(in windowBounds: CGRect) -> CGRect {
    let width = max(windowBounds.width, 240)
    let height = max(width / pipSourceAspectRatio, 135)
    return CGRect(x: 0, y: 0, width: width, height: height)
}
```

**为什么需要 SourceView？**

iOS 的 PiP 功能最初设计用于视频播放场景，系统需要一个"视频源"来捕获画面。即使我们不显示实际视频，也必须提供一个可视区域作为触发源。这里的 SourceView 是完全透明的（alpha = 0.01），用户看不到它，但它满足系统要求。

### 6. 完整组件层级架构

```
┌─────────────────────────────────────────────────────────┐
│                     iOS 系统                              │
│  ┌─────────────────────────────────────────────────┐    │
│  │              PiP 窗口 (系统控制)                  │    │
│  │  ┌─────────────────────────────────────────┐    │    │
│  │  │    AVPictureInPictureVideoCallVC       │    │    │
│  │  │  ┌─────────────────────────────────┐    │    │    │
│  │  │  │     UIHostingController         │    │    │    │
│  │  │  │  ┌─────────────────────────┐    │    │    │    │
│  │  │  │  │  PiPSubtitleOverlayView │    │    │    │    │
│  │  │  │  │  ┌─────────────────┐   │    │    │    │    │
│  │  │  │  │  │ VStack          │   │    │    │    │    │
│  │  │  │  │  │ ├─ PiPSubtitle  │   │    │    │    │    │
│  │  │  │  │  │ │   (原文)       │   │    │    │    │    │
│  │  │  │  │  │ └─ PiPSubtitle  │   │    │    │    │    │
│  │  │  │  │  │     (译文)       │   │    │    │    │    │
│  │  │  │  │  └─────────────────┘   │    │    │    │    │
│  │  │  │  └─────────────────────────┘    │    │    │
│  │  │  └─────────────────────────────────┘    │    │
│  │  └─────────────────────────────────────────┘    │    │
│  └─────────────────────────────────────────────────┘    │
│                                                         │
│  ┌─────────────────────────────────────────────────┐    │
│  │         sourceView (透明/隐藏的源视图)             │    │
│  │    位于主窗口，不可见，用于触发 PiP                 │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

### 7. 内容源配置 (ContentSource)

```swift
let contentSource = AVPictureInPictureController.ContentSource(
    activeVideoCallSourceView: sourceView,      // 视频源（透明视图）
    contentViewController: contentController     // 自定义内容控制器
)
let controller = AVPictureInPictureController(contentSource: contentSource)
```

ContentSource 是 PiP 的核心配置，绑定两个关键部分：
- `activeVideoCallSourceView`: 实际的"视频"来源（我们用透明视图）
- `contentViewController`: 要显示的 UI 内容（我们的字幕界面）

### 8. AVPictureInPictureControllerDelegate 代理

```swift
extension SubtitleOverlayManager: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(...) { }
    func pictureInPictureControllerDidStartPictureInPicture(...) { }
    func pictureInPictureControllerWillStopPictureInPicture(...) { }
    func pictureInPictureControllerDidStopPictureInPicture(...) { }
    func pictureInPictureController(_:failedToStartWithError:) { }
    func pictureInPictureController(_:restoreUserInterfaceForStopWithCompletionHandler:) { }
}
```

代理方法让你在 PiP 状态变化时执行相应操作：
- **即将启动** / **已经启动**
- **即将停止** / **已经停止**
- **启动失败** - 处理错误
- **恢复界面** - 用户点击返回时

---

## 九、双语字幕显示实现

### 1. 字幕显示架构

```
┌─────────────────────────────────────────────────────────────┐
│                   SubtitleOverlayManager                     │
├─────────────────────────────────────────────────────────────┤
│  @Published var currentOriginalText   ←  原文（识别结果）     │
│  @Published var currentTranslatedText ←  译文（翻译结果）    │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              PiPSubtitleOverlayView                  │    │
│  │  ┌─────────────────┐  ┌─────────────────┐          │    │
│  │  │  原文面板       │  │  译文面板       │          │    │
│  │  │  PiPSubtitlePanel│  │  PiPSubtitlePanel│         │    │
│  │  └─────────────────┘  └─────────────────┘          │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### 2. 字幕更新流程

```
ContentViewModel
      │
      ▼
┌─────────────────┐
│ 提交识别结果    │
│ 触发翻译       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌─────────────────┐
│ updateSubtitle │────▶│ currentOriginal │
│ (_ subtitle)   │     │     Text        │
└─────────────────┘     └────────┬────────┘
                                 │
                                 ▼
                        ┌─────────────────┐
                        │ PiP 显示原文    │
                        │ "你好，我是..." │
                        └─────────────────┘

         ┌────────────────────────────────────┐
         │           翻译完成                  │
         └────────┬───────────────────────────┘
                  │
                  ▼
         ┌─────────────────┐     ┌─────────────────┐
         │ updateCurrent  │────▶│ currentTranslated│
         │ TranslatedText │     │     Text        │
         └─────────────────┘     └────────┬────────┘
                                          │
                                          ▼
                                 ┌─────────────────┐
                                 │ PiP 显示译文    │
                                 │ "Hello, I'm..." │
                                 └─────────────────┘
```

### 3. PiP 字幕视图结构

```swift
private struct PiPSubtitleOverlayView: View {
    @ObservedObject var overlayManager: SubtitleOverlayManager

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 8) {
                // 上半部分：原文
                PiPSubtitlePanel(text: originalText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // 下半部分：译文
                PiPSubtitlePanel(text: translatedText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(8)
            .background(Color.black.opacity(0.86))  // 半透明黑色背景
        }
    }
}
```

### 4. 字幕面板设计

```swift
private struct PiPSubtitlePanel: View {
    let text: String

    var body: some View {
        ScrollViewReader { proxy in  // 支持滚动
            ScrollView {
                Text(text)            // 字幕文本
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
            }
            .onAppear { ... }        // 初始滚动到底部
            .onChange(of: text) { _ in
                withAnimation { ... } // 文本变化时动画滚动
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.08))  // 微白背景区分区域
        .cornerRadius(10)                       // 圆角
    }
}
```

### 5. 关键设计点

| 设计点 | 说明 |
|--------|------|
| **半透明背景** | `Color.black.opacity(0.86)` 保证文字清晰可读 |
| **上下分区** | VStack 将原文/译文分成上下两部分 |
| **自动滚动** | 使用 `ScrollViewReader` 确保新文本自动可见 |
| **占位提示** | 空文本时显示 "等待识别中..." / "等待翻译中..." |
| **圆角卡片** | 每个面板独立圆角，视觉层次清晰 |

### 6. 实际显示效果

```
┌─────────────────────────────────┐
│  ┌─────────────────────────┐   │
│  │ 你好，我是来自中国的     │   │  ← 上半部分：原文
│  │ 开发者。                 │   │
│  └─────────────────────────┘   │
│                                 │
│  ┌─────────────────────────┐   │
│  │ Hello, I'm a developer  │   │  ← 下半部分：译文
│  │ from China.              │   │
│  └─────────────────────────┘   │
│                                 │
│    ↑ 半透明黑色背景 ↑           │
└─────────────────────────────────┘
```

---

## 十、总结

| 概念 | 说明 |
|------|------|
| `final class` | 禁止继承的类 |
| `static let` | 类级别的单例 |
| `@Published` | 可观察属性，自动通知 UI 更新 |
| `private(set)` | 只读属性 |
| `guard` | 条件守卫，提前返回 |
| `AVPictureInPictureController` | iOS 画中画控制器 |
| `UIHostingController` | SwiftUI 与 UIKit 桥梁 |
| `ScrollViewReader` | 实现自动滚动 |
