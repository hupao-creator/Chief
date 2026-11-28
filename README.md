<h1 align="center"><img src="design/chief-logo.webp" width="115" height="115" align="absmiddle" hspace="6" alt="">Chief</h1>

<p align="center">Chief brings your AI agents together and gets them cooking.</p>

<p align="center">
  <a href="https://github.com/hupao-creator/Chief/stargazers"><img alt="GitHub stars" src="https://img.shields.io/github/stars/hupao-creator/Chief?style=flat&amp;label=stars&amp;color=blue"></a>
  <a href="https://github.com/hupao-creator/Chief/releases"><img alt="Latest release including prereleases" src="https://img.shields.io/github/v/release/hupao-creator/Chief?include_prereleases&amp;label=release&amp;color=orange"></a>
  <a href="https://github.com/hupao-creator/Chief/actions/workflows/ci.yml?query=branch%3Amain"><img alt="CI status on main" src="https://github.com/hupao-creator/Chief/actions/workflows/ci.yml/badge.svg?branch=main"></a>
  <a href="https://github.com/hupao-creator/Chief/releases?q=draft%3Afalse"><img alt="Download the latest macOS disk image" src="https://img.shields.io/badge/download-macOS%20DMG-blue"></a>
</p>

<p align="center">
  <strong><a href="https://github.com/hupao-creator/Chief/releases?q=draft%3Afalse">Download latest release</a></strong> · <a href="docs/getting-started.md">Get started</a> · <a href="LICENSE">Apache 2.0</a>
</p>

[![Chief Overview showing project filters and API Platform tasks with reports, progress checklists, and file changes](design/overview-readme-preview.webp)](design/overview-readme.png)

## Attention Is All We Need

Three agents need your attention. You’re still halfway through the first reply. When you switch away from unfinished work, some of your attention can stay with it. This is called **attention residue**. [Leroy, 2009](https://doi.org/10.1016/j.obhdp.2009.04.002)

<p align="center"><img src="design/attention-residue.webp" alt="Three agent sessions compete for attention while the developer is still reading." width="480"></p>

### Tags keep one topic in view

Chief groups each project’s conversations under **up to five tags**. Switch from *Bug fixes* to *Design*, and Overview shows the tasks for that topic.

<p align="center"><img src="design/overview-tag-switch.gif" alt="The developer selects Design in the left sidebar. The bug-fix cards give way to app icon, color palette, and toolbar tasks." width="480"></p>

### Super Threads bring the results together

Read **one report** across related conversations. When you want to see how an agent reached a result, open its source conversation on the right.

<p align="center"><img src="design/super-thread-source.gif" alt="The developer reads the installation result in the report on the left, then finds the original Codex conversation on the right." width="480"></p>

## What you get

- **A fully native Mac app.** Chief is built with **SwiftUI and AppKit** for Apple silicon.
- **Your agents in one place.** Bring **Codex, Claude, Pi Agent, OpenCode, and Antigravity** together with the accounts and models you already use.
- **One place to delegate.** Give Chief a task, and it can coordinate agents **across harnesses and models**. Ask Codex to implement a change and Claude Code to review it.
- **Live task overview.** See what’s running, which files changed, and **which agents are waiting for you**. Filter by project folder or tag to focus on one part of your work.
- **Designed around Liquid Glass.** Translucent controls keep your work in view as you move between the task overview and individual conversations.
- **Your CLI setup stays yours.** Chief connects to your agents one session at a time, **without rewriting your user or project settings** or installing global hooks or plugins.

## License

Chief is licensed under the [Apache License 2.0](LICENSE).
Copyright 2026 hupao-creator.

Third-party materials retain their licenses and attribution notices, including
[agent skills](.agents/skills/LICENSE),
[fonts and icons](app/macos/Sources/Shared/PluginUI/Resources/), and
[Unicode data](internal/services/taglabel/UNICODE-LICENSE.txt).
