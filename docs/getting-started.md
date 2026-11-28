# Get started with Chief

## Install Chief Alpha

You'll need a Mac with Apple silicon running macOS 26 or later.

1. Open the [Chief Releases page](https://github.com/hupao-creator/Chief/releases?q=draft%3Afalse). The newest release appears first. If your invitation names a version, choose that release. Expand **Assets** and download the arm64 disk image (`.dmg`), `SHA256SUMS`, and `READ-ME-FIRST.txt` into the same folder.
2. To verify the download, open Terminal in that folder and run `shasum -a 256 -c SHA256SUMS`. Look for the disk image's filename followed by **OK**. If the check fails, download both the disk image and checksum again from the same release before opening it.
3. Open the disk image. In the **Install Chief Alpha** window, drag **Chief Alpha.app** on the left onto **Applications** on the right. When copying finishes, eject the disk image. Open Chief Alpha from **Applications**.
4. If macOS says it can't verify the developer or check the app for malicious software, confirm that you trust this copy. In **System Settings → Privacy & Security**, find the message for Chief Alpha and click **Open Anyway**. If macOS reports malware or damage, or the app still won't open, stop and contact your inviter with the warning text and release version.

While Chief connects, you may see its skillet toss three agent icons. If Overview opens on **No running conversations**, the icons settle into the pan and the message appears beneath it. With Reduce Motion on, the skillet stays still while you wait and the message appears immediately when Overview opens. If Chief says it can't connect to its background service, click **Reconnect**. When the connection succeeds, Chief shows setup or your workspace. If the message returns, include it and the release version when you contact your inviter. Remove account details and private paths before sharing a screenshot.

## Explore the demo workspace

Double-click **Chief Demo.app** in Finder. If you're using the regular Chief app, choose **Help → Open Demo Workspace**. The sample workspace opens on **Checkout** with the same window controls, directory bar and Chief Dock as your workspace. You can explore it before connecting an agent.

- Open **Checkout release brief** to read a Super Thread. Click **Trace the discounted receipt** in **Related executions** to see the original calculation beside the report. You can type a practice reply in the Chief Bar beneath the execution. Returning to the list closes the input. Opening the same execution again restores your text for this demo session.
- **Keep the postal code** shows a Git branch, three changed files and the line counts. **Check the first tap on Safari** shows the conversation on the left and its checklist on the right. Open either card to read its conversation, then close the reading panel to return to the board.
- Scroll horizontally in **Checkout** to find two more Super Threads. **Wallet retry reconciliation** follows two wallet attempts to one paid order. **Where the refund cent goes** shows how three partial refunds add up to €20. Choose **API Platform** or **Launch Desk** at the top to switch projects. Open **CSV export field notes** for a comparison of three export sizes, or **Launch desk handoff** for the decision on sending a translated announcement.
- Hover over an emoji on the left to see its tag. In **Checkout**, choose **Address form** to see the postal code, pasted address and pickup tasks together. Switching folders remembers your tag for each folder. Click the current folder at the top to show all its cards again.

All conversations, file changes and running statuses are samples. Browsing works locally without an agent connection. When you’re finished, press **Command-Q** or close the window to exit the demo. Opening it again starts at **Checkout**.

For a screenshot with the translucent background, keep Chief in a regular window. Colors from the desktop show through the space between cards. Full screen uses a solid background. Press **Shift-Command-4**, press **Space**, then click the window to capture it.

## Connect an agent

Chief opens in Simplified Chinese if Chinese is first in your Mac's preferred languages. For every other primary language, Chief opens in English. This guide uses the English labels. [Change appearance or language on your Mac](settings.md#change-appearance-or-language-on-your-mac)

Chief checks for Codex, Claude, Pi Agent, and OpenCode on your Mac. Each agent’s logo and name appear when it is ready. To install a missing agent, click its name with the arrow on the first setup page. Follow those instructions and sign in or set up a model as needed. Model access and costs depend on the service you use.

Return to Chief. Click **Check again** if it appears, or **Retry** next to an agent that couldn't load. You can click **Continue** once an agent that can serve as Chief is ready. Use **Back** if you want to return to the first page and check any other agents.

For a new Codex setup, Chief checks whether Codex supports its default **approve-for-me** permission mode. If that mode is unavailable on your Mac, you can continue with another ready agent. On a managed Mac, check with your administrator about supported Codex settings.

## Choose who does what

1. On the **Chief** page, choose the agent that will talk to you and coordinate your work. Below it, choose at least one agent it may assign tasks to. Complete any required model choices, then click **Continue** to save them and open the Tag Agent page. If you change the reasoning effort for a ready Codex model, you can continue immediately.
2. On **Find your conversations**, choose how to run **Tag Agent**. Each role offers **Agent off**, **Use Chief**, or **Configure separately**. Choose **Configure separately** to edit the model already on screen. On your first visit, it starts with Chief’s choices. On later visits, it shows the choices you saved for that role. Available options update in place. Complete the required fields, then click **Continue**. You can switch away and return to the same choices. [What each option does](settings.md#set-up-tag-agent-and-super-thread-agent)
3. On **From text to pictures**, choose how to run **Super Thread Agent**, then click **Start using Chief**. The setup panel shrinks into Chief's input box. If the window stays active and visible, Chief's eyes blink once as the box appears. You can start typing as soon as setup closes.

If you choose **Configure separately** and select **OpenCode** for either role, use **OpenCode model variant** (**思考强度** in Simplified Chinese) to choose a preset. Choose **Base model variant** (**模型默认配置** in Simplified Chinese) to use the selected model’s settings without a named preset.

If you see a load or save error, use **Retry** next to it. If you quit partway through setup, Chief returns to the agent check and keeps the choices you've already saved.

## Send your first request

In **Type a message…**, describe what you want done and what you'd like to get back. If you want Chief to work in a project folder, click **+** and select that folder.

Chief can reply directly or assign the work to an agent. When it creates a task conversation, click its card in **Overview** to check progress, read the result, or respond to a request. [Working with Chief](working-with-moku.md)

## Update Chief Alpha

Quit Chief Alpha before updating. In Finder, use **Go → Go to Folder** to open `~/Library/Application Support`. Back up the data folder you find there, **Chief Alpha** or **Mokusei Alpha**. If both exist, back up both. Chief Alpha uses the **Mokusei Alpha** data folder when it exists.

Replace **Chief Alpha.app** in **Applications** with the copy from the new disk image. If your installed copy is named **Mokusei Alpha.app**, move it out of **Applications** first. Open Chief Alpha and check that your conversations and settings appear.

Keep the pre-update backup if you may return to an earlier Alpha. Once Chief saves a large conversation, the earlier app may be unable to open the updated data. To go back, quit Chief, move your current data folders aside and restore the backed-up folders to their original location. The earlier app will show the conversations and settings from the time of that backup.

Alpha updates are manual, and macOS may ask for permissions again. Alpha has its own app data and uses the project folders and agent sign-ins you already have on this Mac.

## Report a problem

Give your report a short title and describe what you tried, what you expected, and what you saw. After you submit it, you can follow replies on the public GitHub issue. [Open the Chief Alpha feedback form](https://github.com/hupao-creator/Chief/issues/new?template=alpha-feedback.yml)

[Back to the product guide](README.md)
