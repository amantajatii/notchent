#!/usr/bin/env python3
"""Point Claude Code's status line at IslandHook so Notchent can show Claude plan limits.

Only the documented `rate_limits` field is saved; the status line still prints a short summary.
An existing, different status line is never replaced unless --replace is given.
"""
import argparse
import datetime
import json
import os
from pathlib import Path
import shlex
import shutil
import tempfile


def status_line(helper):
    return {"type": "command", "command": shlex.quote(str(helper)) + " claude-statusline"}


def merged(settings, entry, replace):
    current = settings.get("statusLine")
    if current is not None and current != entry and not replace:
        raise ValueError("a different statusLine is already configured; rerun with --replace to swap it (a backup is kept)")
    result = json.loads(json.dumps(settings))
    result["statusLine"] = entry
    return result


def install_helper(source, support):
    destination = support / "IslandHook"
    if support.is_symlink() or destination.is_symlink():
        raise ValueError("symlink helper target refused")
    if not source.is_file() or not os.access(source, os.X_OK):
        raise ValueError("build Notchent before installing its helper")
    support.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=support, prefix=".island-helper-", delete=False) as temporary:
        helper_temp = Path(temporary.name)
    try:
        shutil.copyfile(source, helper_temp)
        helper_temp.chmod(0o700)
        os.replace(helper_temp, destination)
    finally:
        helper_temp.unlink(missing_ok=True)
    return destination


def backup(target, original):
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    path = target.with_name(target.name + ".island-backup-" + stamp)
    with path.open("xb") as output:
        os.fchmod(output.fileno(), 0o600)
        output.write(original)
    return path


def write_atomically(target, settings, original):
    with tempfile.NamedTemporaryFile(dir=target.parent, prefix=".island-settings-", delete=False) as output:
        temp = Path(output.name)
        os.fchmod(output.fileno(), 0o600)
        output.write((json.dumps(settings, indent=2, ensure_ascii=False) + "\n").encode())
        output.flush()
        os.fsync(output.fileno())
    try:
        if (target.read_bytes() if target.exists() else None) != original:
            raise RuntimeError("settings changed during install; refusing to overwrite them")
        os.replace(temp, target)
    finally:
        temp.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--claude-home", type=Path, default=Path.home() / ".claude")
    parser.add_argument("--support", type=Path, default=Path.home() / "Library/Application Support/IslandMac")
    parser.add_argument("--helper", type=Path, required=True)
    parser.add_argument("--replace", action="store_true", help="replace an existing, different statusLine")
    args = parser.parse_args()
    target = args.claude_home / "settings.json"
    if target.is_symlink():
        raise ValueError("symlink settings target refused")
    original = target.read_bytes() if target.exists() else None
    settings = json.loads(original) if original else {}
    if not isinstance(settings, dict):
        raise ValueError("Claude settings must be a JSON object")
    destination = args.support / "IslandHook"
    updated = merged(settings, status_line(destination), args.replace)
    install_helper(args.helper, args.support)
    if updated == settings:
        print("Claude status line relay already installed; helper refreshed")
        return
    args.claude_home.mkdir(parents=True, exist_ok=True)
    if original:
        print("Backup: " + str(backup(target, original)))
    write_atomically(target, updated, original)
    print("Claude status line relay installed. Limits appear after Claude Code's next response.")


if __name__ == "__main__":
    main()
