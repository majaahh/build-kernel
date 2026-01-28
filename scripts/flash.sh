#!/bin/bash
#
# SPDX-FileCopyrightText: Majaahh
# SPDX-License-Identifier: Apache-2.0
#

# [
source "$SRC_DIR/scripts/utils/common_utils.sh"
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
# ]

if [[ "$#" -lt "2" ]]; then
    _PRINT_USAGE
    exit 1
fi

if ! type odin4 &>/dev/null; then
    LOGE "Odin4 was not found. Please download and add it to your path!"
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

if adb devices | grep -wq device; then
    LOG "- Rebooting device to download mode"
    EVAL "adb reboot download"
fi

if ! lsusb | grep -q "GT-I9100"; then
    LOGE "Device was not found. Is it in download mode?"
    exit 1
fi

EVAL "odin4 \"$PART\" \"$FILE\""
