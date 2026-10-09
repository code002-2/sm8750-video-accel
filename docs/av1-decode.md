# AV1 解码：Iris 内核驱动已支持，缺的是 VA-API 后端

本文记录在小米平板 8 Pro（SM8750P / piano，内核 7.2.6）上把 AV1 解码接进
VA-API 的工作，包括已完成的改动、实测结论，以及**尚未解决的部分**。

## 一、结论摘要

| 项目 | 状态 |
|---|---|
| 内核 V4L2 暴露 AV1 解码 | ✅ **可用**，`/dev/video0` 枚举出 `AV01`（AV1 OBU Stream） |
| 内核 HFI 层的 AV1 支持 | ✅ **完整**，含 film grain、superblock、profile/level/tier |
| VA-API 暴露 `VAProfileAV1Profile0/1` | ✅ **已实现**（本补丁） |
| VA-API 实际解码 AV1 码流 | ❌ **尚未成功**，见第四节 |
| 硬件 AV1 编码 | ❌ **不可能**，芯片没有 AV1 编码单元 |

## 二、内核侧：AV1 是一等公民

`drivers/media/platform/qcom/iris/` 对 AV1 的支持相当完整，不需要任何内核改动：

```
iris_hfi_gen2_command.c:
    V4L2_PIX_FMT_AV1          -> profile = fw_caps[PROFILE_AV1]
    HFI_PROP_AV1_FILM_GRAIN_PRESENT      <- AV1 的 film grain 合成
    HFI_PROP_AV1_SUPER_BLOCK_ENABLED     <- superblock 尺寸
    inst->codec == V4L2_PIX_FMT_AV1 -> tier = fw_caps[TIER_AV1]
iris_hfi_gen2.c:
    PROFILE_AV1: V4L2_MPEG_VIDEO_AV1_PROFILE_MAIN
    LEVEL_AV1:   2.0 .. 6.1（完整档位）
```

实测设备枚举结果：

```
$ v4l2-ctl -d /dev/video0 --list-formats-out
    [0]: 'H264' (H.264, compressed, dyn-resolution)
    [1]: 'HEVC' (HEVC, compressed, dyn-resolution)
    [2]: 'VP90' (VP9, compressed, dyn-resolution)
    [3]: 'AV01' (AV1 OBU Stream, compressed, dyn-resolution)
```

## 三、本补丁改了什么

`patches/libva-v4l2/0001-av1-decode.patch`，针对 libva-v4l2（Iris 的 VA-API
stateful 后端），基线 `0e4ce1e chore(release): prepare v1.0.0`。

### 新增文件

- **`src/av1.cpp`** —— AV1 的 bitstream 组装。AV1 在 VA-API 中不发送
  `VAPictureParameterBufferType`：序列头与帧头都在 slice data 里，且用的是 OBU
  头而非 Annex-B 起始码，因此这里做纯透传。
- **`src/av1-compat.hpp`** —— 补一个 fourcc。发行版的 `linux/videodev2.h` 只有
  `V4L2_PIX_FMT_AV1_FRAME`（`'AV1F'`，解析后的帧），而驱动枚举的是
  `V4L2_PIX_FMT_AV1`（`'AV01'`，压缩 OBU 流）：

  ```c
  #ifndef V4L2_PIX_FMT_AV1
  #define V4L2_PIX_FMT_AV1 v4l2_fourcc('A', 'V', '0', '1')
  #endif
  ```

### 改动（`src/internal.hpp`）

- `is_av1()` 谓词；`is_10bit()` 纳入 `VAProfileAV1Profile1`
- `Av1Slice` / `Av1Picture` 结构，对应 `VASliceParameterBufferAV1` /
  `VADecPictureParameterBufferAV1`
- `Context` 增加 `av1_picture` 成员

### 改动（`src/backend.cpp`）

- `supported()` 与 `query_profiles()` 加入 `VAProfileAV1Profile0/1`
  （**这是让 `vainfo` 列出 AV1 的关键**）
- **`render_picture()` 的 codec 分派补上 AV1 分支** —— 原实现是
  `is_vp9 ? … : is_hevc ? … : <H264>`，AV1 会掉进 H264 的 picture 对象，
  导致 buffer 永远到不了 `av1_picture`
- `end_picture()` 的分派同样补上 AV1
- AV1 不从 IQ matrix buffer 取数据（该 codec 没有这个 buffer）
- **AV1 的 slice 数据不做起始码剥离** —— 原逻辑只排除了 VP9，
  AV1 的 OBU 数据会被误剥
- slice parameter buffer 按 `min(element_size, sizeof(struct))` 拷贝：
  ffmpeg 用自己的 libva 头文件编译，其 `VASliceParameterBufferAV1`（40 字节）
  可能比运行时的更小，原来的严格 size 检查会直接拒绝

### 改动（`src/decoder.cpp` / `meson.build`）

