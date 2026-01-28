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

TAR_NAME="UN1CA_Kernel-$(date +%Y%m%d-%H%M)-a53x.tar"
FLASH=""
KSU=""
REGENERATE=""
UPLOAD=""
DEVICE=""
MAKE_ARGS="-C\" \"$KERNEL_DIR\" \"-j$(nproc --all)\" \"CC=clang\" \"O=$BUILD_DIR\" \"KBUILD_BUILD_USER=Majaahh\" \"KBUILD_BUILD_HOST=PC"
# ]

while [[ "$1" == "-"* ]]; do
    if [[ "$1" == "-f" ]] || [[ "$1" == "--flash" ]]; then
        FLASH="true"
    elif [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        _PRINT_USAGE
        exit 0
    elif [[ "$1" == "-k" ]] || [[ "$1" == "--ksu" ]]; then
        TAR_NAME="UN1CA_Kernel-$(date +%Y%m%d-%H%M)-KernelSU-a53x.tar"
        KSU="true"
    elif [[ "$1" == "-r" ]] || [[ "$1" == "--regenerate" ]]; then
        REGENERATE="true"
    elif [[ "$1" == "-u" ]] || [[ "$1" == "--upload" ]]; then
        UPLOAD="true"
    else
        LOGE "Unknown option: $1"
        _PRINT_USAGE
        exit 1
    fi

    shift
done

DEVICE="$1"

if [[ "$#" -eq "0" ]] && [[ "$REGENERATE" != "true" ]]; then
    _PRINT_USAGE
    exit 1
fi

if [[ -z "$DEVICE" ]] && [[ "$REGENERATE" != "true" ]]; then
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

if [[ ! -f "$KERNEL_DIR/arch/arm64/configs/$DEVICE.config" ]]; then
    LOGE "Configuration fragment for $DEVICE was not found"
    exit 1
fi

if [[ ! -d "$TOOLCHAIN_DIR" ]]; then
    GET_AOSP_CLANG
else
    if [[ ! -f "$TOOLCHAIN_DIR/bin/clang" ]]; then
        EVAL "rm -rf \"$TOOLCHAIN_DIR\"" || exit 1
        GET_AOSP_CLANG
    fi
fi

LOG_STEP_IN true "Building Kernel"
LOG_STEP_IN "- Generating configuration"
EVAL "make \"$MAKE_ARGS\" \"s5e8825_defconfig\" >/dev/null"

if [[ "$REGENERATE" == "true" ]]; then
    LOG "- Copying configuration to arch/arm64/configs/s5e8825_defconfig"
    EVAL "cp -a \"$BUILD_DIR/.config\" \"$KERNEL_DIR/arch/arm64/configs/s5e8825_defconfig\""
    LOG_STEP_OUT
    exit 0
fi

LOG "- Merging $DEVICE fragment"
EVAL "make \"$MAKE_ARGS\" \"$DEVICE.config\" >/dev/null"

if [[ "$KSU" == "true" ]]; then
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

LOG_STEP_IN true "Building Images"
if [[ -d "$IMAGES_DIR" ]]; then
   EVAL "rm -rf \"$IMAGES_DIR\""
fi
EVAL "mkdir -p \"$IMAGES_DIR\""

for i in "boot" "dtbo" "vendor_boot"; do
    "$SRC_DIR/scripts/build_image.sh" "$i" "$DEVICE" "$IMAGES_DIR"
done
LOG_STEP_OUT

LOG_STEP_IN true "Building TAR archive"

(
cd "$IMAGES_DIR" || exit 1

LOG "- Creating TAR Archive"
EVAL "tar -cf \"$OUT/$TAR_NAME\" *\"img.lz4\""
EVAL "rm -f *\".img.lz4\""
)
LOG_STEP_OUT

if [[ "$FLASH" == "true" ]] || [[ "$UPLOAD" == "true" ]]; then
    LOG_STEP_IN true "Running post-build scripts"
fi

if [[ "$FLASH" == "true" ]]; then
    LOG "- Flashing ${OUT//$SRC_DIR\//}/$TAR_NAME"
    "$SRC_DIR/scripts/flash.sh" -a "$OUT/$TAR_NAME"
fi

if [[ "$UPLOAD" == "true" ]]; then
    (
    cd "$KERNEL_DIR"

    UPLOAD "$OUT/$TAR_NAME"
    ) || exit 1
fi

LOG_STEP_OUT
