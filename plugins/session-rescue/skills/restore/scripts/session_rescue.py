#!/usr/bin/env python3
"""Find and rebuild Claude Code desktop sessions that vanished from the Code tab.

The Code tab lists *cards* stored under
    ~/Library/Application Support/Claude/claude-code-sessions/<org>/<account>/local_<uuid>.json
while the conversation itself lives in a separate transcript
    ~/.claude/projects/<project-slug>/<cliSessionId>.jsonl

Deleting a session removes the card and leaves a `deleted_<cliSessionId>` tombstone
(its contents are the deletion time in epoch ms). The transcript is untouched, so the
session can be put back by writing a new card that points at the same cliSessionId.

Subcommands:
    scan                      list transcripts that have no card (deleted / never imported)
    show <cliSessionId>       print a longer preview of one transcript
    restore <cliSessionId>    write a new card for it and move its tombstone aside
"""

from __future__ import annotations

import argparse
import datetime as dt
import glob
import json
import os
import pathlib
import shutil
import sys
import uuid

SESSIONS_ROOT = pathlib.Path(
    os.path.expanduser("~/Library/Application Support/Claude/claude-code-sessions")
)
PROJECTS_ROOT = pathlib.Path(os.path.expanduser("~/.claude/projects"))
BACKUP_ROOT = pathlib.Path(os.path.expanduser("~/.claude/session-rescue-backups"))

# A transcript this short is an aborted start, not a conversation worth restoring.
MIN_INTERESTING_LINES = 20


def account_dirs() -> list[pathlib.Path]:
    """Every <org>/<account> directory that actually holds cards or tombstones."""
    found = []
    for path in SESSIONS_ROOT.glob("*/*"):
        if not path.is_dir():
            continue
        if any(path.glob("local_*.json")) or any(path.glob("deleted_*")):
            found.append(path)
    return found


def read_cards(account: pathlib.Path) -> dict[str, dict]:
    """cliSessionId -> card, skipping cards that fail to parse."""
    cards = {}
    for path in account.glob("local_*.json"):
        try:
            card = json.loads(path.read_text())
        except (json.JSONDecodeError, OSError):
            continue
        cli_id = card.get("cliSessionId")
        if cli_id:
            card["_path"] = str(path)
            cards[cli_id] = card
    return cards


def read_tombstones(account: pathlib.Path) -> dict[str, int]:
    """cliSessionId -> deletion time in epoch ms (0 when unreadable)."""
    stones = {}
    for path in account.glob("deleted_*"):
        try:
            stones[path.name[len("deleted_"):]] = int(path.read_text().strip())
        except (ValueError, OSError):
            stones[path.name[len("deleted_"):]] = 0
    return stones


def transcripts() -> dict[str, pathlib.Path]:
    """cliSessionId -> transcript path."""
    return {
        pathlib.Path(p).stem: pathlib.Path(p)
        for p in glob.glob(str(PROJECTS_ROOT / "*" / "*.jsonl"))
    }


def summarize(path: pathlib.Path, max_messages: int = 2) -> dict:
    """Cheap preview of a transcript: when it ran, where, and what was asked."""
    first_ts = last_ts = None
    cwd = None
    lines = 0
    prompts: list[tuple[str, str]] = []

    with path.open() as handle:
        for line in handle:
            if not line.strip():
                continue
            lines += 1
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            ts = row.get("timestamp")
            if ts:
                first_ts = first_ts or ts
                last_ts = ts
            cwd = cwd or row.get("cwd")
            if row.get("type") != "user" or row.get("isSidechain"):
                continue
            message = row.get("message") or {}
            content = message.get("content")
            if isinstance(content, list):
                content = " ".join(
                    part.get("text", "")
                    for part in content
                    if isinstance(part, dict) and part.get("type") == "text"
                )
            if not isinstance(content, str):
                continue
            text = content.strip()
            # Skip harness-injected turns; they say nothing about what the user wanted.
            if not text or text.startswith("<") or text.startswith("[Request interrupted"):
                continue
            if len(prompts) < max_messages:
                prompts.append((ts or "", " ".join(text.split())))

    return {
        "path": str(path),
        "lines": lines,
        "size": path.stat().st_size,
        "cwd": cwd,
        "first_ts": first_ts,
        "last_ts": last_ts,
        "prompts": prompts,
    }


def local(ts: str | None) -> str:
    if not ts:
        return "?"
    try:
        parsed = dt.datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return ts[:19]
    return parsed.astimezone().strftime("%Y-%m-%d %H:%M")


def epoch_ms(ts: str | None, fallback: int) -> int:
    if not ts:
        return fallback
    try:
        parsed = dt.datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return fallback
    return int(parsed.timestamp() * 1000)


def collect(include_short: bool = False) -> list[dict]:
    """Transcripts with no card, annotated with tombstone info when deleted."""
    all_cards: dict[str, dict] = {}
    all_stones: dict[str, int] = {}
    for account in account_dirs():
        all_cards.update(read_cards(account))
        all_stones.update(read_tombstones(account))

    rows = []
    for cli_id, path in transcripts().items():
        if cli_id in all_cards:
            continue
        info = summarize(path)
        if not include_short and info["lines"] < MIN_INTERESTING_LINES:
            continue
        info["cliSessionId"] = cli_id
        info["deleted_at"] = all_stones.get(cli_id)
        rows.append(info)

    rows.sort(key=lambda row: row["last_ts"] or "", reverse=True)
    return rows


