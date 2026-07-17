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
    echo "-d,--device      Specifies device codename"
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
    CMD+="--header_version \"$TARGET_IMAGE_HEADER_VERSION\" "
    CMD+="--os_version \"$TARGET_OS_VERSION.0.0\" "
    CMD+="--os_patch_level \"$(date +%Y-%m)\" "

    if [[ "$IMAGE" == "boot" ]]; then
        SIZE="$TARGET_BOOT_IMAGE_SIZE"
        if [[ -n "$TARGET_BOOT_IMAGE_CMDLINE" ]]; then
            CMD+="--cmdline \"$TARGET_BOOT_IMAGE_CMDLINE\" "
        fi
        CMD+="--kernel \"$KERNEL\" "
        CMD+="--output \"$OUTPUT_DIR/$IMAGE.img\" "
        CMD+="--ramdisk \"$TMP_DIR/ramdisk.lz4\""
    elif [[ "$IMAGE" == "vendor_boot" ]]; then
        SIZE="$TARGET_VENDOR_BOOT_IMAGE_SIZE"
        # TODO: Commonize "bootconfig" under proper conditions
        if [[ -n "$TARGET_VENDOR_BOOT_IMAGE_CMDLINE" ]]; then
            CMD+="--cmdline \"$TARGET_VENDOR_BOOT_IMAGE_CMDLINE\" "
        fi
        CMD+="--dtb \"$TMP_DIR/dtb.img\" "
        CMD+="--vendor_boot \"$OUTPUT_DIR/$IMAGE.img\" "
        if [[ -f "$TMP_DIR/bootconfig" ]]; then
            CMD+="--vendor_bootconfig \"$TMP_DIR/bootconfig\" "
        fi
        CMD+="--vendor_ramdisk \"$TMP_DIR/ramdisk_platform.lz4\" "
        if [[ "$TARGET_IMAGE_HEADER_VERSION" == "4" ]]; then
            CMD+="--ramdisk_name \"dlkm\" "
            CMD+="--vendor_ramdisk_fragment \"$TMP_DIR/ramdisk_dlkm.lz4\""
        fi
    fi

    if [[ "$IMAGE" == "vendor_boot" ]]; then
        LOG_STEP_IN "- Generating modules"
        "$SRC_DIR/scripts/gen_modules.sh" "$OUT/modules/$TARGET_CODENAME" || return 1
        LOG_STEP_OUT

        if [[ ! -f "$TMP_DIR/dtb.img" ]]; then
            BUILD_DT_IMAGE "dtb" "$TMP_DIR" || return 1
        fi

        EVAL "mkbootfs \"$OUT/modules\" | lz4 -9cl > \"$TMP_DIR/ramdisk_dlkm.lz4\"" || return 1

        if [[ -d "$TMP_DIR/ramdisk_platform" ]]; then
            EVAL "rm -rf \"$TMP_DIR/ramdisk_platform\""
        fi
        EVAL "mkdir -p \"$TMP_DIR/ramdisk_platform\""

        local FSTAB_DIR
        if [[ -n "$BOARD_DIR" ]]; then
            FSTAB_DIR="$BOARD_DIR"
        else
            FSTAB_DIR="$TARGET_DIR"
        fi

        local FSTAB
        FSTAB="$(find "$FSTAB_DIR" -maxdepth 1 -type f -name "fstab.*")"

        if [[ ! -f "$FSTAB" ]] || [[ -z "$FSTAB" ]]; then
            LOGE "fstab was not found"
            exit 1
        fi

        LOG "- Copying ${FSTAB//$SRC_DIR\//} to ramdisk_platform/$(basename "$FSTAB")"
        EVAL "cp -a \"$FSTAB\" \"$TMP_DIR/ramdisk_platform/$(basename "$FSTAB")\"" || return 1

        for i in "BOARD_DIR" "TARGET_DIR"; do
            if [[ -d "${!i}/prebuilts/firmware" ]]; then
                if [[ ! -d "$TMP_DIR/ramdisk_platform/vendor/firmware" ]]; then
                    EVAL "mkdir -p \"$TMP_DIR/ramdisk_platform/vendor/firmware\""
                fi
                while IFS= read -r f; do
                    LOG "- Copying ${f//$SRC_DIR\//} to ramdisk_platform/vendor/firmware"
                    EVAL "cp -a \"$f\" \"$TMP_DIR/ramdisk_platform/vendor/firmware/$(basename "$f")\"" || return 1
                done < <(find "${!i}/prebuilts/firmware" -type f)
            fi
        done

        EVAL "mkbootfs \"$TMP_DIR/ramdisk_platform\" | lz4 -9cl > \"$TMP_DIR/ramdisk_platform.lz4\"" || return 1

        if COMPARE_KERNEL_VERSION "higher" "5.10"; then
            EVAL "echo \"buildtime_bootconfig=enable\" > \"$TMP_DIR/bootconfig\""
        fi
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
    local DTS_DIR="$BUILD_DIR/arch/arm64/boot/dts"

    if [[ "$IMAGE" == "dtb" ]]; then
        if [[ -f "$TARGET_DIR/$BOARD_CODENAME.cfg" ]]; then
            CONFIGURATION="$TARGET_DIR/$BOARD_CODENAME.cfg"
        elif [[ -f "$BOARD_DIR/$BOARD_CODENAME.cfg" ]]; then
            CONFIGURATION="$BOARD_DIR/$BOARD_CODENAME.cfg"
        else
            LOGE "DTB configuration was not found"
            return 1
        fi
        DTS_DIR="$(dirname "$(find "$DTS_DIR" -type f -name "$TARGET_DTB_NAME.dtb")")"
    elif [[ "$IMAGE" == "dtbo" ]]; then
        CONFIGURATION="$TARGET_DIR/$DEVICE.cfg"
        DTS_DIR="$(dirname "$(find "$DTS_DIR" -type f -name "$TARGET_CODENAME*.dtbo" -print -quit)")"
    fi

    if [[ ! -f "$CONFIGURATION" ]]; then
        LOGE "${CONFIGURATION//$SRC_DIR\//} was not found"
        return 1
    fi

    CMD+="mkdtboimg cfg_create "
    CMD+="\"$OUTPUT_DIR/$IMAGE.img\" "
    CMD+="\"$CONFIGURATION\" "
    CMD+="-d \"$DTS_DIR\""

    if [[ -z "$DTS_DIR" ]] || [[ ! -d "$DTS_DIR" ]]; then
        LOGE "DTS directory was not found"
        return 1
    fi

    if [[ ! -d "$OUTPUT_DIR" ]]; then
        EVAL "mkdir -p \"$OUTPUT_DIR\"" || return 1
    fi

    if [[ -f "$OUTPUT_DIR/$IMAGE.img" ]]; then
        EVAL "rm -f \"$OUTPUT_DIR/$IMAGE.img\"" || return 1
    fi

    LOG_STEP_IN "- Creating $IMAGE image"
    EVAL "$CMD" || return 1

    if ! $SKIP_AVB && [[ "$IMAGE" == "dtbo" ]]; then
        SIGN_IMAGE_WITH_AVB "$OUTPUT_DIR/$IMAGE.img" "$TARGET_DTBO_IMAGE_SIZE" || return 1
    fi
    LOG_STEP_OUT
}

