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
    echo "Arguments:"
    echo "-d,--device      Specify device codename"
    echo "-h,--help        Prints this help menu"
    echo "-k,--ksu         Makes a KernelSU Build"
    echo "-r,--regenerate  Regenerates the defconfig"
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

if [[ ! -d "$KERNEL_DIR" ]]; then
    LOG_STEP_IN "- Setting up kernel source"

    if [[ ! -d "$KERNEL_DIR" ]]; then
        LOG "- Cloning kernel source"
        EVAL "git clone -j\"$(nproc --all)\" \"https://github.com/UN1CA/kernel_samsung_s5e8825.git\" \"$KERNEL_DIR\""
    fi

    if [[ -f "$KERNEL_DIR/.gitmodules" ]]; then
        LOG "- Fetching submodules"
        EVAL "cd \"$KERNEL_DIR\" && git submodule update --init -f --checkout"
    fi

    LOG_STEP_OUT
fi

if [[ ! -d "$TOOLCHAIN_DIR" ]]; then
    # shellcheck disable=SC2119
    GET_AOSP_CLANG || exit 1
else
    GET_LATEST_AOSP_CLANG --compare
fi

TC="$KERNEL_DIR/toolchain/clang/host/linux-x86/clang-r416183b/bin"
GAS="$KERNEL_DIR/toolchain/prebuilts/gas/linux-x86"
BT="/home/Maja/android/lineage-23.2/prebuilts/build-tools/path/linux-x86"

if [[ ":$PATH:" != *":$TC:"* ]]; then
    export PATH="$TC:$PATH"
fi
if [[ ":$PATH:" != *":$GAS:"* ]]; then
    export PATH="$GAS:$PATH"
fi
if [[ ":$PATH:" != *":$BT:"* ]]; then
    export PATH="$BT:$PATH"
fi

export PLATFORM_VERSION=12
export TARGET_SOC=s5e8825
export ANDROID_MAJOR_VERSION=s

export ARCH="arm64"
export CC="$TC/clang"
export CROSS_COMPILE="$TC/aarch64-linux-gnu-"
export CLANG_TRIPLE="$TC/aarch64-linux-gnu-"
export LLVM=1
export LLVM_IAS=1
export KBUILD_BUILD_USER=Majaahh
export KBUILD_BUILD_HOST=PC

LOG_STEP_IN "- Generating configuration"
make -C "$KERNEL_DIR" -j28 O="$BUILD_DIR" s5e8825_defconfig

if $REGENERATE; then
    LOG "- Copying configuration to arch/arm64/configs/s5e8825_defconfig"
    EVAL "cp -a \"$BUILD_DIR/.config\" \"$KERNEL_DIR/arch/arm64/configs/s5e8825_defconfig\""
    LOG_STEP_OUT
    exit 0
fi

LOG "- Merging $DEVICE fragment"
make -C "$KERNEL_DIR" -j28 O="$BUILD_DIR" a53x.config

if $KSU; then
    LOG "- Merging KernelSU fragment"
    BUILD_KERNEL "ksu.config"
fi

if [[ "$("$KERNEL_DIR/scripts/config" -s --file "$BUILD_DIR/.config" "CONFIG_LOCALVERSION_AUTO")" == "n" ]]; then
    LOG "- Generating local version"
    EVAL "sed -i s/\-UN1CA/\-UN1CA\-$(git -C "$KERNEL_DIR" rev-parse --short HEAD)/g \"$BUILD_DIR/.config\""
fi
LOG_STEP_OUT
LOG "- Building kernel image"
make -C "$KERNEL_DIR" -j28 O="$BUILD_DIR"
