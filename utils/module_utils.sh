# [
source "$SRC_DIR/build/utils/common_utils.sh" || return 1
source "$SRC_DIR/build/utils/log_utils.sh" || return 1

GENERATE_MODULES_LOAD()
{
    local MODULES
    local OUTPUT_FILE
    local MODULES_ORDER
    local KERNEL_VERSION
    local DEPMOD_BASE
    local ALL_MODULES
    local TEMP_MODULES
    local MODULES_DEP
    local PRIORITY_MODULES
    local SORTED_MODULES
    local DEPS

    MODULES="$(find "$MOD_OUTDIR/lib/modules" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    OUTPUT_FILE="$TMP_DIR/modules.load"
    MODULES_ORDER="$MODULES/modules.order"
    KERNEL_VERSION=$(basename "$MODULES")
    DEPMOD_BASE=$(dirname "$(dirname "$(dirname "$MODULES")")")
    ALL_MODULES=$(mktemp)
    TEMP_MODULES=$(mktemp)
    MODULES_DEP="$MODULES/modules.dep"
    PRIORITY_MODULES=(
        "exynos-chipid_v2.ko"
        "exynos-reboot.ko"
        "clk_exynos.ko"
        "exynos_mct.ko"
        "s3c2410_wdt.ko"
        "i2c-exynos5.ko"
    )

    if [[ ! -f "$MODULES_ORDER" ]]; then
        LOGE "modules.order not found at $MODULES_ORDER"
        exit 1
    fi

    depmod -b "$DEPMOD_BASE" "$KERNEL_VERSION" 2>/dev/null || {
        LOGW "Depmod failed, will use modules.order without dependency resolution"
    }

    while IFS= read -r line; do
        basename "$line"
    done < "$MODULES_ORDER" > "$ALL_MODULES"

    while IFS= read -r module; do
        echo "$module" >> "$TEMP_MODULES"
    done < "$ALL_MODULES"

    mv -f "$TEMP_MODULES" "$ALL_MODULES"

    if [[ -f "$MODULES_DEP" ]]; then
        SORTED_MODULES=$(mktemp)
        declare -A PROCESSED

        RESOLVE_DEPS() {
            local MODNAME="$1"

            [[ "${PROCESSED[$MODNAME]}" = "1" ]] && return

            DEPS=$(grep "/${MODNAME}:" "$MODULES_DEP" 2>/dev/null | head -1 | cut -d: -f2 || true)

            for d in $DEPS; do
                local DEPNAME
                DEPNAME=$(basename "$d")
                if grep -q "^${DEPNAME}$" "$ALL_MODULES"; then
                    RESOLVE_DEPS "$DEPNAME"
                fi
            done

            PROCESSED[$MODNAME]=1
            echo "$MODNAME" >> "$SORTED_MODULES"
        }

        while IFS= read -r module; do
            RESOLVE_DEPS "$module"
        done < "$ALL_MODULES"

        : > "$OUTPUT_FILE"

        for m in "${PRIORITY_MODULES[@]}"; do
            if grep -q "^$m$" "$SORTED_MODULES"; then
                echo "$m" >> "$OUTPUT_FILE"
                sed -i "/^$m$/d" "$SORTED_MODULES"
            fi
        done

        cat "$SORTED_MODULES" >> "$OUTPUT_FILE"
        rm -f "$SORTED_MODULES"
    else
        : > "$OUTPUT_FILE"

        cat "$ALL_MODULES" >> "$OUTPUT_FILE"
    fi

    rm -f "$ALL_MODULES"

    if [[ ! -f "$OUTPUT_FILE" ]]; then
        LOGE "ERROR: Failed to generate modules.load"
        exit 1
    fi

    declare -A MODULE_MAP
    while IFS= read -r path; do
        NAME=$(basename "$path")
        MODULE_MAP["$NAME"]="$path"
    done < <(find "$MOD_OUTDIR/lib/modules" -name "*.ko" -type f)

    for m in $(cat "$TMP_DIR/modules.load"); do
        SRC="${MODULE_MAP[$m]}"
        if [[ -n "$SRC" ]] && [[ -f "$SRC" ]]; then
            cp -f "$SRC" "$MODULES_DIR/0.0/$m"
        fi
    done

    EVAL "depmod 0.0 -b \"$DLKM_RAMDISK_DIR\""
    EVAL "sed -i \"s/\([^ ]\+\)/\/lib\/modules\/\1/g\" \"$MODULES_DIR/0.0/modules.dep\""

    (
    cd "$MODULES_DIR/0.0"

    for i in $(find . -name "modules.*" -type f); do
        if [[ "$(basename "$i")" != "modules.dep" && "$(basename "$i")" != "modules.softdep" && "$(basename "$i")" != "modules.alias" ]]; then
            EVAL "rm -f \"$i\""
        fi
    done
    )

    EVAL "cp -f \"$TMP_DIR/modules.load\" \"$MODULES_DIR/0.0/modules.load\""
    EVAL "mv -f \"$MODULES_DIR/0.0/\"* \"$MODULES_DIR/\""
    EVAL "rm -rf \"$MODULES_DIR/0.0\""
}
# ]
