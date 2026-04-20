#!/usr/bin/env python3
"""Validate unreviewed community nudge submissions."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SUBMISSIONS_DIR = ROOT / "community" / "submissions"
CORE_NUDGE_FILES = [
    ROOT / "core" / "claude-code" / "nudges.json",
    ROOT / "core" / "gemini-cli" / "nudges.json",
]

ALLOWED_CATEGORIES = {
    "context_clearing",
    "usage_monitoring",
    "security_review",
    "debugging",
    "command_discovery",
}
ALLOWED_EVENTS = {"session_start", "tool_use", "stop"}
ALLOWED_ENVIRONMENTS = {"claude-code", "gemini-cli"}
EXACT_CONDITIONS = {
    "",
    "tool_call_count_mod_20 == 0",
    "tool_call_count_mod_10 == 0",
    "last_file_ext == .env",
    "last_output_has_error == true",
}
CONDITION_PATTERNS = (
    re.compile(r"context_pct >= \d+$"),
    re.compile(r"session_duration_minutes >= \d+$"),
)
ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{2,63}$")
SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9-]{1,63}$")

PASS = 0
FAIL = 0


def pass_check(label: str) -> None:
    global PASS
    PASS += 1
    print(f"[PASS] {label}")


def fail_check(label: str) -> None:
    global FAIL
    FAIL += 1
    print(f"[FAIL] {label}")


def is_supported_condition(condition: str) -> bool:
    if condition in EXACT_CONDITIONS:
        return True
    return any(pattern.fullmatch(condition) for pattern in CONDITION_PATTERNS)


def load_json(path: Path) -> object:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def load_core_ids() -> set[str]:
    ids: set[str] = set()
    for path in CORE_NUDGE_FILES:
        data = load_json(path)
        nudges = data.get("nudges", []) if isinstance(data, dict) else []
        for entry in nudges:
            if isinstance(entry, dict):
                nudge_id = entry.get("id")
                if isinstance(nudge_id, str):
                    ids.add(nudge_id)
    return ids


def validate_submission(path: Path, core_ids: set[str], seen_ids: set[str]) -> None:
    label = path.relative_to(ROOT).as_posix()
    entry_errors = 0

    try:
        data = load_json(path)
    except json.JSONDecodeError as exc:
        fail_check(f"{label}: invalid JSON ({exc})")
        return

    if not isinstance(data, dict):
        fail_check(f"{label}: root value must be a JSON object")
        return

    required_keys = {
        "id",
        "category",
        "trigger",
        "cooldown_minutes",
        "message",
        "environments",
        "comment",
    }
    missing_keys = sorted(required_keys - data.keys())
    if missing_keys:
        fail_check(f"{label}: missing keys: {', '.join(missing_keys)}")
        return

    nudge_id = data.get("id")
    if not isinstance(nudge_id, str) or not ID_RE.fullmatch(nudge_id):
        fail_check(f"{label}: id must match {ID_RE.pattern}")
        entry_errors += 1
    elif nudge_id in core_ids:
        fail_check(f"{label}: id '{nudge_id}' already exists in core nudges")
        entry_errors += 1
    elif nudge_id in seen_ids:
        fail_check(f"{label}: duplicate community id '{nudge_id}'")
        entry_errors += 1
    else:
        seen_ids.add(nudge_id)

    category = data.get("category")
    if category not in ALLOWED_CATEGORIES:
        fail_check(
            f"{label}: category must be one of {', '.join(sorted(ALLOWED_CATEGORIES))}"
        )
        entry_errors += 1

    trigger = data.get("trigger")
    condition = ""
    if not isinstance(trigger, dict):
        fail_check(f"{label}: trigger must be an object")
        entry_errors += 1
    else:
        event = trigger.get("event")
        condition = trigger.get("condition")
        if event not in ALLOWED_EVENTS:
            fail_check(
                f"{label}: trigger.event must be one of {', '.join(sorted(ALLOWED_EVENTS))}"
            )
            entry_errors += 1
        if not isinstance(condition, str) or not is_supported_condition(condition):
            fail_check(f"{label}: trigger.condition must use a supported condition string")
            entry_errors += 1

    cooldown = data.get("cooldown_minutes")
    if not isinstance(cooldown, int) or cooldown < 0:
        fail_check(f"{label}: cooldown_minutes must be an integer >= 0")
        entry_errors += 1

    message = data.get("message")
    if not isinstance(message, str) or not message.startswith("nudge: "):
        fail_check(f"{label}: message must start with 'nudge: '")
        entry_errors += 1
    else:
        if "\n" in message or "\r" in message:
            fail_check(f"{label}: message must be a single line")
            entry_errors += 1
        if len(message) > 120:
            fail_check(f"{label}: message must be 120 characters or fewer")
            entry_errors += 1

    environments = data.get("environments")
    if not isinstance(environments, list) or not environments:
        fail_check(f"{label}: environments must be a non-empty array")
        entry_errors += 1
    else:
        invalid_envs = [env for env in environments if env not in ALLOWED_ENVIRONMENTS]
        if invalid_envs:
            fail_check(
                f"{label}: environments contains unsupported values: {', '.join(invalid_envs)}"
            )
            entry_errors += 1

    comment = data.get("comment")
    if not isinstance(comment, str) or not comment.strip():
        fail_check(f"{label}: comment must be a non-empty string")
        entry_errors += 1

    if isinstance(cooldown, int) and cooldown == 0 and condition not in {
        "tool_call_count_mod_10 == 0",
        "tool_call_count_mod_20 == 0",
    }:
        fail_check(f"{label}: cooldown_minutes=0 is reserved for milestone-based nudges")
        entry_errors += 1

    if path.name != "nudge.json":
        fail_check(f"{label}: file must be named nudge.json")
        entry_errors += 1

    parent_slug = path.parent.name
    if not SLUG_RE.fullmatch(parent_slug):
        fail_check(f"{label}: parent folder must be a lowercase slug")
        entry_errors += 1

    if entry_errors == 0:
        pass_check(f"{label}: valid")


def main() -> int:
    print("Give a Nudge - community submission validation")
    print("==============================================")

    if not SUBMISSIONS_DIR.exists():
        fail_check("community/submissions directory is missing")
        print("==============================================")
        print(f"{PASS} passed, {FAIL} failed")
        return 1

    core_ids = load_core_ids()
    seen_ids: set[str] = set()
    submission_files = sorted(SUBMISSIONS_DIR.rglob("nudge.json"))

    if not submission_files:
        pass_check("no community submissions to validate")
        print("==============================================")
        print(f"{PASS} passed, {FAIL} failed")
        return 0

    for submission in submission_files:
        validate_submission(submission, core_ids, seen_ids)

    print("==============================================")
    print(f"{PASS} passed, {FAIL} failed")
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