BUILD_RAMDISK_BINARY()
{
    _CHECK_NON_EMPTY_PARAM "OUTPUT_DIR" "$1" || return 1

    local OUTPUT_DIR="$1"
    # TODO: Check if this is common and if it's common then how common it is
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

    local INIT
    if [[ -n "$BOARD_DIR" ]]; then
        INIT="$BOARD_DIR"
    else
        INIT="$TARGET_DIR"
    fi
    INIT+="/prebuilts/ramdisk/init"

    if [[ ! -f "$INIT" ]]; then
        LOGE "init was not found"
        exit 1
    fi

    LOG "- Copying ${INIT//$SRC_DIR\//} to ramdisk_build/init"
    EVAL "cp -a \"$INIT\" \"$TMP_DIR/ramdisk_build/init\"" || return 1

    LOG "- Creating ramdisk binary"
    EVAL "mkbootfs \"$TMP_DIR/ramdisk_build\" | lz4 -9cl > \"$OUTPUT_DIR/ramdisk.lz4\"" || return 1

    EVAL "rm -rf \"$TMP_DIR/ramdisk_build\""
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
        EVAL "$CMD" || return 1
    fi
}

if [[ "$#" -lt "2" ]]; then
    _PRINT_USAGE
    exit 1
fi

BINARY=""
IMAGE=""
OUTPUT_DIR="$2"
SKIP_AVB=false
SKIP_LZ4=false
DEVICE="$TARGET_CODENAME"
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
