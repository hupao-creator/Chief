# SQLite 会话写入量 · 2026-11-21

两个隔离会话各接收 4,000 B 流式正文。基线中，普通 Thread 和私有会话占 SQLite 新写入 BLOB 字节的 **99.96%**。保存 100 B 文本片段会重新提交约 560 KiB 的完整记录。修复后，94 次事务全部保留，整轮数据库和 WAL 文件写入从 **58.58 MiB 降至 6.74 MiB**，减少 **88.5%**。两个方向的配对取得相同的字节计数。[逐操作原始样本](samples.jsonl)

## 实验对象

| 项目 | 采集值 |
| --- | --- |
| 基线 A | `2aed57156caae91e38bb651da16340d861e9624d`。与分发版 `v0.1.0-alpha.2`（`df9ad830c3811d31759e110b5b0cd899969255ab`）对照，Store 和 SQLite binding 的 Go 源码仅有一处标识符注释差异。 |
| 修复 B | `66585bc8a0cda0504addef124d543f80cc32a69b` |
| 环境 | macOS 26.5.1（25F80），arm64，Go 1.27.3，系统 SQLite 3.51.0。各次原始样本保留 SQLite source ID 和二进制 SHA-256。 |
| 采集器 | B 提交的 `sqlite-writes`。按文件名排序拼接两个 Go 源文件的 SHA-256 为 `b26c7345f565f3dff8b5a0be760bcaf002990bbe92c3db48e78d930ae0dd0ce0`。基线通过 Go overlay 替换生产 Go 源码。 |
| 起点 | 四份 v1 数据库均为 `fb2e2bc2d63dba63ca5537e2d082d3c55bb7e5e89bc7b7661fc47d90c79a662b`。每个会话有 16 个已完成的 Codex 回合，普通 Thread 起始记录为 576,651 B。 |
| 顺序与判据 | 持有共享资源锁，依次运行 A1、B1、B2、A2，每轮使用新临时目录。比较之前逐步核对输入字节、提交数、各类逻辑记录的变更数与完整长度。每个流式前缀、追加的用户内容和重开后的完整记录均通过检查。 |
| SQLite 设置 | 每次在写连接上读取到 8,192 B 页、`synchronous=2`、`fullfsync=1`、`checkpoint_fullfsync=1`、`wal_autocheckpoint=1000`。两端都在测量前排空已有 WAL，结束时计入最后一次 checkpoint。 |

复现命令使用 `GOFLAGS=-buildvcs=false` 和 `./scripts/go.sh build -trimpath`。先按采集器说明构建 A、B，再按上述顺序分别执行二进制并保存标准输出。每次 JSONL 采集头保留原始输出摘要，后续每行对应一次实际操作。采集器在准入返回后用第二个连接读取已提交的 revision。[完整负载与构建命令](../../sqlite-writes/README.md)

采集器预检曾在注册 `sqlite3_auto_extension` 时退出 2，报错为 `SQLite observer unavailable`，尚未进入负载。计入比较的四轮通过系统 SQLite 的 `SQLITE_CONFIG_SQLLOG` 取得写连接，交叉核对 commit hook 与持久 revision、各记录 BLOB 字节之和，以及 WAL 页数与成功的文件写调用。

## 整轮结果

| 每次独立回放 | 基线 A | 修复 B |
| --- | ---: | ---: |
| 操作 / SQLite 写事务 | 106 / 94 | 106 / 94 |
| fixture 输入（含相同 Git 请求重试） | 11,152 B | 11,152 B |
| 变更记录的完整 JSON 长度之和 | 49,375,419 B | 49,375,419 B |
| SQLite 写入的 BLOB 载荷 | 49,375,419 B | 3,925,179 B |
| WAL 帧 | 6,390 | 697 |
| WAL 文件写入 | 52,500,464 B | 5,726,584 B |
| 主数据库文件写入，含最后 checkpoint | 8,929,280 B | 1,343,488 B |
| **主数据库 + WAL 文件写入** | **61,429,744 B** | **7,070,072 B** |
| macOS 计入进程的写入，含最后 checkpoint | 63,307,776 B | 8,568,832 B |
| checkpoint 后主库文件大小（起始 1,204,224 B） | 1,835,008 B | 1,343,488 B |

