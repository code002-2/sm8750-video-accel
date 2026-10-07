#!/bin/bash
# ============================================================================
#  qualcomm-video-codec-check.sh
#  Tells you which Qualcomm video codec block a mainline Linux device has:
#  Iris (SM8550/SM8650/SM8750 and newer) or Venus (SM8250/SM8350/SM8450 era),
#  or neither - and what that means for hardware video decode/encode.
#
#  Usage:  ./qualcomm-video-codec-check.sh
#  No arguments, no dependencies beyond standard tools (v4l2-ctl is used if present).
# ============================================================================
set -u

hr() { printf '%s\n' '------------------------------------------------------------'; }
have() { command -v "$1" >/dev/null 2>&1; }

echo "Qualcomm video codec check - $(date '+%F %T')"
echo "kernel: $(uname -r)   machine: $(uname -m)"
hr

# ---------------------------------------------------------------- 1. device tree
echo "[1] device tree: is a video codec node described at all?"
dt_hits=0
DT=""
[ -d /sys/firmware/devicetree/base ] && DT=/sys/firmware/devicetree/base
[ -z "$DT" ] && [ -d /proc/device-tree ] && DT=/proc/device-tree
if [ -n "$DT" ]; then
    for d in $(find "$DT" -name '*video-codec*' 2>/dev/null | head -5); do
        echo "    node: ${d#$DT}"
        dt_hits=$((dt_hits+1))
    done
    [ "$dt_hits" = 0 ] && echo "    no *video-codec* node found under $DT"
    # compatible strings are the strongest hint, and they are present before any driver
    # binds - useful on a device whose codec has never probed successfully
    for c in $(find "$DT" -name compatible 2>/dev/null | head -400); do
        v=$(tr -d '\0' < "$c" 2>/dev/null)
        case "$v" in
            *qcom,iris*|*qcom,sm8650-iris*|*qcom,sm8750-iris*) echo "    compatible: $v  <-- IRIS";;
            *qcom,venus*|*qcom,sm8250-venus*)                   echo "    compatible: $v  <-- VENUS";;
        esac
    done
else
    echo "    no device tree exposed (/sys/firmware/devicetree and /proc/device-tree both absent)"
fi

# ---------------------------------------------------------------- 2. kernel config
echo
echo "[2] kernel config"
cfg=""
for f in /proc/config.gz /boot/config-$(uname -r) /lib/modules/$(uname -r)/config; do
    case "$f" in
        *.gz) [ -r "$f" ] && cfg="zcat $f" && break;;
        *)    [ -r "$f" ] && cfg="cat $f" && break;;
    esac
done
if [ -n "$cfg" ]; then
    $cfg 2>/dev/null | grep -E '^CONFIG_VIDEO_QCOM_(IRIS|VENUS)' | sed 's/^/    /' || echo "    no CONFIG_VIDEO_QCOM_IRIS / _VENUS set"
else
    echo "    no kernel config readable (try /proc/config.gz or /boot/config-\$(uname -r))"
fi

