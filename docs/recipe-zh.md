# 视频硬件编解码 + VA-API 完整配方（Xiaomi Pad 8 Pro / SM8750P）

日期：2026-10-07　设备：`piano`（Debian 13 trixie，内核 `7.2.6-sm8750-piano-code002`）

## 最终成果

| 能力 | 实现方式 | 验证 |
|---|---|---|
| **H.264 解码** | Iris 解码器（V4L2 stateful M2M） | ✅ mpv 实测 `Using hardware decoding` |
| **HEVC 解码（含 Main10）** | 同上 | ✅ 含 **4K HEVC** |
| **VP9 解码（Profile 0/2）** | 同上 | ✅ |
| **AV1 解码** | 驱动支持 ✓（Firefox 报支持 ✓；mpv 的 v4l2m2m 列表还没有） | ✅ 驱动层 |
| **H.264 / HEVC 编码** | Iris 编码器 + VA-API 后端 | ✅ **Firefox 已显示硬件编码** |
| **VA-API** | `libva-v4l2`（Radxa fork）+ 内核 iris 补丁 | ✅ `vainfo` 返回 0，全部 profile |

硬件：`/dev/video0` = Iris Decoder ✓，`/dev/video1` = Iris Encoder ✓，驱动 `qcom-iris` ✓（`piano-video.service` 负责把 codec 的 IOMMU 组切成 DMA 域 ✓）。

---

## 一、VA-API 后端（这条最绕，按顺序做）

### 1. 关键选择：必须用 Radxa 的 fork

| 版本 | 支持 | 能否用 |
|---|---|---|
| `mxsrc/libva-v4l2`（上游） | **只支持 stateless** ✗（README 把 stateful 列为未来计划） | ❌ |
| **`radxa-pkg/libva-v4l2`** | **"for Qualcomm Iris, using the Linux V4L2 stateful M2M interface"** | ✅ |

### 2. 编译依赖：**绝对不要装 `libgbm-dev`** ⚠️

这台机器的 Mesa 是**项目为 Adreno 830 打过补丁的**（版本带 `+piano1`）。`libgbm-dev` 会把 `libgbm1` **降级** ✗ → **GPU 加速报废**。

```bash
# 先上保险，锁住整个图形栈
for p in libgbm1 libegl1 libgles2 libgl1 libglx0 mesa-libgallium; do apt-mark hold "$p"; done
dpkg -l | awk '/piano/ && /^ii/ {print $2}' | xargs -r apt-mark hold

# 只装安全的编译依赖
apt-get install -y build-essential meson ninja-build pkg-config libva-dev libdrm-dev libegl-dev libgles-dev
```

手工提供 `gbm`（**不安装** `libgbm-dev`）：

```bash
apt-get download libgbm-dev
mkdir -p /root/gbm-dev && dpkg-deb -x libgbm-dev_*.deb /root/gbm-dev
cp -a /root/gbm-dev/usr/include/* /usr/local/include/
# 写一个指向 piano 版 libgbm 的 .pc
sed -e 's|^prefix=.*|prefix=/usr/local|' \
    -e 's|^libdir=.*|libdir=/usr/lib/aarch64-linux-gnu|' \
    -e 's|^includedir=.*|includedir=/usr/local/include|' \
    /root/gbm-dev/usr/lib/aarch64-linux-gnu/pkgconfig/gbm.pc > /usr/local/lib/pkgconfig/gbm.pc

# 链接时还需要 libgbm.so 这个符号链接（-dev 包唯一必需的东西）
ln -sf libgbm.so.1.0.0 /usr/lib/aarch64-linux-gnu/libgbm.so
```

### 3. 编译与安装

```bash
git clone --depth 1 https://github.com/radxa-pkg/libva-v4l2.git /root/libva-v4l2
cd /root/libva-v4l2
PKG_CONFIG_PATH=/usr/local/lib/pkgconfig meson setup build
ninja -C build && ninja -C build install
# → /usr/local/lib/aarch64-linux-gnu/dri/{v4l2_drv_video.so, msm_drv_video.so}
```

### 4. 让所有程序都能用（无需环境变量）

