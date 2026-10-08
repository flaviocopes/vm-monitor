#!/usr/bin/env python3
"""Writes a made-up testvm history into a folder laid out like a home folder, to test VM Peek in the VM:
four chats (Cursor, Claude Code, Codex and someone in a terminal), their transcripts, command output,
and images.txt, the screenshots the log points to, one "App<TAB>/tmp/testvm/file.png" per line.

Usage: Scripts/sample-activity.py /tmp/vm-monitor-sample [VM home folder]
"""

import json
import os
import sys
import time

out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/vm-monitor-sample"
vm_home = sys.argv[2] if len(sys.argv) > 2 else "/Users/admin"
now = time.time()
logs = os.path.join(out, "Library/Logs/testvm")
os.makedirs(os.path.join(logs, "runs"), exist_ok=True)
lines, images = [], []
counter = 0


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


def run(chat, ago, command, args=(), took=1.2, status=0, output="", last=None, input=None, running=False, pid=None):
    global counter
    counter += 1
    started = now - ago
    run_id = time.strftime("%Y%m%d-%H%M%S", time.localtime(started)) + f"-{9000 + counter}"
    start = {
        "v": 1, "event": "start", "id": run_id, "time": round(started, 3), "pid": pid or 9000 + counter,
        "command": command, "args": list(args), "cwd": chat["cwd"], "agent": chat["agent"],
        "session": chat["session"], "target": "vm",
    }
    if chat.get("transcript"):
        start["transcript"] = chat["transcript"]
    if input:
        start["input"] = input
    lines.append(start)
    if command == "shot" and status == 0:
        name = args[0] if args else "screen"
        path = f"/tmp/testvm/{name.replace(' ', '-')}-{time.strftime('%H%M%S', time.localtime(started))}.png"
        images.append((name, path))
        output = path + "\n"
    if output:
        write(os.path.join(logs, "runs", run_id + ".txt"), output)
    if running:
        return
    if last is None:
        printed = [line for line in output.splitlines() if line.strip()]
        last = printed[-1][:300] if printed else ""
    lines.append({"v": 1, "event": "end", "id": run_id, "time": round(started + took, 3), "status": status, "last": last})


cursor = {
    "agent": "cursor", "session": "7c1e2a4b-5d3f-4e8a-9b6c-1f2e3d4c5b6a", "cwd": "/Users/flavio/dev/skill-cabinet",
    "prompt": "Add a Sort by usage option to the skills list in Skill Cabinet, so the skills I use most come first. Check it in the test VM.",
}
cursor["transcript"] = (
    f"{vm_home}/.cursor/projects/Users-flavio-dev-skill-cabinet/agent-transcripts/"
    f"{cursor['session']}/{cursor['session']}.jsonl"
)
claude = {
    "agent": "claude", "session": "claude-48213", "cwd": "/Users/flavio/dev/note-repo",
    "prompt": "The New Note button does nothing when the sidebar is collapsed. Fix it and test it in the VM.",
}
codex = {
    "agent": "codex", "session": "01a3f2c4-8b1d-7e20-9c4a-5f6e7d8c9b0a", "cwd": "/Users/flavio/dev/tranquillity-maker",
    "prompt": "Release Tranquillity Maker 1.3. Check the new rain sound in the VM before tagging.",
}
terminal = {"agent": "terminal", "session": "terminal-ttys004", "cwd": "/Users/flavio/dev/number-pantry"}

skillscout_ui = """WINDOW "Skill Cabinet"
AXStaticText "Skills"  center 120,96
AXPopUpButton [pop up button] = Newest first  center 855,113
AXButton "Find repeated tasks"  center 976,113
AXTextField [search text field]  center 1171,114
AXStaticText "flavioify"  center 300,180
AXStaticText "mac-test-vm"  center 300,240
"""
noterepo_ui = """WINDOW "Note Repo"
AXButton "Hide Sidebar"  center 64,60
AXButton "New Note"  center 120,60
AXTextArea [text entry area]  center 760,420
"""
soundscape_ui = """WINDOW "Tranquillity Maker"
AXButton "Rain"  center 420,380
AXButton "Forest"  center 620,380
AXSlider [slider] = 0.6  center 520,520
"""

# Codex, two and a half hours ago: one open timed out, the next one worked.
run(codex, 9000, "push", ["/Users/flavio/dev/tranquillity-maker/Tests/Fixtures/sounds/", "Library/Application Support/Soundscape/sounds/"], took=2.1)
run(codex, 8990, "open", ["build/Build/Products/Release/Tranquillity Maker.app"], took=60, status=143, output="")
run(codex, 8900, "open", ["build/Build/Products/Release/Tranquillity Maker.app"], took=2.9, output="Tranquillity Maker is open\n")
run(codex, 8890, "shot", ["Tranquillity Maker"], took=0.6)
run(codex, 8880, "ui", ["Tranquillity Maker"], took=0.9, output=soundscape_ui)
run(codex, 8870, "click", ["420", "380"], took=0.2)
run(codex, 8860, "shot", ["Tranquillity Maker"], took=0.6)
run(codex, 8850, "quit", ["Tranquillity Maker"], took=0.8, output="quit Tranquillity Maker\n")

