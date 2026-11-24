# Chief logo 加载动效

各段动效取自同一张[应用图标原画](../../design/chief-logo.webp)。下表并排展示动作草图。点开名称可查看 384 × 384 的透明循环 WebP。动画按 25 fps 采样。

| [颠勺](toss.webp) | [三拍接力](relay.webp) | [锅底余火](ember.webp) |
| :---: | :---: | :---: |
| <img src="toss.webp" width="120" height="120" alt="锅沿一挑，三个 Agent 先后弹起再落回锅中"> | <img src="relay.webp" width="120" height="120" alt="Codex、Claude Code 和 Pi 从左到右依次轻跳"> | <img src="ember.webp" width="120" height="120" alt="金色高光沿橙色锅底掠过，两缕热气缓缓升起"> |
| 2.4 秒 · 60 帧 | 1.8 秒 · 45 帧 | 3.6 秒 · 90 帧 |

- **颠勺**以锅柄为转轴。锅沿先下压再上挑，三个 Agent 错开离锅，达到最高点时展开成原图构图。落回锅沿时，锅身轻轻回弹。
- **三拍接力**固定锅身，按 Codex、Claude Code、Pi 的顺序，每隔 0.6 秒起一拍。轮到的 Agent 上移并恢复全色，其余保留轮廓。
- **锅底余火**固定锅和三个 Agent，把移动的暖光限制在原图的橙色锅底内。两缕热气错开升起，淡出后各自重新出现。

## 颠勺的四种抛接方式

| [A · 低抛双颠](toss-variants/double.webp) | [B · 高抛慢接](toss-variants/high.webp) | [C · 沿锅翻炒](toss-variants/rim.webp) | [D · 逐个抛接](toss-variants/solo.webp) |
| :---: | :---: | :---: | :---: |
| <img src="toss-variants/double.webp" width="120" height="120" alt="锅沿连续挑两次，第二次稍高"> | <img src="toss-variants/high.webp" width="120" height="120" alt="三个 Agent 在一次高抛的顶点展开"> | <img src="toss-variants/rim.webp" width="120" height="120" alt="三个 Agent 沿锅沿向右滑，再从上方翻回左边"> | <img src="toss-variants/solo.webp" width="120" height="120" alt="锅身连续点动，依次抛起蓝、橙、黑三个标记"> |
| 1.6 秒 | 3.2 秒 | 2.4 秒 | 3.2 秒 |

双颠的两次抛接共用一次短停顿。高抛在顶点放慢，使三个标记充分展开。沿锅翻炒让每个标记轮流经过同一条弧线。逐个抛接时，其余两个标记贴着锅沿随锅身起伏。

## 原生加载标记

启动、打开对话和其他整页加载界面共用颠勺动效。锅和三个角色取自应用图标原画。锅口随锅柄下压、上挑，角色依次离锅，落回锅口后锅身轻轻回弹。开启「减少动态效果」时，三个角色停在锅中。启动状态由 [NativeRuntimeSurface](../../app/macos/Sources/Host/Shell/NativeRuntimeSurface.swift) 控制。

[原生回放](Replay.swift) 在同一个 900 × 560 pt 内容区挂载真实启动界面，在注入会话目录后显示 Overview 的「没有运行中的会话」组件。回放录制连续两个以上周期，切换窗口内的「减少动态效果」与外观，并保存开启减少动态效果后相隔约一秒的两个画面。截图校验对比两张静帧、恢复动效后的画面及两只锅的可见宽度。运行时使用独立的临时 profile。

[等比例截图对照](evidence/comparison.png) · [原生窗口录像](evidence/window.mp4)

```sh
swift build --package-path app/macos --product Chief
python3 demos/chief-logo-loading/replay.py .build/loading-replay/current
```
