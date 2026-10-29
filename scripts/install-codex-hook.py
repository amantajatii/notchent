#!/usr/bin/env python3
"""Install only IslandMac's hooks; Codex still owns trust and approval policy."""
import argparse
import datetime
import json
import os
from pathlib import Path
import shlex
import shutil
import tempfile


def merged(settings, command):
    result = json.loads(json.dumps(settings))
    hooks = result.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        raise ValueError("hooks must be an object; existing configuration was not changed")
    for event, matcher in [("PermissionRequest", None), ("PreToolUse", r"(^|\.)request_user_input(_async)?$")]:
        groups = hooks.setdefault(event, [])
        if not isinstance(groups, list) or any(not isinstance(g, dict) or not isinstance(g.get("hooks"), list) for g in groups):
            raise ValueError("invalid hook groups; existing configuration was not changed")
        entry = {"hooks": [{"type": "command", "command": command, "timeout": 125}]}
        if matcher is not None:
            entry["matcher"] = matcher
        if entry not in groups:
            groups.append(entry)
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--codex-home", type=Path, default=Path.home() / ".codex")
    parser.add_argument("--support", type=Path, default=Path.home() / "Library/Application Support/IslandMac")
    parser.add_argument("--helper", type=Path, required=True)
    args = parser.parse_args()
    target = args.codex_home / "hooks.json"
    if target.is_symlink() or args.support.is_symlink():
        raise ValueError("symlink installation target refused")
    original = target.read_bytes() if target.exists() else None
    settings = json.loads(original) if original else {}
    if not isinstance(settings, dict):
        raise ValueError("hook configuration must be an object")
    destination = args.support / "IslandHook"
    command = shlex.quote(str(destination))
    updated = merged(settings, command)
    args.support.mkdir(parents=True, exist_ok=True)
    if destination.is_symlink():
        raise ValueError("symlink helper target refused")
    if not args.helper.is_file() or not os.access(args.helper, os.X_OK):
        raise ValueError("build IslandMac before installing its helper")
    with tempfile.NamedTemporaryFile(dir=args.support, prefix=".island-helper-", delete=False) as temporary:
        helper_temp = Path(temporary.name)
    try:
        shutil.copyfile(args.helper, helper_temp)
        helper_temp.chmod(0o700)
        os.replace(helper_temp, destination)
    finally:
        helper_temp.unlink(missing_ok=True)
    args.codex_home.mkdir(parents=True, exist_ok=True)
    if updated == settings:
        print("IslandMac hooks already installed; helper refreshed")
        return
    if original:
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        backup = target.with_name("hooks.json.island-backup-" + stamp)
        with backup.open("xb") as output:
            os.fchmod(output.fileno(), 0o600)
            output.write(original)
    with tempfile.NamedTemporaryFile(dir=target.parent, prefix=".island-hooks-", delete=False) as output:
        temp = Path(output.name)
        os.fchmod(output.fileno(), 0o600)
        output.write((json.dumps(updated, indent=2, ensure_ascii=False) + "\n").encode())
        output.flush()
        os.fsync(output.fileno())
    try:
        if (target.read_bytes() if target.exists() else None) != original:
            raise RuntimeError("hook configuration changed during install; refusing to overwrite it")
        os.replace(temp, target)
    finally:
        temp.unlink(missing_ok=True)
    print("IslandMac hooks installed; other hooks and Codex trust/policy were preserved")


if __name__ == "__main__":
    main()
