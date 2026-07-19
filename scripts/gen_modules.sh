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

RESOLVE_DEPS()
{
    local MODNAME="$1"

    if [[ "${PROCESSED[$MODNAME]}" == 1 ]]; then
        return 0
    fi

    local DEPS
    DEPS=$(grep "/$MODNAME:" "$DEP_MODULES_FILE" 2>/dev/null | head -1 | cut -d: -f2 || true)

    while read -r d; do
        local DEPNAME
        DEPNAME=$(basename "$d")
        if grep -q "^$DEPNAME$" "$ALL_MODULES"; then
            RESOLVE_DEPS "$DEPNAME" || return 1
        fi
    done <<< "$DEPS"

    PROCESSED[$MODNAME]=1
    EVAL "echo \"$MODNAME\" >> \"$SORTED_MODULES\"" || return 1
}

MODULES_OUT="$1"
MODULES_GEN_DIR="$TMP_DIR/modules_gen"
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

if [[ "$#" -lt 1 ]]; then
    echo "Usage: gen_modules_load.sh <output_dir>"
    exit 1
fi

if [[ -d "$MODULES_INSTALL_DIR" ]]; then
    EVAL "rm -rf \"$MODULES_INSTALL_DIR\"" || exit 1
fi
EVAL "mkdir -p \"$MODULES_INSTALL_DIR\"" || exit 1

BUILD_KERNEL "INSTALL_MOD_STRIP=\"--strip-debug --keep-section=.ARM.attributes\" INSTALL_MOD_PATH=\"$MODULES_INSTALL_DIR\" modules_install" || exit 1

KMODULES_DIR="$(find "$MODULES_INSTALL_DIR/lib/modules" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
MODULES_ORDER="$KMODULES_DIR/modules.order"

if [[ ! -f "$KMODULES_DIR/modules.order" ]]; then
    LOGE "modules.order not found in ${KMODULES_DIR//$SRC_DIR\//}"
    exit 1
fi

while IFS= read -r l; do
    basename "$l"
done < "$MODULES_ORDER" > "$ALL_MODULES"

while IFS= read -r m; do
    EVAL "echo \"$m\" >> \"$TEMP_MODULES\"" || exit 1
done < "$ALL_MODULES"

EVAL "mv \"$TEMP_MODULES\" \"$ALL_MODULES\"" || exit 1

if [[ -f "$MODULES_LOAD" ]]; then
    EVAL "rm -f \"$MODULES_LOAD\"" || exit 1
fi
EVAL "touch \"$MODULES_LOAD\"" || exit 1

EVAL "mkdir -p \"$MODULES_GEN_DIR/lib/modules/0.0\"" || exit 1

while IFS= read -r i; do
    NAME=$(basename "$i")
    MODULE_MAP["$NAME"]="$i"
done < <(find "$KMODULES_DIR" -name "*.ko" -type f)

for f in "${MODULE_MAP[@]}"; do
    EVAL "cp -a \"$f\" \"$MODULES_GEN_DIR/lib/modules/0.0/\"" || exit 1
done

EVAL "depmod 0.0 -b \"$MODULES_GEN_DIR\"" || exit 1
DEP_MODULES_FILE="$MODULES_GEN_DIR/lib/modules/0.0/modules.dep"

LOG "- Generating modules.load"
SORTED_MODULES=$(mktemp)
declare -A PROCESSED

while IFS= read -r m; do
    RESOLVE_DEPS "$m" || exit 1
done < "$ALL_MODULES"

for m in "${PRIORITY_MODULES[@]}"; do
    if grep -q "^$m$" "$SORTED_MODULES"; then
        EVAL "echo \"$m\" >> \"$MODULES_LOAD\"" || exit 1
        EVAL "sed -i \"/^$m$/d\" \"$SORTED_MODULES\"" || exit 1
    fi
done

EVAL "cat \"$SORTED_MODULES\" >> \"$MODULES_LOAD\"" || exit 1
EVAL "rm -f \"$SORTED_MODULES\"" || exit 1
EVAL "rm -f \"$ALL_MODULES\"" || exit 1

EVAL "sed -i \"s/\([^ ]\+\)/\/lib\/modules\/\1/g\" \"$MODULES_GEN_DIR/lib/modules/0.0/modules.dep\"" || exit 1

while IFS= read -r f; do
    NAME="$(basename "$f")"

    if [[ "$NAME" != "modules.dep" ]] && \
        [[ "$NAME" != "modules.softdep" ]] && \
        [[ "$NAME" != "modules.alias" ]]; then
        EVAL "rm -f \"$f\"" || exit 1
    fi
done < <(find "$MODULES_GEN_DIR/lib/modules/0.0" -type f -name "modules.*")

if [[ -d "$MODULES_OUT" ]]; then
    EVAL "rm -rf \"$MODULES_OUT\"" || exit 1
fi
EVAL "mkdir -p \"$MODULES_OUT/lib/modules\"" || exit 1

EVAL "mv \"$MODULES_GEN_DIR/lib/modules/0.0/\"* \"$MODULES_OUT/lib/modules\"" || exit 1
EVAL "mv \"$MODULES_LOAD\" \"$MODULES_OUT/lib/modules/modules.load\"" || exit 1

EVAL "rm -rf \"$TMP_DIR\"" || exit 1
