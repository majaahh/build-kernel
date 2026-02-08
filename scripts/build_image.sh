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
    echo "Usage: build_image.sh <image> <output_dir> [arguments]"
    echo "Images: boot, dtb, dtbo, vendor_boot"
    echo "Arguments:"
    echo "-d,--device      Specify device codename (required for dtbo)"
    echo "-h,--help        Prints this help menu"
    echo "--skip-avb       Skips AVB Sign"
    echo "--skip-lz4       Skips LZ4 Compression"
}

BUILD_BOOT_IMAGE()
{
    _CHECK_NON_EMPTY_PARAM "IMAGE" "$1" || return 1
    _CHECK_NON_EMPTY_PARAM "OUTPUT_DIR" "$2" || return 1

    local IMAGE="$1"
    local OUTPUT_DIR="$2"
    local SIZE
    local MKBOOTIMG="$SRC_DIR/external//mkbootimg/mkbootimg.py"
    local MKBOOTIMG_ARGUMENTS
    local KERNEL="$BUILD_DIR/arch/arm64/boot/Image"
    local RAMDISK="$SRC_DIR/prebuilts/boot/ramdisk"

    if [[ ! -f "$MKBOOTIMG" ]]; then
        LOG "- Fetching submodules"
        EVAL "git submodule update --init -f --checkout"
        if [[ ! -f "$MKBOOTIMG" ]]; then
            LOGE "${MKBOOTIMG//$SRC_DIR\//} was not found"
            return 1
        fi
    fi

    MKBOOTIMG_ARGUMENTS+="--header_version 4 "
    MKBOOTIMG_ARGUMENTS+="--os_version 16.0.0 "
    MKBOOTIMG_ARGUMENTS+="--os_patch_level \"$(date +%Y-%m)\" "

    if [[ "$IMAGE" == "boot" ]]; then
        SIZE="67108864"
        MKBOOTIMG_ARGUMENTS+="--kernel \"$KERNEL\" "
        MKBOOTIMG_ARGUMENTS+="--output \"$OUTPUT_DIR/$IMAGE.img\" "
        MKBOOTIMG_ARGUMENTS+="--ramdisk \"$RAMDISK\""
    elif [[ "$IMAGE" == "vendor_boot" ]]; then
        SIZE="33554432"
        MKBOOTIMG_ARGUMENTS+="--vendor_boot \"$OUTPUT_DIR/$IMAGE.img\" "
        MKBOOTIMG_ARGUMENTS+="--vendor_bootconfig \"$TMP_DIR/bootconfig\" "
        MKBOOTIMG_ARGUMENTS+="--dtb \"$TMP_DIR/dtb.img\" "
        MKBOOTIMG_ARGUMENTS+="--vendor_ramdisk \"$TMP_DIR/ramdisk_platform.lz4\" "
        MKBOOTIMG_ARGUMENTS+="--ramdisk_type \"dlkm\" "
        MKBOOTIMG_ARGUMENTS+="--ramdisk_name \"dlkm\" "
        MKBOOTIMG_ARGUMENTS+="--vendor_ramdisk_fragment \"$TMP_DIR/ramdisk_dlkm.lz4\""
    fi

    LOG_STEP_IN "- Building $IMAGE image"
    if [[ "$IMAGE" == "vendor_boot" ]]; then
        LOG_STEP_IN "- Generating modules"
        "$SRC_DIR/scripts/gen_modules.sh" "$OUT/modules"
        LOG_STEP_OUT

        if [[ ! -f "$TMP_DIR/dtb.img" ]]; then
            BUILD_DT_IMAGE "dtb" "$TMP_DIR"
        fi

        EVAL "cd \"$OUT/modules\" && find . | cpio --quiet -o -H newc -R root:root | lz4 -9cl > \"$TMP_DIR/ramdisk_dlkm.lz4\"" || return 1

        if [[ -d "$TMP_DIR/ramdisk_platform" ]]; then
            EVAL "rm -rf \"$TMP_DIR/ramdisk_platform\""
        fi
        EVAL "mkdir -p \"$TMP_DIR/ramdisk_platform\""

        EVAL "cp -rf \"$SRC_DIR/prebuilts/vboot_platform/\"* \"$TMP_DIR/ramdisk_platform\""
        EVAL "mkdir -p \"$TMP_DIR/ramdisk_platform/first_stage_ramdisk\""
        EVAL "cp -f \"$TMP_DIR/ramdisk_platform/fstab.s5e8825\" \"$TMP_DIR/ramdisk_platform/first_stage_ramdisk/fstab.s5e8825\""

        EVAL "cd \"$TMP_DIR/ramdisk_platform\" && find . | cpio --quiet -o -H newc -R root:root | lz4 -9cl > \"$TMP_DIR/ramdisk_platform.lz4\"" || return 1

        if [[ -f "$TMP_DIR/bootconfig" ]]; then
            EVAL "rm -f \"$TMP_DIR/bootconfig\""
        fi

        EVAL "echo \"buildtime_bootconfig=enable\" > \"$TMP_DIR/bootconfig\""
    fi

    if [[ ! -d "$OUTPUT_DIR" ]]; then
        EVAL "mkdir -p \"$OUTPUT_DIR\"" || return 1
    fi

    if [[ -f "$OUTPUT_DIR/$IMAGE.img" ]]; then
        EVAL "rm -f \"$OUTPUT_DIR/$IMAGE.img\""
    fi

    EVAL "\"$MKBOOTIMG\" $MKBOOTIMG_ARGUMENTS"

    if [[ "$IMAGE" == "vendor_boot" ]]; then
        EVAL "rm -f \"$TMP_DIR/dtb.img\""
    fi

    if [[ "$SKIP_AVB" != "true" ]]; then
        SIGN_IMAGE_WITH_AVB "$OUTPUT_DIR/$IMAGE.img" "$SIZE"
    fi

    if [[ -d "$TMP_DIR" ]]; then
        EVAL "rm -rf \"$TMP_DIR\""
    fi
    LOG_STEP_OUT
}

