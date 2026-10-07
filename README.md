# SM8750 / Qualcomm Iris video acceleration on mainline Linux

Hardware **decode** (H.264, HEVC incl. Main10, VP9, AV1) and hardware **encode**
(H.264, HEVC) for Qualcomm's Iris codec, exposed to normal applications through
**VA-API**, plus the kernel-side patches that makes it actually work.

Developed on a **Xiaomi Pad 8 Pro (SM8750P, codename "piano")** running Debian 13 with
a 7.2.6 kernel, but nothing here is tablet-specific: it applies to any device whose
kernel has the `qcom-iris` driver (`CONFIG_VIDEO_QCOM_IRIS`).

## What you get

| Path | Status |
|---|---|
| `v4l2m2m-copy` (mpv, Firefox) | works without any of this - the driver exposes V4L2 M2M directly |
| **VA-API** (Chrome, Firefox encode, Sunshine, GStreamer, ffmpeg) | **this repository** |
| Hardware encode | H.264 and HEVC only - a silicon limit |

## The two pieces

1. **A VA-API backend for stateful V4L2 M2M** - use
   [radxa-pkg/libva-v4l2](https://github.com/radxa-pkg/libva-v4l2), *not* the upstream
   `mxsrc/libva-v4l2`, which is stateless-only. `scripts/30-build-libva-v4l2.sh`.
2. **Kernel patches to the iris driver** - decode-order output, larger capture pools,
   encoder deblocking controls. Without decode-order output the firmware can withhold a
   decoded frame until more input arrives, and synchronous clients (VA-API) stall with:

   ```
   iris-vaapi: S_CTRL DISPLAY_DELAY (Iris decode-order patch required): Invalid argument
   ```

   `patches/clean/` applies to Linux v7.2.6 with `fuzz=0`.

## Quick start

```bash
scripts/00-check-prereqs.sh            # confirm the Iris codec is present
scripts/10-install-build-deps.sh       # build deps; holds vendor Mesa first
scripts/20-provide-gbm-headers.sh      # gbm headers without libgbm-dev
scripts/30-build-libva-v4l2.sh         # build the VA-API backend
scripts/40-install-vaapi-driver.sh     # install it system-wide
scripts/50-patch-and-build-iris.sh /path/to/linux   # kernel side
scripts/60-install-iris-module.sh <path>/qcom-iris.ko   # then reboot
scripts/70-configure-apps.sh           # mpv / Firefox / Chrome settings
scripts/90-verify.sh *.mp4             # prove it
```

## Read this before you start

[docs/gotchas.md](docs/gotchas.md) - seven traps, each of which cost hours here. The
worst two are a test command that bricks the codec until reboot, and a `patch --fuzz`
artefact that looks like a kernel version incompatibility but is a misplaced enum.
