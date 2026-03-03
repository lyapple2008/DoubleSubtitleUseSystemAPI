# ContentView.swift 代码详解

这是一份面向 Swift/iOS 开发小白的完整指南。

---

## 一、文件整体结构

```
ContentView.swift 包含两部分：
├── 1. ContentView (SwiftUI 视图) - 第 1-111 行
└── 2. ContentViewModel (业务逻辑) - 第 114-604 行
```

---

## 二、导入的框架

```swift
import SwiftUI      // Apple 的现代 UI 框架
import AVFoundation // 音视频处理
import ReplayKit    // 屏幕录制/系统音频捕获
```

---

## 三、SwiftUI 基础语法

### 1. `@State` - 视图内部状态

```swift
@State private var triggerSystemPicker = false
```
- `private` - 私有属性
- `@State` - SwiftUI 专用的属性包装器，表示"视图内部可变的临时状态"
- 当值改变时，SwiftUI 会自动重新渲染视图

### 2. `@StateObject` - 视图模型（重点！）

```swift
@StateObject private var viewModel = ContentViewModel()
```
- 创建 ViewModel 实例
- **关键区别**：
  - `@State` - 用于简单数据类型（String, Bool, Int）
  - `@StateObject` - 用于 class 类型的 ViewModel

### 3. `$` 绑定语法

```swift
LanguageSelectorView(
    sourceLanguage: $viewModel.sourceLanguage,  // $ 符号创建双向绑定
    targetLanguage: $viewModel.targetLanguage
)
```
- `$viewModel.sourceLanguage` - 传递**引用**而非值
- 当子视图修改值时，父视图的 viewModel 也会更新

---

## 四、SwiftUI 视图结构

### `some View` 返回类型

```swift
var body: some View {
    // body 必须返回一个遵循 View 协议的类型
    VStack(spacing: 0) {
        // ... 内容
    }
}
```

### 常见布局容器

| 容器 | 作用 |
|------|------|
| `VStack` | 垂直排列（vertical） |
| `HStack` | 水平排列（horizontal） |
| `ZStack` | 叠加排列（z-axis） |
| `Spacer()` | 占据剩余空间 |

### 修饰器链

```swift
Button(action: {...}) {
    Text("开始识别")
        .font(.headline)           // 字体
        .frame(maxWidth: .infinity) // 宽度
        .padding()                  // 内边距
        .background(Color.blue)    // 背景色
        .foregroundColor(.white)   // 文字颜色
        .cornerRadius(12)         // 圆角
}
```

---

## 五、ViewModel 部分

### `@Published` - 发布属性（配合 ObservableObject）

```swift
@Published var sourceLanguage: LanguageOption = .defaultSource
```
- 当值改变时，自动通知所有观察者（SwiftUI 视图）
- 类似于 Android 的 LiveData

### `@MainActor` - 主线程执行

```swift
@MainActor
final class ContentViewModel: NSObject, ObservableObject {
```
- 保证所有成员都在主线程执行
- UI 更新必须在主线程

### `NSObject` 继承

```swift
class ContentViewModel: NSObject, ObservableObject
```
- 继承 `NSObject` 是为了使用 `Timer` 和其他 Objective-C 兼容功能

---

## 六、关键 Swift 语法

### 1. 闭包（Closure）

```swift
Button(action: {
    viewModel.startRecording {
        triggerSystemPicker = true
    }
}) { ... }
```
- `action: { ... }` - 点击时执行的代码块
- `viewModel.startRecording { ... }` - 回调闭包参数

### 2. `@escaping` - 逃逸闭包

```swift
func startRecording(onReadyToShowPicker: @escaping () -> Void)
```
- 闭包可能在函数返回后才执行
- 需要用 `@escaping` 标记

### 3. `[weak self]` - 避免循环引用

```swift
Task { [weak self] in
    guard let self = self else { return }
    // 使用 self
}
```
- 防止内存泄漏（闭包持有 self，self 不持有闭包）

### 4. `Task { @MainActor in }` - 并发处理

```swift
Task { @MainActor in
    self.performPrepareAndShowPicker(...)
}
```
- 异步执行代码
- `@MainActor` 确保在主线程更新 UI

### 5. Protocol 协议

```swift
extension ContentViewModel: AudioCaptureDelegate {
    nonisolated func audioCaptureDidStart() { ... }
}
```
- 类似 Java 的接口
- `nonisolated` - 允许在非主线程调用

### 6. 可选类型（Optional）

```swift
@Published var currentSubtitle: SubtitleItem?  // ? 表示可选
```
- `?` - 值可以是 `nil`
- 使用 `?.` 或 `if let` 解包

### 7. `guard` - 条件守卫

```swift
guard granted else {
    // 权限未授予时执行
    Task { @MainActor in
        self?.showError(message: "需要语音识别权限")
    }
    return  // 提前退出函数
}
```
- 条件不满足时执行 else 分支并提前返回
- 类似于 if-else，但更简洁，强制要求 return

---

## 七、startRecording 函数详解（第 167-179 行）

