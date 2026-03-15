#!/bin/bash
#
# SPDX-FileCopyrightText: Majaahh
# SPDX-License-Identifier: Apache-2.0
#

# [
_PRINT_USAGE()
{
    echo "Usage: build.sh [arguments] <device>"
    echo "Arguments:"
    echo "-f,--flash       Flashes latest build"
    echo "-h,--help        Prints this help menu"
    echo "-k,--ksu         Makes a KernelSU Build"
    echo "-r,--regenerate  Regenerates the defconfig"
    echo "-u,--upload      Creates a release on GitHub"
}

# shellcheck disable=SC1091
source "$SRC_DIR/scripts/utils/common_utils.sh" || exit 1
# shellcheck disable=SC1091
source "$SRC_DIR/scripts/utils/log_utils.sh" || exit 1

KERNEL_TAR_NAME="UN1CA_Kernel-$(date +%Y%m%d-%H%M)-a53x"
DTBO_TAR_NAME="UN1CA_DTBO-$(date +%Y%m%d-%H%M)-a53x"
FLASH=false
KSU=false
REGENERATE=false
UPLOAD=false
DEVICE=""
POST=false
MAKE_ARGS="-C\" \"$KERNEL_DIR\" \"-j$(nproc --all)\" \"CC=clang\" \"O=$BUILD_DIR\" \"KBUILD_BUILD_USER=Majaahh\" \"KBUILD_BUILD_HOST=PC"
# ]