事务的 COMMIT 语句和调用返回分别计时。下表是 94 笔有写入事务的最近秩分位数，单位 ms。SQLite 观测钩子、FULL 同步和实机负载会影响计时。

| 轮次 | COMMIT P50 / P95 | 调用返回 P50 / P95 |
| --- | ---: | ---: |
| A1 | 1.238 / 2.277 | 6.084 / 9.128 |
| B1 | 0.666 / 1.383 | 5.369 / 8.345 |
| B2 | 0.663 / 1.293 | 5.326 / 8.635 |
| A2 | 1.207 / 2.013 | 5.979 / 7.882 |

## 归因

| 记录种类 | 逻辑变更次数 | 完整 JSON 字节 | 基线 SQL BLOB 字节 | 修复 SQL BLOB 字节 |
| --- | ---: | ---: | ---: | ---: |
| `thread` | 43 | 24,677,064 | 24,677,064 | 1,959,624 |
| `private-session` | 43 | 24,680,676 | 24,680,676 | 1,947,876 |
| `event` | 8 | 10,562 | 10,562 | 10,562 |
| `moku-delivery` | 1 | 4,529 | 4,529 | 4,529 |
| `application`（Git） | 4 | 1,844 | 1,844 | 1,844 |
| `application-command-receipt` | 4 | 488 | 488 | 488 |
| `telemetry` | 4 | 216 | 216 | 216 |
| `directory-scope` | 1 | 35 | 35 | 35 |
| `application-collection` | 4 | 4 | 4 | 4 |
| `moku-delivery-sequence` | 1 | 1 | 1 | 1 |

每个会话的 43 次提交包含准入、40 次正文、一次用户追加和一次终态。仅看正文，公开 Thread 的 WAL 帧从 2,947 降到 240，私有会话从 2,958 降到 239。8 次空闲读取和 4 次相同 Git 请求重试都产生零写事务。WAL 页、checkpoint 和文件写入按整个事务统计，多记录共同提交的字节归属只细分到 SQL BLOB 层。

首次写回 v1 大记录会转换整条记录。两次准入合计的 WAL 帧从 150 增至 163，这项开销已计入整轮。块按字节偏移对齐，靠前字段变长仍可能移动后续内容。修复后的某次 100 B 公开正文提交仍写了 569,640 B BLOB。回放未测序列化完整快照的 CPU 改善。

## 持久性与覆盖

在 B 提交运行 `make lint`、`./scripts/go.sh build ./...`，以及 `python3 tools/verification/pbt/run.py --property <ID> --seed 1121`。流式存储加 `--race --cases 30`，快照、生命周期、Runtime 准入、Moku outbox 和 Codex 终态各 100 例。六项合计 530 个生成案例通过。每项实际命令、时长、退出状态、案例数及原始日志摘要均已记录。[验证记录](checks.json)

属性以独立字节前缀及提交 revision 为判据，覆盖 v1 原值、并发追加、旧快照、相同内容重试、晚期 SQL 失败回滚、删除、尺寸跨界和重开。子进程成功提交后立即退出，完整 WAL 恢复片段和同事务回执。保留若干 WAL 帧、截在完整提交帧之前的副本恢复到上一 revision。畸形分块被拒绝。[存储契约与生成域](../../../../../internal/core/store/README.md#large-records)

文件写量是 SQLite Unix VFS 对主库及 WAL 的成功 `write/pwrite` 字节，包含覆盖写。进程写量来自 `proc_pid_rusage`。现场诊断的 34.36 GB 是另一个进程时窗内系统计入的文件后备内存脏写。本次没有接触日常数据库，没有采集 SSD 物理写入或模拟硬件断电。现场各记录的占比、真实模型负载和原生界面时延仍无对应实测。