# ---------------------------------------------------------------- 3. driver binding
echo
echo "[3] driver bound to the codec device"
bound=""
for d in /sys/bus/platform/devices/*video-codec*; do
    [ -e "$d" ] || continue
    drv=$(basename "$(readlink -f "$d/driver" 2>/dev/null)" 2>/dev/null)
    printf '    %-34s driver=%s\n' "$(basename "$d")" "${drv:-<unbound>}"
    case "$drv" in
        qcom-iris)  bound="iris";;
        qcom-venus) bound="venus";;
    esac
done
[ -z "$bound" ] && echo "    (no codec platform device, or it never probed)"

# ---------------------------------------------------------------- 4. modules
echo
echo "[4] kernel modules"
lsmod 2>/dev/null | awk '/iris|venus/ {printf "    loaded: %s (%s bytes, %s users)\n", $1, $2, $3}' || true
for m in qcom_iris qcom_venus; do
    p=$(find /lib/modules/"$(uname -r)" -name "${m}.ko*" 2>/dev/null | head -1)
    [ -n "$p" ] && echo "    file  : $p"
done

# ---------------------------------------------------------------- 5. firmware
echo
echo "[5] firmware (Iris needs vpu35, Venus needs venus-*)"
fw=$(find /lib/firmware -iname 'vpu35*.mbn' -o -iname 'venus*.mbn' 2>/dev/null | head -6)
if [ -n "$fw" ]; then echo "$fw" | sed 's/^/    /'; else echo "    none found"; fi

# ---------------------------------------------------------------- 6. v4l2 nodes
echo
echo "[6] v4l2 devices and codecs"
if have v4l2-ctl; then
    v4l2-ctl --list-devices 2>/dev/null | grep -iE 'iris|venus' | sed 's/^/    /'
    for n in /dev/video0 /dev/video1; do
        [ -e "$n" ] || continue
        card=$(v4l2-ctl -d "$n" --info 2>/dev/null | awk -F: '/Card type/{gsub(/^ +/,"",$2);print $2}')
        case "$card" in *Iris*|*Venus*) echo "    $n: $card";;
        esac
    done
    # decoder: coded formats are the OUTPUT queue. encoder: they are the CAPTURE queue.
    for n in /dev/video0 /dev/video1; do
        [ -e "$n" ] || continue
        card=$(v4l2-ctl -d "$n" --info 2>/dev/null | awk -F: '/Card type/{print $2}')
        out=$(v4l2-ctl -d "$n" --list-formats-out 2>/dev/null | grep -oE "'[A-Z0-9]{4}'" | tr '\n' ' ')
        cap=$(v4l2-ctl -d "$n" --list-formats 2>/dev/null | grep -oE "'[A-Z0-9]{4}'" | tr '\n' ' ')
        case "$card" in
            *Decoder*) echo "    $n decoder: decodes $out | outputs $cap";;
            *Encoder*) echo "    $n encoder: encodes $cap | accepts $out";;
        esac
    done
else
    echo "    v4l2-ctl not installed (apt install v4l-utils) - falling back to sysfs"
    for n in /dev/video*; do [ -e "$n" ] && echo "    $n"; done | head -6
fi

# ---------------------------------------------------------------- 7. verdict
echo
hr
echo "VERDICT"
case "$bound" in
    iris)
        echo "    This device has IRIS, and the kernel driver is bound."
        echo "    -> V4L2 stateful M2M. mpv/celluloid can use it right now:"
        echo "         mpv --hwdec=v4l2m2m-copy file.mp4"
        echo "    -> VA-API (Chrome, Firefox encode, Sunshine, ffmpeg) needs the backend"
        echo "       at https://github.com/code002-2/sm8750-video-accel (stateful only:"
        echo "       use radxa-pkg/libva-v4l2, NOT the stateless mxsrc one)."
        echo "    -> If VA-API reports 'DISPLAY_DELAY ... Iris decode-order patch required',"
        echo "       that repo ships the kernel patch, regenerated for 7.2.x."
        ;;
    venus)
        echo "    This device has VENUS (the generation before Iris)."
        echo "    -> Also V4L2 stateful M2M: mpv --hwdec=v4l2m2m-copy works."
        echo "    -> The Iris VA-API backend does not target Venus; check your distro's"
        echo "       libva packages, or stay with mpv/GStreamer directly."
        ;;
    *)
        if [ "$dt_hits" != 0 ]; then
            echo "    A codec node exists in the device tree but no driver is bound."
            echo "    Check: dmesg | grep -iE 'iris|venus|vcodec'  and the kernel config in [2]."
        else
            echo "    No Qualcomm video codec block found."
            echo "    Either this SoC has none, or the mainline device tree does not"
            echo "    describe it yet (common on very new SoCs)."
        fi
        ;;
esac
hr
