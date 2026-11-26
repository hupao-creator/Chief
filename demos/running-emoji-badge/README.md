# Agent Thread 运行态徽章

## 微孔范围

打开窗口即可以原尺寸对照截图中的 Codex 卡片。四张卡均挂载正式运行态徽章，44 pt 圆底内的 21 pt 🎞️ 静止，Core Animation 在它背后扫亮 2 pt 微孔。左上是现状。其余三张在同一 5.25 pt 网格上把微孔延伸到卡面的留白处。

| 候选 | 在卡面上观察的位置 |
| --- | --- |
| A · 右上斜掠 | 从徽章向左掠过模型旁的留白，沿右边缘向下消散。 |
| B · 穿过行间 | 延伸到卡片上沿，沿右侧转入摘要行间。 |
| C · 漫游全卡 | 横穿摘要之间的空隙，扫到左侧和底边。 |

三档共用同一组弯曲轨迹、孔径、颜色和 2.8 秒周期。范围由沿轨迹向左、向下的覆盖距离控制。演示层位于正式卡片内容下方，按这张固定卡片的文字位置留白。勾选「静态对照」可在同一相位查看孔位。勾选「全部显示现状」会同时收回三张卡的外扩点阵，取消勾选即可原位比较。

[原生窗口截图](range.png) · [动态对照录像](range.mp4)

## 其他徽章对照

在候选组菜单选择「Harness 配色」，可并排查看 Codex、Claude、Pi Agent、OpenCode。四张卡同步播放同一种点阵动效。运行时，亮起的微孔取对应 Harness 的原生主题色，暗孔与圆底使用中性色。微孔按 5.25 pt 间距排在 9 × 9 网格上，上下左右四个轴端的孔与圆边相切，其余外缘微孔由同一个圆形蒙版裁切。点阵从 emoji 背后连续铺到圆边。切到「空闲」可同时看到四枚原始徽章，切到「完成」可查看带勾号的终态。

| Harness | 浅色外观 | 深色外观 |
| --- | --- | --- |
| [Codex](../../app/macos/Sources/Plugins/Harnesses/Codex/CodexLogo.swift) | 靛蓝 | 长春花蓝 |
| [Claude](../../app/macos/Sources/Plugins/Harnesses/Claude/ClaudeLogo.swift) | 陶土橙 | 杏橙 |
| [Pi Agent](../../app/macos/Sources/Plugins/Harnesses/Pi/PiLogo.swift) | 紫罗兰 | 淡紫 |
| [OpenCode](../../app/macos/Sources/Plugins/Harnesses/OpenCode/OpenCodeLogo.swift) | 石墨灰 | 银白 |

点「微孔点阵」菜单可更换同步播放的动效。要在同一 Harness 下比较四种节奏，选择「点阵候选」，再从 Harness 菜单选择品牌。各款均为 44 pt 正圆，使用 21 pt emoji。启用 macOS「减弱动态效果」时，运行中的候选保留静态标记。[观看 Harness 配色录像](harness-colors.mp4) · [查看徽章边缘放大录像](dot-edge-detail.mp4)

| 点阵候选 | 观察位置与节奏 |
| --- | --- |
| 微孔点阵 | 正式方案。一列亮点沿对角线扫过，短暂停顿，2.8 秒一轮。 |
| 对开 | 亮点从中轴同时传向左右两侧，在两边收尾。3.1 秒一轮。 |
| 双拍 | 左上的一簇微孔短亮，右下的一簇稍后缓亮，随后留白。2.8 秒一轮。 |
| 折线 | 两枚对称亮点沿网格逐孔折行，各留一小截渐暗的尾迹。2.8 秒一轮。 |

四种节奏的同屏对照见配色录像末段。

从「点阵候选」菜单切换到「材质对照」，可与沿边绕行的游弧、反光缓移的拉丝钛、纬带依次接光的纬光以及原选微孔点阵比较。[材质对照录像](materials.mp4)

## X 动效参考

