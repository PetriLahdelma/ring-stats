#!/bin/bash
# Renders the README's Holographic GIF from the app's own code: the state
# gallery writes 81 frames of the popover with the pointer sweeping across
# the foil (RING_STATS_RENDER_HOVER=1), and ffmpeg assembles them. Run from
# the repository root after a change to the popover or the foil.
set -euo pipefail
cd "$(dirname "$0")/../.."
command -v ffmpeg >/dev/null || { echo "ffmpeg is required (brew install ffmpeg)" >&2; exit 1; }
RING_STATS_RENDER_HOVER=1 swift test --filter holographicHoverFramesRenderForTheReadmeGif >/dev/null
frames=.build/state-gallery/hover
out=.github/assets/ring-stats-holographic.gif
# 12 fps at 560 px with 96 colors keeps the file under 3 MB; the foil's
# gradients are the worst case for GIF.
ffmpeg -v error -y -framerate 20 -i "$frames/frame-%03d.png" \
  -vf "fps=12,scale=560:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=96:stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
  -loop 0 "$out"
printf 'Wrote %s (%s bytes)\n' "$out" "$(stat -f%z "$out")"