BUILD_DT_IMAGE()
{
    _CHECK_NON_EMPTY_PARAM "IMAGE" "$1" || return 1
    _CHECK_NON_EMPTY_PARAM "OUTPUT_DIR" "$2" || return 1

    local IMAGE="$1"
    local OUTPUT_DIR="$2"
    local CONFIGURATION
    local DTS_DIR="$BUILD_DIR/arch/arm64/boot/dts/exynos"

    if [[ -z "$DEVICE" ]] && [[ "$IMAGE" == "dtbo" ]]; then
        LOGE "Device must be set for dtbo build"
        _PRINT_USAGE
        return 1
    fi

    if [[ "$IMAGE" == "dtb" ]]; then
        CONFIGURATION="s5e8825"
    elif [[ "$IMAGE" == "dtbo" ]]; then
        local SIZE

        CONFIGURATION="$DEVICE"
        DTS_DIR+="/samsung/$DEVICE"
        SIZE="8388608"
    fi

    if [[ ! -f "$SRC_DIR/configs/$CONFIGURATION.cfg" ]] && [[ "$IMAGE" == "dtbo" ]]; then
        LOGE "$CONFIGURATION.cfg was not found"
        return 1
    fi

    if [[ ! -d "$DTS_DIR" ]]; then
        LOGE "${DTS_DIR//$SRC_DIR\//} was not found"
        return 1
    fi

    LOG_STEP_IN "- Building $IMAGE image"
    if [[ ! -d "$OUTPUT_DIR" ]]; then
        EVAL "mkdir -p \"$OUTPUT_DIR\"" || return 1
    fi

    if [[ -f "$OUTPUT_DIR/$IMAGE.img" ]]; then
        EVAL "rm -f \"$OUTPUT_DIR/$IMAGE.img\"" || return 1
    fi

    EVAL "mkdtboimg cfg_create \"$OUTPUT_DIR/$IMAGE.img\" \"$SRC_DIR/configs/$CONFIGURATION.cfg\" -d \"$DTS_DIR\"" || return 1

    if [[ "$SKIP_AVB" != "true" ]] && [[ "$IMAGE" == "dtbo" ]]; then
        SIGN_IMAGE_WITH_AVB "$OUTPUT_DIR/$IMAGE.img" "$SIZE"
    fi
    LOG_STEP_OUT
}

# https://github.com/salvogiangri/UN1CA/blob/3.0.0/scripts/internal/build_flashable_zip.sh#L486-L511
SIGN_IMAGE_WITH_AVB()
{
    _CHECK_NON_EMPTY_PARAM "FILE" "$1" || return 1
    _CHECK_NON_EMPTY_PARAM "PARTITION_SIZE" "$2" || return 1

    local FILE="$1"
    local PARTITION_SIZE="$2"

    if ! avbtool info_image --image "$FILE" &> /dev/null; then
        local PARTITION_NAME
        PARTITION_NAME="$(basename "$FILE")"
        PARTITION_NAME="${PARTITION_NAME//.img/}"

        local CMD
        CMD+="avbtool add_hash_footer "
        CMD+="--image \"$FILE\" "
        CMD+="--partition_size \"$PARTITION_SIZE\" "
        CMD+="--partition_name \"$PARTITION_NAME\" "
        CMD+="--hash_algorithm \"sha256\" "
        CMD+="--algorithm \"SHA256_RSA4096\" "
        CMD+="--key \"$SRC_DIR/security/testkey_rsa4096.pem\""

        LOG "- Signing image with AVB"
        EVAL "$CMD"
    fi
}

if [[ "$#" -lt "2" ]]; then
    _PRINT_USAGE
    exit 1
fi

IMAGE="$1"
OUTPUT_DIR="$2"
DEVICE=""
SKIP_AVB=""
SKIP_LZ4=""

shift 2
# ]

if [[ "$IMAGE" != "boot" ]] && [[ "$IMAGE" != "dtb" ]] && \
    [[ "$IMAGE" != "dtbo" ]] && [[ "$IMAGE" != "vendor_boot" ]]; then
    LOGE "$1 is not a valid image"
    _PRINT_USAGE
    exit 1
fi

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
    elif [[ "$1" == "--skip-avb" ]]; then
        SKIP_AVB="true"
    elif [[ "$1" == "--skip-lz4" ]]; then
        SKIP_LZ4="true"
    fi

    shift
done

if [[ "$IMAGE" == "dtb"* ]]; then
    BUILD_DT_IMAGE "$IMAGE" "$OUTPUT_DIR" || exit 1
fi

if [[ "$IMAGE" == *"boot" ]]; then
    BUILD_BOOT_IMAGE "$IMAGE" "$OUTPUT_DIR" || exit 1
fi

if [[ "$SKIP_LZ4" != "true" ]]; then
    LOG_STEP_IN

    if [[ -f "$OUTPUT_DIR/$IMAGE.img.lz4" ]]; then
        EVAL "rm -f \"$OUTPUT_DIR/$IMAGE.img.lz4\""
    fi
    LOG "- Compressing $IMAGE image with lz4"
    EVAL "lz4 -B6 -c -12 --content-size \"$OUTPUT_DIR/$IMAGE.img\" > \"$OUTPUT_DIR/$IMAGE.img.lz4\""
    EVAL "rm -f \"$OUTPUT_DIR/$IMAGE.img\""
    LOG_STEP_OUT
fi
