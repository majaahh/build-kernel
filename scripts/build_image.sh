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
    echo "Usage: build_image.sh <binary/image> <output_dir> [arguments]"
    echo "Images: boot, dtb, dtbo, vendor_boot"
    echo "Binaries: ramdisk"
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
    local MKBOOTIMG="$SRC_DIR/external/mkbootimg/mkbootimg.py"
    local CMD
    local KERNEL="$BUILD_DIR/arch/arm64/boot/Image"
    local RAMDISK="ramdisk"

    if ! $SKIP_LZ4; then
        RAMDISK="ramdisk.lz4"
    fi

    LOG_STEP_IN "- Starting $IMAGE image build"

    if [[ "$IMAGE" == "boot" ]]; then
        if [[ ! -d "$TMP_DIR" ]]; then
            EVAL "mkdir -p \"$TMP_DIR\""
        fi

        LOG_STEP_IN "- Building ramdisk binary"
        BUILD_RAMDISK_BINARY "$TMP_DIR" || return 1
        LOG_STEP_OUT
    fi

    if [[ ! -f "$MKBOOTIMG" ]]; then
        LOG "- Fetching submodules"
        EVAL "git submodule update --init -f --checkout"
        if [[ ! -f "$MKBOOTIMG" ]]; then
            LOGE "${MKBOOTIMG//$SRC_DIR\//} was not found"
            return 1
        fi
    fi

    CMD+="$MKBOOTIMG "
    CMD+="--header_version 4 "
    CMD+="--os_version 16.0.0 "
    CMD+="--os_patch_level \"$(date +%Y-%m)\" "

    if [[ "$IMAGE" == "boot" ]]; then
        SIZE="67108864"
        CMD+="--kernel \"$KERNEL\" "
        CMD+="--output \"$OUTPUT_DIR/$IMAGE.img\" "
        CMD+="--ramdisk \"$TMP_DIR/$RAMDISK\""
    elif [[ "$IMAGE" == "vendor_boot" ]]; then
        SIZE="33554432"
        CMD+="--vendor_boot \"$OUTPUT_DIR/$IMAGE.img\" "
        CMD+="--vendor_bootconfig \"$TMP_DIR/bootconfig\" "
        CMD+="--dtb \"$TMP_DIR/dtb.img\" "
        CMD+="--vendor_ramdisk \"$TMP_DIR/ramdisk_platform.lz4\" "
        CMD+="--ramdisk_type \"dlkm\" "
        CMD+="--ramdisk_name \"dlkm\" "
        CMD+="--vendor_ramdisk_fragment \"$TMP_DIR/ramdisk_dlkm.lz4\""
    fi

    if [[ "$IMAGE" == "vendor_boot" ]]; then
        LOG_STEP_IN "- Generating modules"
        "$SRC_DIR/scripts/gen_modules.sh" "$OUT/modules" || return 1
        LOG_STEP_OUT

        if [[ ! -f "$TMP_DIR/dtb.img" ]]; then
            BUILD_DT_IMAGE "dtb" "$TMP_DIR" || return 1
        fi

        EVAL "cd \"$OUT/modules\" && find . | cpio --quiet -o -H newc -R root:root | lz4 -9cl > \"$TMP_DIR/ramdisk_dlkm.lz4\"" || return 1

        if [[ -d "$TMP_DIR/ramdisk_platform" ]]; then
            EVAL "rm -rf \"$TMP_DIR/ramdisk_platform\""
        fi
        EVAL "mkdir -p \"$TMP_DIR/ramdisk_platform\""

        LOG "- Copying prebuilts/vboot_platform/fstab.s5e8825 to ramdisk_platform/fstab.s5e8825"
        EVAL "cp -rf \"$SRC_DIR/prebuilts/vboot_platform/fstab.s5e8825\" \"$TMP_DIR/ramdisk_platform\""

        EVAL "mkdir -p \"$TMP_DIR/ramdisk_platform/vendor/firmware\""
        LOG "- Copying touch firmware for $DEVICE from prebuilts/vboot_platform/vendor/firmware to ramdisk_platform/vendor/firmware"
        EVAL "find \"$SRC_DIR/prebuilts/vboot_platform/vendor/firmware\" -type f -name \"*$DEVICE*.bin\" -exec \
            cp -a {} \"$TMP_DIR/ramdisk_platform/vendor/firmware\" \;"

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

    LOG_STEP_IN "- Creating $IMAGE image"
    EVAL "$CMD" || return 1

    if [[ "$IMAGE" == "vendor_boot" ]]; then
        EVAL "rm -f \"$TMP_DIR/dtb.img\""
    fi

    if ! $SKIP_AVB; then
        SIGN_IMAGE_WITH_AVB "$OUTPUT_DIR/$IMAGE.img" "$SIZE" || return 1
    fi

    if [[ -d "$TMP_DIR" ]]; then
        EVAL "rm -rf \"$TMP_DIR\""
    fi
    LOG_STEP_OUT; LOG_STEP_OUT
}

