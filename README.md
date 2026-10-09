# SM8750 / Qualcomm Iris video acceleration on mainline Linux

Hardware **decode** (H.264, HEVC incl. Main10, VP9) and hardware **encode**
(H.264, HEVC) for Qualcomm's Iris codec, exposed to normal applications through
**VA-API**, plus the kernel-side patches that makes it actually work.

**AV1** is a separate, unfinished story: the kernel driver supports it completely and
this repository teaches the VA-API backend to advertise it, but decoding still fails at
the final submit. See [docs/av1-decode.md](docs/av1-decode.md) for exactly how far it
got and where it stops. AV1 *encoding* is not possible at all - the silicon has no AV1
encoder.

Developed on a **Xiaomi Pad 8 Pro (SM8750P, codename "piano")** running Debian 13 with
a 7.2.6 kernel, but nothing here is tablet-specific: it applies to any device whose
kernel has the `qcom-iris` driver (`CONFIG_VIDEO_QCOM_IRIS`).

## What you get

| Path | Status |
|---|---|
| `v4l2m2m-copy` (mpv, Firefox) | works without any of this - the driver exposes V4L2 M2M directly |
| AV1 decode | kernel-ready, VA-API advertises it, **decoding not yet working** - [docs/av1-decode.md](docs/av1-decode.md) |
| AV1 encode | **not possible** - the silicon has no AV1 encoder |
| **VA-API** (Chrome, Firefox encode, Sunshine, GStreamer, ffmpeg) | **this repository** |
| Hardware encode | H.264 and HEVC only - a silicon limit |

## Does my device have Iris?

Run `scripts/05-detect-codec.sh`. It reports the generation, the bound driver, the
firmware it wants and the codecs it exposes, then says what to do:

    [3] driver bound to the codec device
        aa00000.video-codec-ml             driver=qcom-iris
    [5] firmware (Iris needs vpu35, Venus needs venus-*)
        /lib/firmware/qcom/sm8750/xiaomi/piano/vpu35_4v.mbn
    [6] v4l2 devices and codecs
        /dev/video0 decoder: decodes 'H264' 'HEVC' 'VP90' 'AV01' | outputs 'NV12' 'P010'
        /dev/video1 encoder: encodes 'H264' 'HEVC' | accepts 'NV12' 'Q08C'

Quick manual equivalents:

    # which driver is bound (qcom-iris = Iris, qcom-venus = the older block)
    for d in /sys/bus/platform/devices/*video-codec*; do
        basename "$(readlink -f "$d/driver")"
    done

    # is the driver even built?
    zcat /proc/config.gz | grep -E 'CONFIG_VIDEO_QCOM_(IRIS|VENUS)'

    # what can the decoder take, and what can the encoder produce?
    v4l2-ctl -d /dev/video0 --list-formats-out     # decoder: coded input
    v4l2-ctl -d /dev/video1 --list-formats         # encoder: coded output

If only `qcom-venus` shows up, this repository's VA-API work does not apply (the Radxa
backend targets Iris); use `mpv --hwdec=v4l2m2m-copy` directly, which needs no backend
at all.

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
