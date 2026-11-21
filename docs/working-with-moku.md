# Work with Chief

## Send a request

From **Overview**, click Chief's eyes or press **⌘⇧B** to open **Type a message…**. After pressing the shortcut, start typing in the box. Ask a question, describe a task for Chief to assign, or ask it to find work you already started. Say what you want back and which materials to use.

In a task conversation, the same input box shows the agent's icon and sends to that conversation. In a Super Thread, open a source conversation in **Related executions** before sending a follow-up. [Agent conversations](task-conversations.md) · [Super Threads](reports-tags-and-changes.md#see-the-work-behind-a-super-thread)

When Chief's input is at the bottom of Overview, click outside it or press **Esc** to close it. Your unsent draft is there when you reopen the box.

## Point Chief to the right files

Tell Chief what you want it to do in your project folder. You can select the folder with **+** or type its full path. You can type or paste `@` as part of your message.

Click **+** just to the right of Chief's eyes to open the file chooser on your Mac. Select a folder to give Chief its path. You can Command-click to select several files and folders together. Each selection appears above the input. Click **Cancel** to keep your draft as it is. You can also drop files into the input box.

To browse the connected host, Control-click **+** and choose **Choose host files** to attach files or **Choose a host directory** to reference a folder.

When you send from Overview, Chief takes the current Overview folder into account. A folder you select with **+** or **Choose a host directory** takes priority. Tasks created without a project folder go into Inbox.

Click an image thumbnail to preview it, or click **×** on a file or folder to remove it. Wait for the files to finish preparing, then click **Send**. You can attach up to 20 files per message. Size limits apply, and the agent running Chief determines which attachment types it can use. If you want Chief to delegate work on a file, say which file the agent should use in your request.

## Remove a finished task’s worktree

From Overview, tell Chief which task’s worktree to remove. For example, “Remove the worktree for the finished settings review in my Calendar project.” Chief uses the task to identify the checkout it created.

Finish any foreground and background work first. Create a branch or tag at any task commits you want to keep. Leave the checkout in its original detached HEAD state and move out any files you want to keep, including ignored files. A locked checkout or one shared with another task must stay in place. If Chief reports a reason it kept the worktree, resolve it before asking again.

Chief also keeps the worktree if it cannot verify the files or find a saved branch or tag for a recoverable commit. If Git has already unregistered the worktree and Chief reports files left behind, inspect the folder it names. Move the remaining folder somewhere safe, then ask Chief to finish removing the same task’s worktree. If the checkout folder is gone but Chief says Git still lists it, resolve any reported permission issue and ask Chief to finish removing that same task’s worktree. You can also retry the same task after a recording failure.

After a successful removal, the checkout folder is gone. The task conversation stays in its original project, and its saved commits and branches remain in Git. Start a new task if you want an agent to do more work there.

## Find Chief's replies and notes

- **Replies.** A direct reply appears where you typed your request. You can select the text and scroll through a longer reply. The reply closes on its own, so ask Chief to put anything you want to keep in its note.
- **Task updates.** A dispatch message tells you that Chief handed off your request. Open the task card in Overview to see how the work is going.
- **Notes.** From Overview, press **⌘⇧N** or swipe up with two fingers over Chief to open **Chief Note**. Scroll to a run and click its link. The note closes. If your current Overview filter includes the destination, it stays selected. If the card is in another folder or tag, Overview switches there. If the conversation belongs to exactly one Super Thread, its card opens with the run you clicked in **Related executions**. A collection turns to that Super Thread’s page first. Other links open the cited run in the task conversation. In both readers, you start at the top of the run. Click the **×** at the top left of the reader or press **⌘K** to return to Overview with the note closed. To resume the note from a task conversation, press **Esc** in the run you opened. In a Super Thread, you can use **Back to related executions** to browse other runs before closing the report. To reopen the note from Overview, press **⌘⇧N**.
- **Conversation history.** Press **⌘B** or click **Chief history** below the note. As Chief works, each finished reply appears in order. When the run ends, its final answer and any reported error stay on the page. Click **Show work** for the reasoning and tool counts when available. To read an earlier run, select its mark along the left edge. The input at the bottom still sends to your current Chief conversation. Click **×** or press **⌘B** to return. When a different agent takes over as Chief, a new conversation starts and the note carries over.

## Stop work or acknowledge an alert

To stop Chief's current response, hover over its eyes at the bottom of Overview and click the square **Stop Chief** button on the right. The button stays on the right when you open the input box. To stop one or more delegated tasks, name them in a message to Chief. Chief tries each request separately. You can also stop a task yourself from its conversation. [Stop a run](task-conversations.md#respond-to-a-request-or-stop-a-run)

Chief can send an immediate alert that rings until you click **Received**. If another alert is waiting, it appears next. Alerts are kept while Chief is open and are cleared when you quit.

If a message fails to send, review the error and the text in the input box before retrying. If Chief is still checking the previous send, wait for confirmation or use **Check previous receipt** if shown. Open any task card Chief already created to see what happened.

[Back to the product guide](README.md)
