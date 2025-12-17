# [
source "$SRC_DIR/build/utils/log_utils.sh" || return 1

CLEANUP()
{
    local POST="$1"

    if [[ -d "$IMAGES_DIR" ]]; then
        LOG "- Deleting images dir"
        rm -rf "$IMAGES_DIR"
    fi
    if [[ "$POST" != "true" ]]; then
        mkdir -p "$IMAGES_DIR"
    fi

    if [[ -d "$MOD_OUTDIR" ]]; then
        LOG "- Deleting modules dir"
        rm -rf "$MOD_OUTDIR"
    fi
    if [[ "$POST" != "true" ]]; then
        mkdir -p "$MOD_OUTDIR"
    fi

    if [[ -d "$TMP_DIR" ]]; then
        LOG "- Deleting temp dir"
        rm -rf "$TMP_DIR"
    fi
    if [[ "$POST" != "true" ]]; then
        mkdir -p "$TMP_DIR"
    fi

    if [[ -d "$PLATFORM_RAMDISK_DIR" ]]; then
        LOG "- Deleting platform ramdisk dir"
        rm -rf "$PLATFORM_RAMDISK_DIR"
    fi
    if [[ "$POST" != "true" ]]; then
        mkdir -p "$PLATFORM_RAMDISK_DIR/first_stage_ramdisk"
    fi

    if [[ -d "$MODULES_DIR/0.0" ]]; then
        LOG "- Deleting modules/0.0 dir"
        rm -rf "$MODULES_DIR/0.0"
    fi
    if [[ "$POST" != "true" ]]; then
        mkdir -p "$MODULES_DIR/0.0"
    fi

    if [[ -f "$OUT_BOOTIMG" ]] && [[ "$POST" != "true" ]]; then
        LOG "- Deleting boot image"
        rm -f "$OUT_BOOTIMG"
    fi

    if [[ -f "$OUT_DTBOIMAGE" ]] && [[ "$POST" != "true" ]]; then
        LOG "- Deleting boot image"
        rm -f "$OUT_DTBOIMAGE"
    fi

    if [[ -f "$OUT_VENDORBOOTIMG" ]] && [[ "$POST" != "true" ]]; then
        LOG "- Deleting vendot boot image"
        rm -f "$OUT_VENDORBOOTIMG"
    fi

    if [[ -f "$OUT_KERNEL" ]]; then
        LOG "- Deleting kernel"
        rm -f "$OUT_KERNEL"
    fi

    if [[ -f "$BUILDS_DIR/$TAR" ]] && [[ "$POST" != "true" ]]; then
        LOG "- Deleting TAR"
        rm -f "$BUILDS_DIR/$TAR"
    fi
}

# https://github.com/salvogiangri/UN1CA/blob/3.0.0/scripts/utils/common_utils.sh#L485
EVAL()
{
    local CMD="$1"

    local OUT
    OUT="$(eval "$CMD" 2>&1)"
    # shellcheck disable=SC2181,SC2291
    if [ $? -ne 0 ]; then
        LOGE "Command returned a non-zero exit code\n"
        echo -e    '\033[0;31m'"$CMD"'\033[0m\n' >&2
        echo -n -e '\033[0;33m' >&2
        echo -n    "$OUT" >&2
        echo -e    '\033[0m' >&2
        exit 1
    fi
}
# ]
