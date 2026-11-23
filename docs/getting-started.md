# Get started with Chief

## Install Chief Alpha

You'll need a Mac with Apple silicon running macOS 26 or later.

1. Find the version from your invitation on the [Chief Releases page](https://github.com/hupao-creator/Chief/releases). Under **Assets**, download the arm64 disk image (`.dmg`), `SHA256SUMS`, and `READ-ME-FIRST.txt` into the same folder.
2. To verify the download, open Terminal in that folder and run `shasum -a 256 -c SHA256SUMS`. Look for the disk image's filename followed by **OK**. If the check fails, download both the disk image and checksum again from the same release before opening it.
3. Open the disk image, drag **Chief Alpha.app** into **Applications**, and eject the disk image. Open Chief Alpha from **Applications**.
4. If macOS says it can't verify the developer or check the app for malicious software, confirm that you trust this copy. In **System Settings → Privacy & Security**, find the message for Chief Alpha and click **Open Anyway**. If macOS reports malware or damage, or the app still won't open, stop and contact your inviter with the warning text and release version.

If Chief opens but says it can't connect to its background service, click **Reconnect**. When the connection succeeds, Chief shows setup or your workspace. If the message returns, include it and the release version when you contact your inviter. Remove account details and private paths before sharing a screenshot.

## Connect an agent

Chief opens in Simplified Chinese if Chinese is first in your Mac's preferred languages. For every other primary language, Chief opens in English. This guide uses the English labels. [Change appearance or language on your Mac](settings.md#change-appearance-or-language-on-your-mac)

Chief checks for Codex, Claude, Pi Agent, and OpenCode on your Mac. Each agent’s logo and name appear when it is ready. To install a missing agent, click its name with the arrow on the first setup page. Follow those instructions and sign in or set up a model as needed. Model access and costs depend on the service you use.

Return to Chief. Click **Check again** if it appears, or **Retry** next to an agent that couldn't load. You can click **Continue** once an agent that can serve as Chief is ready. Use **Back** if you want to return to the first page and check any other agents.

For a new Codex setup, Chief checks whether Codex supports its default **approve-for-me** permission mode. If that mode is unavailable on your Mac, you can continue with another ready agent. On a managed Mac, check with your administrator about supported Codex settings.

## Choose who does what

1. On the **Chief** page, choose the agent that will talk to you and coordinate your work. Below it, choose at least one agent it may assign tasks to. Complete any required model choices and click **Continue**.
2. On the next two pages, choose how to run **Tag Agent** and **Super Thread Agent**. For either role, choose **Agent off**, **Use Chief**, or **Configure separately**. If you configure a role separately, wait for its agent choices to load and complete any required fields before continuing. [What each option does](settings.md#set-up-tag-agent-and-super-thread-agent)
3. Click **Start using Chief**. The setup panel shrinks into Chief's input box. If the window stays active and visible, Chief's eyes blink once as the box appears. You can start typing as soon as setup closes.

If you see a load or save error, use **Retry** next to it. If you quit partway through setup, Chief returns to the agent check and keeps the choices you've already saved.

## Send your first request

In **Type a message…**, describe what you want done and what you'd like to get back. If you want Chief to work in a project folder, click **+** and select that folder.

Chief can reply directly or assign the work to an agent. When it creates a task conversation, click its card in **Overview** to check progress, read the result, or respond to a request. [Working with Chief](working-with-moku.md)

## Update Chief Alpha

Quit Chief Alpha before updating. In Finder, use **Go → Go to Folder** to open `~/Library/Application Support`. Back up the data folder you find there, **Chief Alpha** or **Mokusei Alpha**. If both exist, back up both. Chief Alpha uses the **Mokusei Alpha** data folder when it exists.

Replace **Chief Alpha.app** in **Applications** with the copy from the new disk image. If your installed copy is named **Mokusei Alpha.app**, move it out of **Applications** first. Open Chief Alpha and check that your conversations and settings appear.

Keep the pre-update backup if you may return to an earlier Alpha. Once Chief saves a large conversation, the earlier app may be unable to open the updated data. To go back, quit Chief, move your current data folders aside and restore the backed-up folders to their original location. The earlier app will show the conversations and settings from the time of that backup.

Alpha updates are manual, and macOS may ask for permissions again. Alpha has its own app data and uses the project folders and agent sign-ins you already have on this Mac.

[Back to the product guide](README.md)
