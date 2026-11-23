# Read and continue a task conversation

## Read a result

Click a task card in Overview to read its conversation. If the reader takes a moment to open, Chief’s skillet appears in the reading panel until the conversation is ready. Each reply appears when the agent finishes that message, even if the run continues. When the run ends, the latest finished answer stays on the page. If the run also reports an error, you can read the error alongside the answer. Reopening the conversation brings back the same result. [Overview](overview.md)

Click **Show work** when it appears for a summary, including the number of reasoning steps and tool calls when available. If you scroll up during a live run, use **Jump to latest** when it appears to return to new replies.

A Codex task continues normally when a command returns binary data. You can follow the agent’s next step in the same conversation.

When you open a Codex task, Chief’s eyes flip to the Codex logo inside the input bar. When you close the conversation, the logo flips back to the eyes as the bar shrinks.

When a conversation opens with an **Execution** sidecard on the right, the input bar glides beneath it and opens there. Click **×** at the top left of the conversation or click the blank margin to return to Overview. The bar shrinks beneath the sidecard, moves left at the same height, then rises into place at the center of Overview.

## Respond to a request or stop a run

If the agent asks a question or requests permission, respond to the prompt. The choices depend on the agent and its request.

To stop the current run, click **Stop this thread**. The button shares the **Send** position and appears when the run is active and the input box is empty. Keep any unsent draft you want before clearing the box. When the run stops, Chief receives a notification that you stopped it. You can send a new message to continue later. Closing the conversation or its **Execution** sidecard leaves the task running. [Watch a live run](sidecards.md#watch-a-run-in-progress)

## Send a follow-up or attachment

Type your follow-up in **Type a message…** and click **Send** or press Return. Use Shift+Return for a new line. When you send to a running agent, your message fades into place alongside the agent’s work. With Reduce Motion on, it appears in place immediately. If the run has ended, sending starts a new run in the same conversation. Answer any pending question or permission request first.

Click **+** to attach files or point the agent to a folder on your Mac. Command-click to select several items together. Their names or image previews appear above your draft. Supported attachments vary by agent. If the agent rejects an attachment, remove it and try a supported type or describe it in text. You can return to finish an unsent draft after opening a different conversation.

If Chief is still connected to a background service from before an update, your message appears when the agent records it.

When you send from the latest finished result, the **Execution** sidecard opens immediately. You can fold it or switch to another sidecard while the run starts.

You can start writing the next message while Chief confirms the previous send. Once the send succeeds, the next draft stays in the box. If the send is rejected, Chief puts the earlier message above your new text so you can review both before sending.

## Revisit or branch from an earlier run

When there are several runs to read, look for the short horizontal lines halfway down the left edge of the reading area. Each line in **Conversation contents** represents a run, from oldest at the top to newest at the bottom. The darker line marks the run on screen. Hover over a line and it extends to the right, along with the lines nearest to it.

Hover over a line to preview the run, then click it to read. With keyboard focus on **Conversation contents**, use the Up and Down arrows to preview runs and Return to open one. Click the newest run’s line to return to it. You can then press Up to preview the previous run again. Any newer work keeps going while you read.

If you send a message from an earlier run, Chief tries to start a separate conversation from that point. The original stays intact. Branching depends on whether the agent can recover the selected run's history.

## Recover an interrupted send

If you see **Check the conversation for this interrupted send**, use **Check previous receipt** when available. If Chief asks you to check the conversation yourself, look for the earlier message. Choose **Keep next draft** if it arrived or **Restore to draft** to put it back above the new text. Review the draft before sending again.

If Chief says a branch was created but the message didn't send, choose what to keep and continue in that branch. If you see **Finish previous receipt cleanup**, click it before trying to send again.

[Back to the product guide](README.md)
