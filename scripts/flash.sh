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
    echo "Usage: flash.sh <part> <file>"
    echo "Parts:"
    echo "-a (AP)"
    echo "-b (BL)"
    echo "-s (CSC)"
    echo "-c (CP)"
}

PART="$1"
FILE="$2"
RETRY=false
DEPS=()
MISSING_DEPS=()
# ]

if [[ "$#" -lt "2" ]]; then
    _PRINT_USAGE
    exit 1
fi

DEPS=("brokkr" "lsusb")

for i in "${DEPS[@]}"; do
    if ! type "$i" &>/dev/null; then
        MISSING_DEPS+=("$i")
    fi
done

if [[ "${#MISSING_DEPS[@]}" -ne 0 ]]; then
    echo -e '\033[1;31m'"The following dependencies are missing from your system:"'\033[0;31m' >&2
    printf '%s ' "${MISSING_DEPS[@]}" >&2
    echo -e '\033[0m' >&2
    exit 1
fi

if [[ "$PART" != "-a" ]] && [[ "$PART" != "-b" ]] && \
    [[ "$PART" != "-s" ]] && [[ "$PART" != "-c" ]]; then
    LOGE "$PART is not a valid part"
    _PRINT_USAGE
    exit 1
fi

if [[ ! -f "$FILE" ]]; then
    LOGE "$FILE was not found"
    exit 1
fi

if adb devices | grep -Ew "device|recovery" &>/dev/null; then
    LOG "- Rebooting device to download mode"
    EVAL "adb reboot download"
fi

while true; do
    if ! lsusb | grep -q "GT-I9100"; then
        if ! $RETRY; then
            LOG "- Waiting for device"
            RETRY=true
        fi
    else
        break
    fi

    sleep 0.5
done

EVAL "brokkr \"$PART\" \"$FILE\""
