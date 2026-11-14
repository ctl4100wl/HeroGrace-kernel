#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${CROSS_COMPILE:?Set CROSS_COMPILE to the Linaro 4.9.4 aarch64-linux-gnu- prefix}"
: "${ANYKERNEL3_DIR:?Set ANYKERNEL3_DIR to the pinned AnyKernel3 checkout}"

export ARCH=arm64
# Retain the upstream HeroGrace compiler-side platform settings.
export PLATFORM_VERSION=10 ANDROID_MAJOR_VERSION=q
export LOCALVERSION=-HeroGrace-G930X-Eylem
export KBUILD_BUILD_USER=herograce KBUILD_BUILD_HOST=github-actions

mkdir -p artifacts
python3 scripts/ci/check-manager-abi.py | tee artifacts/manager-abi.log
python3 scripts/ci/check-susfs-control.py | tee artifacts/susfs-control.log
grep -qx 'KSU_VERSION := 33355' drivers/kernelsu/Kbuild
grep -qx '#define KERNEL_SU_UAPI_VERSION 5' drivers/kernelsu/include/uapi/supercall.h

dts=arch/arm64/boot/dts/exynos8890.dtsi
if [[ -e "$dts" ]]; then
    echo "Remove or rename the existing $dts before building." >&2
    exit 1
fi
trap 'rm -f "$dts"' EXIT
cp arch/arm64/boot/exynos8890_Oneui.dtsi "$dts"

make_args=('HOSTCFLAGS=-O2 -fcommon')
make "${make_args[@]}" herograce_g930x_defconfig
for option in CONFIG_MODEL_HEROLTE CONFIG_KSU CONFIG_KSU_MANUAL_HOOK CONFIG_IOSCHED_MAPLE CONFIG_KSU_SUSFS; do
    grep -qx "$option=y" .config || { echo "Missing $option" >&2; exit 1; }
done
cp .config artifacts/kernel.config
make "${make_args[@]}" -j"${JOBS:-$(nproc)}" Image dtb.img 2>&1 | tee artifacts/build.log
"${CROSS_COMPILE}nm" vmlinux | awk '{print $3}' > artifacts/kernel-symbols.txt
for symbol in kernelsu_init ksu_handle_sys_reboot maple_init_queue susfs_init ksu_susfs_prctl; do
    grep -qx "$symbol" artifacts/kernel-symbols.txt || { echo "Missing linked symbol $symbol" >&2; exit 1; }
done
python3 scripts/ci/package-g930x.py
