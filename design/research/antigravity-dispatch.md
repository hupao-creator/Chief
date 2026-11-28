# Antigravity 普通任务派发审查

2026-11-28。范围从 Chief 选择派发目标开始，到协调者收到同一普通 Agent Thread 的终态为止。Chief 比较基线为本地 `main` 的 `006dd4d2f2c1811e1e1212e1f4ed5a9fdd2d4acf`（#420）。基线的 Go 和 Swift 注册表只有 Codex、Claude、Pi 和 OpenCode。实际检出的对象在 Go、Swift 和启动命令中分别写作 `agy`、Antigravity 和 `agy acp --stdio`。没有支持将 HYCUI 关联到这条路径的项目证据。

## 找回的源

| 本地引用 | 与基线的关系 | 差异及历史验证边界 |
| --- | --- | --- |
| `refs/heads/archive/agy-antigravity-acp`，`50e94add07cbb595c835d87d11eefc314bebc358` | `agy-harness-adapter` 的已登记工作树指向同一 SHA。与基线共有父提交 `b9c72b7d0d5ed01fb6efc16f14a51ce628917528`，候选独有 1 个提交，基线独有 83 个。 | 33 个文件，增加 2005 行、删除 37 行。包含 Go ACP、Swift reader、注册、旧设置补键、PBT 和需要本地 DeepSeek driver 的回放。该提交没有附带可认证本次构建的运行结果。 |
| reflog `0d14a0d834d032749c0c09b6dd107c00e5d217c6`、`e144b8934ae55a806d788bc7097580166f319b05` | 两者与归档 tip 的父提交相同，是同一项修改的修订稿。 | 从首稿到中稿涉及 8 个文件，增加按执行读取、保存模型和桌面挂载回放。中稿到 tip 仅改动回放及其说明，收紧授权检查。各稿都没有随提交保存的独立实测成绩。 |
| `isolate-agy-support` 对应的工作树 HEAD `53ab597db9fc7b87cd9b6a2cf3698582edba7eba` | 提交内容是 Tag Space 滑动修正。该树的 Harness 目录只有原来的四项。 | 没有可复用的 AGY 注册或回放。 |

检索包含现有分支、远端跟踪引用、标签、各已登记工作树的 Git 元数据、reflog、五份 stash 的变更及项目文档，并核对 Chief 官方 PR 元数据。未发现归档 tip 已进入基线、标签或已发布 PR 的证据。当时的非语音 WIP stash 为 `501a237bd7824e8dc41796cc8c2d0d95a74416e7`，语音修复工作树登记在同一比较基线；两者独立。直接对归档做合并预演会在 SwiftPM、架构检查、Harness/Moku 手册和两个验证索引产生六处冲突。

在本仓库任一含这些对象的 checkout 中，可用以下只读命令复查原件和行号。

```sh
git show --stat 50e94add07cbb595c835d87d11eefc314bebc358
git diff 0d14a0d8 e144b893 --stat
git diff e144b893 50e94add --stat
git show 50e94add:internal/plugins/harness/agy/settings.go | nl -ba
git rev-list --left-right --count 006dd4d2...50e94add
```

## 历史问题和本期处理

下表的归档文件行均相对于 `50e94add`。Go 适配器文件位于 `internal/plugins/harness/agy/`，Swift 阅读器位于 `app/macos/Sources/Plugins/Harnesses/Agy/`。落地依次需要可辨认的原生引擎、可发布的目标和模型、可归属的执行与终态，最后才是更丰富的会话能力。

