# session-rescue

A Claude Code plugin that brings back a desktop session which disappeared from the Code tab.

## Why it exists

The Code tab's sidebar reads small *card* files. The conversation itself is a separate
transcript on disk. Archiving or deleting a session removes it from the list — the
transcript is left alone.

```
Sidebar card                         Conversation
~/Library/Application Support/       ~/.claude/projects/<project>/
  Claude/claude-code-sessions/         <cliSessionId>.jsonl
  <org>/<account>/
    local_<uuid>.json      ──────────►  linked by cliSessionId
    deleted_<cliSessionId>              (tombstone, epoch ms)
    archived-sessions.idx               (array of local_ ids)
```

So "I deleted the session" usually means "the card is gone", not "the conversation is gone".

## What it does

| Case | What happens |
| --- | --- |
| Archived | Restored through the app's own unarchive, not by editing files |
| Deleted | A new card is written for the surviving transcript, and the tombstone is moved aside |
| Transcript already cleaned up | Says so — there is nothing to recover, and deletion does not go through the Trash |

## Install

```
/plugin marketplace add shiruten/claude-plugins
/plugin install session-rescue@shiruten
```

## Use

```
/session-rescue:restore
```

It lists what can be restored — deletion time, duration, size, working directory and the
first prompt of each — and restores the one you pick. The script is also usable directly:

```bash
python3 skills/restore/scripts/session_rescue.py scan
python3 skills/restore/scripts/session_rescue.py show <cliSessionId>
python3 skills/restore/scripts/session_rescue.py restore <cliSessionId> [--title "..."] [--dry-run]
```

## Limits

- macOS desktop app only. It reads the app's own session directory.
- Restores nothing that is past
  [`cleanupPeriodDays`](https://code.claude.com/docs/en/settings-reference#cleanupperioddays)
  (default 30 days; from v2.1.248 desktop transcripts are exempt unless
  `desktopSessionCleanupPeriodDays` is set).
- Card files are cloned from an existing card, so the app version that wrote them has to be
  the one reading them. Restore soon after the accident, not years later.
- Cloud sessions deleted from the web are out of scope: that deletion removes the event data
  on the server.

## License

MIT
