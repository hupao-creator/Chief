# 全局 Voice Mode 原生交互 Demo

![原生录屏四帧，从左到右为待机、眼睛向右瞥、蓝球与 Bar 相连、球完全分离。](preview.png)

在 macOS 26 或更高版本上，从仓库根目录构建并打开独立窗口。

```sh
python3 demos/global-voice-mode/build.py --open
```

应用在 `.build/global-voice-mode/Chief Voice Mode.app`，也可以直接双击打开。原型用固定对白和本机合成的中文回复模拟通话，麦克风保持关闭，可以离线体验。文字和会话状态保存在内存中，退出应用即清空。

## 试一遍

1. 在概览底部长按 Chief Bar 半秒。Chief 的眼睛向右轻瞥，右眼略微抬起，望着球即将出现的位置。准备好时双眼回正，球从右端分离。这一刻已经可以说话，松手后通话继续。
2. 轻点 Bar 写字，选中几个字。文字框展开后，长按左侧眼睛也能开启语音，选区和键盘焦点保留。通话中再次长按可继续当前通话。
3. 单击球静音，再单击恢复收音。球会留在原位，静音时云纹褪色。在「语音演示 → 模拟说一句」可试听 Chief 的本地回复。回复过程中单击球可以切换麦克风，正在播放的回复继续，菜单中的「打断回复」可停止播放。
4. 打开「整理本周发布说明」。语音球随 Bar 移到 Claude 任务列，保持在输入框右侧。文字发给 Claude。返回概览后可继续原来的 Chief 草稿和通话。
5. 右键点球退出语音模式，球收回 Bar。触控板可用辅助点按，或按住 Control 点按。「语音演示」菜单的 ⇧⌘V 可开始通话、取消仍在准备中的连接或退出通话。

按住期间把指针拖离可取消手势。编辑器中的文字选择和发送按钮各自处理鼠标。窗口缩窄时，任务列为球预留空间。

## 语音球的外观

参考的是桌面 App 里与 Codex 交谈时的默认蓝色语音球。上半部为钴蓝，靠近下缘有一条柔和的浅蓝白色云带。聆听时云带缓缓起伏，回复时波峰升高并横向流动。这个 demo 用原生代码重新绘制，球缩到适合 Chief Bar 的尺寸。静音时降低饱和度，待回复结束后静止，是本原型的处理。[OpenAI 桌面 Voice 指南](https://learn.chatgpt.com/docs/features/voice) · [官方视频中的 Codex 演示](https://www.youtube.com/watch?v=E0ZMOschrTU&t=39s)

外观对照来自本机桌面客户端 `26.1120.50957`（build `30866`）。在 `ChatGPT.app/Contents/Resources/app.asar` 内，`webview/assets/async/324381.d0f8b10e2b.js` 把语音状态交给 `317638.202af12185.js` 的 `HorizonVoiceOrbController`。对照帧由这个原版渲染器离线生成。demo 自行绘制纹理，用示例输入点亮内圈，云带随示例输入和回复中较强的电平起伏。[绘制代码](../../app/macos/Sources/Host/MokuScene/VoiceOrb.swift)

## 实现与回放

原型和正式工作区共用语音球、准备表情和鼠标交互。窗口挂载生产的 `NativeMokuScene`、`NativeMokuDock`、原生编辑器及 Claude 标识。Bar 和直径 40 pt 的球共用一个 SwiftUI `GlassEffectContainer`，各有稳定的 `glassEffectID`，在同一水平中线上从相叠移至相距 16 pt。系统根据两块表面的距离绘制玻璃连接。启用「减弱动态效果」时，球直接就位。启用「降低透明度」时使用实色底。[玻璃与布局](../../app/macos/Sources/Host/MokuScene/VoiceDock.swift) · [Apple 的自定义 Liquid Glass 指南](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)

按满半秒发起连接，提早松手进入文字输入。会话进入聆听后球才出现。全局通话的可视反馈由球承担。样例回复使用 macOS 的 Tingting 声音预先生成。[按压手势](../../app/macos/Sources/Host/MokuScene/VoiceBarPress.swift) · [工作区](Workspace.swift) · [语音菜单](Demo.swift) · [示例会话](VoiceSession.swift)

在可用的 macOS 图形会话中运行窗口回放。构建、链接和回放共用桌面独占锁。验证指定提交时，使用下方命令重新编译生产模块。已有本工作树的 Debug Chief 模块时，可用 `--skip-build` 本地调试；此时报告记录驱动版本、可执行文件哈希和复用标记，生产模块版本留空。

```sh
python3 demos/global-voice-mode/build.py --replay
```

[回放](Replay.swift)向窗口投递鼠标事件，核对球首次出现时已进入聆听、单击静音或恢复、右键退出，以及通话中的焦点、选区、草稿和任务文字接收方。它比较模拟发言前后的窗口文本和附属窗口，并在概览、展开的输入框、任务列和缩放后测量球与实际 Bar 的位置。回放使用独立的临时应用标识。结果、截图和录下分离、静音及回收的主窗口视频 `voice-glass.mp4` 写入 `.build/global-voice-mode/evidence/`。
