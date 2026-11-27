# 演示能力清单

本目录包含当前源码可定位的独立预览。可构建状态来自 build.py 的输入、参数和
生产模块检查。各 App 的实际构建和窗口回放证据见对应目录。
内存 fixture 只能展示其状态，不能认证 Runtime 持久化、模型、语音、真实输入和回执。
截图或 headless 数据导出不等于 e2e 验收；已有证据只覆盖其记录的源码/制品身份。

| 目录 | 当前边界 |
| --- | --- |
| [chief-logo-loading](chief-logo-loading/README.md) | Chief 图标加载动效与四种颠勺候选，含整页加载与 Overview 空态的同窗原生回放 |
| [empty-state-native-candidates](empty-state-native-candidates/README.md) | 复用睡锅，比较 Running 无结果时的最近完成会话与 Unread 无结果时的最近已读会话 |
| [execution-handoff](execution-handoff/README.md) | 独立交互/材质方案 fixture；生产行为见所属模块 |
| [landing-setup](landing-setup/README.md) | 链接生产组件的交互 fixture；不连接真实 Runtime/账户，无自动验收 |
| [moku-gradient-material](moku-gradient-material/README.md) | 链接生产组件的交互 fixture；不连接真实 Runtime/账户，无自动验收 |
| [moku-landing](moku-landing/README.md) | 链接生产组件的交互 fixture；不连接真实 Runtime/账户，无自动验收 |
| [moku-mention-transition](moku-mention-transition/README.md) | 链接生产组件的交互 fixture；不连接真实 Runtime/账户，无自动验收 |
| [moku-panel-transition](moku-panel-transition/README.md) | 隔离回放 Agent/Report Dock 动画、AppKit 输入和待确认草稿；本地 Host 回放通过 Go transport 核对回执，使用 fixture 命令结果 |
| [moku-thinking-orbit](moku-thinking-orbit/README.md) | 链接生产组件的交互 fixture；不连接真实 Runtime/账户，无自动验收 |
| [report-thread](report-thread/README.md) | 链接生产组件的交互 fixture；不连接真实 Runtime/账户，无自动验收 |
| [running-emoji-badge](running-emoji-badge/README.md) | 固定正式徽章，在原尺寸 Agent Thread 卡片上比较三档边缘反光与微孔显现范围，可打开 X 动效参考；附窗口截图和录像，也可切换 Harness 配色、状态、点阵与材质 |
| [settings-navigation](settings-navigation/README.md) | 链接生产组件的交互 fixture；不连接真实 Runtime/账户，无自动验收 |
| [settings-tabs](settings-tabs/README.md) | 独立交互/材质方案 fixture；生产行为见所属模块 |
| [super-thread-carousel](super-thread-carousel/README.md) | 链接生产组件的交互 fixture；不连接真实 Runtime/账户，无自动验收 |
| `tag-cloud-loading/` | 构建不可用：build.py 引用缺失的 NativeContentHost.swift；不提供验证覆盖 |
| [tag-filter-morph](tag-filter-morph/README.md) | 链接生产组件的交互 fixture；不连接真实 Runtime/账户，无自动验收 |
| [tag-glass-morph](tag-glass-morph/README.md) | 独立交互/材质方案 fixture；生产行为见所属模块 |
| [tag-space-haptics](tag-space-haptics/README.md) | 在隔离的 Overview 窗口手动体验触觉反馈；无窗口回放核对生产路由的选中项和请求次数 |
| [tag-selection-preview](tag-selection-preview/README.md) | 独立 HTML 样式预览；不代表生产组件 |
| [thread-card-cloud](thread-card-cloud/README.md) | 构建不可用：build.py 引用缺失的 NativeContentHost.swift；不提供验证覆盖 |
| `thread-card-glass-timeline/` | 构建不可用：build.py 引用缺失的 NativeContentHost.swift；不提供验证覆盖 |
| [thread-panel-transition](thread-panel-transition/README.md) | 链接生产组件的交互 fixture；不连接真实 Runtime/账户，无自动验收 |

当前产品事实归属见[索引](../tools/verification/facts.md)，验证分工见[策略](../scripts/ci/verification-policy.md)。
