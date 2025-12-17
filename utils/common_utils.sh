# [
source "$SRC_DIR/build/utils/log_utils.sh" || return 1

CLEANUP()
{
    local DIRTY
    local DIRS=("$IMAGES_DIR" "$MOD_OUTDIR" "$TMP_DIR")
    local FILES=("$OUT_KERNEL")

    for i in "${DIRS[@]}"; do
        if [[ -d "$i" ]] && [[ "$DIRTY" != "true" ]]; then
            LOG_STEP_IN true "Cleaning up build remainings"
            DIRTY="true"
        fi
        if [[ -d "$i" ]]; then
            LOG "- Deleting "${i//$SRC_DIR\//}""
            EVAL "rm -rf \"$i\""
        fi
    done

    for i in ${FILES[@]}; do
        if [[ -f "$i" ]] && [[ "$DIRTY" != "true" ]]; then
            LOG_STEP_IN true "Cleaning up build remainings"
            DIRTY="true"
        fi
        if [[ -f "$i" ]]; then
            LOG "- Deleting "${i//$SRC_DIR\//}""
            EVAL "rm -f \"$i\""
        fi
    done

    if [[ "$DIRTY" == "true" ]]; then
        LOG_STEP_OUT
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