### 原始代码

```swift
func startRecording(onReadyToShowPicker: @escaping () -> Void) {
    requestPermissions { [weak self] granted in
        guard granted else {
            Task { @MainActor in
                self?.showError(message: "需要语音识别权限")
            }
            return
        }
        Task { @MainActor in
            self?.performPrepareAndShowPicker(onReadyToShowPicker: onReadyToShowPicker)
        }
    }
}
```

### 中文翻译

```swift
// 函数：开始录制
// 参数：onReadyToShowPicker - 一个闭包参数，表示"准备好显示系统选择器时"要执行的代码
func startRecording(onReadyToShowPicker: @escaping () -> Void) {

    // 调用 requestPermissions 请求权限
    // 参数是一个闭包：{ granted in ... }
    // granted 是权限是否授予的布尔值
    requestPermissions { [weak self] granted in

        // guard：权限未授予时执行
        guard granted else {
            // 创建一个异步任务，在主线程执行
            Task { @MainActor in
                // self?. 可能为空的调用
                self?.showError(message: "需要语音识别权限")
            }
            // 提前返回，不再执行后续代码
            return
        }

        // 权限已授予，创建异步任务
        Task { @MainActor in
            // 调用准备方法，传入 onReadyToShowPicker 闭包
            self?.performPrepareAndShowPicker(onReadyToShowPicker: onReadyToShowPicker)
        }
    }
}
```

### 涉及的 Swift 语法

| 语法 | 含义 |
|------|------|
| `@escaping () -> Void` | 逃逸闭包参数（函数返回后闭包仍可能被调用） |
| `{ [weak self] granted in` | 闭包捕获列表，使用弱引用避免循环引用 |
| `guard granted else { ... }` | 条件守卫，不满足时执行 else 并提前返回 |
| `self?.showError(...)` | 可选链调用（self 可能为 nil） |
| `Task { @MainActor in ... }` | Swift 并发，在主线程执行异步任务 |
| `onReadyToShowPicker: onReadyToShowPicker` | 将闭包参数传递给下一个函数 |

### 执行流程图

```
用户点击「开始识别」按钮
           │
           ▼
┌──────────────────────────────┐
│  startRecording() 被调用      │
│  传入闭包 onReadyToShowPicker │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│  requestPermissions()        │
│  请求语音识别权限              │
└──────────────┬───────────────┘
               │
       ┌───────┴───────┐
       ▼               ▼
  权限已授予        权限被拒绝
       │               │
       ▼               ▼
┌──────────────┐  ┌────────────────────┐
│ Task {       │  │ Task {             │
│   @MainActor │  │   @MainActor       │
│   self?.     │  │   self?.showError   │
│   perform... │  │ }                  │
│ }            │  └────────────────────┘
└──────────────┘
       │
       ▼
┌──────────────────────────────────┐
│  performPrepareAndShowPicker()    │
│  1. 配置 delegate                 │
│  2. 配置语音识别器语言             │
│  3. 启动等待广播开始               │
│  4. 执行 onReadyToShowPicker()    │
│     (触发系统弹窗)                │
└──────────────────────────────────┘
```

### 关键点总结

1. **`@escaping`** - 这个闭包会被"保存"下来，在 `performPrepareAndShowPicker` 后面才调用，所以需要 `@escaping`

2. **`[weak self]`** - 防止闭包和 self 之间产生循环引用（内存泄漏）

3. **`guard else`** - Swift 的提前返回语法，类似于 if-else 但更简洁

4. **`Task { @MainActor }`** - Swift 的现代并发方式，确保 UI 操作在主线程

---

## 八、数据流图示

```
┌─────────────────────────────────────────────────────────────┐
│                        ContentView                          │
│  ┌─────────────┐  ┌──────────────────┐  ┌───────────────┐  │
│  │ Language    │  │ SubtitleDisplay  │  │ Buttons       │  │
│  │ Selector    │  │ View              │  │               │  │
│  └──────┬──────┘  └────────┬─────────┘  └───────┬───────┘  │
│         │                  │                     │          │
│         └──────────────────┼─────────────────────┘          │
│                            │                                  │
│                     ┌──────▼──────┐                          │
│                     │ @StateObject │                          │
│                     │ viewModel    │                          │
│                     └──────┬──────┘                          │
└────────────────────────────┼────────────────────────────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
    ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
    │  Audio     │  │ Speech      │  │ Translation │
    │  Capture   │  │ Recognition │  │ Manager     │
    │  Manager   │  │ Manager     │  │             │
    └─────────────┘  └─────────────┘  └─────────────┘
```

---

## 九、总结

| 概念 | 说明 |
|------|------|
| `@State` | 视图内部状态 |
| `@Published` | ViewModel 的可观察属性 |
| `@StateObject` | 创建 ViewModel 实例 |
| `$` 绑定 | 双向数据绑定 |
| `some View` | SwiftUI 返回类型 |
| `@escaping` | 逃逸闭包 |
| `[weak self]` | 防止循环引用 |
| `Task { }` | 异步并发 |
