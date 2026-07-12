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
    echo "-h,--help        Prints this help menu"
    echo "-k,--ksu         Makes a KernelSU Build"
    echo "-r,--regenerate  Regenerates the defconfig"
}

KSU=false
REGENERATE=false
# ]

while [[ "$1" ]]; do
    if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
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

if [[ ! -d "$KERNEL_DIR" ]]; then
    LOG_STEP_IN "- Setting up kernel source"

    if [[ ! -d "$KERNEL_DIR" ]]; then
        LOG "- Cloning kernel source"
        EVAL "git clone -j\"$(nproc --all)\" \"https://github.com/$TARGET_KERNEL_SOURCE.git\" \"$KERNEL_DIR\""
    fi

    if [[ -f "$KERNEL_DIR/.gitmodules" ]]; then
        LOG "- Fetching submodules"
        EVAL "git -C \"$KERNEL_DIR\" submodule update --init -f --checkout"
    fi

    LOG_STEP_OUT
fi

if [[ "$TARGET_TOOLCHAIN" == "clang"* ]]; then
    if [[ ! -d "$CLANG_DIR" ]]; then
        # shellcheck disable=SC2119
        GET_AOSP_CLANG || exit 1
    else
        GET_LATEST_AOSP_CLANG --compare
    fi
fi

if [[ "$TARGET_TOOLCHAIN" == *"gcc" ]]; then
    if [[ ! -d "$GCC_DIR_32" ]]; then
        LOG "- Cloning 32-bit AOSP GCC"
        EVAL "git clone --depth=1 -j\"$(nproc --all)\" \"https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_arm_arm-linux-androideabi-4.9.git\" \"$GCC_DIR_32\"" || exit 1
    fi

    if [[ ! -d "$GCC_DIR_64" ]]; then
        LOG "- Cloning 64-bit AOSP GCC"
        EVAL "git clone --depth=1 -j\"$(nproc --all)\" \"https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9.git\" \"$GCC_DIR_64\"" || exit 1
    fi
fi

BUILD_KERNEL "$TARGET_KERNEL_DEFCONFIG" || exit 1
LOG_STEP_IN

if $REGENERATE; then
    LOG "- Copying configuration to arch/arm64/configs/$TARGET_KERNEL_DEFCONFIG"
    EVAL "cp -a \"$BUILD_DIR/.config\" \"$KERNEL_DIR/arch/arm64/configs/$TARGET_KERNEL_DEFCONFIG\""
    LOG_STEP_OUT
    exit 0
fi

if [[ -n "$TARGET_KERNEL_DEFCONFIG_FRAGMENTS" ]]; then
    for i in $TARGET_KERNEL_DEFCONFIG_FRAGMENTS; do
        BUILD_KERNEL "$i" -m || exit 1
    done
fi

if $KSU; then
    LOG "- Merging KernelSU fragment"
    BUILD_KERNEL "ksu.config" -q || exit 1
fi

if [[ "$("$KERNEL_DIR/scripts/config" -s --file "$BUILD_DIR/.config" "CONFIG_LOCALVERSION_AUTO")" == "n" ]]; then
    LOG "- Generating local version"
    EVAL "sed -i s/\-UN1CA/\-UN1CA\-$(git -C "$KERNEL_DIR" rev-parse --short HEAD)/g \"$BUILD_DIR/.config\""
fi
LOG_STEP_OUT

BUILD_KERNEL "dtbs" || exit 1
BUILD_KERNEL || exit 1
