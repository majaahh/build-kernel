# shellcheck shell=bash
#
# SPDX-FileCopyrightText: Majaahh
# SPDX-License-Identifier: Apache-2.0
#

SRC_DIR="$(git rev-parse --show-toplevel)"
PREV_DIR="$(readlink -f ../)"

export SRC_DIR
export PREV_DIR
export OUT="$SRC_DIR/out"
export BUILD_DIR="$OUT/build"
export IMAGES_DIR="$OUT/images"
export KERNEL_DIR="$OUT/kernel"
export TOOLCHAIN_DIR="$OUT/aospclang"
export GCC_DIR_32="$OUT/gcc_32"
export GCC_DIR_64="$OUT/gcc_64"
export TOOLS_DIR="$SRC_DIR/prebuilts/tools"
export TMP_DIR="$OUT/tmp"
if [[ ":$PATH:" != *":$TOOLCHAIN_DIR/bin:"* ]]; then
    export PATH="$TOOLCHAIN_DIR/bin:$PATH"
fi
if [[ ":$PATH:" != *":$TOOLS_DIR:"* ]]; then
    export PATH="$TOOLS_DIR:$PATH"
fi

alias m='$SRC_DIR/scripts/build.sh'