- Xchyler Drenth 的 *Thinking states* 在一个小圆内比较多种运动态。第一种用固定纬带依次接光，demo 的「纬光」保留这个动作，将对比度压低，为前景 emoji 留出层次。[X 原帖](https://x.com/xchylerdrenth/status/2072203766523363623)
- Shawn 的 *Dot matrix animations* 用同一套固定点位组合出多种循环。「微孔点阵」在 emoji 背后铺开网格，让一条斜向波前依次经过。[X 原帖](https://x.com/zzzzshawn/status/2047737258170835450) · [作者的可交互作品集](https://dotmatrix.zzzzshawn.cloud/)
- Sasha 的 *Whimsy Loaders* 展示了如何让少数像素形成可读的小动作。「微孔点阵」借用小颗粒的尺度，每轮结束留出停顿。正式微孔点阵使用 Core Animation。其余材质候选用 SwiftUI Canvas 绘制。[X 原帖](https://x.com/aleksksaa/status/2060045788676345888)

## 本机打开

在仓库根目录执行：

```sh
python3 demos/running-emoji-badge/build.py --open
```

产物为 `.build/running-emoji-badge/ThreadBadgeDemo.app`，可在 Finder 中双击。构建需要 macOS 26 和项目的 Swift 工具链。使用 `--skip-build` 可复用当前工作树已构建的原生模块。使用 `--capture-range` 可在产物目录生成微孔范围的 `range.png` 与 `range.mp4`。使用 `--capture` 会通过 ScreenCaptureKit 录制 demo 自身窗口，把 `preview.mp4` 写入同一产物目录。

## 比较条件

- Harness 配色、点阵和材质三个候选组的[原生卡片](../../app/macos/Sources/Shared/PluginUI/Cards/HarnessThreadCard.swift)负责标题、模型、用量、摘要和徽章定位。四张卡片共用一份内存 fixture，计时固定为 1 分 24 秒。
- [生产徽章](../../app/macos/Sources/Shared/PluginUI/Cards/ThreadCardBrand.swift)绘制直径 44 pt 的圆底和 21 pt 的 🧭，距顶边 12 pt、右边 17 pt。「微孔点阵」、空闲与完成态均使用卡片内置徽章。游弧叠加在原生徽章上，其余运行候选通过已有徽章插槽绘制等大 emoji 及圆形底板，动画只绘制在 emoji 背后的材质层。
- 画布和卡片取 [Overview 调色板及 320 × 196 pt 单格](../../app/macos/Sources/Shared/PluginUI/Design/NativePalette.swift)，每张卡从其 Harness plugin 读取名称、logo 和自适应主题色，通过生产环境值传给徽章。卡面使用中性底色。
- 构建使用仓库的 [NativeReplay](../../tools/verification/native_replay.py) 打包生产组件与资源。演示仅使用本地 fixture，独立于 Chief 进程和用户数据。

## 录像核对

微孔范围在 Apple Silicon、macOS 27.2.1、Swift 6.3.2 上使用 `python3 demos/running-emoji-badge/build.py --skip-build --capture-range --open` 录制。窗口为 1408 × 1214 像素，持续 9.18 秒。生产模块来自 `efc2113d`，录制制品的可执行文件 SHA-256 为 `6b93df370bdfefae78125c1d9050cf9ae57634fd99894e90a129e6233155c4f4`。

对运行段和恢复播放段每秒抽取八帧，以 RGB 单通道跨度超过 18/255 判定变化。标题旁的取样区仅 A、B、C 有变化，第一、二行摘要之间仅 B、C 有变化，左下底边仅 C 有变化。静态对照段三处取样区均静止。另在交互窗口实际点按两个复选框，四卡均回到「仅徽章内」，关闭复选框后恢复三档候选。取样与交互仅覆盖此固定卡面的 demo。

Harness 配色录像在 Apple Silicon、macOS 26.5.1 上通过 `build.py --skip-build --capture` 取得，时长 15.80 秒，分辨率 1408 × 1214。深色运行、空闲、浅色运行之后，窗口展示 Claude 的四种节奏，最后四张卡均切到带勾号的完成态。录制版可执行文件 SHA-256 为 `a5ccfeb0e2df93c625583d52a0ae644b8fe0825a8a1daf81e39a07ac75aa4776`。

对正式徽章的窗口录像逐帧抽样，深浅两种外观下各 Harness 的四个轴端均有亮度变化。四张卡在空闲段均静止，完成段各徽章变化不超过 1 个像素（RGB 单通道跨度阈值 18/255）。三倍放大录像来自原窗口的 100 × 100 像素区域。另用隔离 Runtime 挂载正式 Overview，预热前观测到四枚有效动画徽章、零个光云视图。前台窗口及热状态条件未满足，本次未取得性能采样结果。

点阵候选录像对应提交 `b455062a`。在 Apple Silicon、macOS 26.5.1 深色外观下，通过 `build.py --skip-build --capture --open` 打开窗口并录得 10.14 秒、1408 × 1214 的 H.264 点阵录像。录制版可执行文件 SHA-256 为 `2075ddb798c3058b66319edaab9327b1d0723a84d8ae778282871367dee97136`。对四个徽章各自的 88 × 88 像素区域每秒抽取六帧，前后两段运行画面均有像素变化，中间空闲段四处均静止（RGB 单通道跨度阈值 18/255）。材质对照录像对应提交 `7c68211f`。两组使用同一版生产组件，来自 `01c6a17f`。
