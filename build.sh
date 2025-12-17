#!/bin/bash
#
# Copyright (C) 2020-2021 Adithya R. (original version)
# Copyright (C) 2022-2025 Flopster101 (rewrite)
# Copyright (C) 2025 Majaahh (rewrite)
#
# Additional credits:
# * Gabriel2392: Logic previously used for module packaging.
# * ExtremeXT: Logic for generating modules.load on the fly.
#

# [
# shellcheck disable=SC1007,SC2164
# https://android.googlesource.com/platform/build/+/refs/tags/android-15.0.0_r1/envsetup.sh#18
_GET_SRC_DIR()
{
    local TOPFILE="build/build.sh"
    if [ -n "$SRC_DIR" ] && [ -f "$SRC_DIR/$TOPFILE" ]; then
        # The following circumlocution ensures we remove symlinks from SRC_DIR.
        (cd "$SRC_DIR"; PWD= /bin/pwd)
    else
        if [ -f "$TOPFILE" ]; then
            # The following circumlocution (repeated below as well) ensures
            # that we record the true directory name and not one that is
            # faked up with symlink names.
            PWD= /bin/pwd
        else
            local HERE="$PWD"
            local T=
            while [ \( ! \( -f "$TOPFILE" \) \) ] && [ \( "$PWD" != "/" \) ]; do
                \cd ..
                T="$(PWD= /bin/pwd -P)"
            done
            \cd "$HERE"
            if [ -f "$T/$TOPFILE" ]; then
                echo "$T"
            fi
        fi
    fi
}

SRC_DIR="$(_GET_SRC_DIR)"
if [ ! "$SRC_DIR" ]; then
    echo "Couldn't locate the top of the tree. Always source buildenv.sh from the root of the tree." >&2
    return 1
fi

unset -f _GET_SRC_DIR

source "$SRC_DIR/build/utils/common_utils.sh" || exit 1
source "$SRC_DIR/build/utils/log_utils.sh" || exit 1
source "$SRC_DIR/build/utils/module_utils.sh" || exit 1
# ]

# Variables
PREV_DIR="$(readlink -f ../)"
OUTDIR="$SRC_DIR/out"
MOD_OUTDIR="$SRC_DIR/modules_out"
TMP_DIR="$SRC_DIR/build/tmp"
IN_PLATFORM="$SRC_DIR/build/vboot_platform"
IN_DLKM="$SRC_DIR/build/vboot_dlkm"
DTS_DIR="$OUTDIR/arch/arm64/boot/dts/exynos"
PLATFORM_RAMDISK_DIR="$TMP_DIR/ramdisk_platform"
DLKM_RAMDISK_DIR="$TMP_DIR/ramdisk_dlkm"
PREBUILT_RAMDISK="$SRC_DIR/build/boot/ramdisk"
MODULES_DIR="$DLKM_RAMDISK_DIR/lib/modules"
OUT_KERNEL="$OUTDIR/arch/arm64/boot/Image"
IMAGES_DIR="$SRC_DIR/build/images"
OUT_BOOTIMG="$IMAGES_DIR/boot.img"
OUT_VENDORBOOTIMG="$IMAGES_DIR/vendor_boot.img"
OUT_DTBIMAGE="$IMAGES_DIR/dtb.img"
OUT_DTBOIMAGE="$IMAGES_DIR/dtbo.img"
MKBOOTIMG="$(pwd)/build/mkbootimg/mkbootimg.py"
MKDTBOIMG="$(pwd)/build/dtb/mkdtboimg.py"
AOSP_LIST="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+/mirror-goog-main-llvm-toolchain-source"
AOSP_ARCHIVE="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/mirror-goog-main-llvm-toolchain-source"
AOSP_DIR="$PREV_DIR/aospclang"
DATE="$(date +%Y%m%d-%H%M)"
MONTH="$(date +%Y-%m)"
BUILDS_DIR="$SRC_DIR/build/builds"
TAR="UN1CA_Kernel-$DATE-a53x.tar"

export KBUILD_BUILD_USER="Majaahh"
export KBUILD_BUILD_HOST="PC"
export PLATFORM_VERSION="12"
export ANDROID_MAJOR_VERSION="s"
export TARGET_SOC="s5e8825"
export LLVM=1
export LLVM_IAS=1
export ARCH=arm64
export PATH="$AOSP_DIR/bin:$PATH"

CLEANUP

