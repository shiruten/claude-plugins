#!/usr/bin/env bash
# Assemble one narrated, captioned mp4 from scenes.tsv + <scene_id>.mp4|webm|mov in <workdir>, then verify it.
# usage: build.sh <workdir> [--captions] [--voice NAME] [--rate WPM] [--height 1280] [--crf 23] [--font NAME] [--font-size N] [--title-color 0x222222] [--title-sec 1.2] [--no-title-cards]
set -euo pipefail

usage() { sed -n '2,3p' "$0" | sed 's/^# //' >&2; exit 2; }
[ $# -ge 1 ] || usage
DIR=$1; shift
VOICE= RATE=190 HEIGHT=1280 CRF=23 FONT= FONT_SIZE= TITLE_COLOR=0x222222 TITLE_SEC=1.2 CAPTIONS=0 TITLES=1
while [ $# -gt 0 ]; do
  case $1 in
    --captions)       CAPTIONS=1;     shift ;;
    --voice)          VOICE=$2;       shift 2 ;;
    --rate)           RATE=$2;        shift 2 ;;
    --height)         HEIGHT=$2;      shift 2 ;;
    --crf)            CRF=$2;         shift 2 ;;
    --font)           FONT=$2;        shift 2 ;;
    --font-size)      FONT_SIZE=$2;   shift 2 ;;
    --title-color)    TITLE_COLOR=$2; shift 2 ;;
    --title-sec)      TITLE_SEC=$2;   shift 2 ;;
    --no-captions)    CAPTIONS=0;     shift ;;
    --no-title-cards) TITLES=0;       shift ;;
    *) usage ;;
  esac
done

for t in say ffmpeg ffprobe; do
  command -v "$t" >/dev/null || { echo "$t not found" >&2; exit 1; }
done
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# `say` silently falls back to another voice when the name is unknown, so validate the name up front.
if [ -n "$VOICE" ]; then
  say -v '?' | awk -v v="$VOICE" 'index($0, v " ") == 1 { f = 1 } END { exit !f }' \
    || { echo "voice '$VOICE' is not installed. See: say -v '?'" >&2; exit 1; }
  SAY=(say -v "$VOICE" -r "$RATE")
else
  SAY=(say -r "$RATE")   # system default voice; pick one matching the narration language with --voice
fi
tts() { "${SAY[@]}" -o "$2" --data-format=LEI16@22050 "$1"; }   # $1=text $2=out.wav

# Text renderer for captions/title cards (CoreText). Built once with swiftc; cached in scripts/.bin.
CAP="$SCRIPT_DIR/.bin/caption"
if [ "$CAPTIONS" = 1 ] || [ "$TITLES" = 1 ]; then
  if ! command -v swiftc >/dev/null; then
    echo "swiftc not found: continuing without captions/title cards (install Xcode Command Line Tools to enable)" >&2
    CAPTIONS=0; TITLES=0
  elif [ ! -x "$CAP" ] || [ "$SCRIPT_DIR/caption.swift" -nt "$CAP" ]; then
    mkdir -p "$SCRIPT_DIR/.bin"
    swiftc -O -o "$CAP" "$SCRIPT_DIR/caption.swift" >/dev/null 2>&1 \
      || { echo "failed to build the caption renderer; drop --captions and pass --no-title-cards" >&2; exit 1; }
  fi
fi

cd "$DIR"
NAME=$(basename "$PWD")
[ -f scenes.tsv ] || { echo "$PWD/scenes.tsv not found" >&2; exit 1; }