| 优先级 | 原文件及触发条件 | 本期处理或后续条件 |
| --- | --- | --- |
| 阻塞 | `internal/plugins/harness/agy/settings.go:169,200,212`。归档靠一分钟的进程内目录和 `modelId`。基线 `internal/services/moku/context.go:26` 取静态创建契约，`internal/services/dispatchconfig/projection.go:52,66` 需要可用 CLI 与 `id` 或 `value`。直接移植时，已安装的 AGY 仍不能给协调者发布模型选项。 | 注册静态仅模型参数、发布标准目录，执行时再次核对实际模型。在原生 Codex 模型请求里检查发布的选项，并用其中的非默认模型创建 Thread。 |
| 阻塞 | `settings.go:41,55` 只凭 PATH 文件标为已安装，探测与手填可执行路径使用不同来源。`acp.go:214` 仅检查协议版本。同名程序、错误引擎、1.5.0 白名单版会造成假可用。 | 探测和执行共用 Chief 解析到的 `agy`，核对原生身份、ACP v1、稳定版本 ≥1.5.1 及实际会话能力。进程参数由适配器构造。原型里本地手填可执行路径的私有配置不在已分发 Alpha 契约内。 |
| 阻塞 | 基线 `internal/core/runtime/runtime.go:156` 仅为全新 profile 初始化字典，`settings.go` 的保存验证要求每个注册 Harness 有一个键。升级后第一次保存或选择 AGY 可能失败。 | 复用归档的启动补键，按现有事务和 revision 规则只补缺项；原有目标与角色配置完整保留。PBT 在每份生成的配置上依次补零项、一项和两项，每批连续重开两次，比对整份设置与 revision。 |
| 高 | `thread.go:234,255` 在等待 prompt 前停用启动超时。保持管道打开却无进展的子进程能让普通任务一直运行。`events.go:226` 的早到授权应答有窗口，原生已出请求，发送方尚未标记 prompting。 | 设准备期限和按进展续期的 15 分钟等待，等待人答复时暂停计时。按已发布请求、原始选项和执行 ID 应答。Stop 只取消被选中执行，原生无响应时回收自己的进程。 |
| 高 | `thread.go:136` 与 `AgyThread.swift:76` 丢失已准入的手动追加行 ID，面板重开和链接可能找不到用户刚发的那一行。 | v1 执行可选保存 `userRowId`，新行使用原始 ID，旧行保留原显示锚点。按 execution ID 读回独立的 prompt、模型、内容与状态。 |
| 高 | `outcome.go:59,80` 与 `acp.go:81` 涉及原生异常语义。1.5.17 可把服务错误作为文本发出，再以 `end_turn` 结束。归档按 `GEMINI_HOME` 查库；临时 home 实测原生 CLI 将会话写在 `~/.gemini`，另设的 `GEMINI_HOME` 没有收到轨迹。 | 读取与默认启动参数配套的原生目录，只查本会话新增末步类型 17。回放设置干扰目录并注入 HTTP 400，检查子任务及协调者看到 failed。数据库不可读、原生格式变化、错误后又追加其他类型时仍可能被判 completed。 |
| 中 | `tools/e2e/agy/run.py:85,251` 依赖外部 driver、账号、额度和模型的工具调用决策。其他提交的回放不能作为当前组合的证据。 | 使用真实 Codex、真实 AGY 和两个本机模型服务，验证确切回复、恢复、一次性授权与拒绝后的文件结果、停止和失败。可选隔离桌面回放在挂载的设置页启用目标并保存，重开后从项目的 Overview 卡片进入阅读器。真实账号、鼠标交互、性能独立验收。 |

## T3 Code 对照

官方仓库 `pingdotgg/t3code` 的 `main` 固定在 `40b0a98a2057b7de511807f12fef8ac8c30077fe`。#32503 将原生 `agy` 接入已有 Antigravity provider 的自定义可执行路径（合并 `7b680b616f6d35fa3ba16c3dbdd6f9146b1f3a92`）；#37916 增加 PATH 回退（`0058a4abb3adda91313c8e22d9a183cac0c4b8d5`）；#43087 要求使用真实客户端标识并处理 1.5.0 的限制（`5e37e6db563e0cb45d5f975241c923440397411c`）。Chief 原稿引用的 `c991a91ec6def51242fc9bdb8205b4be098d9b74` 是较早截面，早于最后这项修复。已读下列源码和测试，T3 自身测试套件未在本机执行。[官方仓库](https://github.com/pingdotgg/t3code) · [CLI PR](https://github.com/pingdotgg/t3code/pull/32503) · [PATH PR](https://github.com/pingdotgg/t3code/pull/37916) · [版本修复 PR](https://github.com/pingdotgg/t3code/pull/43087)

