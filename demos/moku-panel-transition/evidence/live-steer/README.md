# Live follow-ups in a Report sidecard

Open the [window recording](sidecard.mp4) at 2.96s and 6.85s to see two clicks
on **Send** during one running execution. Each follow-up and its timestamp rise
and fade into place together. The Report stays open on the left. The [frame
strip](frames.png) shows five crops from each entrance at the labeled video
times. The first message retained over 99.9% of its settled glyph contrast
in the 78 sampled frames around the second send.

The recording uses Chief, its Go Runtime and the installed Codex CLI in an
isolated macOS profile. A local Responses peer supplies the test replies and
keeps the execution streaming. System keyboard input fills the sidecard draft
and system pointer clicks submit it. The public turn contains each typed text
once as a follow-up to the same execution. The [observations](observations.json)
identify the tested production commit, binary and video hashes, control hits,
execution IDs and persisted messages.

In a separate run on the same build, a long reply filled the sidecard. After
scrolling to 230pt, two more sends grew the content from 2,353pt to 6,866pt.
All 124 timeline observations retained the 230pt offset with following off.
The [test procedure](../../../../tools/e2e/README.md#live-follow-up-in-a-related-execution)
describes the interaction. The window recordings used normal motion.
The [receipt replay](../../README.md#host-receipt-replay) exercises the
reduced-motion environment on the mounted reader.
