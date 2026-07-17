# shellcheck shell=bash
#
# SPDX-FileCopyrightText: Majaahh
# SPDX-License-Identifier: Apache-2.0
#

# Images
export TARGET_BOOT_IMAGE_SIZE="67108864"
export TARGET_DTBO_IMAGE_SIZE="8388608"
export TARGET_IMAGE_HEADER_VERSION="4"
# Temporary
export TARGET_OS_VERSION="16"
export TARGET_VENDOR_BOOT_IMAGE_SIZE="33554432"

# Kernel
export TARGET_KERNEL_DEFCONFIG="s5e8825_defconfig"
export TARGET_KERNEL_SOURCE="UN1CA/kernel_samsung_s5e8825"
export TARGET_TOOLCHAIN="clang"
