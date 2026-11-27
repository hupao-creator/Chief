# Native Git card extensions

[NativeGitService](NativeGitService.swift) reads bounded metadata pages from the built-in [Go Git application](../../../../../internal/plugins/applications/git/README.md). [NativeGitWorkspaceModel](NativeGitWorkspaceModel.swift) shares typed worktree facts with Harness card composers. Git has no separate Overview thread or enablement switch.

The card extension shows the changed-file count, signed added/deleted line totals and branch. When the snapshot has recent files, the header places the totals beside the file count, followed by up to three file rows. Each row shows a JetBrains Mono file name, the repository-relative parent directory, and its own signed counts. Long file names truncate in the middle and long directories retain their final components. The tooltip and accessibility label expose the full path. The file rows fit in the same extension cell and clicking the owning task card opens the Agent conversation.

The snapshot's independent `lineStatsError` survives decoding, caching and Harness projection. Failed line counts display a reason (limit, timeout or unavailable); unknown counts display an unknown label. Neither state displays signed dashes, zeroes or a loading indicator: observations arrive after the bounded statistics attempt. A status/polling failure retains the last successful values and recent files with a visible stale label. A line-only failure keeps the fresh file count at full opacity. Known added/deleted totals of zero remove the entire extension before card composition, including when changed files or HEAD exist. Hidden Git contributes no placement, footprint or structural-key segment. The extension is read-only metadata.

The native host requests recent files through `git.list` in pages of 100, validates the paths and their counts against the snapshot totals, and projects each completed page set together. A Runtime that rejects the optional input is queried with the base summary fields. The Go application's `git.files` and `git.diff` queries remain separate on-demand APIs.

No Git card test or capture replay is configured in this source tree. The
production client and projection contracts above remain the evidence boundary.