# Someone in a terminal, yesterday.
run(terminal, 90000, "status", took=0.1, output="running at 192.168.64.3\n")
run(terminal, 89990, "open", ["dist/Number Pantry.app"], took=4.4, output="Number Pantry is open\n")
run(terminal, 89980, "shot", ["Number Pantry"], took=0.7)
run(terminal, 89900, "quit", ["Number Pantry"], took=0.9, output="quit Number Pantry\n")

# Cursor, working on Skill Cabinet for the last 25 minutes.
run(cursor, 1500, "note", ["Testing the new Sort by usage option in the skills list"], took=0.02)
run(cursor, 1495, "open", ["build/Build/Products/Debug/Skill Cabinet.app"], took=3.8, output="Skill Cabinet is open\n")
run(cursor, 1488, "shot", ["Skill Cabinet"], took=0.6)
run(cursor, 1480, "ui", ["Skill Cabinet"], took=1.1, output=skillscout_ui)
run(cursor, 1472, "click", ["855", "113"], took=0.2)
run(cursor, 1468, "click", ["840", "160"], took=0.2)
run(cursor, 1460, "shot", ["Skill Cabinet"], took=0.6)
run(cursor, 900, "open", ["build/Build/Products/Debug/Skill Cabinet.app"], took=4.1, output="Skill Cabinet is open\n")
run(cursor, 890, "ui", ["Skill Cabinet"], took=1.0, output=skillscout_ui)
run(cursor, 884, "click", ["1171", "114"], took=0.2)
run(cursor, 880, "type", ["flavioify"], took=0.3)
run(cursor, 876, "key", ["cmd+a"], took=0.2)
run(cursor, 870, "shot", ["Skill Cabinet"], took=0.6)
run(cursor, 300, "script", took=0.4, input='tell application "System Events" to tell process "Skill Cabinet"\n  click menu item "Settings…" of menu "Skill Cabinet" of menu bar 1\nend tell')
run(cursor, 295, "shot", ["Skill Cabinet"], took=0.6)
run(cursor, 40, "logs", ["Skill Cabinet"], took=0.2, output="Loaded 42 skills from 3 folders\nSorting by usage: 18 skills used this month\n")
# pid 1 is always alive, so this one shows as running.
run(cursor, 20, "open", ["build/Build/Products/Debug/Skill Cabinet.app", "--reset-defaults"], running=True, pid=1)

# Claude Code, on Note Repo at the same time, so the two overlap.
run(claude, 600, "note", ["Reproducing the New Note bug with the sidebar collapsed"], took=0.02)
run(claude, 595, "open", ["dist/mac-arm64/Note Repo.app"], took=5.2, output="Note Repo is open\n")
run(claude, 585, "ui", ["Note Repo"], took=0.8, output=noterepo_ui)
run(claude, 580, "click", ["64", "60"], took=0.2)
run(claude, 576, "click", ["120", "60"], took=0.2)
run(claude, 572, "shot", ["Note Repo"], took=0.7)
run(claude, 330, "open", ["dist/mac-arm64/Note Repo.app"], took=4.9, output="Note Repo is open\n")
run(claude, 320, "key", ["cmd+n"], took=0.2)
run(claude, 316, "type", ["Groceries for the weekend"], took=0.4)
run(claude, 312, "shot", ["Note Repo"], took=0.3, status=1, output="testvm: no window for Note Repo\n")
run(claude, 305, "logs", ["Note Repo"], took=0.2, output="Uncaught TypeError: Cannot read properties of undefined (reading 'id')\n    at createNote (renderer.js:812)\n")
run(claude, 70, "open", ["dist/mac-arm64/Note Repo.app"], took=5.0, output="Note Repo is open\n")
run(claude, 60, "key", ["cmd+n"], took=0.2)
run(claude, 55, "shot", ["Note Repo"], took=0.7)

lines.sort(key=lambda line: line["time"])
write(os.path.join(logs, "activity.jsonl"), "".join(json.dumps(line, ensure_ascii=False) + "\n" for line in lines))

day = time.strftime("%Y/%m/%d", time.localtime(now - 9000))
user_query = f"<timestamp>Saturday</timestamp>\n<user_query>\n{cursor['prompt']}\n</user_query>"
write(
    os.path.join(out, f".cursor/projects/Users-flavio-dev-skill-cabinet/agent-transcripts/{cursor['session']}/{cursor['session']}.jsonl"),
    json.dumps({"role": "user", "message": {"content": [{"type": "text", "text": user_query}]}}) + "\n",
)
write(
    os.path.join(out, ".claude/projects/-Users-flavio-dev-note-repo/3fcd5a84-8d05-470d-9c9f-81ef6976ab23.jsonl"),
    json.dumps({"type": "user", "message": {"role": "user", "content": claude["prompt"]}}) + "\n",
)
write(
    os.path.join(out, f".codex/sessions/{day}/rollout-2026-10-03T16-40-00-{codex['session']}.jsonl"),
    json.dumps({"type": "session_meta", "payload": {"id": codex["session"]}}) + "\n"
    + json.dumps({"type": "event_msg", "payload": {"type": "user_message", "message": codex["prompt"]}}) + "\n",
)
write(os.path.join(out, "images.txt"), "".join(f"{name}\t{path}\n" for name, path in images))
print(f"Wrote {len(lines)} log lines and {len(images)} screenshot paths to {out}")
