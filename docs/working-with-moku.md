# Work with Chief

## Send a request

From **Overview**, click Chief's eyes or press **⌘⇧B** to open **Type a message…**. The bar opens around its center. If Chief is showing a dispatch message, the input box takes its place. You can start typing as the bar opens. The cursor shows where your text will go. Press the shortcut again to fold the bar. Ask a question, describe a task for Chief to assign, or ask it to find work you already started. Say what you want back and which materials to use.

Typing or pressing Delete in the open bar plays a keyboard click when your Mac has the matching Apple sounds and interface sound effects are enabled. To silence the clicks, turn off **Play user interface sound effects** in **System Settings → Sound**. Pasting text is quiet. Choosing an input method candidate adds no extra click. You can still type normally on Macs where the sounds are unavailable.

In a task conversation, the same input box shows the agent's icon and sends to that conversation. In a Super Thread, open a source conversation in **Related executions** before sending a follow-up. [Agent conversations](task-conversations.md) · [Super Threads](reports-tags-and-changes.md#see-the-work-behind-a-super-thread)

The button at the right of the input box shows **Send** when your message is ready, even while Chief is working. Click it or press **Return** to send. When you send from the compact input, the bar folds back around Chief’s eyes. It expands again when Chief shows a reply or task update. When Chief is idle, an empty or whitespace-only draft leaves **Send** disabled. A ready file or a selected folder can be sent on its own.

You can send your request while a task agent’s model list is unavailable. Chief can use the choices that agent last reported. If the agent rejects a model when the task starts, Chief receives the error and can choose how to continue.

When you ask what happened in an earlier task, Chief can consult that conversation. If a Codex lookup stops producing answer text for 30 seconds, Chief can try once more using the saved conversation. In a long conversation, this retry can miss earlier details. The two attempts share a 90-second limit. If it times out, Chief can continue with the information it already has. You can also open the task’s card to read its replies yourself.

When Chief's input is at the bottom of Overview, click outside it or press **Esc** to close it. Your unsent draft is there when you reopen the box. [Watch Chief Bar open for typing and chat](chief-bar-and-tags.md)

When the bar is folded, watch the three dots beneath it while Chief thinks or uses a tool. They brighten in turn, lift off and circle the bar once as Chief’s eyes follow. The dots settle back into a row and Chief briefly squints before the sequence repeats. Switching tools keeps the rhythm. The dots fade out when the work ends. If Chief needs your permission or an answer, a request appears above the bar.

To check your OpenCode Go allowance, ask Chief how much of your subscription is left. You can keep your usual default model. After you switch accounts in OpenCode, Chief checks the new account on your next message. If the reading is still pending, ask again after the refresh finishes.

## Point Chief to the right files

Tell Chief what you want it to do in your project folder. You can select the folder with **+** or type its full path. You can type or paste `@` as part of your message.

Click **+** just to the right of Chief's eyes to open the file chooser. It starts on your Mac's desktop each time. Select a folder to give Chief its path. You can Command-click to select several files and folders together. Each selection appears above the input. Click **Cancel** to keep your draft as it is. You can also drop files into the input box.

To browse the connected host, Control-click **+** and choose **Choose host files** to attach files or **Choose a host directory** to reference a folder.

When you send from Overview, Chief takes the current Overview folder into account. A folder you select with **+** or **Choose a host directory** takes priority. To find a running task in a project folder, select the folder in Overview and click ⏳ **Running** in the left column. Once Tag Agent assigns the task its first tag, Overview opens that tag.

Click an image thumbnail to preview it, or click **×** on a file or folder to remove it. Wait for the files to finish preparing, then click **Send**. You can attach up to 20 files per message. Size limits apply, and the agent running Chief determines which attachment types it can use. If you want Chief to delegate work on a file, say which file the agent should use in your request.

## Send the same follow-up to several tasks

In Chief's input box, name the existing tasks and give the instruction each agent should receive. For example, “Tell both the settings review and the onboarding review to check keyboard navigation.”

Open each task’s card in Overview to see the follow-up in its conversation. A finished task can start a new run. If a task is waiting for an answer or approval, respond in that conversation, then ask Chief to retry that task. The other tasks can receive the follow-up even if one is blocked.

## Remove a finished task’s worktree

From Overview, tell Chief which task’s worktree to remove. For example, “Remove the worktree for the finished settings review in my Calendar project.” Chief uses the task to identify the checkout it created.

