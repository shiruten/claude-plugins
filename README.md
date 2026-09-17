# shiruten/claude-plugins

A Claude Code plugin marketplace.

```
/plugin marketplace add shiruten/claude-plugins
```

| Plugin | What it does |
| --- | --- |
| [demo-video](plugins/demo-video) | Records a narrated, captioned demo video of a pull request actually working, then attaches it to the PR with `gh`. |
| [session-rescue](plugins/session-rescue) | Brings back a desktop session that disappeared from the Code tab — unarchives it, or rebuilds its sidebar card from the transcript still on disk. |

Install one:

```
/plugin install demo-video@shiruten
/plugin install session-rescue@shiruten
```

Each plugin's own README covers what it needs and how to use it. Both are macOS-only:
they drive local tooling (screen recording, the desktop app's session storage) rather
than anything hosted.

## Layout

```
.claude-plugin/marketplace.json   the catalog
plugins/<name>/                   one directory per plugin, each with its own
                                  .claude-plugin/plugin.json and skills/
```

## License

MIT
