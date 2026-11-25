<h1 align="center"><img src="design/chief-logo.webp" width="115" height="115" align="absmiddle" hspace="6" alt="">Chief</h1>

<p align="center">Chief brings your AI agents together and gets them cooking.</p>

<p align="center">
  <a href="https://github.com/hupao-creator/Chief/stargazers"><img alt="GitHub stars" src="https://img.shields.io/github/stars/hupao-creator/Chief?style=flat&amp;label=stars&amp;color=blue"></a>
  <a href="https://github.com/hupao-creator/Chief/releases"><img alt="Latest release including prereleases" src="https://img.shields.io/github/v/release/hupao-creator/Chief?include_prereleases&amp;label=release&amp;color=orange"></a>
  <a href="https://github.com/hupao-creator/Chief/actions/workflows/ci.yml?query=branch%3Amain"><img alt="CI status on main" src="https://github.com/hupao-creator/Chief/actions/workflows/ci.yml/badge.svg?branch=main"></a>
  <a href="https://github.com/hupao-creator/Chief/releases/tag/v0.1.0-alpha.4"><img alt="Alpha 4 DMG download size, 25.5 MiB" src="https://img.shields.io/badge/download-25.5%20MiB-blue"></a>
</p>

<p align="center">
  <strong><a href="https://github.com/hupao-creator/Chief/releases/tag/v0.1.0-alpha.4">Download Alpha 4</a></strong> · <a href="docs/getting-started.md">Get started</a> · <a href="LICENSE">Apache 2.0</a>
</p>

[![Chief Overview filtered to bug fixes, with two illustrated reports above an active task](design/overview-readme-preview.webp)](design/overview-readme.png)

The active task shows the latest agent activity and a summary of file changes. Select the screenshot to view it at full size. [Watch the Overview demo (MP4, 6.5 sec) →](design/overview-readme-demo.mp4)

## What you get

- **Your agents in one Mac app.** Use Codex, Claude, Pi Agent, and OpenCode with the accounts and models you already use on your Mac.
- **One place to delegate.** Give Chief a task and the files it needs. Chief can answer directly or assign the work to an agent you’ve enabled. [Working with Chief](docs/working-with-moku.md)
- **Live task overview.** Filter by folder or tag to see what’s running, which files changed, and which agents need an answer or permission to proceed. [Overview](docs/overview.md)
- **Conversations you can pick up again.** Revisit an earlier run, send a follow-up, or branch the conversation when the agent supports it. [Agent conversations](docs/task-conversations.md)
- **Reports with sources.** A Super Thread summarizes completed work in a project and links back to the conversations behind it. [Super Threads](docs/reports-tags-and-changes.md#see-the-work-behind-a-super-thread)
- **Feedback right on the page.** Open a web page beside a conversation, mark what you want changed, and send the screenshot and your comment to the agent. [Sidecards](docs/sidecards.md#mark-up-a-web-page-and-send-feedback)

<a name="auto-categorization"></a>

## Agent roles

<table width="100%">
  <thead>
    <tr>
      <th width="33%" align="center"><a href="docs/working-with-moku.md">Chief Agent</a></th>
      <th width="33%" align="center"><a href="docs/reports-tags-and-changes.md#group-tasks-with-tags">Tag Agent</a></th>
      <th width="33%" align="center"><a href="docs/reports-tags-and-changes.md#see-the-work-behind-a-super-thread">Super Thread Agent</a></th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td align="center"><img src="design/chief-agent-readme.webp" alt="One request branches into several agent tasks"></td>
      <td align="center"><img src="design/tag-agent-readme.webp" alt="Conversation cards form three groups with colored tags"></td>
      <td align="center"><img src="design/super-thread-agent-readme.webp" alt="Source conversations connect to a single report"></td>
    </tr>
    <tr>
      <td align="center">Assign work to agents.</td>
      <td align="center">Group tasks by topic.</td>
      <td align="center">Sum up work with source links.</td>
    </tr>
  </tbody>
</table>

## License

Chief is licensed under the [Apache License 2.0](LICENSE).
Copyright 2026 hupao-creator.

Third-party materials retain their licenses and attribution notices, including
[agent skills](.agents/skills/LICENSE),
[fonts and icons](app/macos/Sources/Shared/PluginUI/Resources/), and
[Unicode data](internal/services/taglabel/UNICODE-LICENSE.txt).
