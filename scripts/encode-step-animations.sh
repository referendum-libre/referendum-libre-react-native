#!/usr/bin/env bash
#
# Regenerate assets/webp/*.webp — the looping animations on the illustrated
# voting-flow steps and the Comprendre hero.
#
# Source of truth is the original 1440x1440 / 24fps Kling masters, which were
# removed from the tree in 1430c4b. Recover them first:
#
#   mkdir -p /tmp/step-masters
#   for f in $(git ls-tree -r --name-only 1430c4b^ -- assets/videos); do
#     git show "1430c4b^:$f" > "/tmp/step-masters/$(basename "$f")"
#   done
#   SRC=/tmp/step-masters ./scripts/encode-step-animations.sh
#
# Encode from those masters, never from the intermediate GIFs that briefly
# shipped in 1430c4b: GIF quantises to a 256-colour palette and dithers, which
# on one sampled frame collapsed 2597 source colours to 94. That damage is
# baked in and cannot be recovered by a later re-encode.
#
# Sizing: these render small. Per constants/theme.ts and
# components/voting-modal/styles.ts the largest box is 175 dp (iOS step media
# container; Android is 100-120 dp), and the Comprendre hero is 71x100 dp with
# resizeMode="cover". Targets below are ~3x the dp box, which saturates an
# xxxhdpi screen with nothing wasted — encoding larger only grows the bundle.
set -euo pipefail

SRC=${SRC:-/tmp/step-masters}
OUT=${OUT:-assets/webp}
FPS=${FPS:-24}   # masters are 24fps; the GIFs had been decimated to 12.5
Q=${Q:-72}       # visually transparent on this flat-shaded content

if [ ! -d "$SRC" ]; then
  echo "error: master videos not found at $SRC — see the header for how to recover them" >&2
  exit 1
fi

mkdir -p "$OUT"

encode() {
  local name=$1 src=$2 w=$3 h=$4
  ffmpeg -v error -y -i "$SRC/$src" \
    -vf "fps=${FPS},scale=${w}:${h}:flags=lanczos" \
    -c:v libwebp_anim -lossless 0 -q:v "$Q" -compression_level 6 -loop 0 -an \
    "$OUT/${name}.webp"
  printf '%-22s %8d bytes\n' "$name" "$(stat -c%s "$OUT/${name}.webp")"
}

K=kling_20250904_Image_to_Video_A_playful_

encode step1-card         "${K}_4846_0.mp4"   525 525
encode step2-phone        "${K}_4900_0.mp4"   513 513
encode step3-ballot       "${K}_5078_0.mp4"   525 525
encode step7-verify       "${K}_5198_0.mp4"   525 525
encode step6-nfc          "phoneOverCard.mp4" 776 525
encode comprendre-welcome "${K}_5643_0.mp4"   300 300