BUILD_DT_IMAGE()
{
    _CHECK_NON_EMPTY_PARAM "IMAGE" "$1" || return 1
    _CHECK_NON_EMPTY_PARAM "OUTPUT_DIR" "$2" || return 1

    local IMAGE="$1"
    local OUTPUT_DIR="$2"
    local CONFIGURATION
    local CMD
    local DTS_DIR

    if [[ "$IMAGE" == "dtb" ]]; then
        CONFIGURATION="s5e8825"
        DTS_DIR="$BUILD_DIR/arch/arm64/boot/dts/exynos"
    elif [[ "$IMAGE" == "dtbo" ]]; then
        local SIZE

        CONFIGURATION="$DEVICE"
        DTS_DIR="$(find "$BUILD_DIR/arch/arm64/boot/dts" -type d -name "$(echo "$DEVICE" | cut -d"_" -f1)" | tail -n 1)"
        DTS_DIR="$BUILD_DIR/arch/arm64/boot/dts/samsung/a53x"
        SIZE="8388608"
    fi

    if [[ ! -f "$SRC_DIR/configs/$CONFIGURATION.cfg" ]] && [[ "$IMAGE" == "dtbo" ]]; then
        LOGE "$CONFIGURATION.cfg was not found"
        return 1
    fi

    LOG_STEP_IN "- Starting $IMAGE image build"

    CMD+="mkdtboimg cfg_create "
    CMD+="\"$OUTPUT_DIR/$IMAGE.img\" "
    CMD+="\"$SRC_DIR/configs/$CONFIGURATION.cfg\" "
    CMD+="-d \"$DTS_DIR\""

    if [[ -z "$DTS_DIR" ]] || [[ ! -d "$DTS_DIR" ]]; then
        LOGE "Dts directory was not found"
        return 1
    fi

    LOG_STEP_IN "- Creating $IMAGE image"
    if [[ ! -d "$OUTPUT_DIR" ]]; then
        EVAL "mkdir -p \"$OUTPUT_DIR\"" || return 1
    fi

    if [[ -f "$OUTPUT_DIR/$IMAGE.img" ]]; then
        EVAL "rm -f \"$OUTPUT_DIR/$IMAGE.img\"" || return 1
    fi

    EVAL "$CMD" || return 1

    if ! $SKIP_AVB && [[ "$IMAGE" == "dtbo" ]]; then
        SIGN_IMAGE_WITH_AVB "$OUTPUT_DIR/$IMAGE.img" "$SIZE" || return 1
    fi
    LOG_STEP_OUT; LOG_STEP_OUT
}

