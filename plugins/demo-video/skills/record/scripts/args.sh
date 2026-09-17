#!/usr/bin/env bash
# Parse the skill's flags into key=value lines. Flags may appear in any order; anything else is a scene request.
# usage: args.sh [-w|--web] [-i|--ios] [-t|--title <name>] [-pr|--pr <#123|123|url>] [-c|--captions] [-sr|--scenes <text>] [free text...]
set -euo pipefail
target=web title= pr= captions=off scenes=
while [ $# -gt 0 ]; do
  case $1 in
    -w|--web)       target=web; shift ;;
    -i|--ios)       target=ios; shift ;;
    -t|--title)     [ $# -ge 2 ] || { echo "error=-t needs a value" ; exit 2; }; title=$2; shift 2 ;;
    -pr|--pr)       [ $# -ge 2 ] || { echo "error=-pr needs a value"; exit 2; }; pr=$2; shift 2 ;;
    -c|--captions)  captions=on; shift ;;
    -sr|--scenes)   [ $# -ge 2 ] || { echo "error=-sr needs a value"; exit 2; }; scenes="${scenes:+$scenes }$2"; shift 2 ;;
    -h|--help)      sed -n '2,3p' "$0" | sed 's/^# //'; exit 0 ;;
    -*)             echo "error=unknown flag $1"; sed -n '3p' "$0" | sed 's/^# //'; exit 2 ;;
    *)              scenes="${scenes:+$scenes }$1"; shift ;;   # bare words are scene requests
  esac
done

# Video name: -t, else the current branch. Keep it safe as a folder/file name.
name=${title:-$(git branch --show-current 2>/dev/null || echo demo)}
name=$(printf '%s' "$name" | tr '/ ' '--' | tr -cd 'A-Za-z0-9._-' )
[ -n "$name" ] || name=demo

# PR: accept "#123", "123", or a pull-request URL; gh takes either the number or the URL.
case "$pr" in
  '')            pr_ref= ;;
  \#[0-9]*)      pr_ref=${pr#\#} ;;
  [0-9]*)        pr_ref=$pr ;;
  http*/pull/*)  pr_ref=$pr ;;
  *)             echo "error=-pr expects #123, 123, or a pull request URL (got: $pr)"; exit 2 ;;
esac

printf 'target=%s\nname=%s\npr=%s\ncaptions=%s\nscenes=%s\n' "$target" "$name" "${pr_ref:-none}" "$captions" "$scenes"