- 设备探测同时接受 `V4L2_PIX_FMT_AV1`；按 profile 选择 `V4L2_PIX_FMT_AV1`
- `meson.build` 编译 `src/av1.cpp`

## 四、尚未解决：实际解码仍失败

`vainfo` 已经正确列出 AV1：

```
VAProfileAV1Profile0            :	VAEntrypointVLD
VAProfileAV1Profile1            :	VAEntrypointVLD
```

`ffmpeg` 也确实选择了硬件路径：

```
Initialised VAAPI connection: version 1.22
VAAPI driver: Iris V4L2 stateful VA-API backend.
Selecting decoder 'av1' because of requested hwaccel method vaapi
```

但解码在 `end_picture` 阶段失败：

```
iris-vaapi: pending pictures at context destruction (VA status 0x26)
Failed to end picture decode after error: 1 (operation failed)
```

排查过程中逐层排除的假设：

1. ~~polkit / D-Bus 权限~~ —— 与控制无关，同一路径下 H.264 正常
2. ~~buffer 没有到达 `av1_picture`~~ —— 已由 dispatch 修复解决
3. ~~slice 参数被拒~~ —— 已由放宽 size 检查解决
4. ~~起始码被误剥~~ —— 已排除

### 更精确的失败点（Firefox 实测暴露）

用 `MOZ_LOG=PlatformDecoderModule:5` 让 Firefox 播放一个 AV1 文件，日志显示它确实
走到了本后端的硬件路径，随后被内核拒绝：

```
iris-vaapi: AV1 debug slice-data: 1 elements, 12923 bytes each, pending=1
iris-vaapi: AV1 debug slice: flag=0 off=0 n=12923 bufsize=12923
iris-vaapi: Iris bitstream error (VA status 0x17)
iris-vaapi: pending pictures at context destruction (VA status 0x26)
```

`0x17` 是 `VA_STATUS_ERROR_DECODING_ERROR`，来自后端对 `V4L2_BUF_FLAG_ERROR` 的
检查。**关键是 buffer 已经按正确的参数提交了** —— `flag=0` 即
`VA_SLICE_DATA_FLAG_ALL`（完整 slice），偏移 0、长度 12923 与 buffer 大小一致 ——
是内核驱动/固件判定码流本身无法解码。

因此问题收敛为一点：**VA 交给后端的 AV1 slice 数据，是否已经是 V4L2 stateful
解码器期望的完整 temporal unit**。最可能的情况是它只含 tile 数据，缺少必要的 OBU
头（序列头 / 帧头 / tile group 头），需要在 `av1_bitstream()` 里重新组装成合法的
OBU 序列，而不是像现在这样直接拼接透传。这是下一步该试的方向。

参考对照：同一条 VA-API 路径下 H.264 完全正常（`frame= 60 speed=39.4x`），
FFmpeg 自己的 VA-API AV1 路径也报同样的 `end picture` 失败，说明问题在
bitstream 组装而非框架、权限或设备。

## 五、AV1 编码：硬件不支持

```c
/* drivers/media/platform/qcom/iris/iris_venc.c */
    [IRIS_FMT_H264] = V4L2_PIX_FMT_H264,
    [IRIS_FMT_HEVC] = V4L2_PIX_FMT_HEVC,
```

编码器的格式表里只有 H.264 与 HEVC。这与高通公开规格一致：骁龙 8 Elite 的
视频编码单元不含 AV1 编码能力。**这不是驱动缺失，写代码也无法弥补。**

`encode_supported()` 因此刻意不加入 AV1 profile。

## 六、附一：浏览器「报告支持」与「实际硬解」是两件事

Firefox 的 PDM 顺序里并没有 VA-API 专用解码器：

```
0: FFmpeg(FFVPX)
1: FFmpeg(OS library)
2: Agnostic
```

它由 `FFmpeg(FFVPX)` 先尝试 `video/av1`，失败后回退 `libdav1d`：

```
FFmpeg decoder rejects requested type 'video/av1'
FFmpeg decoder supports requested type 'video/av1'
FFMPEG: Using preferred software codec libdav1d
```

媒体能力查询看到 VA-API 暴露了 profile 就回答「支持」，真正解码失败后静默回退软件
解码。**所以浏览器显示支持 AV1 硬解，并不代表解码真的走硬件。** 播放本身是正常的，
只是跑在 CPU 上。

## 七、附二：AV1 软件解码够用

在 AV1 硬件路径打通之前，`libdav1d` 在 1280x720 上实测 **147 倍速**：

```
Stream #0:0 -> #0:0 (av1 (libdav1d) -> wrapped_avframe (native))
frame=   60 fps=0.0 q=-0.0 Lsize=N/A time=00:00:02.00 bitrate=N/A speed= 147x
```

对 1080p 乃至 4K 的 AV1 播放而言，CPU 解码在这颗 SoC 上并不构成瓶颈。