def cmd_scan(args: argparse.Namespace) -> int:
    rows = collect(include_short=args.all)
    if not rows:
        print("No restorable transcripts: every transcript on disk already has a card.")
        return 0

    print(f"{len(rows)} transcript(s) with no entry in the Code tab:\n")
    for row in rows:
        mark = "deleted" if row["deleted_at"] else "never imported"
        when = (
            dt.datetime.fromtimestamp(row["deleted_at"] / 1000).strftime("%Y-%m-%d %H:%M")
            if row["deleted_at"]
            else "-"
        )
        print(f"  {row['cliSessionId']}  [{mark}{'' if when == '-' else ' ' + when}]")
        print(f"    {local(row['first_ts'])} -> {local(row['last_ts'])}"
              f"  |  {row['lines']} lines  |  {row['size'] // 1024} KB")
        print(f"    cwd: {row['cwd'] or '?'}")
        for _, text in row["prompts"][:1]:
            print(f"    first prompt: {text[:110]}")
        print()
    return 0


def cmd_show(args: argparse.Namespace) -> int:
    path = transcripts().get(args.cli_session_id)
    if not path:
        print(f"No transcript on disk for {args.cli_session_id}", file=sys.stderr)
        return 1
    info = summarize(path, max_messages=8)
    print(json.dumps(info, ensure_ascii=False, indent=2))
    return 0


def cmd_restore(args: argparse.Namespace) -> int:
    cli_id = args.cli_session_id
    path = transcripts().get(cli_id)
    if not path:
        print(f"No transcript on disk for {cli_id}: either the id is wrong (run `scan`) "
              f"or the transcript is past cleanupPeriodDays and is gone.", file=sys.stderr)
        return 1

    accounts = account_dirs()
    if not accounts:
        print(f"No account directory under {SESSIONS_ROOT}", file=sys.stderr)
        return 1

    for account in accounts:
        if cli_id in read_cards(account):
            print(f"{cli_id} already has a card in {account.name} — nothing to do.")
            return 0

    account = accounts[0] if len(accounts) == 1 else max(
        accounts, key=lambda a: len(list(a.glob("local_*.json")))
    )
    info = summarize(path)

    # Clone the card of a session in the same directory: it carries the MCP/tool
    # snapshots this app version expects, which are impractical to write by hand.
    candidates = [
        (json.loads(p.read_text()), p)
        for p in account.glob("local_*.json")
    ]
    if not candidates:
        print(f"No card in {account} to use as a template", file=sys.stderr)
        return 1
    same_cwd = [c for c, _ in candidates if c.get("cwd") == info["cwd"]]
    template = (
        max(same_cwd, key=lambda c: c.get("lastActivityAt", 0))
        if same_cwd
        else max((c for c, _ in candidates), key=lambda c: c.get("lastActivityAt", 0))
    )

    title = args.title
    if not title and info["prompts"]:
        title = info["prompts"][0][1][:60]
    title = title or f"Restored session {cli_id[:8]}"

    created = epoch_ms(info["first_ts"], 0)
    last = epoch_ms(info["last_ts"], created)

    card = dict(template)
    card.pop("_path", None)
    session_id = "local_" + str(uuid.uuid4())
    card.update({
        "sessionId": session_id,
        "cliSessionId": cli_id,
        "cwd": info["cwd"] or template.get("cwd"),
        "originCwd": info["cwd"] or template.get("originCwd"),
        "title": title,
        "titleSource": "auto",
        "titleTurn": 0,
        "isArchived": False,
        "createdAt": created,
        "lastActivityAt": last,
        "lastFocusedAt": last,
        "latestUserFrameAt": last,
    })

    out = account / f"{session_id}.json"
    if args.dry_run:
        print(f"[dry-run] would write {out}")
        print(f"[dry-run]   cliSessionId={cli_id} title={title!r} cwd={card['cwd']}")
        return 0

    out.write_text(json.dumps(card, ensure_ascii=False))
    out.chmod(0o600)

    tombstone = account / f"deleted_{cli_id}"
    moved = None
    if tombstone.exists():
        BACKUP_ROOT.mkdir(parents=True, exist_ok=True)
        moved = BACKUP_ROOT / tombstone.name
        shutil.move(str(tombstone), str(moved))

    # Fail loudly rather than leaving a card the app will choke on.
    json.loads(out.read_text())

    print(f"Wrote {out.name} -> {cli_id}")
    print(f"  title: {title}")
    print(f"  cwd:   {card['cwd']}")
    if moved:
        print(f"  tombstone moved to {moved}")
    print("Open the Code tab to confirm; restart the app if it does not appear.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    scan = sub.add_parser("scan", help="list transcripts with no Code tab entry")
    scan.add_argument("--all", action="store_true",
                      help="include transcripts under %d lines" % MIN_INTERESTING_LINES)
    scan.set_defaults(func=cmd_scan)

    show = sub.add_parser("show", help="preview one transcript as JSON")
    show.add_argument("cli_session_id")
    show.set_defaults(func=cmd_show)

    restore = sub.add_parser("restore", help="write a card for one transcript")
    restore.add_argument("cli_session_id")
    restore.add_argument("--title", help="card title (default: first user prompt)")
    restore.add_argument("--dry-run", action="store_true")
    restore.set_defaults(func=cmd_restore)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