```bash
ln -sf /usr/local/lib/aarch64-linux-gnu/dri/v4l2_drv_video.so /usr/lib/aarch64-linux-gnu/dri/
ln -sf /usr/local/lib/aarch64-linux-gnu/dri/msm_drv_video.so   /usr/lib/aarch64-linux-gnu/dri/

cat > /etc/environment.d/50-piano-vaapi.conf <<'EOF'
LIBVA_DRIVER_NAME=v4l2
LIBVA_DRIVERS_PATH=/usr/lib/aarch64-linux-gnu/dri:/usr/local/lib/aarch64-linux-gnu/dri
GST_VAAPI_ALL_DRIVERS=1
EOF
```
（`msm_drv_video.so` 这个名字很关键：libva **默认就会去开它** ✓，所以连没改过的程序也能用 ✓。）

---

## 二、内核补丁（不解码就卡死的那一步）

**症状**：`vainfo` 正常，但一解码就 `iris-vaapi: S_CTRL DISPLAY_DELAY (Iris decode-order patch required): Invalid argument`。

`libva-v4l2/patches/` 里有三个补丁：

```
0001-media-iris-support-decode-order-output-on-HFI-gen2.patch   ← 缺它就报上面那个错
0002-media-iris-allow-larger-capture-buffer-pools-on-HFI-.patch
0003-media-iris-Add-deblocking-filter-controls-for-HFI-ge.patch
```

### ⚠️ 最大的坑

补丁是针对 **6.18.x-qcom** 写的，套到 **7.2.6** 上 `git apply` 会失败 ✗。用 `patch --fuzz=3` 能"应用成功" ✓，但**会把两行枚举插进错误的枚举** ✗：

```c
enum platform_inst_fw_cap_flags {          /* 这是 flags 枚举，不该放这里 */
    CAP_FLAG_DYNAMIC_ALLOWED = BIT(0),
    DISPLAY_DELAY_ENABLE,                  /* 插错位置 → = 2 */
    DISPLAY_DELAY,                         /* = 3 */
    CAP_FLAG_MENU            = BIT(1),     /* = 2  ← 撞车 → duplicate case value */
```

**它不是"补丁与内核不兼容"，而是两行代码放错了枚举** ✓。修法：

```python
# 从 flags 枚举里删掉，插到 type 枚举的 INST_FW_CAP_MAX 之前
s = re.sub(r'^[ \t]*DISPLAY_DELAY_ENABLE,[ \t]*\n', '', s, flags=re.M)
s = re.sub(r'^[ \t]*DISPLAY_DELAY,[ \t]*\n', '', s, flags=re.M)
s = re.sub(r'^([ \t]*)(INST_FW_CAP_MAX,)',
           r'\1DISPLAY_DELAY_ENABLE,\n\1DISPLAY_DELAY,\n\1\2', s, count=1, flags=re.M)
```

### 编译与安装

内核树 `/root/kernel/linux-7.2.6`（`CONFIG_CC_IS_GCC=y` → **必须用交叉 gcc，不是 clang** ✗）：

```bash
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j14 M=drivers/media/platform/qcom/iris modules
# → drivers/media/platform/qcom/iris/qcom-iris.ko（补丁版约 1,453,768 字节）
# 推到设备并备份原模块
ssh root@设备 "cp -a .../qcom-iris.ko{,.orig-piano}"
ssh root@设备 "cat > .../qcom-iris.ko" < qcom-iris.ko
ssh root@设备 "depmod -a $(uname -r)"
# 重启（模块在用，不能热替换）
```

**验证**（重启后）：

```bash
v4l2-ctl -d /dev/video0 --list-ctrls | grep -i delay
# display_delay        0x00990b8d (int)  : min=0 max=0 step=1 default=0 ✓
# display_delay_enable 0x00990b8e (bool) : default=0 ✓   ← 补丁前根本不存在
```

---

## 三、应用侧配置

**Firefox**（中文 + 硬解/硬编码）—— `user.js` 要放进**真实**配置文件目录（用 `find` 找，别用通配符 ✗）：

```js
user_pref("intl.locale.requested", "zh-CN");
user_pref("media.hardware-video-decoding.enabled", true);
user_pref("media.hardware-video-decoding.force-enabled", true);
```
+ 策略文件 `/etc/firefox-esr/policies/policies.json`（两处都写更保险）+ `firefox-esr-l10n-zh-cn`

