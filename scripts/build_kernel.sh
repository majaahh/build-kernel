#!/bin/bash
#
# SPDX-FileCopyrightText: Majaahh
# SPDX-License-Identifier: Apache-2.0
#

# [
# shellcheck disable=SC1091
source "$SRC_DIR/scripts/utils/common_utils.sh" || exit 1
# shellcheck disable=SC1091
source "$SRC_DIR/scripts/utils/log_utils.sh" || exit 1

_PRINT_USAGE()
{
    echo "Usage: build_kernel.sh <arguments>"
    echo "Images: boot, dtb, dtbo, vendor_boot"
    echo "Arguments:"
    echo "-d,--device      Specify device codename"
    echo "-h,--help        Prints this help menu"
    echo "-k,--ksu         Makes a KernelSU Build"
    echo "-r,--regenerate  Regenerates the defconfig"
}

BUILD_KERNEL()
{
    local CMD
    local EXTRA_CMD="$1"

    CMD+="make "
    CMD+="-C \"$KERNEL_DIR\" "
    CMD+="-j\"$(nproc --all)\" "
    CMD+="\"CC=clang\" "
    CMD+="\"O=$BUILD_DIR\" "
    CMD+="\"KBUILD_BUILD_USER=Majaahh\" "
    CMD+="\"KBUILD_BUILD_HOST=PC\" "
    if [[ -n "$EXTRA_CMD" ]]; then
        CMD+="$1 "
    fi
    CMD+="> /dev/null"

    EVAL "$CMD" || return 1
}

DEVICE=""
KSU=false
REGENERATE=false
# ]

while [[ "$1" == "-"* ]]; do
    if [[ "$1" == "-d" ]] || [[ "$1" == "--device" ]]; then
        if [[ -z "$2" ]] || [[ "$2" == "-"* ]]; then
            LOGE "Missing argument for $1"
            _PRINT_USAGE
            exit 1
        fi
        DEVICE="$2"
        shift
    elif [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        _PRINT_USAGE
        exit 0
    elif [[ "$1" == "-k" ]] || [[ "$1" == "--ksu" ]]; then
        KSU=true
    elif [[ "$1" == "-r" ]] || [[ "$1" == "--regenerate" ]]; then
        REGENERATE=true
    else
        LOGE "Unknown option: $1"
        _PRINT_USAGE
        exit 1
    fi

    shift
done

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
    EVAL "cd \"$KERNEL_DIR\" && git submodule update --init -f --checkout"

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

LOG_STEP_IN "- Generating configuration"
BUILD_KERNEL "s5e8825_defconfig"

if $REGENERATE; then
    LOG "- Copying configuration to arch/arm64/configs/s5e8825_defconfig"
    EVAL "cp -a \"$BUILD_DIR/.config\" \"$KERNEL_DIR/arch/arm64/configs/s5e8825_defconfig\""
    LOG_STEP_OUT
    exit 0
fi

LOG "- Merging $DEVICE fragment"
BUILD_KERNEL "$DEVICE.config"

if $KSU; then
    LOG "- Merging KernelSU fragment"
    BUILD_KERNEL "ksu.config"
fi

LOG "- Setting local version"
EVAL "sed -i s/\-UN1CA/\-UN1CA\-$(git rev-parse --short HEAD)/g \"$BUILD_DIR/.config\""
LOG_STEP_OUT
LOG "- Building dtbs"
BUILD_KERNEL "dtbs"
LOG "- Building kernel image"
BUILD_KERNEL