while [[ "$1" == "-"* ]]; do
    if [[ "$1" == "-f" ]] || [[ "$1" == "--flash" ]]; then
        FLASH=true
        POST=true
    elif [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        _PRINT_USAGE
        exit 0
    elif [[ "$1" == "-k" ]] || [[ "$1" == "--ksu" ]]; then
        KERNEL_TAR_NAME="UN1CA_Kernel-$(date +%Y%m%d-%H%M)-KernelSU-a53x"
        KSU=true
    elif [[ "$1" == "-r" ]] || [[ "$1" == "--regenerate" ]]; then
        REGENERATE=true
    elif [[ "$1" == "-u" ]] || [[ "$1" == "--upload" ]]; then
        UPLOAD=true
        POST=true
    else
        LOGE "Unknown option: $1"
        _PRINT_USAGE
        exit 1
    fi

    shift
done

DEVICE="$1"

if ! $REGENERATE && [[ "$#" -eq "0" ]]; then
    _PRINT_USAGE
    exit 1
fi

if ! $REGENERATE && [[ -z "$DEVICE" ]]; then
    LOGE "No device specified"
    _PRINT_USAGE
    exit 1
fi

if [[ ! -d "$KERNEL_DIR" ]] || [[ ! -d "$KERNEL_DIR/drivers/kernelsu" ]]; then
    LOG_STEP_IN true "Setting up kernel source"

    if [[ ! -d "$KERNEL_DIR" ]]; then
        LOG "- Cloning kernel source"
        EVAL "git clone -j\"$(nproc --all)\" \"https://github.com/majaahh/android_kernel_samsung_a53x.git\" \"$KERNEL_DIR\""
    fi

    LOG "- Fetching submodules"
    (
    cd "$KERNEL_DIR"
    EVAL "git submodule update --init -f --checkout"
    ) || exit 1

    LOG_STEP_OUT
fi

if ! $REGENERATE && [[ ! -f "$KERNEL_DIR/arch/arm64/configs/$DEVICE.config" ]]; then
    LOGE "Configuration fragment for $DEVICE was not found"
    exit 1
fi

if [[ ! -d "$TOOLCHAIN_DIR" ]]; then
    GET_AOSP_CLANG || exit 1
else
    if [[ ! -f "$TOOLCHAIN_DIR/bin/clang" ]]; then
        EVAL "rm -rf \"$TOOLCHAIN_DIR\"" || exit 1
        GET_AOSP_CLANG || exit 1
    fi
fi

LOG_STEP_IN true "Building Kernel"
LOG_STEP_IN "- Generating configuration"
EVAL "make \"$MAKE_ARGS\" \"s5e8825_defconfig\" >/dev/null"

if $REGENERATE; then
    LOG "- Copying configuration to arch/arm64/configs/s5e8825_defconfig"
    EVAL "cp -a \"$BUILD_DIR/.config\" \"$KERNEL_DIR/arch/arm64/configs/s5e8825_defconfig\""
    LOG_STEP_OUT
    exit 0
fi

LOG "- Merging $DEVICE fragment"
EVAL "make \"$MAKE_ARGS\" \"$DEVICE.config\" >/dev/null"

if $KSU; then
    LOG "- Merging KernelSU fragment"
    EVAL "make \"$MAKE_ARGS\" \"ksu.config\" >/dev/null"
fi

LOG "- Setting local version"
EVAL "sed -i s/\-UN1CA/\-UN1CA\-$(git rev-parse --short HEAD)/g \"$BUILD_DIR/.config\""
LOG_STEP_OUT
LOG "- Building dtbs"
EVAL "make \"$MAKE_ARGS\" \"dtbs\" >/dev/null"
LOG "- Building Kernel"
EVAL "make \"$MAKE_ARGS\" >/dev/null"
LOG_STEP_OUT

LOG_STEP_IN true "Building TAR Archives"
if [[ -d "$IMAGES_DIR/kernel" ]]; then
   EVAL "rm -rf \"$IMAGES_DIR/kernel\""
fi
EVAL "mkdir -p \"$IMAGES_DIR/kernel\""

for i in "boot" "vendor_boot"; do
    "$SRC_DIR/scripts/build_image.sh" "$i" "$IMAGES_DIR/kernel" -d "$DEVICE" || exit 1
done

LOG "- Creating Kernel TAR Archive"
CREATE_TAR_ARCHIVE "$OUT/$KERNEL_TAR_NAME.tar" "$IMAGES_DIR/kernel/boot.img.lz4" "$IMAGES_DIR/kernel/vendor_boot.img.lz4" || exit 1

if [[ -d "$IMAGES_DIR/dtbo" ]]; then
    EVAL "rm -rf \"$IMAGES_DIR/dtbo\""
fi
EVAL "mkdir -p \"$IMAGES_DIR/dtbo\""

if [[ "$DEVICE" == "a53x" ]]; then
    for i in "" "_jpn"; do
        "$SRC_DIR/scripts/build_image.sh" "dtbo" "$IMAGES_DIR/dtbo" -d "${DEVICE}${i}" || exit 1
        LOG "- Creating dtbo TAR Archive"
        CREATE_TAR_ARCHIVE "$OUT/$DTBO_TAR_NAME$i.tar" "$IMAGES_DIR/dtbo/dtbo.img.lz4" || exit 1
    done
else
    "$SRC_DIR/scripts/build_image.sh" "$i" "$IMAGES_DIR/dtbo" -d "$DEVICE" || exit 1
    LOG "- Creating dtbo TAR Archive"
    CREATE_TAR_ARCHIVE "$OUT/$DTBO_TAR_NAME.tar" "$IMAGES_DIR/dtbo/dtbo.img.lz4" || exit 1
fi
LOG_STEP_OUT

if $POST; then
    LOG_STEP_IN true "Running post-build scripts"
fi

if $FLASH; then
    LOG "- Flashing ${OUT//$SRC_DIR\//}/$KERNEL_TAR_NAME.tar"
    "$SRC_DIR/scripts/flash.sh" -a "$OUT/$KERNEL_TAR_NAME.tar" || exit 1
fi

if $UPLOAD; then
    (
    cd "$KERNEL_DIR"

    UPLOAD "$OUT/$KERNEL_TAR_NAME.tar" || exit 1
    UPLOAD "$OUT/$DTBO_TAR_NAME.tar" || exit 1
    if [[ "$DEVICE" == "a53x" ]]; then
        UPLOAD "$OUT/${DTBO_TAR_NAME}_jpn.tar" || exit 1
    fi
    ) || exit 1
fi

LOG_STEP_OUT
