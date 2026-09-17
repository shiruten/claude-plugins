---
name: restore
description: Bring back a Claude Code desktop session that disappeared from the Code tab — archived (restore it through the app) or deleted (the sidebar card is gone but the transcript is still on disk, so rebuild the card). Use when the user says a session or conversation is gone, was deleted or archived by mistake, or asks to get an old session back.
argument-hint: "[keyword|cliSessionId] [--list]"
disable-model-invocation: true
allowed-tools: Bash(python3 ${CLAUDE_SKILL_DIR}/scripts/session_rescue.py:*) Bash(ls ~/.claude/projects/*) Bash(osascript -e *)
---

A session that vanished from the Code tab is almost never lost. The sidebar reads small
*card* files; the conversation itself is a separate transcript on disk. Archiving and
deleting both remove the session from the list without touching the transcript.

Work out which of the two happened before doing anything — the fixes are different, and
only one of them needs to touch files.

## Where things live

| What | Path |
| --- | --- |
| Sidebar card (what the Code tab lists) | `~/Library/Application Support/Claude/claude-code-sessions/<org>/<account>/local_<uuid>.json` |
| Deletion marker left behind | same directory, `deleted_<cliSessionId>` (contents: deletion time, epoch ms) |
| Archived list | same directory, `archived-sessions.idx` (array of `local_` ids) |
| The conversation itself | `~/.claude/projects/<project-slug>/<cliSessionId>.jsonl` |

A card's `cliSessionId` is the transcript's filename. That link is what makes recovery possible.

## 1. Archived — use the app, never the files

Archiving is a supported, reversible feature. Do not hand-edit `archived-sessions.idx`.

1. `list_sessions` with `include_archived: true`.
2. Match by title, cwd or PR number and confirm the right one with the user.
3. `unarchive_session` with its `sessionId`.

If those tools are not available in the current session, tell the user to open the
archived view in the sidebar and unarchive it there. Stop — do not fall through to the
delete path, which would create a second card for a session that still has one.

## 2. Deleted — rebuild the card

Deleting removes the card and writes a tombstone. The transcript survives, so a new card
pointing at the same `cliSessionId` brings the session back with its history intact.

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/session_rescue.py scan
```

Every transcript with no card, newest first, each with its deletion time (or
`never imported`), duration, size, cwd and first prompt. Long sessions the user is likely
to want are at the top; pass `--all` to include transcripts under 20 lines, which are
usually aborted starts.

Show the candidates and let the user pick — first prompt plus timestamp identifies a
session far better than a UUID. `show <cliSessionId>` prints a longer preview when two
look alike.

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/session_rescue.py restore <cliSessionId>
```

This clones an existing card from the same account directory (it carries the MCP and tool
snapshots the installed app version expects), rewrites identity and timestamps, and moves
the tombstone to `~/.claude/session-rescue-backups/`. Pass `--title` to name it; the
default is the first user prompt. `--dry-run` prints what it would write.

Then confirm with `list_sessions` — the restored session appears under its new
`local_` id. If the user cannot see it in the sidebar, have them restart the app.

## Rules

- **One card per transcript.** `restore` refuses when a card already exists. Never write a
  second card for the same `cliSessionId`; the sidebar would show the conversation twice.
- **Only add files.** Write the new card, move the tombstone. Never edit or delete an
  existing card, and never touch a transcript.
- **Confirm before restoring.** Show the preview and get a yes. Restoring the wrong
  session clutters the sidebar and the user has to delete it again.
- **Never restore in bulk.** A user who deleted 40 sessions meant to delete them.

## When recovery is not possible

No transcript on disk means nothing to restore. Claude Code deletes transcripts older than
[`cleanupPeriodDays`](https://code.claude.com/docs/en/settings-reference#cleanupperioddays)
(default 30). From v2.1.248, transcripts of sessions started or most recently continued in
Claude Desktop are kept at any age unless
[`desktopSessionCleanupPeriodDays`](https://code.claude.com/docs/en/settings-reference#desktopsessioncleanupperioddays)
is set; earlier versions delete them on the `cleanupPeriodDays` schedule. Say this plainly
rather than hunting for a backup that does not exist — deletion does not go through the
macOS Trash.

Other things that are *not* this skill's job: a session that is merely running elsewhere,
a cloud session deleted from the web, and a transcript the user purged with
`claude project purge`.
