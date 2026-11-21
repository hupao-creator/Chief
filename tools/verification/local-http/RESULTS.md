# 本地设置 HTTP 长尾 · 2026-11-21

**在执行配置已经固定、另一请求正在保存配置时，预取会等待与本次读取无关的原生校验。** 相同的五次争用下，已预热的 Moku 设置读取从 **1,277.25 ms** 降至 **1.37 ms**（中位数）。修复后五次均在保存的原生校验返回前完成。保存仍等待校验，每次只推进一个 revision。

## 等待发生在哪里

在新建的隔离 profile 中，采集器通过同一台机器的回环 HTTP 访问生产 Go runtime 和 Claude 适配器。先初始化执行配置并预热两个目录，再交替保存权限设置。确定性 Claude peer 进入保存的 `get_settings` 后等待 1.25 秒，此时同时发出三个独立 HTTP 请求。下表为从发起请求到读完响应体的时间，每格取五次的中位数，单位 ms。

| 已知命令与角色 | 基线 | 修复版 |
| --- | ---: | ---: |
| Moku 执行配置预取 · `harness:settings-presentation` | 1,277.25 | 1.37 |
| 普通 Harness 默认设置 · 同一命令，另一工作目录 | 1.05 | 1.20 |
| 保存 · `app:update-settings`，含 1,250 ms 的校验等待 | 1,342.56 | 1,342.48 |

预取响应体两侧均为 318 B。五次基线读取均把超过 99.99% 的时间用在收到响应头之前，同期普通读取可以返回。实验中 HTTP 请求数、连接方式、原生校验等待和请求容量相同。[基线原始样本](evidence/before.jsonl) · [修复版原始样本](evidence/after.jsonl)

另用相同的构建期插桩对两版各做五次同样的争用，跳过两轮目录老化等待。以下为进入设置 handler（完成命令参数解码）之后的中位数，子区间包含在总时长中。

| 已预热的执行配置读取 | 基线 | 修复版 |
| --- | ---: | ---: |
| handler 总时长 | 1,273.391 ms | 0.229 ms |
| 调用配置锁次数（每次读取） | 1 | 0 |
| 等到配置锁返回 | 1,273.067 ms | 0 ms |
| Harness 原生 presentation | 0.193 ms | 0.184 ms |

这五次的积压发生在服务端配置锁上。热目录处理、响应传输和全局 HTTP 槽位耗尽可以排除为**这组**秒级等待的原因。Swift 在发起 HTTP 之前还会按 Harness 排队，全局最多四个设置读取，每个 Harness 同时一个。这会影响编辑器等待时间，采集器的三个独立客户端请求绕过了这段队列，现场 CFNetwork 的事务时长也从发起 HTTP 后才开始计。[服务端分段基线](evidence/service-before.txt) · [服务端分段修复版](evidence/service-after.txt) · [客户端准入](../../../app/macos/Sources/Core/RuntimeSettingsReads.swift)

## 周期与实时性

- **事件流。** 两版 `/events` 的首条 hello 分别在 0.60 和 0.68 ms 到达。其后约 15,000 ms 收到保活换行。连接寿命包含等待新事件的时间。原诊断中的 372/373 条慢事务在响应开始之前已耗用九成时间，无法用这种首帧后空闲解释。[流协议](../../../internal/platform/transport/stream.go)
- **五分钟重读。** 基线两次执行配置重读分别为 82.26、82.87 ms，修复版为 326.63、73.97 ms。普通默认目录对应为 95.11、59.50 ms 和 62.21、60.84 ms。修复版第一轮执行目录重读耗时更长，两轮样本不足以判定非争用刷新的时延变化。 每侧两个时间点均在上轮完成后实等 300 秒。执行目录和普通默认目录各触发了一次原生初始化，命令名相同而工作目录不同。测试中两者都成功返回模型目录。按工作目录区分的刷新保留了实时性。含争用对照在内，每侧共 43 次安装探测，中位数分别为 0.92 和 0.98 ms。 [预取调度](../../../app/macos/Sources/Host/Shell/NativeWorkspaceSettingsPrefetch.swift) · [Harness 缓存键](../../../internal/plugins/harness/claude/settings.go)
- **取消和并发。** 显式刷新的唯一 HTTP 读者断开后，等待中的 peer 进程在 7.59 / 6.31 ms 内退出，下一次读取成功。带 race detector 的 100 个生成用例覆盖读取在提交前返回、跨提交返回和取消。被改写的执行配置会拒绝旧结果，默认设置读取可成功。保存只推进自己的 revision。seed 为 `20261121`。[PBT 运行回执](evidence/pbt.json) · [属性与生成域](../pbt/runtime/settings_property_test.go)

## 归因边界与复现

先前的《Chief 日常实例诊断》（2026-11-21）记录了 373/5,604 次慢事务、P95 1,615 ms 和 P99 3,874 ms，来自日常开发包。该报告的建连 P95 为 1 ms，13 个错误完成均为客户端取消。现场没有命令、配置锁持有者或前台读取者标识。上述实验确认一个能够独立产生秒级长尾的条件，无法计算它在那 373 次中的占比，也不能据此给出真实安装的修复后 P95。五分钟目录刷新耗时取决于真实 CLI、账户及目录内容。

- **制品。** macOS 26.5.1 arm64，Go 1.27.3，Python 3.13.3。未插桩基线 `2aed57156caae91e38bb651da16340d861e9624d`，修复 `b20e87bc22a0126659c5df62da1864dd5f144f98`，两个普通 runtime 二进制均由各自 clean 源码以 `-trimpath` 构建。日常 Go 包的源码号为 `f7e02067e4036d07932d53c377de1a13fafed0a7`。该提交与实验基线的配置、HTTP 传输及预取相关文件相同。现场原生客户端的源码号未知。每份 JSONL 首行包含实际二进制、seed、采集器和 peer 的 SHA-256。[分段采集的基线 HTTP 样本](evidence/diagnostic-before.jsonl) · [修复版分段采集的 HTTP 样本](evidence/diagnostic-after.jsonl)
- **负载。** 两侧串行使用同一独占锁、同一采集器、同一 seed 二进制和新的临时 home/profile。没有挂载 Settings、运行真实模型或访问日常 profile。peer 提供初始化和设置校验回复，后台 `get_usage` 记录调用但不提供账户用量。本轮覆盖 Moku 执行配置和普通默认设置。独立应用配置、Git 轮询、其他 Harness、登录 shell、签名 Release、UI 帧和整机 CPU 未采样。仅一次前后配对，毫秒量级差异没有统计校准。
- **复跑。** 用采集说明中的构建和运行命令，普通采样使用 `--rounds 5 --interval 300`，分段采样使用 `--rounds 5 --interval 0`。运行 `python3 tools/verification/pbt/run.py --property PBT-RUNTIME-SETTINGS --seed 20261121 --cases 100 --race` 可复跑属性。首次沙箱试跑在临时 profile 的所有权端口返回 `PROFILE_IN_USE`，获准使用本机回环后才取得样本，随后校正采集器的客户端变量和 PBT fixture 的指针类型。本文采用修正后的完整运行。提交钩子的 `make lint` 与受影响的 Go 构建通过。[采集与判据](README.md)
