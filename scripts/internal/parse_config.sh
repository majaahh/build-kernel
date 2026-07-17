#!/bin/bash
#
# SPDX-FileCopyrightText: Majaahh
# SPDX-License-Identifier: Apache-2.0
#

# [
# shellcheck disable=SC1091
source "$SRC_DIR/scripts/utils/common_utils.sh" || return

TARGET="$1"
TARGET_CONFIG="$SRC_DIR/target/$TARGET/config.sh"
BOARD_CODENAME=""
BOARD_CONFIG=""
REQUIRED_CONFIGS=(
    # General
    "TARGET_CODENAME"
    # Images
    "TARGET_BOOT_IMAGE_SIZE" "TARGET_DTBO_IMAGE_SIZE"
    "TARGET_IMAGE_HEADER_VERSION" "TARGET_VENDOR_BOOT_IMAGE_SIZE"
    # Kernel
    "TARGET_KERNEL_DEFCONFIG" "TARGET_KERNEL_SOURCE" "TARGET_TOOLCHAIN"
)
MISSING=()

# Available variables:
# - General
#   TARGET_CODENAME
#   BOARD_CODENAME
#
# - Images
#   TARGET_BOOT_IMAGE_CMDLINE
#   TARGET_BOOT_IMAGE_SIZE
#   TARGET_DTBO_IMAGE_SIZE
#   TARGET_IMAGE_HEADER_VERSION
#   TARGET_OS_VERSION
#   TARGET_VENDOR_BOOT_IMAGE_CMDLINE
#   TARGET_VENDOR_BOOT_IMAGE_SIZE
#
# - Kernel
#   TARGET_KERNEL_DEFCONFIG
#   TARGET_KERNEL_SOURCE
#   TARGET_KERNEL_DEFCONFIG_FRAGMENTS
#   TARGET_TOOLCHAIN
# ]

if [[ -z "$TARGET" ]]; then
    echo "Usage: parse_config.sh <codename>" >&2
    exit 1
fi

if [[ ! -f "$TARGET_CONFIG" ]]; then
    LOGE "Configuration for $TARGET was not found"
    exit 1
fi

# shellcheck disable=SC1090
source "$TARGET_CONFIG"
# shellcheck disable=SC2269
BOARD_CODENAME="$BOARD_CODENAME"

if [[ -n "$BOARD_CODENAME" ]]; then
    BOARD_CONFIG="$SRC_DIR/board/$BOARD_CODENAME/config.sh"

    if [[ ! -f "$BOARD_CONFIG" ]]; then
       unset BOARD_CONFIG
    else
        # shellcheck disable=SC1090
        source "$BOARD_CONFIG"
        # shellcheck disable=SC1090
        # Workaround
        source "$TARGET_CONFIG"
    fi
fi

for i in "${REQUIRED_CONFIGS[@]}"; do
      if ! grep -q "^export $i=" "$TARGET_CONFIG"; then
          if [[ -n "$BOARD_CONFIG" ]]; then
              if ! grep -q "^export $i=" "$BOARD_CONFIG"; then
                  MISSING+=("$i")
              fi
          else
              MISSING+=("$i")
          fi
      fi
done

if [[ "${#MISSING[@]}" -ne 0 ]]; then
    echo -e '\033[1;31m'"The following configs are not set:"'\033[0;31m' >&2
    printf '%s ' "${MISSING[@]}" >&2
    echo -e '\033[0m' >&2
    unset MISSING
    exit 1
fi

if [[ "$TARGET_KERNEL_SOURCE" == *"://"* ]] || [[ "$TARGET_KERNEL_SOURCE" == "git@"* ]]; then
    TARGET_KERNEL_URL="$TARGET_KERNEL_SOURCE"
    if [[ "$TARGET_KERNEL_SOURCE" == "git@"* ]]; then
        _KS_REPO="${TARGET_KERNEL_SOURCE#git@}"
        _KS_REPO="${_KS_REPO#*:}"
    else
        _KS_REPO="${TARGET_KERNEL_SOURCE#*://}"
        _KS_REPO="${_KS_REPO#*/}"
    fi
    _KS_REPO="${_KS_REPO%.git}"
    _KS_REPO="${_KS_REPO%/}"
    TARGET_KERNEL_REPO="$_KS_REPO"
else
    TARGET_KERNEL_REPO="$TARGET_KERNEL_SOURCE"
    TARGET_KERNEL_URL="https://github.com/$TARGET_KERNEL_SOURCE.git"
fi
export TARGET_KERNEL_REPO
export TARGET_KERNEL_URL

unset TARGET TARGET_CONFIG REQUIRED_CONFIGS _KS_REPO
