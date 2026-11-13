#!/usr/bin/env python3
"""Add Notchent's Claude Code hooks so the island can show Claude sessions and "Task complete".

The hook (`IslandHook claude-hook`) stores only the session id, project folder, state, times and a
300-character preview of the last reply. It prints nothing and always exits 0, so it never blocks
Claude Code. Other hooks (for example another notch app's) are left untouched. A backup is kept.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import shlex

EVENTS = ["SessionStart", "UserPromptSubmit", "Notification", "PostToolUse", "Stop", "SessionEnd"]
MARKER = " claude-hook"

_spec = importlib.util.spec_from_file_location("statusline", Path(__file__).with_name("install-claude-statusline.py"))
statusline = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(statusline)


def is_ours(hook):
    command = hook.get("command", "") if isinstance(hook, dict) else ""
    return "IslandHook" in command and command.endswith(MARKER)


def without_ours(groups):
    """Drop Notchent's hook from every matcher group, then drop groups left empty."""
    kept = []
    for group in groups if isinstance(groups, list) else []:
        if not isinstance(group, dict):
            kept.append(group)
            continue
        hooks = [hook for hook in group.get("hooks", []) if not is_ours(hook)]
        if hooks:
            kept.append({**group, "hooks": hooks})
    return kept


def merged(settings, helper, install):
    result = json.loads(json.dumps(settings))
    hooks = result.get("hooks", {})
    if not isinstance(hooks, dict):
        raise ValueError("Claude settings 'hooks' must be a JSON object")
    command = shlex.quote(str(helper)) + MARKER
    for event in EVENTS:
        groups = without_ours(hooks.get(event, []))
        if install:
            groups.append({"matcher": "", "hooks": [{"type": "command", "command": command, "timeout": 5}]})
        if groups:
            hooks[event] = groups
        else:
            hooks.pop(event, None)
    if hooks:
        result["hooks"] = hooks
    else:
        result.pop("hooks", None)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--claude-home", type=Path, default=Path.home() / ".claude")
    parser.add_argument("--support", type=Path, default=Path.home() / "Library/Application Support/IslandMac")
    parser.add_argument("--helper", type=Path, help="built IslandHook to install (required unless --uninstall)")
    parser.add_argument("--uninstall", action="store_true", help="remove Notchent's Claude hooks")
    args = parser.parse_args()
    target = args.claude_home / "settings.json"
    if target.is_symlink():
        raise ValueError("symlink settings target refused")
    original = target.read_bytes() if target.exists() else None
    settings = json.loads(original) if original else {}
    if not isinstance(settings, dict):
        raise ValueError("Claude settings must be a JSON object")
    destination = args.support / "IslandHook"
    if not args.uninstall:
        if args.helper is None:
            raise ValueError("--helper is required to install")
        statusline.install_helper(args.helper, args.support)
    updated = merged(settings, destination, install=not args.uninstall)
    if updated == settings:
        print("Nothing to change" + ("" if args.uninstall else "; helper refreshed"))
        return
    args.claude_home.mkdir(parents=True, exist_ok=True)
    if original:
        print("Backup: " + str(statusline.backup(target, original)))
    statusline.write_atomically(target, updated, original)
    print("Notchent Claude hooks " + ("removed." if args.uninstall else "installed. New Claude Code sessions pick them up."))


if __name__ == "__main__":
    main()