dur() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }
wh()  { ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$1"; }
spec() { ffprobe -v error -show_entries stream=codec_type,width,height,r_frame_rate,pix_fmt,sample_rate,channels -of csv=p=0 "$1" | sort | tr '\n' '|'; }
src_of() { for e in mp4 webm mov; do [ -f "$1.$e" ] && { echo "$1.$e"; return; }; done; return 1; }
ENC=(-c:v libx264 -preset veryfast -crf "$CRF" -c:a aac -b:a 128k -ac 1 -movflags +faststart)

mkdir -p frames sheets captions
: > concat.txt
: > summary_rows.md
printf 'scene_id\tvideo_s\taudio_s\tsegment_s\tsize\tsheet\n' > report.tsv
FAIL=0 N=0 SIZE_REF= EXPECTED_TOTAL=0

while IFS=$'\t' read -r id ops text || [ -n "${id:-}" ]; do
  case "$id" in ''|scene_id|'#'*) continue ;; esac
  [ -n "$text" ] || { echo "$id: empty narration" >&2; exit 1; }
  SRC=$(src_of "$id") || { echo "$id.mp4 not found (missing recording)" >&2; exit 1; }
  N=$((N+1))

  tts "$text" "$id.wav"
  V=$(dur "$SRC"); A=$(dur "$id.wav")
  # Invariant: a scene lasts as long as the longer of video and audio.
  DUR=$(awk -v a="$A" -v v="$V" 'BEGIN{printf "%.3f", (a>v)?a:v}')
  PAD=$(awk -v a="$A" -v v="$V" 'BEGIN{printf "%.3f", (a>v)?a-v:0}')

  # Output size: height capped at HEIGHT, width keeps the aspect ratio and is rounded to even.
  SRC_WH=$(wh "$SRC"); SW=${SRC_WH%x*}; SH=${SRC_WH#*x}
  OH=$(( SH < HEIGHT ? SH : HEIGHT ))
  OW=$(awk -v sw="$SW" -v sh="$SH" -v oh="$OH" 'BEGIN{w=int(sw*oh/sh); if (w%2) w--; print w}')

  # Title card: the "what happens" column on a solid background, same stream specs as the scenes so concat can copy.
  if [ "$TITLES" = 1 ] && [ -n "$ops" ]; then
    "$CAP" "captions/$id.title.png" "$OW" "$(( OW / 14 ))" "$FONT" "$ops" >/dev/null
    ffmpeg -nostdin -y -v error -f lavfi -i "color=c=${TITLE_COLOR}:s=${OW}x${OH}:r=30:d=${TITLE_SEC}" \
      -f lavfi -i "anullsrc=r=44100:cl=mono:d=${TITLE_SEC}" -loop 1 -i "captions/$id.title.png" \
      -filter_complex "[0:v][2:v]overlay=(W-w)/2:(H-h)/2:shortest=1,fade=t=in:d=0.2,fade=t=out:st=$(awk -v t="$TITLE_SEC" 'BEGIN{printf "%.2f", t-0.25}'):d=0.25,format=yuv420p[v]" \
      -map '[v]' -map 1:a -t "$TITLE_SEC" "${ENC[@]}" "$id.title.mp4"
    printf "file '%s.title.mp4'\n" "$id" >> concat.txt
    EXPECTED_TOTAL=$(awk -v e="$EXPECTED_TOTAL" -v t="$TITLE_SEC" 'BEGIN{printf "%.3f", e+t}')
  fi

  # Scene: freeze the last frame until the audio ends (tpad), pad audio with silence until the video ends (apad), cut at DUR.
  VF="[0:v]tpad=stop_mode=clone:stop_duration=${PAD},scale=${OW}:${OH},fps=30,format=yuv420p[base]"
  if [ "$CAPTIONS" = 1 ]; then
    "$CAP" "captions/$id.png" "$OW" "${FONT_SIZE:-$(( OW / 22 ))}" "$FONT" "$text" >/dev/null
    # The PNG input must be looped (-loop 1); a single-frame input would end the overlay after one frame.
    ffmpeg -nostdin -y -v error -i "$SRC" -i "$id.wav" -loop 1 -i "captions/$id.png" \
      -filter_complex "${VF};[2:v]format=rgba[cap];[base][cap]overlay=(W-w)/2:H-h-${OH}*3/100:shortest=1[v];[1:a]apad,aresample=44100[a]" \
      -map '[v]' -map '[a]' -t "$DUR" "${ENC[@]}" "$id.seg.mp4"
  else
    ffmpeg -nostdin -y -v error -i "$SRC" -i "$id.wav" \
      -filter_complex "${VF};[base]copy[v];[1:a]apad,aresample=44100[a]" \
      -map '[v]' -map '[a]' -t "$DUR" "${ENC[@]}" "$id.seg.mp4"
  fi
  printf "file '%s.seg.mp4'\n" "$id" >> concat.txt
  EXPECTED_TOTAL=$(awk -v e="$EXPECTED_TOTAL" -v d="$DUR" 'BEGIN{printf "%.3f", e+d}')

  S=$(dur "$id.seg.mp4"); SZ=$(wh "$id.seg.mp4")
  # Evidence for a reviewer that cannot play video: a mid frame and a 3x3 contact sheet spanning the scene.
  ffmpeg -nostdin -y -v error -ss "$(awk -v d="$DUR" 'BEGIN{printf "%.3f", d/2}')" -i "$id.seg.mp4" -frames:v 1 "frames/$id.png"
  ffmpeg -nostdin -y -v error -i "$id.seg.mp4" -vf "fps=9/${DUR},scale=300:-2,tile=3x3" -frames:v 1 "sheets/$id.png"

  awk -v s="$S" -v d="$DUR" 'BEGIN{exit ((s-d)>0.3||(d-s)>0.3)?1:0}' \
    || { echo "$id: duration mismatch expected=$DUR actual=$S" >&2; FAIL=1; }
  : "${SIZE_REF:=$SZ}"
  [ "$SZ" = "$SIZE_REF" ] || { echo "$id: resolution differs from other scenes ($SZ vs $SIZE_REF). Did you mix web and ios recordings?" >&2; FAIL=1; }

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$V" "$A" "$S" "$SZ" "sheets/$id.png" >> report.tsv
  printf '| %s | %s | %s |\n' "$N" "${ops:-}" "$text" >> summary_rows.md
done < scenes.tsv

[ "$N" -gt 0 ] || { echo "no scenes in scenes.tsv" >&2; exit 1; }
[ "$FAIL" -eq 0 ] || exit 1

# concat -c copy assumes identical stream specs across every input, title cards included.
SPEC_REF=
while read -r line; do
  f=${line#file \'}; f=${f%\'}
  s=$(spec "$f"); : "${SPEC_REF:=$s}"
  [ "$s" = "$SPEC_REF" ] || { echo "$f: stream specs differ from the first segment ($s)" >&2; exit 1; }
done < concat.txt
ffmpeg -nostdin -y -v error -f concat -safe 0 -i concat.txt -c copy -movflags +faststart "$NAME.mp4"

TOTAL=$(dur "$NAME.mp4")
BYTES=$(stat -f%z "$NAME.mp4" 2>/dev/null || stat -c%s "$NAME.mp4")
MB=$(awk -v b="$BYTES" 'BEGIN{printf "%.1f", b/1048576}')
STREAMS=$(ffprobe -v error -show_entries stream=codec_type -of csv=p=0 "$NAME.mp4" | sort | tr '\n' ' ')
ffmpeg -nostdin -y -v error -i "$NAME.mp4" -vf "fps=9/${TOTAL},scale=300:-2,tile=3x3" -frames:v 1 "sheets/_all.png"

# summary.md: paste-ready PR comment body (the video itself is attached with gh pr comment --attach).
{
  printf '## Demo video\n\n%s scenes, %.0fs, %s MB. Narration is also burned in as captions.\n\n' "$N" "$TOTAL" "$MB"
  printf '| # | Scene | Narration |\n| --- | --- | --- |\n'
  cat summary_rows.md
} > summary.md
rm -f summary_rows.md

column -t -s $'\t' report.tsv
printf '\n%s.mp4  %ss (expected %ss)  %s MB  streams: %s  captions: %s  title-cards: %s\n' "$NAME" "$TOTAL" "$EXPECTED_TOTAL" "$MB" "$STREAMS" \
  "$([ "$CAPTIONS" = 1 ] && echo on || echo off)" "$([ "$TITLES" = 1 ] && echo on || echo off)"
case "$STREAMS" in *audio*video*) ;; *) echo "missing audio or video stream" >&2; exit 1 ;; esac
awk -v t="$TOTAL" -v e="$EXPECTED_TOTAL" 'BEGIN{exit ((t-e)>0.5||(e-t)>0.5)?1:0}' || { echo "total duration differs from the sum of segments (concat dropped something)" >&2; exit 1; }
[ "$BYTES" -le 104857600 ] || echo "over 100 MB (GitHub's video limit on paid plans; 10 MB on free plans). Re-run with --crf 28 or --height 960, or drop scenes" >&2