**mpv** `~/.config/mpv/mpv.conf`：

```
hwdec=v4l2m2m-copy      # 或 hwdec=vaapi（会话内）
vo=gpu
```

**Chrome**：Google Chrome **有 arm64 版** ✓（`dl.google.com` 在设备上实测 **27 MB/s** ✓，别绕道下载）。加参数：

```
--enable-features=VaapiVideoDecoder,VaapiVideoEncoder,AcceleratedVideoDecodeLinuxGL,VaapiIgnoreDriverChecks
--ozone-platform-hint=auto
--enable-zero-copy
```

⚠️ **flag 名必须对着这台机器的 Chrome 二进制核实**（教程里的名字常常是过时的 ✗）：

```bash
strings -a /opt/google/chrome/chrome | grep -oE '(Accelerated|Vaapi)[A-Za-z]*(Video|Encode|Decode)[A-Za-z]*' | sort -u
# Chrome 155 实测存在：AcceleratedVideoDecode / AcceleratedVideoDecodeLinuxGL /
#   AcceleratedVideoDecodeLinuxZeroCopyGL / AcceleratedVideoDecoder / AcceleratedVideoEncoder /
#   VaapiVideoDecoder / VaapiVideoEncodeAccelerator / VaapiIgnoreDriverChecks
# 不存在（教程里常见但已过时）：VaapiVideoEncoder ✗
```
核实方式要用 **`grep -oF`（子串）**，用 `grep -cx`（整行）会全部查不到 ✗ —— `strings` 的行里还有别的内容。

⚠️ **Chrome 的编码支持很窄**：VA-API 编码只用于 **H.264 / VP8 / VP9** 且只在 **WebRTC / 录制**路径触发，**从不支持 HEVC** ✗。所以 `chrome://gpu` 的 Video Encode 显示 software only 很常见 ✓，**看视频靠的是 Decode** ✓。要 HEVC 硬件编码用 **Firefox** ✓（实测已可用 ✓）。

⚠️ **改 `.desktop` 时最容易犯的错**：参数**必须放在可执行文件之后** ✗：

```diff
- Exec=--enable-features=VaapiVideoDecoder … /usr/bin/google-chrome-stable %U   ✗ 菜单里整个消失 ✗
+ Exec=/usr/bin/google-chrome-stable --enable-features=VaapiVideoDecoder … %U   ✓
```

`Exec=` 的第一个词必须是**可执行文件** ✓ —— 否则 GNOME 解析菜单时直接**丢弃这一项**（图标就"不见了" ✓），而 **`desktop-file-validate` 查不出来** ✗（它只验语法 ✓）。
**正确的验证方式**：检查 `Exec=` 的第一个词是否 `-x` 可执行 ✓，然后 `update-desktop-database` ✓。

Google 还自带一个 `com.google.Chrome.desktop` ✓（未改过 ✓）—— 如果不想动包里的启动器，也可以另建一个**新名字**的 `.desktop` ✓ 指向带参数的包装脚本 ✓。

---

## 四、血泪教训

1. **`ffmpeg -hwaccel v4l2m2m` / `-vcodec h264_v4l2m2m` 会永久卡死 codec** ✗（`SIGTERM`/`timeout` 都杀不掉，要 `-s KILL`，而且会把整机拖到 SSH 都不响应）。**测试一律用 mpv** ✓（它的缓冲协商是对的）。
2. **`iw scan` 会让网卡反复离开信道** ✗ → 信号满格却丢包 85% ✓。**绝不在活动连接上跑**；要用就用 `nmcli device wifi list`。
3. **`libgbm-dev` 会降级 piano 的 Mesa** ✗ → 先把图形栈 `apt-mark hold` 住。
4. **VM 里 `apt` 先试 IPv6** ✗（这台设备 IPv6 无路由）→ 加 `Acquire::ForceIPv4 "true";`。
5. **别用 `scp`** ✗（这条链路上会静默失败）→ 用 `ssh 'cat > file' < local` ✓，并核对大小。
6. **Jetsam**：设备内存只有 7 GiB，装大包时用 `systemd-run` 跑独立单元 ✓，别放在 SSH 会话的 cgroup 里（会话一断就被 SIGKILL，日志里是 `EXIT=137`）。
