#!/bin/bash
#
# SPDX-FileCopyrightText: Majaahh
# SPDX-License-Identifier: Apache-2.0
#
# [
# shellcheck disable=SC1091
source "$SRC_DIR/scripts/utils/common_utils.sh"
# shellcheck disable=SC1091
source "$SRC_DIR/scripts/utils/log_utils.sh"

_PRINT_USAGE()
{
    echo "Usage: gen_modules_load.sh <modules_out>"
}

MODULES_OUT="$1"
MODULES_DIR="$TMP_DIR/modules_gen"
MODULES_INSTALL_DIR="$TMP_DIR/modules_dir"
MODULES_LOAD="$TMP_DIR/modules.load"
ALL_MODULES=$(mktemp)
TEMP_MODULES=$(mktemp)
PRIORITY_MODULES=(
    "exynos-chipid_v2.ko"
    "exynos-reboot.ko"
    "clk_exynos.ko"
    "exynos_mct.ko"
    "s3c2410_wdt.ko"
    "i2c-exynos5.ko"
)

declare -A MODULE_MAP
# ]

if [[ "$#" -lt "1" ]]; then
    _PRINT_USAGE
    exit 1
fi

if [[ -d "$MODULES_INSTALL_DIR" ]]; then
    EVAL "rm -rf \"$MODULES_INSTALL_DIR\""
fi
EVAL "mkdir -p \"$MODULES_INSTALL_DIR\""

(
cd "$KERNEL_DIR"

LOG "- Installing modules"
EVAL "make -j\"$(nproc --all)\" O=\"$BUILD_DIR\" CC=\"clang\" \
    INSTALL_MOD_STRIP=\"--strip-debug --keep-section=.ARM.attributes\" \
    INSTALL_MOD_PATH=\"$MODULES_INSTALL_DIR\" \"modules_install\" >/dev/null" || exit 1
) || exit 1

KMODULES_DIR="$(find "$MODULES_INSTALL_DIR/lib/modules" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
MODULES_ORDER="$KMODULES_DIR/modules.order"

if [[ ! -f "$KMODULES_DIR/modules.order" ]]; then
    LOGE "modules.order not found in ${KMODULES_DIR//$SRC_DIR\//}"
    exit 1
fi

depmod -b "$(dirname "$(dirname "$(dirname "$KMODULES_DIR")")")" "$(basename "$KMODULES_DIR")" 2>/dev/null || {
    LOGW "depmod failed, will use modules.order without dependency resolution"
}

while IFS= read -r l; do
    basename "$l"
done < "$MODULES_ORDER" > "$ALL_MODULES"

while IFS= read -r m; do
    EVAL "echo \"$m\" >> \"$TEMP_MODULES\""
done < "$ALL_MODULES"

EVAL "mv \"$TEMP_MODULES\" \"$ALL_MODULES\""

if [[ -f "$MODULES_LOAD" ]]; then
    EVAL "rm -f \"$MODULES_LOAD\""
fi
EVAL "touch \"$MODULES_LOAD\""

LOG "- Generating modules.load"
if [[ -f "$KMODULES_DIR/modules.dep" ]]; then
    SORTED_MODULES=$(mktemp)
    declare -A PROCESSED

    RESOLVE_DEPS()
    {
        local MODNAME="$1"

        if [[ "${PROCESSED[$MODNAME]}" = "1" ]]; then
           return
        fi

        local DEPS
        DEPS=$(grep "/$MODNAME:" "$KMODULES_DIR/modules.dep" 2>/dev/null | head -1 | cut -d: -f2 || true)

        while read -r d; do
            local DEPNAME
            DEPNAME=$(basename "$d")
            if grep -q "^${DEPNAME}$" "$ALL_MODULES"; then
                RESOLVE_DEPS "$DEPNAME"
            fi
        done <<< "$DEPS"

        PROCESSED[$MODNAME]=1
        EVAL "echo \"$MODNAME\" >> \"$SORTED_MODULES\""
    }

    while IFS= read -r m; do
        RESOLVE_DEPS "$m" || exit 1
    done < "$ALL_MODULES"

    for m in "${PRIORITY_MODULES[@]}"; do
        if grep -q "^$m$" "$SORTED_MODULES"; then
            EVAL "echo \"$m\" >> \"$MODULES_LOAD\""
            EVAL "sed -i \"/^$m$/d\" \"$SORTED_MODULES\""
        fi
    done

    EVAL "cat \"$SORTED_MODULES\" >> \"$MODULES_LOAD\""
    EVAL "rm -f \"$SORTED_MODULES\""
else
    for m in "${PRIORITY_MODULES[@]}"; do
        if grep -q "^${m}$" "$ALL_MODULES"; then
            EVAL "echo \"${m}\" >> \"$MODULES_LOAD\""
            EVAL "sed -i \"/^${m}$/d\" \"$ALL_MODULES\""
        fi
    done

    EVAL "cat \"$ALL_MODULES\" >> \"$MODULES_LOAD\""
fi

EVAL "rm -f \"$ALL_MODULES\""

LOG "- Generating modules dir"
while IFS= read -r i; do
    NAME=$(basename "$i")
    MODULE_MAP["$NAME"]="$i"
done < <(find "$KMODULES_DIR" -name "*.ko" -type f)

if [[ -d "$MODULES_DIR" ]]; then
    EVAL "rm -rf \"$MODULES_DIR\""
fi
EVAL "mkdir -p \"$MODULES_DIR/lib/modules/0.0\""

while IFS= read -r m; do
    SRC="${MODULE_MAP[$m]}"
    if [[ -n "$SRC" ]] && [[ -f "$SRC" ]]; then
        EVAL "cp \"$SRC\" \"$MODULES_DIR/lib/modules/0.0/$m\""
    fi
done < "$MODULES_LOAD"

EVAL "depmod 0.0 -b \"$MODULES_DIR\""

EVAL "sed -i \"s/\([^ ]\+\)/\/lib\/modules\/\1/g\" \"$MODULES_DIR/lib/modules/0.0/modules.dep\""

(
cd "$MODULES_DIR/lib/modules/0.0"

find . -type f -name 'modules.*' -print0 | while IFS= read -r -d '' i; do
    NAME="$(basename "$i")"

    if [[ "$NAME" != "modules.dep" ]] && \
       [[ "$NAME" != "modules.softdep" ]] && \
       [[ "$NAME" != "modules.alias" ]]; then
        EVAL "rm -f \"$i\""
    fi
done
) || exit 1

if [[ -d "$MODULES_OUT" ]]; then
    EVAL "rm -rf \"$MODULES_OUT\""
fi
EVAL "mkdir -p \"$MODULES_OUT/lib/modules\""

EVAL "mv \"$MODULES_DIR/lib/modules/0.0/\"* \"$MODULES_OUT/lib/modules\""
EVAL "mv \"$MODULES_LOAD\" \"$MODULES_OUT/lib/modules/modules.load\""

EVAL "rm -rf \"$TMP_DIR\""
