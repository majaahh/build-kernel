# shellcheck shell=bash
#
# SPDX-FileCopyrightText: Majaahh
# SPDX-License-Identifier: Apache-2.0
#

# [
SRC_DIR="$(git rev-parse --show-toplevel)"
PREV_DIR="$(readlink -f ../)"
TARGET="$1"

export SRC_DIR
export PREV_DIR
export OUT="$SRC_DIR/out"
export BUILDS_DIR="$OUT/builds"
export IMAGES_DIR="$OUT/images"
export KERNELS_DIR="$OUT/kernels"
export TOOLCHAIN_DIR="$OUT/toolchains"
export CLANG_DIR="$TOOLCHAIN_DIR/aospclang"
export GCC_DIR_32="$TOOLCHAIN_DIR/gcc_32"
export GCC_DIR_64="$TOOLCHAIN_DIR/gcc_64"
export TOOLS_DIR="$SRC_DIR/prebuilts/tools"
export TMP_DIR="$OUT/tmp"
if [[ ":$PATH:" != *":$TOOLS_DIR:"* ]]; then
    export PATH="$TOOLS_DIR:$PATH"
fi

alias m='$SRC_DIR/scripts/build.sh'
# ]

if [[ -z "$TARGET" ]]; then
    echo "Usage: env <device>"
    return 1
fi

. "$SRC_DIR/scripts/internal/parse_config.sh" "$TARGET" || return 1

export TARGET_DIR="$SRC_DIR/target/$TARGET_CODENAME"
if [[ -d "$SRC_DIR/board/$BOARD_CODENAME" ]]; then
    export BOARD_DIR="$SRC_DIR/board/$BOARD_CODENAME"
elif [[ -n "$BOARD_DIR" ]]; then
    unset BOARD_DIR
fi

export KERNEL_DIR="$BUILDS_DIR/$TARGET_CODENAME"
export KERNEL_DIR="$KERNELS_DIR/${TARGET_KERNEL_REPO/\//_}"

unset TARGET