if [[ ! -d "$AOSP_DIR" ]]; then
    LOG_STEP_IN true "Downloading clang"
    EVAL "mkdir -p \"$AOSP_DIR\""

    HTML="$(curl -s "$AOSP_LIST")"
    CURRENT_CLANG="$(printf '%s\n' "$HTML" | grep -oP 'href="[^"]*clang-r[0-9]+/' | grep -oP 'clang-r[0-9]+' | sort -V | tail -n1)"

    if [[ -z "$CURRENT_CLANG" ]]; then
        LOGE "Couldn’t find any clang-r### dirs in $AOSP_LIST"
        exit 1
    fi

    LOG "- Latest AOSP Clang is $CURRENT_CLANG, downloading."
    EVAL "wget -nv -O \"$CURRENT_CLANG.tar.gz\" \"$AOSP_ARCHIVE/$CURRENT_CLANG.tar.gz\""

    EVAL "tar -xf \"$CURRENT_CLANG.tar.gz\" -C \"$AOSP_DIR\" && rm \"$CURRENT_CLANG.tar.gz\""

    EVAL "touch \"$AOSP_DIR/bin/aarch64-linux-gnu-elfedit\" && chmod +x \"$AOSP_DIR/bin/aarch64-linux-gnu-elfedit\""
    EVAL "touch \"$AOSP_DIR/bin/arm-linux-gnueabi-elfedit\" && chmod +x \"$AOSP_DIR/bin/arm-linux-gnueabi-elfedit\""

    LOG_STEP_OUT
fi

LOG_STEP_IN true "Starting build"
LOG_STEP_IN "- Generating configuration"
EVAL "make -j\"$(nproc --all)\" O=\"$OUTDIR\" CC=\"clang\" \"a53x_defconfig\" >/dev/null"
LOG "- Setting local version"
EVAL "sed -i s/\-UN1CA/\-UN1CA\-$(git rev-parse --short HEAD)/g \"$OUTDIR/.config\""
LOG_STEP_OUT
LOG "- Building dtbs"
EVAL "make -j\"$(nproc --all)\" O=\"$OUTDIR\" CC=\"clang\" \"dtbs\" >/dev/null"
LOG "- Building kernel"
EVAL "make -j\"$(nproc --all)\" O=\"$OUTDIR\" CC=\"clang\" >/dev/null"
LOG "- Installing modules"
EVAL "make -j\"$(nproc --all)\" O=\"$OUTDIR\" CC=\"clang\" \
    INSTALL_MOD_STRIP=\"--strip-debug --keep-section=.ARM.attributes\" \
    INSTALL_MOD_PATH=\"$MOD_OUTDIR\" \"modules_install\" >/dev/null"

EVAL "mkdir -p \"$PLATFORM_RAMDISK_DIR/first_stage_ramdisk\""
EVAL "cp -rf \"$IN_PLATFORM/\"* \"$PLATFORM_RAMDISK_DIR\""
EVAL "cp -f \"$PLATFORM_RAMDISK_DIR/fstab.s5e8825\" \"$PLATFORM_RAMDISK_DIR/first_stage_ramdisk/fstab.s5e8825\""

if ! find "$MOD_OUTDIR/lib/modules" -mindepth 1 -type d | read; then
    LOGE "Unknown error"
    exit 1
fi

LOG_STEP_IN "- Generating modules.load"
GENERATE_MODULES_LOAD
LOG_STEP_OUT
LOG_STEP_OUT

LOG_STEP_IN true "Building TAR archive"
if [[ ! -d "$IMAGES_DIR" ]]; then
    EVAL "mkdir -p \"$IMAGES_DIR\""
fi

LOG "- Building dtb image"
EVAL "\"$MKDTBOIMG\" cfg_create \"$OUT_DTBIMAGE\" \"$SRC_DIR/build/configs/s5e8825.cfg\" -d \"$DTS_DIR\""

LOG "- Building dtbo image"
EVAL "\"$MKDTBOIMG\" cfg_create \"$OUT_DTBOIMAGE\" \"$SRC_DIR/build/configs/a53x.cfg\" -d \"$DTS_DIR/samsung/a53x\""

LOG "- Building boot image"
EVAL "\"$MKBOOTIMG\" \
    --header_version 4 \
    --kernel \"$OUT_KERNEL\" \
    --output \"$OUT_BOOTIMG\" \
    --ramdisk \"$PREBUILT_RAMDISK\" \
    --os_version 16.0.0 \
    --os_patch_level \"$MONTH\""

(
cd "$DLKM_RAMDISK_DIR" || exit 1
EVAL "find . | cpio --quiet -o -H newc -R root:root | lz4 -9cl > \"../ramdisk_dlkm.lz4\""
)

(
cd "$PLATFORM_RAMDISK_DIR" || exit 1
EVAL "find . | cpio --quiet -o -H newc -R root:root | lz4 -9cl > \"../ramdisk_platform.lz4\""
)

EVAL "echo \"buildtime_bootconfig=enable\" > \"$TMP_DIR/bootconfig\""

LOG "- Building vendor_boot image"
EVAL "\"$MKBOOTIMG\" \
    --header_version 4 \
    --vendor_boot \"$OUT_VENDORBOOTIMG\" \
    --vendor_bootconfig \"$TMP_DIR/bootconfig\" \
    --dtb \"$OUT_DTBIMAGE\" \
    --vendor_ramdisk \"$TMP_DIR/ramdisk_platform.lz4\" \
    --ramdisk_type \"dlkm\" \
    --ramdisk_name \"dlkm\" \
    --vendor_ramdisk_fragment \"$TMP_DIR/ramdisk_dlkm.lz4\" \
    --os_version 16.0.0 \
    --os_patch_level \"$MONTH\""

LOG "- Creating kernel archive"
if [[ ! -d "$BUILDS_DIR" ]]; then
    EVAL "mkdir -p \"$BUILDS_DIR\""
fi

(
cd "$SRC_DIR/build"

EVAL "lz4 -c -12 -B6 --content-size \"$OUT_BOOTIMG\" > \"boot.img.lz4\""
EVAL "lz4 -c -12 -B6 --content-size \"$OUT_DTBOIMAGE\" > \"dtbo.img.lz4\""
EVAL "lz4 -c -12 -B6 --content-size \"$OUT_VENDORBOOTIMG\" > \"vendor_boot.img.lz4\""
EVAL "tar -cf \"$BUILDS_DIR/$TAR\" \"boot.img.lz4\" \"dtbo.img.lz4\" \"vendor_boot.img.lz4\""
EVAL "rm -f \"boot.img.lz4\" \"dtbo.img.lz4\" \"vendor_boot.img.lz4\""
)
LOG_STEP_OUT

CLEANUP