| 路径 | T3 Code 固定源码与测试 | Chief 采用的做法 |
| --- | --- | --- |
| 启动和探测 | 自定义、托管与 PATH 来源分开。对托管下载核对原生身份、预期版本和能力。配置 `acp --gemini-dir … --app-data-dir antigravity-acp`，默认使用 stdio。[查找](https://github.com/pingdotgg/t3code/blob/40b0a98a2057b7de511807f12fef8ac8c30077fe/apps/server/src/provider/AntigravityInstallation.ts#L637-L666) · [身份验证](https://github.com/pingdotgg/t3code/blob/40b0a98a2057b7de511807f12fef8ac8c30077fe/apps/server/src/provider/AntigravityInstallation.ts#L786-L799) · [真实 CLI 及 shim 测试](https://github.com/pingdotgg/t3code/blob/40b0a98a2057b7de511807f12fef8ac8c30077fe/apps/server/src/provider/AntigravityInstallation.test.ts#L962-L1005) · [启动参数](https://github.com/pingdotgg/t3code/blob/40b0a98a2057b7de511807f12fef8ac8c30077fe/apps/server/src/provider/antigravityAuthSupport.ts#L547-L570) | 直接使用本机安装、普通账号目录、显式 stdio 和 Thread cwd。使用自身身份并验证原生版本与协议；不明版本显示探测错误。 |
| 模型、认证和权限 | T3 主动认证、默认个人账号，按能力协商客户端读取，关闭写文件与终端服务；重开后可恢复已选模型，拒绝未知 ID。工具审批与原生问题分流。[能力与认证](https://github.com/pingdotgg/t3code/blob/40b0a98a2057b7de511807f12fef8ac8c30077fe/apps/server/src/provider/acp/AntigravityAcpSupport.ts#L74-L139) · [恢复和未知模型测试](https://github.com/pingdotgg/t3code/blob/40b0a98a2057b7de511807f12fef8ac8c30077fe/apps/server/src/provider/acp/AntigravityAcpSupport.test.ts#L207-L280) · [问题卡测试](https://github.com/pingdotgg/t3code/blob/40b0a98a2057b7de511807f12fef8ac8c30077fe/apps/server/src/orchestration-v2/Adapters/AntigravityAdapterV2.test.ts#L131-L152) | 沿用 CLI 的账号和原生 default 权限；选定认证方法才发送 authenticate。使用原生完整模型 ID，执行时 set_model。只回答原生提供的工具授权选项，问题形式返回取消。 |
| 协议、事件与状态 | ACP stdio 通知区分 assistant、reasoning、工具事件。T3 还建模 prompt 结束后的后台命令、权限与主动唤醒。[流式转换](https://github.com/pingdotgg/t3code/blob/40b0a98a2057b7de511807f12fef8ac8c30077fe/packages/provider-acp/src/server/adapter.ts#L7267-L7306) · [后台与 steering](https://github.com/pingdotgg/t3code/blob/40b0a98a2057b7de511807f12fef8ac8c30077fe/apps/server/src/orchestration-v2/Adapters/AntigravityAdapterV2.ts#L254-L275) | 复用归档的 ACP 数据边界，由 Chief 自己持久化执行、摘要与活动，Swift 读取同一份结果。首期执行边界为前台 prompt；原生后台任务的后续动作没有独立 Chief 执行归属。 |
| 取消、恢复和沉默 | T3 按能力选择 resume/load，取消可等待 prompt 结算；AGY 适配器设 15 分钟无进展期限。[恢复](https://github.com/pingdotgg/t3code/blob/40b0a98a2057b7de511807f12fef8ac8c30077fe/packages/provider-acp/src/server/AcpSessionRuntime.ts#L2464-L2509) · [取消](https://github.com/pingdotgg/t3code/blob/40b0a98a2057b7de511807f12fef8ac8c30077fe/packages/provider-acp/src/server/AcpSessionRuntime.ts#L2632-L2669) · [超时设置](https://github.com/pingdotgg/t3code/blob/40b0a98a2057b7de511807f12fef8ac8c30077fe/apps/server/src/orchestration-v2/Adapters/AntigravityAdapterV2.ts#L311-L322) | 保存 native session ID，重新握手后优先 resume，load 路径忽略重放。用 Chief 的 cancellation ID 和前台执行生命周期处理停止，不把迟到取消发给后继执行。 |
| 错误与测试 | T3 将每个 prompt 的轨迹与错误关联，还可解析有界错误数据、额度和可重试状态，有按会话/路径的测试。[错误分类](https://github.com/pingdotgg/t3code/blob/40b0a98a2057b7de511807f12fef8ac8c30077fe/apps/server/src/provider/acp/AntigravityTurnOutcome.ts#L218-L285) · [末步归属测试](https://github.com/pingdotgg/t3code/blob/40b0a98a2057b7de511807f12fef8ac8c30077fe/apps/server/src/provider/acp/AntigravityTurnOutcome.test.ts#L106-L167) · [文件边界测试](https://github.com/pingdotgg/t3code/blob/40b0a98a2057b7de511807f12fef8ac8c30077fe/apps/server/src/provider/acp/AntigravityTurnOutcome.test.ts#L339-L368) | Chief 使用自身原生目录下当前会话的步号与类型。保留普通失败和 Stop 的不同终态。错误正文解析、配额分类、自动恢复和后台生命周期可分别评估。 |

## 本机可复核的边界

独立的 1.5.17 握手返回 `Antigravity ACP Server`、ACP 1、`loadSession` 以及 resume/close。认证清单有 `oauth-personal`、`oauth-business`、`gemini-api-key`、`agent-platform`。在临时 API-key 配置里 new 返回 25 个模型和 default、accept-edits、plan 三种模式。目录随账号配置变化。这份清单不能证明任一真实付费模型的授权。

按 [普通派发回放](../../tools/e2e/README.md#antigravity-task-dispatch) 可从实际协调者调用开始复核。独立探测 profile 检查可执行文件缺失、其他 ACP 身份和 1.5.0 旧版。正常回放的模型响应可控，命令和文件效果由真实 CLI 产生。一次验收覆盖子任务成功、权限等待、允许、拒绝、停止、失败，及这些终态的协调者回执；重开后能按执行读回两次不同回答。独立属性覆盖静态参数与安装升级补键。可延后的验收包括真实 Google OAuth 和线上额度、仅支持 load 的旧引擎、断电中断恢复、15 分钟实际超时、原生问题表单、后台命令及更多附件。首期用户入口和完整验收命令见[设置指南](../../docs/settings.md#choose-who-coordinates-and-who-can-take-tasks)和[适配器说明](../../internal/plugins/harness/agy/README.md)。

回放里有三项可复用的诊断。1.5.17 的原生 `run_command` 需要 `toolSummary`，初始模型样例被 CLI 拒绝，修正参数后才出现真实的权限请求。以 `chief-*` 命名的系统临时目录按产品契约进入 Inbox；测试关闭自动分类时，已完成的无标签任务不会出现在 Running 中。桌面验收改用显式、可见的临时项目目录，从挂载的 Overview 卡片打开执行。设置属性原型额外消费了一个 Rapid 输入，导致原有 routing-during-catalog 反例无法完整重放；现有版本在每份生成配置上遍历新增项批次，保留原反例及其输入域。
