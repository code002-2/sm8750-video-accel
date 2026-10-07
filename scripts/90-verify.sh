#!/bin/bash
# Verify the whole stack.  Note what is NOT here: no bare ffmpeg v4l2m2m decode.
# That invocation hangs the codec (uninterruptible, takes the machine with it).
set -u
echo "== 1. the driver advertises the decode-order control (patch applied)? =="
v4l2-ctl -d /dev/video0 --list-ctrls 2>/dev/null | grep -iE 'display_delay' || echo "  MISSING - kernel patch not loaded"

echo "== 2. VA-API =="
vainfo --display drm --device /dev/dri/renderD128 2>&1 | grep -E 'Driver version|va_openDriver|VAProfile' | head -14

echo "== 3. hardware decode (mpv negotiates the buffers correctly; ffmpeg CLI does not) =="
for f in "$@"; do
  [ -f "$f" ] || continue
  printf '  %-30s ' "$(basename "$f")"
  timeout -s KILL 60 mpv --no-config --vo=null --ao=null --hwdec=v4l2m2m-copy --length=3 "$f" 2>&1 \
    | grep -q 'Using hardware decoding' && echo "hardware ✓" || echo "software ✗"
done

echo "== 4. hardware encode (VA-API, H.264 / HEVC only - the silicon supports nothing else) =="
timeout -s KILL 120 ffmpeg -hide_banner -loglevel error -f lavfi -i testsrc2=size=1280x720:rate=30 -t 3 \
  -vf 'format=nv12,hwupload' -c:v h264_vaapi -b:v 4M /tmp/vaapi-encode-test.mp4 \
  && ls -l /tmp/vaapi-encode-test.mp4 || echo "  encode failed"
