# Change Chief settings

## Open Settings and save changes

From **Overview**, click the **Settings** gear in the upper-right corner, press **⌘,**, or choose **Settings…** from the Chief menu. If you're reading a conversation or a Super Thread, press **⌘K** to return to Overview first.

Settings opens on **Chief Agent**, with Overview blurred behind it. Close Settings to save your agent changes and return to the same place on the canvas. If the panel stays open, check the message and complete any required choices. If a save error appears after the panel closes, reopen Settings and click **Retry saving**. If the saved settings changed elsewhere, choose **Keep my changes and retry** to apply your choices or **Discard draft and load latest settings** to use the saved ones.

## Choose who coordinates and who can take tasks

On the **Chief Agent** tab, choose the coordinating agent in the top row and at least one agent it can assign tasks to in the bottom row. Dashed lines connect Chief to the agents it can assign work to. Use **Chief Model** to choose the coordinating agent’s model. Before switching the coordinating agent, finish work that's running, waiting for a response, or waiting to send. Switching to a different agent starts a new Chief session. You can still read the saved messages from the previous agent by right-clicking Chief Bar in Overview.

You can change a ready agent’s settings while Chief checks the others. Close Settings, then reopen **Chief Agent** to see the saved model and reasoning choice or variant. If an agent check fails, click **Retry** to check again.

If Chief says no agents are available, install and sign in to a supported agent on your Mac, then return to the **Chief Agent** tab and click **Retry**. [Supported agents](getting-started.md#connect-an-agent)

Antigravity takes ordinary tasks. To enable it, select its multicolor A in the bottom row and look for a dashed line from Chief. Expand **Antigravity** below the map to choose **Authentication**. **Use native settings** uses the account set up in `agy`. If you choose a sign-in method, complete its setup in `agy`. Close Settings to save, then ask Chief to assign Antigravity a task in your chosen project folder. Open the folder in Overview and click the task card to read the reply.

Use **Task Orchestration Preferences** to guide which models Chief chooses when it assigns tasks. Pick **Economy**, **Balanced**, or **Performance**, or select **Custom** and click the text box below. When the cursor appears, describe what you prefer. The hint disappears as you type. Hover over a choice marked with an info icon to read its description. Chief keeps your custom text if you switch presets. Chief chooses from the agents you've enabled and the models available when it assigns the work.

Chief can use Artificial Analysis measurements for the specific model and reasoning effort it matched. If you ask Chief to compare models, it can compare Intelligence Index scores and cost per task when their published index versions match. A model with an unknown version stays available for assignment.

## Set up Tag Agent and Super Thread Agent

Use **Auto-Categorization** to set up Tag Agent and **Super Thread** to set up Super Thread Agent. Each page lists the installed agents that can run that role. You can use Antigravity for ordinary tasks alongside either role. When an agent is available, an illustration on a rounded glass panel plays above the role's settings. In the Super Thread illustration, several documents come together into one page with three diagrams. You can turn either role on independently. Hover over a choice marked with an info icon to see what it does.

- **Agent off** stops automatic work for that role and keeps its existing tags or Super Threads and saved choices. Pending work resumes when you turn the agent back on.
- **Use Chief** uses Chief's agent and model settings for future work.
- **Configure separately** opens with the role’s saved choices, or Chief’s choices the first time. You can edit them while the list of models updates. If a refresh fails, use **Retry** in the form. Chief keeps those choices if you later switch to **Use Chief** or **Agent off**.

Choose **OpenCode** to see its providers, models and variants. If **Loading Agent configuration…** appears, wait for the options to open, then make your selections. If your saved model is marked **Unavailable in catalog**, check the provider in OpenCode or choose another listed model.

[Find tags and Super Threads](reports-tags-and-changes.md)

## Reset Chief and start setup again

Open **Settings** from Overview. Press and hold the eyes at the left end of the Settings header for three seconds, until the confirmation appears. Release early or drag away to abandon the hold. Choose **Cancel** to keep working with your current settings and history.

**Erase and Restart** permanently clears the current Chief profile. This includes conversations, Super Threads, tags, agent settings, unsent drafts, Chief’s attachment and transfer copies, saved agent sessions, usage records, reading and command history, and local caches such as the Codex plugin catalog stored by Chief. Chief stops active work. Your project files, task folders, Git worktrees, and external agents’ accounts, credentials and history stay on disk.

After Chief restarts, the first setup page opens. If Chief reports that another window is using this profile, quit the other copy and try again. If reset stops with an error, keep the error message and reopen Chief. It finishes a pending erase before opening the workspace.

## Change appearance or language on your Mac

To change Chief's appearance, open **System Settings → Appearance** on your Mac and choose **Light**, **Dark**, or **Auto**. You can see the change in Overview. The first-run setup panel, Settings, Chief Bar, and your conversation with Chief stay dark.

Chief uses Simplified Chinese when Chinese is first in your Mac's preferred languages. It uses English when English or any other language is first. To change the order, go to **System Settings → General → Language & Region** and check the labels in Chief after macOS applies the change.

[Back to the product guide](README.md)
