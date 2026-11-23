# Agent Thread 运行态徽章

窗口默认在「Harness 配色」中并排展示 Codex、Claude、Pi Agent、OpenCode。四张卡同步播放同一种点阵动效。运行时，亮起的微孔取对应 Harness 的原生主题色，暗孔与圆底使用中性色。微孔按 5.25 pt 间距排在 9 × 9 网格上，上下左右四个轴端的孔与圆边相切，其余外缘微孔由同一个圆形蒙版裁切。点阵从 emoji 背后连续铺到圆边。切到「空闲」可同时看到四枚原始徽章。

| Harness | 浅色外观 | 深色外观 |
| --- | --- | --- |
| [Codex](../../app/macos/Sources/Plugins/Harnesses/Codex/CodexLogo.swift) | 靛蓝 | 长春花蓝 |
| [Claude](../../app/macos/Sources/Plugins/Harnesses/Claude/ClaudeLogo.swift) | 陶土橙 | 杏橙 |
| [Pi Agent](../../app/macos/Sources/Plugins/Harnesses/Pi/PiLogo.swift) | 紫罗兰 | 淡紫 |
| [OpenCode](../../app/macos/Sources/Plugins/Harnesses/OpenCode/OpenCodeLogo.swift) | 石墨灰 | 银白 |

点「微孔点阵」菜单可更换同步播放的动效。要在同一 Harness 下比较四种节奏，选择「点阵候选」，再从 Harness 菜单选择品牌。各款均为 44 pt 正圆，使用 21 pt emoji。启用 macOS「减弱动态效果」时，运行中的候选保留静态标记。[观看 Harness 配色录像](harness-colors.mp4) · [查看徽章边缘放大录像](dot-edge-detail.mp4)

| 点阵候选 | 观察位置与节奏 |
| --- | --- |
| 微孔点阵 | 原选方案。一列亮点沿对角线扫过，短暂停顿，2.8 秒一轮。 |
| 对开 | 亮点从中轴同时传向左右两侧，在两边收尾。3.1 秒一轮。 |
| 双拍 | 左上的一簇微孔短亮，右下的一簇稍后缓亮，随后留白。2.8 秒一轮。 |
| 折线 | 两枚对称亮点沿网格逐孔折行，各留一小截渐暗的尾迹。2.8 秒一轮。 |

四种节奏的同屏对照见配色录像末段。

从「点阵候选」菜单切换到「材质对照」，可与沿边绕行的游弧、反光缓移的拉丝钛、纬带依次接光的纬光以及原选微孔点阵比较。[材质对照录像](materials.mp4)

## X 动效参考

- Xchyler Drenth 的 *Thinking states* 在一个小圆内比较多种运动态。第一种用固定纬带依次接光，demo 的「纬光」保留这个动作，将对比度压低，为前景 emoji 留出层次。[X 原帖](https://x.com/xchylerdrenth/status/2072203766523363623)
- Shawn 的 *Dot matrix animations* 用同一套固定点位组合出多种循环。「微孔点阵」在 emoji 背后铺开网格，让一条斜向波前依次经过。[X 原帖](https://x.com/zzzzshawn/status/2047737258170835450) · [作者的可交互作品集](https://dotmatrix.zzzzshawn.cloud/)
- Sasha 的 *Whimsy Loaders* 展示了如何让少数像素形成可读的小动作。「微孔点阵」借用小颗粒的尺度，每轮结束留出停顿。运行材质均以 SwiftUI Canvas 自绘。[X 原帖](https://x.com/aleksksaa/status/2060045788676345888)

## 本机打开

在仓库根目录执行：

```sh
python3 demos/running-emoji-badge/build.py --open
```

产物为 `.build/running-emoji-badge/ThreadBadgeDemo.app`，可在 Finder 中双击。构建需要 macOS 26 和项目的 Swift 工具链。使用 `--skip-build` 可复用当前工作树已构建的原生模块。使用 `--capture` 会通过 ScreenCaptureKit 录制 demo 自身窗口，把 `preview.mp4` 写入同一产物目录。

## 比较条件

- [原生卡片](../../app/macos/Sources/Shared/PluginUI/Cards/HarnessThreadCard.swift)负责标题、模型、用量、摘要和徽章定位。四张卡片共用一份内存 fixture，计时固定为 1 分 24 秒。
- [生产徽章](../../app/macos/Sources/Shared/PluginUI/Cards/ThreadCardBrand.swift)绘制直径 44 pt 的圆底和 21 pt 的 🧭，距顶边 12 pt、右边 17 pt。空闲态与游弧直接复用生产徽章。其余候选通过已有徽章插槽绘制等大 emoji 及圆形底板，动画只绘制在 emoji 背后的材质层。
- 画布和卡片取 [Overview 调色板及 320 × 196 pt 单格](../../app/macos/Sources/Shared/PluginUI/Design/NativePalette.swift)，每张卡从其 Harness plugin 读取名称、logo 和自适应主题色，通过生产环境值传给徽章。四张卡片的光云调色板均为空。
- 构建使用仓库的 [NativeReplay](../../tools/verification/native_replay.py) 打包生产组件与资源。演示仅使用本地 fixture，独立于 Chief 进程和用户数据。

## 录像核对

Harness 配色录像在 Apple Silicon、macOS 26.5.1 上通过 `build.py --skip-build --capture --open` 取得。13.59 秒的 H.264 录像先展示四个 Harness 在深色外观下同步运行、切到空闲，再展示浅色外观下同步运行，最后切到 Claude 的四种节奏。录制版可执行文件 SHA-256 为 `24328120c9f47bb5527f9d88344d619948f62d02cd80db6d6f0fd8b121301f92`。在两种外观的录像中抽样四枚徽章，确认亮孔分别呈蓝、橙、紫和中性灰阶。中间空闲段的四枚徽章均静止。深浅外观各以 12 帧/秒抽样 2.9 秒，四种 Harness 在上、右、下、左四个轴端的 9 × 9 像素区域都观测到亮孔变化。放大录像截取该窗口中 Codex 徽章的 100 × 100 像素区域，按三倍最近邻缩放。

点阵候选录像对应提交 `b455062a`。在 Apple Silicon、macOS 26.5.1 深色外观下，通过 `build.py --skip-build --capture --open` 打开窗口并录得 10.14 秒、1408 × 1214 的 H.264 点阵录像。录制版可执行文件 SHA-256 为 `2075ddb798c3058b66319edaab9327b1d0723a84d8ae778282871367dee97136`。对四个徽章各自的 88 × 88 像素区域每秒抽取六帧，前后两段运行画面均有像素变化，中间空闲段四处均静止（RGB 单通道跨度阈值 18/255）。材质对照录像对应提交 `7c68211f`。两组使用同一版生产组件，来自 `01c6a17f`。
