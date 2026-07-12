#!/bin/bash
#
# SPDX-FileCopyrightText: Majaahh
# SPDX-License-Identifier: Apache-2.0
#

# [
_PRINT_USAGE()
{
    echo "Usage: build.sh [arguments]"
    echo "Arguments:"
    echo "-f,--flash       Flashes latest build"
    echo "-h,--help        Prints this help menu"
    echo "-k,--ksu         Makes a KernelSU Build"
    echo "-r,--regenerate  Regenerates the defconfig"
    echo "--skip-dtbo      Skips DTBO build"
    echo "-u,--upload      Creates a release on GitHub"
}

# shellcheck disable=SC1091
source "$SRC_DIR/scripts/utils/common_utils.sh" || exit 1
# shellcheck disable=SC1091
source "$SRC_DIR/scripts/utils/log_utils.sh" || exit 1

FLASH=false
UPLOAD=false
KSU=false
POST=false
SKIP_DTBO=false
BUILD_KERNEL_ARGS=""
DATE="$(date +%Y%m%d-%H%M)"
# ]

while [[ "$1" ]]; do
    if [[ "$1" == "-f" ]] || [[ "$1" == "--flash" ]]; then
        FLASH=true
        POST=true
    elif [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        _PRINT_USAGE
        exit 0
    elif [[ "$1" == "-k" ]] || [[ "$1" == "--ksu" ]]; then
        KSU=true
    elif [[ "$1" == "-r" ]] || [[ "$1" == "--regenerate" ]]; then
        BUILD_KERNEL_ARGS+="-r "
    elif [[ "$1" == "--skip-dtbo" ]]; then
        SKIP_DTBO=true
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

SUFFIX="$TARGET_CODENAME"
if $KSU; then
    SUFFIX="KernelSU-$TARGET_CODENAME"
fi

KERNEL_TAR_NAME="UN1CA_Kernel-$DATE-$SUFFIX"
DTBO_TAR_NAME="UN1CA_DTBO-$DATE-$TARGET_CODENAME"

LOG_STEP_IN true "Building kernel"
# shellcheck disable=SC2086
"$SRC_DIR/scripts/build_kernel.sh" $BUILD_KERNEL_ARGS || exit 1
LOG_STEP_OUT

if [[ "$("$KERNEL_DIR/scripts/config" -s --file "$BUILD_DIR/.config" "CONFIG_LOCALVERSION_AUTO")" == "y" ]]; then
    KERNEL_TAR_NAME="${KERNEL_TAR_NAME#UN1CA_}"
    DTBO_TAR_NAME="${DTBO_TAR_NAME#UN1CA_}"
fi

if [[ "$BUILD_KERNEL_ARGS" == *"-r"* ]]; then
    exit 0
fi

LOG_STEP_IN true "Building TAR Archives"
if [[ -d "$IMAGES_DIR/kernel" ]]; then
   EVAL "rm -rf \"$IMAGES_DIR/kernel\""
fi
EVAL "mkdir -p \"$IMAGES_DIR/kernel\""

IMAGES=("boot")

if [[ -n "$TARGET_VENDOR_BOOT_IMAGE_SIZE" ]]; then
    IMAGES+=("vendor_boot")
fi

for i in "${IMAGES[@]}"; do
    "$SRC_DIR/scripts/build_image.sh" "$i" "$IMAGES_DIR/kernel" || exit 1
done

LOG "- Creating Kernel TAR Archive"
CREATE_TAR_ARCHIVE "$OUT/$KERNEL_TAR_NAME.tar" "$IMAGES_DIR/kernel/boot.img.lz4" "$IMAGES_DIR/kernel/vendor_boot.img.lz4" || exit 1

if ! $SKIP_DTBO; then
    while IFS= read -r f; do
        DEVICE="$(basename "$f" ".cfg")"

        if [[ -d "$IMAGES_DIR/dtbo" ]]; then
            EVAL "rm -rf \"$IMAGES_DIR/dtbo\""
        fi
        EVAL "mkdir -p \"$IMAGES_DIR/dtbo\""

        "$SRC_DIR/scripts/build_image.sh" "dtbo" "$IMAGES_DIR/dtbo" -d "$DEVICE" || exit 1

        LOG "- Creating DTBO TAR Archive for $DEVICE"
        CREATE_TAR_ARCHIVE "$OUT/${DTBO_TAR_NAME/$TARGET_CODENAME/$DEVICE}.tar" "$IMAGES_DIR/dtbo/dtbo.img.lz4" || exit 1
    done < <(find "$TARGET_DIR" -maxdepth 1 -type f -name "$TARGET_CODENAME*.cfg")
    LOG_STEP_OUT
fi

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
    if ! $SKIP_DTBO; then
        while IFS= read -r f; do
            UPLOAD "${f//$SRC_DIR\//}" || exit 1
        done < <(find "$OUT" -maxdepth 1 -type f -name "*DTBO-$DATE-$TARGET_CODENAME*.tar")
    fi
    ) || exit 1
fi

LOG_STEP_OUT
