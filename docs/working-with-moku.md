# Work with Chief

## Send a request

From **Overview**, click Chief's eyes or press **⌘⇧B** to open **Type a message…**. The bar opens around its center. If Chief is showing a dispatch message, the input box takes its place. Start typing, or press the shortcut again to fold the bar. Ask a question, describe a task for Chief to assign, or ask it to find work you already started. Say what you want back and which materials to use.

Typing or pressing Delete in the open bar plays a keyboard click when your Mac has the matching Apple sounds and interface sound effects are enabled. You can still type normally on Macs where the sounds are unavailable.

In a task conversation, the same input box shows the agent's icon and sends to that conversation. In a Super Thread, open a source conversation in **Related executions** before sending a follow-up. [Agent conversations](task-conversations.md) · [Super Threads](reports-tags-and-changes.md#see-the-work-behind-a-super-thread)

The button at the right of the input box shows **Send** when your message is ready, even while Chief is working. Click it or press **Return** to send. When Chief is idle, an empty or whitespace-only draft leaves **Send** disabled. A ready file or a selected folder can be sent on its own.

When Chief's input is at the bottom of Overview, click outside it or press **Esc** to close it. Your unsent draft is there when you reopen the box.

When the bar is folded, three dots fade in and circle its edge while Chief thinks or uses tools such as updating its note. They keep circling as Chief switches tools and fade out when the work ends. If Chief needs your permission or an answer, a request appears above the bar.

To check your OpenCode Go allowance, ask Chief how much of your subscription is left. You can keep your usual default model. After you switch accounts in OpenCode, Chief checks the new account on your next message. If the reading is still pending, ask again after the refresh finishes.

## Point Chief to the right files

Tell Chief what you want it to do in your project folder. You can select the folder with **+** or type its full path. You can type or paste `@` as part of your message.

Click **+** just to the right of Chief's eyes to open the file chooser. It starts on your Mac's desktop each time. Select a folder to give Chief its path. You can Command-click to select several files and folders together. Each selection appears above the input. Click **Cancel** to keep your draft as it is. You can also drop files into the input box.

To browse the connected host, Control-click **+** and choose **Choose host files** to attach files or **Choose a host directory** to reference a folder.

When you send from Overview, Chief takes the current Overview folder into account. A folder you select with **+** or **Choose a host directory** takes priority. Tasks created without a project folder go into Inbox.

Click an image thumbnail to preview it, or click **×** on a file or folder to remove it. Wait for the files to finish preparing, then click **Send**. You can attach up to 20 files per message. Size limits apply, and the agent running Chief determines which attachment types it can use. If you want Chief to delegate work on a file, say which file the agent should use in your request.

## Send the same follow-up to several tasks

In Chief's input box, name the existing tasks and give the instruction each agent should receive. For example, “Tell both the settings review and the onboarding review to check keyboard navigation.”

Open each task’s card in Overview to see the follow-up in its conversation. A finished task can start a new run. If a task is waiting for an answer or approval, respond in that conversation, then ask Chief to retry that task. The other tasks can receive the follow-up even if one is blocked.

## Remove a finished task’s worktree

From Overview, tell Chief which task’s worktree to remove. For example, “Remove the worktree for the finished settings review in my Calendar project.” Chief uses the task to identify the checkout it created.

Finish any foreground and background work first. Create a branch or tag at any task commits you want to keep. Leave the checkout in its original detached HEAD state and move out any files you want to keep, including ignored files. A locked checkout or one shared with another task must stay in place. If Chief reports a reason it kept the worktree, resolve it before asking again.

Chief also keeps the worktree if it cannot verify the files or find a saved branch or tag for a recoverable commit. If Git has already unregistered the worktree and Chief reports files left behind, inspect the folder it names. Move the remaining folder somewhere safe, then ask Chief to finish removing the same task’s worktree. If the checkout folder is gone but Chief says Git still lists it, resolve any reported permission issue and ask Chief to finish removing that same task’s worktree. You can also retry the same task after a recording failure.

After a successful removal, the checkout folder is gone. The task conversation stays in its original project, and its saved commits and branches remain in Git. Start a new task if you want an agent to do more work there.

## Find Chief's replies and notes

- **Replies.** A direct reply appears where you typed your request. You can select the text and scroll through a longer reply. The reply closes on its own, so ask Chief to put anything you want to keep in its note.
- **Task updates.** A dispatch message tells you that Chief handed off your request. Open the task card in Overview to see how the work is going.
- **Notes.** In Overview, press **⌘⇧N** to open **Chief Note**. With the input box closed, you can also swipe up with two fingers anywhere in Overview, including over a card, a tag, or Chief Bar. Click the eyes centered below the note to start a message, or click a run’s link to read it. The note closes. Overview keeps your selected filter and scroll position. If the conversation belongs to exactly one Super Thread, its card opens with the run you clicked in **Related executions**. If its collection is visible, it turns to that Super Thread’s page first. Other links open the cited run in the task conversation. In both readers, you start at the top of the run. Click the **×** at the top left of the reader or press **⌘K** to return to Overview with the note closed. To resume the note from a task conversation, press **Esc** in the run you opened. In a Super Thread, you can use **Back to related executions** to browse other runs before closing the report. To reopen the note from Overview, press **⌘⇧N**.

## Stop work or acknowledge an alert

To stop Chief's current response, hover over its eyes at the bottom of Overview and click the square **Stop Chief** button on the right. With the input box open, **Stop Chief** appears in the same spot whenever the draft cannot be sent. If you want to stop Chief while keeping a ready draft, fold the bar with **⌘⇧B**, then hover over the eyes. To stop one or more delegated tasks, name them in a message to Chief. Chief tries each request separately. You can also stop a task yourself from its conversation. [Stop a run](task-conversations.md#respond-to-a-request-or-stop-a-run)

When Chief sends an alert, read it in the compact bar at the bottom of the workspace. Scroll inside a longer message to read the rest. To open Chief Note while an alert is visible, start your upward swipe elsewhere in Overview. Click **Received** to confirm just that alert. If more are waiting, the bar shows how many and brings up the next one.

The bell keeps ringing until you confirm the last alert. If the bell fails to play, you can still confirm the message or click **Retry bell**. An open input box keeps your draft and selection above the alert. After the final receipt, the bar returns to its current task. Quitting Chief clears pending alerts.

If a message fails to send, review the error and the text in the input box before retrying. If Chief is still checking the previous send, wait for confirmation or use **Check previous receipt** if shown. Open any task card Chief already created to see what happened.

[Back to the product guide](README.md)
