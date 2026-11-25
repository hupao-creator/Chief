# Chief

<p align="center">
  <img src="design/chief-logo.webp" width="144" height="144" alt="Chief logo: a skillet tossing three coding agents">
</p>

<p align="center">
  <strong>A native Mac workspace for coordinating AI agents.</strong>
</p>

<p align="center">
  <a href="#get-started">Get started</a> · <a href="LICENSE">Apache 2.0</a>
</p>

<p align="center">
  Apple silicon · macOS 26+ · Invited alpha · <a href="https://github.com/hupao-creator/Chief/releases/tag/v0.1.0-alpha.3">Alpha 3 download</a>
</p>

---

Chief brings Codex, Claude, Pi Agent, and OpenCode into one workspace.
Talk to the **Chief** assistant to coordinate work, then open each task's conversation
to follow the work and give it more direction.

[![Chief Overview filtered to bug fixes, with two illustrated reports above an active task](design/overview-readme-preview.webp)](design/overview-readme.png)

The active task shows the latest agent activity and a summary of file changes. Select the screenshot to view it at full size. [Watch the Overview demo (MP4, 6.5 sec) →](design/overview-readme-demo.mp4)

- **Ask once, coordinate across agents.** Give Chief a task, attach files, and include the full path of any project folder Chief should use. Chief can answer directly or assign work to the agents you've enabled. [Working with Chief →](docs/working-with-moku.md)
- **See what needs you.** Overview uses a bento box design to show task status, questions, and permission requests on cards of different sizes. The canvas grows with your work for the feel of infinite horizontal scrolling as you browse from the first column to the last. Filter by folder or tag, then open a conversation to step in. [Overview →](docs/overview.md)
- **Read results and keep going.** Read completed replies, revisit earlier runs, send a follow-up, or branch from an earlier run when the agent supports it. [Agent conversations →](docs/task-conversations.md)
- **Connect the work.** Super Thread Agent prepares Super Threads with links back to source conversations. Git task cards can show branch and change summaries. [Super Threads and file changes →](docs/reports-tags-and-changes.md#see-the-work-behind-a-super-thread)
- **Give feedback beside the work.** Open a web page in a sidecard, annotate an element or area, and send the screenshot and comment to the current agent conversation. [Sidecards →](docs/sidecards.md)

Chief uses the agent CLIs you’ve already configured on your Mac, with their
existing accounts, models, and credentials. Chief connects its tools within the
session without rewriting user or project configuration, registering global
hooks, or installing global plugins.

The interface uses SwiftUI and AppKit, backed by a Go service.

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

---

## Get started

[Install Chief Alpha, connect an agent, and send your first request.](docs/getting-started.md)

## License

Chief is licensed under the [Apache License 2.0](LICENSE).
Copyright 2026 hupao-creator.

Third-party materials retain their licenses and attribution notices, including
[agent skills](.agents/skills/LICENSE),
[fonts and icons](app/macos/Sources/Shared/PluginUI/Resources/), and
[Unicode data](internal/services/taglabel/UNICODE-LICENSE.txt).
