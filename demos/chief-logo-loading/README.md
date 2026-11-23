# Chief logo 加载动效

三段动效取自同一张[应用图标原画](../../design/chief-logo.webp)。表中以原生[启动加载标记](../../app/macos/Sources/Host/Shell/NativeLoadingMark.swift)的 96 pt 布局尺寸并排展示。点开名称可查看 384 × 384 的透明循环 WebP。三段均以每帧 40 ms 播放，象牙白底板和外圈透明区域随图保留。

| [颠勺](toss.webp) | [三拍接力](relay.webp) | [锅底余火](ember.webp) |
| :---: | :---: | :---: |
| <img src="toss.webp" width="96" height="96" alt="锅沿一挑，三个 Agent 先后弹起再落回锅中"> | <img src="relay.webp" width="96" height="96" alt="Codex、Claude Code 和 Pi 从左到右依次轻跳"> | <img src="ember.webp" width="96" height="96" alt="金色高光沿橙色锅底掠过，两缕热气缓缓升起"> |
| 2.4 秒 · 60 帧 | 1.8 秒 · 45 帧 | 3.6 秒 · 90 帧 |

- **颠勺**以锅柄为转轴。锅沿先下压再上挑，三个 Agent 错开离锅，达到最高点时展开成原图构图。落回锅沿时，锅身轻轻回弹。
- **三拍接力**固定锅身，按 Codex、Claude Code、Pi 的顺序，每隔 0.6 秒起一拍。轮到的 Agent 上移并恢复全色，其余保留轮廓。
- **锅底余火**固定锅和三个 Agent，把移动的暖光限制在原图的橙色锅底内。两缕热气错开升起，淡出后各自重新出现。

这些素材用于动效选型。产品启动界面的实现见 [NativeRuntimeSurface](../../app/macos/Sources/Host/Shell/NativeRuntimeSurface.swift)。
