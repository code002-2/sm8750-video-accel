# Where this comes from

- **VA-API backend**: [radxa-pkg/libva-v4l2](https://github.com/radxa-pkg/libva-v4l2),
  a fork of [mxsrc/libva-v4l2](https://github.com/mxsrc/libva-v4l2).
  The upstream version supports **stateless** V4L2 only; Radxa's fork adds the
  **stateful** support that Qualcomm Iris needs. Check its own README for licensing.
- **Kernel patches**: `patches/upstream/` are Radxa's, by Xilin Wu <sophon@radxa.com>,
  written against their 6.18.x-qcom tree. `patches/clean/` is the same change
  regenerated against Linux v7.2.6 so it applies with `fuzz=0`.
- Everything else (scripts, configs, notes) was written while bringing this up on a
  Xiaomi Pad 8 Pro (SM8750P, "piano"), and is offered as-is with no warranty.

## Licensing

The kernel patches in `patches/` are Linux kernel code and are **GPL-2.0**, hence the
repository licence. The VA-API backend is a separate project with its own licence -
see radxa-pkg/libva-v4l2. The scripts and notes here may be reused freely.
