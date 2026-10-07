#!/bin/bash
# App-side configuration.  Every step here has bitten someone already.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
U=${1:-$(id -un 1000 2>/dev/null || echo piano)}
H=$(getent passwd "$U" | cut -d: -f6)

echo "== mpv =="
install -d -o "$U" -g "$U" "$H/.config/mpv"
cp "$HERE/../configs/mpv.conf" "$H/.config/mpv/mpv.conf"; chown "$U:$U" "$H/.config/mpv/mpv.conf"

echo "== firefox =="
for d in /etc/firefox/policies /etc/firefox-esr/policies; do
  mkdir -p "$d"; cp "$HERE/../configs/firefox-policies.json" "$d/policies.json"
done
# user.js must go in the profile Firefox actually uses - found with find, not a glob
for p in $(find "$H/.mozilla/firefox" -maxdepth 1 -type d -name '*.default*' 2>/dev/null); do
  cp "$HERE/../configs/firefox-user.js" "$p/user.js"; chown "$U:$U" "$p/user.js"; echo "  installed in $p"
done

echo "== chrome =="
install -d -o "$U" -g "$U" "$H/.config"
cp "$HERE/../configs/chrome-flags.conf" "$H/.config/chrome-flags.conf"; chown "$U:$U" "$H/.config/chrome-flags.conf"
# Exec= MUST start with the executable; flags in front make GNOME drop the entry
F=/usr/share/applications/google-chrome.desktop
if [ -f "$F" ]; then
  cp -n "$F" "$F.orig" 2>/dev/null || true
  python3 - "$F" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
flags = open('/dev/stdin').read() if False else None
PY
  echo "  NOTE: patch Exec= by hand or with the repo's helper - flags must follow the binary"
fi
