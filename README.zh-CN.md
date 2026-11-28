<h1 align="center"><img src="design/chief-logo.webp" width="115" height="115" align="absmiddle" hspace="6" alt="">Chief</h1>

<p align="center"><a href="README.md">English</a> / <strong>简体中文</strong></p>

<p align="center">Chief 把你的 AI Agent 聚到一起，让它们协作开工。</p>

<p align="center">
  <a href="https://github.com/hupao-creator/Chief/stargazers"><img alt="GitHub 星标数" src="https://img.shields.io/github/stars/hupao-creator/Chief?style=flat&amp;label=stars&amp;color=blue"></a>
  <a href="https://github.com/hupao-creator/Chief/releases"><img alt="最新发布版本（含预发行版）" src="https://img.shields.io/github/v/release/hupao-creator/Chief?include_prereleases&amp;label=release&amp;color=orange"></a>
  <a href="https://github.com/hupao-creator/Chief/actions/workflows/ci.yml?query=branch%3Amain"><img alt="main 分支的 CI 状态" src="https://github.com/hupao-creator/Chief/actions/workflows/ci.yml/badge.svg?branch=main"></a>
  <a href="https://github.com/hupao-creator/Chief/releases?q=draft%3Afalse"><img alt="下载最新的 macOS 磁盘映像" src="https://img.shields.io/badge/download-macOS%20DMG-blue"></a>
</p>

<p align="center">
  <strong><a href="https://github.com/hupao-creator/Chief/releases?q=draft%3Afalse">下载最新版本</a></strong> · <a href="docs/getting-started.md">快速上手（英文）</a> · <a href="LICENSE">Apache 2.0</a>
</p>

[![Chief 概览展示项目筛选项，以及 API Platform 中的任务报告、进度清单和文件变更](design/overview-readme-preview.webp)](design/overview-readme.png)

## 我们需要的只是注意力

三个 Agent 都在等你，你却还没读完第一条回复。从一项尚未完成的工作切到另一项时，你的一部分注意力可能还留在前一项工作上。这种现象叫作**注意力残留**。 [Leroy, 2009](https://doi.org/10.1016/j.obhdp.2009.04.002)

<p align="center"><img src="design/attention-residue.webp" alt="开发者还在阅读，三个 Agent 会话都在等待关注。" width="480"></p>

### 用标签专注于一个主题

Chief 用**最多五个标签**归类每个项目中的对话。从 *Bug fixes（缺陷修复）* 切换到 *Design（设计）*，概览便会显示该主题下的任务。

<p align="center"><img src="design/overview-tag-switch.gif" alt="开发者在左侧栏选中 Design，缺陷修复卡片随即切换为应用图标、配色和工具栏任务。" width="480"></p>

### 用超级线程汇总结果

在**一份报告**中阅读相关对话的结果。想了解某个 Agent 是如何得出结果的，可以在右侧打开对应的原始对话。

<p align="center"><img src="design/super-thread-source.gif" alt="开发者在左侧的报告中查看安装结果，再在右侧找到原始的 Codex 对话。" width="480"></p>

## 功能一览

- **原生 Mac 应用。** Chief 使用 **SwiftUI 和 AppKit** 构建，面向搭载 Apple 芯片的 Mac。
- **集中使用你的 Agent。** 用你已有的账号和模型，把 **Codex、Claude、Pi Agent、OpenCode 和 Antigravity** 聚到一起。
- **统一委派任务。** 把任务交给 Chief，它可以协调**不同 Harness 和模型**的 Agent。比如，让 Codex 实现一项改动，再让 Claude Code 审查。
- **实时任务概览。** 查看哪些任务正在运行、哪些文件有变更，以及**哪些 Agent 正在等你**。按项目文件夹或标签筛选，专注于当前的工作。
- **采用 Liquid Glass 设计。** 在任务概览与单个对话之间切换时，半透明控件让工作内容始终可见。
- **保留你的 CLI 配置。** Chief 逐个会话连接 Agent，**无需改写用户或项目设置**，也无需安装全局钩子或插件。

## 许可证

Chief 采用 [Apache License 2.0](LICENSE) 许可协议。
Copyright 2026 hupao-creator.

第三方材料保留各自的许可证和署名声明，包括
[Agent 技能](.agents/skills/LICENSE)、
[字体和图标](app/macos/Sources/Shared/PluginUI/Resources/)和
[Unicode 数据](internal/services/taglabel/UNICODE-LICENSE.txt)。