BUILD_RAMDISK_BINARY()
{
    _CHECK_NON_EMPTY_PARAM "OUTPUT_DIR" "$1" || return 1

    local OUTPUT_DIR="$1"
    local DIRS=(
        "debug_ramdisk" "first_stage_ramdisk/debug_ramdisk" "first_stage_ramdisk/dev" "first_stage_ramdisk/metadata" 
        "first_stage_ramdisk/mnt" "first_stage_ramdisk/proc" "first_stage_ramdisk/second_stage_resources"
        "first_stage_ramdisk/sys" "dev" "metadata" "mnt" "proc" "second_stage_resources" "sys" "system/etc/ramdisk"
      )

    if [[ -f "$OUTPUT_DIR/ramdisk" ]] || [[ -f "$OUTPUT_DIR/ramdisk.lz4" ]]; then
        EVAL "find \"$OUTPUT_DIR\" -maxdepth 1 -name \"ramdisk*lz4\" -type f | rm -f" || return 1
    fi

    if [[ -d "$TMP_DIR/ramdisk_build" ]]; then
        EVAL "rm -rf \"$TMP_DIR/ramdisk_build\""
    fi
    EVAL "mkdir -p \"$TMP_DIR/ramdisk_build\"" || return 1

    if [[ ! -d "$OUTPUT_DIR" ]]; then
        EVAL "mkdir -p \"$OUTPUT_DIR\""
    fi

    for i in "${DIRS[@]}"; do
        EVAL "mkdir -p \"$TMP_DIR/ramdisk_build/$i\"" || return 1
    done

    LOG "- Adding init from prebuilts/ramdisk/init"
    EVAL "cp -a \"$SRC_DIR/prebuilts/ramdisk/init\" \"$TMP_DIR/ramdisk_build/init\""

    LOG "- Creating ramdisk binary"
    EVAL "cd \"$TMP_DIR/ramdisk_build\" && find . | cpio --quiet -o -H newc -R root:root > \"ramdisk\"" || return 1
    EVAL "mv \"$TMP_DIR/ramdisk_build/ramdisk\" \"$OUTPUT_DIR/ramdisk\""

    EVAL "rm -rf \"$TMP_DIR/ramdisk_build\""

    if ! $SKIP_LZ4; then
        LOG "- Compressing ramdisk binary with lz4"
        EVAL "lz4 -9cl \"$OUTPUT_DIR/ramdisk\" > \"$OUTPUT_DIR/ramdisk.lz4\""
        EVAL "rm -f \"$OUTPUT_DIR/ramdisk\""
    fi
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

BINARY=""
IMAGE=""
OUTPUT_DIR="$2"
DEVICE=""
SKIP_AVB=false
SKIP_LZ4=false
# ]

if [[ "$1" != "boot" ]] && [[ "$1" != "dtb" ]] && \
    [[ "$1" != "dtbo" ]] && [[ "$1" != "ramdisk" ]] && \
    [[ "$1" != "vendor_boot" ]]; then
    LOGE "$1 is not a valid binary or image"
    _PRINT_USAGE
    exit 1
fi

if [[ "$1" == "ramdisk" ]]; then
    BINARY="$1"
else
    IMAGE="$1"
fi

shift 2
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
        SKIP_AVB=true
    elif [[ "$1" == "--skip-lz4" ]]; then
        SKIP_LZ4=true
    fi

    shift
done

if [[ -z "$DEVICE" ]]; then
    if [[ "$IMAGE" == "dtbo" ]] || [[ "$IMAGE" == "vendor_boot" ]]; then
        LOGE "Device must be set for $IMAGE build"
        _PRINT_USAGE
        exit 1
    fi
fi

if [[ "$BINARY" == "ramdisk" ]]; then
    if [[ ! -d "$OUTPUT_DIR" ]]; then
        EVAL "mkdir -p \"$OUTPUT_DIR\"" || exit 1
    fi
    BUILD_RAMDISK_BINARY "$OUTPUT_DIR" || exit 1
    exit 0
fi

if [[ "$IMAGE" == "dtb"* ]]; then
    BUILD_DT_IMAGE "$IMAGE" "$OUTPUT_DIR" || exit 1
elif [[ "$IMAGE" == *"boot" ]]; then
    BUILD_BOOT_IMAGE "$IMAGE" "$OUTPUT_DIR" || exit 1
fi

if ! $SKIP_LZ4 && [[ -z "$BINARY" ]]; then
    LOG_STEP_IN

    if [[ -f "$OUTPUT_DIR/$IMAGE.img.lz4" ]]; then
        EVAL "rm -f \"$OUTPUT_DIR/$IMAGE.img.lz4\""
    fi
    LOG "- Compressing $IMAGE image with lz4"
    EVAL "lz4 -B6 -c -12 --content-size \"$OUTPUT_DIR/$IMAGE.img\" > \"$OUTPUT_DIR/$IMAGE.img.lz4\""
    EVAL "rm -f \"$OUTPUT_DIR/$IMAGE.img\""
    LOG_STEP_OUT
fi
