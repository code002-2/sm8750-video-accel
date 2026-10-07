# Things that cost real time here

## 1. `ffmpeg -hwaccel v4l2m2m` / `-vcodec h264_v4l2m2m` hangs the codec - permanently

It negotiates the format, then blocks in `VIDIOC_G_FMT`. `timeout` and `SIGTERM` do
not kill it; you need `SIGKILL`, and the machine can stop answering the network while
it is stuck. **Use mpv to test decoding** - its buffer negotiation is correct.

## 2. `patch --fuzz` puts the new enum entries in the wrong enum

Applying Radxa's patches to 7.2.6 with fuzz succeeds, but `DISPLAY_DELAY_ENABLE` and
`DISPLAY_DELAY` land in `enum platform_inst_fw_cap_flags`, where their implicit values
collide with `CAP_FLAG_MENU = BIT(1)` and `CAP_FLAG_INPUT_PORT = BIT(2)`:

```
error: duplicate case value
```

That reads like a version incompatibility. It is not - they belong in
`enum platform_inst_fw_cap_type`, just before `INST_FW_CAP_MAX`.
`patches/clean/` already has them in the right place.

## 3. `iw scan` on a live connection looks exactly like a broken link

Scanning makes the interface leave the channel repeatedly: signal stays at -30 dBm
while 85% of packets vanish and the AP drops the rx rate to 6 Mbit/s. Use
`nmcli device wifi list` instead, or scan before associating.

## 4. `libgbm-dev` downgrades vendor Mesa

It depends on an exact `libgbm1`, so on a device with patched Mesa it will pull the
distro build and can break GPU acceleration. Hold the graphics stack, then take the
headers from the .deb by hand (`scripts/20-provide-gbm-headers.sh`).

## 5. Chrome flags must be verified against the binary

Guide-derived names age badly: Chrome 155 has `VaapiVideoEncodeAccelerator` and
`AcceleratedVideoEncoder`, **not** `VaapiVideoEncoder`. Grep the binary. And use
substring matching (`grep -oF`) - a whole-line match finds nothing, because `strings`
output lines contain more than the token.

## 6. `Exec=` must begin with the executable

Putting flags first still passes `desktop-file-validate` but makes GNOME drop the menu
entry entirely, so the application "disappears". Verify by checking that the first
token is executable.

## 7. The silicon encodes H.264 and HEVC only

`/dev/video1` produces `H264` and `HEVC`. VP9 and AV1 are **decode-only** on this part.
Chrome will never hardware-encode HEVC (its own limitation); Firefox does, via this
backend. For AV1/VP9 encoding use software (libsvtav1, libvpx-vp9).
