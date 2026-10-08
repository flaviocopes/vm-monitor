# VM Peek

A SwiftUI Mac app that shows what coding agents do in a macOS test VM. Agents drive the VM with `testvm`, which logs every command. The app reads that log, finds each chat's prompt in the agents' transcripts, and grabs the VM's screen over SSH. A Swift package with no dependencies.

`testvm` has its own repo, [flaviocopes/testvm](https://github.com/flaviocopes/testvm). It writes `~/Library/Logs/testvm/activity.jsonl` and `runs/<id>.txt`, the files the app reads. Install it from there to work on this app.

- `Sources/MonitorCore`: everything that isn't UI, with tests.
  - `Run.swift`: `LogEvent` (one line of the log), `Agent`, `Run` (one command, from its start and end lines) and `RunState`. A run without an end line is running while its pid lives, for at most 30 minutes. Exit 130 and 143 mean Ctrl-C or the agent's timeout stopped it.
  - `Activity.swift`: builds runs from events, and groups them into `Session`s (one per chat) and `AppInfo`s. Clicks, keys, typing and scripts belong to the app the same chat named last.
  - `ActivityLog.swift`: reads the log a little at a time, keeps a half-written line for the next read, and starts over with `activity.1.jsonl` when `testvm` rotates the log.
  - `Describe.swift`: the plain-words summaries, keys as symbols, the shell-quoted command line, and `Control`, which parses `testvm ui` listings so a click can name the control at its coordinates.
  - `Transcripts.swift`: finds a chat's transcript (Cursor by chat id, Codex by thread id and day, Claude Code by the project folder) and reads its first prompt. `Project` names a folder after its git root.
  - `VM.swift`: reads `~/.config/testvm/config`, asks Tart whether `mac-test` runs, and runs the screenshot and open-apps commands over SSH with `testvm`'s own options, so both share one connection.
- `Sources/VMMonitorApp`: the app. `AppModel` reads the log every second, checks the VM every 3 seconds and grabs the screen every 2 while Live is open and the window is visible. `ContentView` (split view, sidebar, inspector), `LiveView`, `ActivityView` (timelines and their headers, `RunRow`), `RunInspector`, `Styling.swift`.
- `Sources/VMMonitorApp/AppUpdater.swift`: checks the GitHub releases once a day and installs updates. It's an identical copy of the template in the `mac-app-updater` skill, so change the template and copy it over instead of editing it here.
- `Scripts/sample-activity.py`: a made-up history with four chats, their transcripts and output.

## Build and test

Requirements: macOS 15 or later, Swift 6.2 (Xcode 26).

```bash
swift test                                         # must pass before committing
Scripts/build-app.sh                               # universal dist/VM Peek.app
Scripts/build-release.sh                           # signs, notarizes and zips it into dist/VM-Peek-<version>.zip
Scripts/screenshot.sh <screen.png> <shots folder>  # docs/screenshot-*.png and docs/chat-*.png, rendered in the VM
swift Scripts/render-banner.swift                  # docs/banner.png, from docs/screenshot-dark.png
swift Scripts/render-icon.swift Assets/AppIcon.png # after changing a constant
```

Don't open the app on your own screen to check a change. Test it in the VM with `testvm`, the way it's meant to be used:

1. The VM has no Tart and no history. Give it its own SSH key to log into itself, generated inside the VM, and put `TEST_HOST=localhost` in the VM's `~/.config/testvm/config`. Never copy your own `testvm` key into the VM.
2. Run `Scripts/sample-activity.py /tmp/vm-monitor-sample` and push its `Library/Logs/testvm/`, `.cursor/`, `.claude/` and `.codex/` folders to the VM's home. `images.txt` lists the screenshots the log points to. Push images to those paths in `/tmp/testvm/`.
3. `testvm open "dist/VM Peek.app"`. The Live view shows the VM's own screen, with the app inside it.
4. Remove what you added. The VM's home can hold other test data, so delete only your files.

`Scripts/screenshot.sh` does all of this for the README images, and cleans up after itself. Other agents can be using the VM, so pass it images of apps that are already public instead of capturing whatever is on the screen.

## Rules

- The app only watches. It never clicks, types or opens anything in the VM, and never starts or stops it.
- The log format is a contract between `testvm` and `ActivityLog`, across the two repos. Change both together, and keep old lines readable: new fields are optional.
- `VM.sshArguments` uses the same SSH options and `ControlPath` as `testvm`, so they share one connection. Keep them in sync.
- The VM screenshot goes to `/tmp/vm-monitor.jpg` in the VM, never to `testvm`'s files, so it can't clash with an agent's `testvm shot`.
- Screenshots live in `/tmp/testvm` on the Mac, which macOS empties when it restarts. The app shows a placeholder for the ones that are gone.
- Releases are minor by default (1.1.0): new features, changes people notice, and bug fixes people care about. A point release (1.0.1) is only for really unimportant stuff. The `open-source-release` skill has the rule. The version lives in `Sources/VMMonitorApp/Version.swift`.
- The updater trusts the GitHub release. Every release needs its `vX.Y.Z` tag, the zip from `Scripts/build-release.sh` attached, and an app version that matches the tag, or the app refuses the update.
- Releases are signed with Flavio Copes's Developer ID (team `DGFKNTAG99`) with the hardened runtime, and notarized by `Scripts/build-release.sh` when the certificate is in the keychain and a notarytool profile named `notary` exists. CI and forks have no certificate, so the scripts sign ad hoc there and skip notarization.
- The app isn't sandboxed, because it reads the agents' transcripts and runs `ssh` and `tart`.

## Naming compatibility

The public app name is VM Peek. Keep its existing bundle ID, saved data paths, URL schemes, CLI commands and internal Swift targets so installed copies and agent integrations remain compatible. Use the renamed checkout folder and GitHub repository in new links and build instructions.