Finish any foreground and background work first. Create a branch or tag at any task commits you want to keep. Leave the checkout in its original detached HEAD state and move out any files you want to keep, including ignored files. A locked checkout or one shared with another task must stay in place. If Chief reports a reason it kept the worktree, resolve it before asking again.

Chief also keeps the worktree if it cannot verify the files or find a saved branch or tag for a recoverable commit. If Git has already unregistered the worktree and Chief reports files left behind, inspect the folder it names. Move the remaining folder somewhere safe, then ask Chief to finish removing the same task’s worktree. If the checkout folder is gone but Chief says Git still lists it, resolve any reported permission issue and ask Chief to finish removing that same task’s worktree. You can also retry the same task after a recording failure.

After a successful removal, the checkout folder is gone. The task conversation stays in its original project, and its saved commits and branches remain in Git. Start a new task if you want an agent to do more work there.

## Find Chief's replies

In Overview, right-click Chief Bar to open your conversation above the input. The panel stays dark even when your Mac uses Light. You can also Control-click or use your trackpad’s secondary click. If you already have a draft open, right-click the bar beside the text to see the conversation and keep typing. Your messages appear in blue on the right and Chief’s replies in gray on the left. Look for the date and time in a small dark label above each exchange. To see when an individual message was sent, hold the pointer over its bubble.

Click a capsule with a globe icon in your message, Chief’s reply, or the compact bar to open the web link in your default browser. Look for the same dark capsule in both conversation bubbles. It shows the web address or the label you give it with Markdown, as in `[Project site](https://example.com)`. Hover over the link to see its address. Drag across the message to select text and links together.

While Chief is working, a small gray bubble with three dots appears on the left below the latest message. The dots rise in turn, or stay still if Reduce Motion is on. The bubble disappears when Chief finishes, stops, or encounters an error.

Each time you open the panel, you can see the end of the latest message once the messages load. A larger gap marks a change of speaker. A short exchange fits in a compact panel. Longer conversations can fill most of a small window, with the input at the bottom. Scroll up above the input to read earlier messages. Your place stays put as new replies arrive while you’re reading further up. At the top of a page, **Earlier messages** takes you further back. **Newer messages** at the bottom takes you forward.

Use the input at the bottom to reply. A draft you started in the compact bar is already there. Press **Return** or click **Send**. Your message appears on the right as soon as you send it, and the panel stays open for Chief’s reply. You can also send from the compact bar and right-click it to see your message while Chief is working. Press **Esc** or click outside the bar to close it and keep your draft.

You can revisit these messages after restarting Chief in the same profile, including saved exchanges with a previous coordinating agent. A message can be recovered as long as Chief still has its conversation record. Clearing the history removes those exchanges. Messages you sent directly to a task stay in that task’s conversation.

- **Replies.** When Chief assigns your request, look here for what it handed off. Check back for the result or anything Chief needs from you. Chief shows a short reply on the compact bar for one minute. The bar grows to about six lines. If a reply extends below the visible area, scroll inside the bar to read the rest. You can select the text or click a link to open the run with the details. Right-click the bar to read the full saved reply.
- **Task updates.** Watch the bar for **Dispatching task**. **Thread started** means the task is ready to open. If the handoff fails, the bar shows **Dispatch failed**. Open the task card in Overview to see how the work is going.
- **Links to a run.** Click the capsule with the arrow in the compact reply or in your conversation with Chief. The capsule shows Chief’s label or the task name. Each link opens the run it names, even if the agent has since started another. If the task belongs to one Super Thread, the run opens beside that report. Otherwise it opens in the task conversation. Both readers start at the top of the run. Click **×** or press **⌘K** to return to Overview. If the run is unavailable, you can still read the original message in your conversation with Chief.

## Stop Chief or a delegated task

To stop Chief's current response, hover over its eyes at the bottom of Overview and click the square **Stop Chief** button on the right. With the input box open, **Stop Chief** appears in the same spot whenever the draft cannot be sent. If you want to stop Chief while keeping a ready draft, fold the bar with **⌘⇧B**, then hover over the eyes. To stop one or more delegated tasks, name them in a message to Chief. Chief tries each request separately. You can also stop a task yourself from its conversation. [Stop a run](task-conversations.md#respond-to-a-request-or-stop-a-run)

If a message fails to send, review the error and the text in the input box before retrying. If Chief is still checking the previous send, wait for confirmation or use **Check previous receipt** if shown. Open any task card Chief already created to see what happened.

[Back to the product guide](README.md)
