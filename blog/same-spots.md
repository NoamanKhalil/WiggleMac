# A workflow replays the same spots

A workflow clicks the same screen positions, at the speed you recorded. Move a window, and it still aims at the old spot. It does not look at the screen and choose again.

By Noaman · November 9, 2026
## Key points

- A workflow replays fixed screen positions.
- Windows need to be where they were when you recorded.
- It plays at the speed you recorded, from 1 to 99 times.
- It does not use AI, read the screen, or adapt.
- Esc pauses. A wiggle, or the stop button, stops the run.

## Same spots
Press play next to a saved workflow and it goes back to the spots you clicked, in the same order, at the speed you recorded. You can run it 1 to 99 times in a row. A small bar shows progress, such as “Step 3 of 14 · run 2 of 5”, and places itself away from the spots the workflow clicks.

How to record one is in [Record a workflow and play it back](/blog/workflow/).

## If a window moved
The replay does not look for the button by name. It aims at the position on the screen. If you dragged the window, or the Mac opened it somewhere else, the click still lands on the old spot.

Put the windows back where they were when you recorded, then press play. A careful drag across the screen while you were recording is a step too, so the first recording is worth keeping short.

## What stops a run
Esc pauses between steps. Esc again resumes. A wiggle, or the stop button, stops the run. A run also stops if a display is connected or disconnected, or the Mac goes to sleep.

Esc cannot be recorded as a step. While you are recording, Esc pauses and resumes, and nothing you do while paused is recorded.

## What it never does
A workflow does not use AI, read the screen, or adapt to changes. It does not record audio. macOS withholds keystrokes typed into password fields, so passwords are never recorded.

The file stays on your Mac, in ~/Library/Application Support/Wiggle/workflows.json, and is never sent anywhere. Workflow needs Accessibility. macOS asks for it the first time you record or run a workflow.

## Questions
What if a workflow goes wrong? Esc pauses between steps. Esc again resumes. A wiggle, or the stop button, stops the run.

Does this website move my pointer? No. The preview and the films do not record, replay, or move your pointer.
