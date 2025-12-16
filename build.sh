#!/bin/bash
#
# Copyright (C) 2020-2021 Adithya R. (original version)
# Copyright (C) 2022-2025 Flopster101 (rewrite)
# Copyright (C) 2025 Majaahh (mod)
#
# Additional credits:
# * Gabriel2392: Logic previously used for module packaging.
# * ExtremeXT: Logic for generating modules.load on the fly.
#

if [[ ! -d drivers ]]; then
    echo -e "ERROR: Please execute from top-level kernel tree"
    exit 1
fi

# Variables
DIR="$(readlink -f .)"
PREV_DIR="$(readlink -f ../)"
OUTDIR="$DIR/out"
MOD_OUTDIR="$DIR/modules_out"
TMP_DIR="$DIR/build/tmp"
IN_PLATFORM="$DIR/build/vboot_platform"
IN_DLKM="$DIR/build/vboot_dlkm"
IN_DTB="$OUTDIR/arch/arm64/boot/dts/exynos/s5e8825.dtb"
PLATFORM_RAMDISK_DIR="$TMP_DIR/ramdisk_platform"
DLKM_RAMDISK_DIR="$TMP_DIR/ramdisk_dlkm"
PREBUILT_RAMDISK="$DIR/build/boot/ramdisk"
MODULES_DIR="$DLKM_RAMDISK_DIR/lib/modules"
OUT_KERNEL="$OUTDIR/arch/arm64/boot/Image"
IMAGES_DIR="$DIR/build/images"
OUT_BOOTIMG="$IMAGES_DIR/boot.img"
OUT_VENDORBOOTIMG="$IMAGES_DIR/vendor_boot.img"
OUT_DTBIMAGE="$IMAGES_DIR/dtb.img"
MKBOOTIMG="$(pwd)/build/mkbootimg/mkbootimg.py"
MKDTBOIMG="$(pwd)/build/dtb/mkdtboimg.py"
AOSP_LIST="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+/mirror-goog-main-llvm-toolchain-source"
AOSP_ARCHIVE="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/mirror-goog-main-llvm-toolchain-source"
AOSP_DIR="$PREV_DIR/aospclang"
DATE="$(date +%Y%m%d-%H%M)"
MONTH="$(date +%Y-%m)"
TAR="$DIR/build/UN1CA-kernel_a53x-$DATE.tar"

export KBUILD_BUILD_USER="Majaahh"
export KBUILD_BUILD_HOST="PC"
export PATH="$AOSP_DIR/bin:$PATH"
export PLATFORM_VERSION="12"
export ANDROID_MAJOR_VERSION="s"
export TARGET_SOC="s5e8825"
export LLVM=1
export LLVM_IAS=1
export ARCH=arm64

if [[ -d "$IMAGES_DIR" ]]; then
    rm -rf "$IMAGES_DIR"
fi
mkdir -p "$IMAGES_DIR"

if [[ -d "$MOD_OUTDIR" ]]; then
    rm -rf "$MOD_OUTDIR"
fi
mkdir -p "$MOD_OUTDIR"

if [[ ! -d "$AOSP_DIR" ]]; then
    mkdir -p "$AOSP_DIR"

    HTML="$(curl -s "$AOSP_LIST")"
    CURRENT_CLANG="$(printf '%s\n' "$HTML" | grep -oP 'href="[^"]*clang-r[0-9]+/' | grep -oP 'clang-r[0-9]+' | sort -V | tail -n1)"

    if [[ -z "$CURRENT_CLANG" ]]; then
        echo "Couldn’t find any clang-r### dirs in $AOSP_LIST" >&2
        exit 1
    fi

    echo "Latest AOSP Clang is $CURRENT_CLANG, downloading."
    if ! wget -nvq -O "$CURRENT_CLANG.tar.gz" "$AOSP_ARCHIVE/$CURRENT_CLANG.tar.gz"; then
        echo "Download failed"
        exit 1
    fi

    tar -xf "$CURRENT_CLANG.tar.gz" -C "$AOSP_DIR" && rm "$CURRENT_CLANG.tar.gz"

    touch "$AOSP_DIR/bin/aarch64-linux-gnu-elfedit" && chmod +x "$AOSP_DIR/bin/aarch64-linux-gnu-elfedit"
    touch "$AOSP_DIR/bin/arm-linux-gnueabi-elfedit" && chmod +x "$AOSP_DIR/bin/arm-linux-gnueabi-elfedit"
fi

make -j"$(nproc --all)" O="$OUTDIR" CC="clang" "a53x_defconfig" >/dev/null
make -j"$(nproc --all)" O="$OUTDIR" CC="clang" "dtbs" >/dev/null
make -j"$(nproc --all)" O="$OUTDIR" CC="clang" >/dev/null
make -j"$(nproc --all)" O="$OUTDIR" CC="clang" \
    INSTALL_MOD_STRIP="--strip-debug --keep-section=.ARM.attributes" \
    INSTALL_MOD_PATH="$MOD_OUTDIR" "modules_install" >/dev/null

if [[ ! -f "$OUTDIR/arch/arm64/boot/Image" ]]; then
    echo "Compilation failed"
    exit 1
fi

if [[ -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
fi
mkdir -p "$TMP_DIR"

if [[ -d "$PLATFORM_RAMDISK_DIR" ]]; then
    rm -rf "$PLATFORM_RAMDISK_DIR"
fi
mkdir -p "$PLATFORM_RAMDISK_DIR/first_stage_ramdisk"

if [[ -d "$MODULES_DIR/0.0" ]]; then
    rm -rf "$MODULES_DIR/0.0"
fi
mkdir -p "$MODULES_DIR/0.0"

if [[ -f "$OUT_BOOTIMG" ]]; then
    rm -f "$OUT_BOOTIMG"
fi

if [[ -f "$OUT_VENDORBOOTIMG" ]]; then
    rm -f "$OUT_VENDORBOOTIMG"
fi

cp -rf "$IN_PLATFORM/"* "$PLATFORM_RAMDISK_DIR"
cp -f "$PLATFORM_RAMDISK_DIR/fstab.s5e8825" "$PLATFORM_RAMDISK_DIR/first_stage_ramdisk/fstab.s5e8825"

if ! find "$MOD_OUTDIR/lib/modules" -mindepth 1 -type d | read; then
    echo "Unknown error"
    exit 1
fi

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
    echo "modules.order not found at $MODULES_ORDER"
    exit 1
fi

depmod -b "$DEPMOD_BASE" "$KERNEL_VERSION" 2>/dev/null || {
    echo "WARNING: depmod failed, will use modules.order without dependency resolution"
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
        local DEPS

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

    # Process all modules
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
    echo "ERROR: Failed to generate modules.load"
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

depmod 0.0 -b "$DLKM_RAMDISK_DIR"
sed -i 's/\([^ ]\+\)/\/lib\/modules\/\1/g' "$MODULES_DIR/0.0/modules.dep"

(
cd "$MODULES_DIR/0.0"

for i in $(find . -name "modules.*" -type f); do
    if [[ "$(basename "$i")" != "modules.dep" && "$(basename "$i")" != "modules.softdep" && "$(basename "$i")" != "modules.alias" ]]; then
        rm -f "$i"
    fi
done
)

cp -f "$TMP_DIR/modules.load" "$MODULES_DIR/0.0/modules.load"
mv -f "$MODULES_DIR/0.0"/* "$MODULES_DIR/"
rm -rf "$MODULES_DIR/0.0"

python3 "$MKDTBOIMG" create "$OUT_DTBIMAGE" --custom0=0x00000000 --custom1=0xff000000 --version=0 --page_size=2048 "$IN_DTB" || exit 1

"$MKBOOTIMG" \
    --header_version 4 \
    --kernel "$OUT_KERNEL" \
    --output "$OUT_BOOTIMG" \
    --ramdisk "$PREBUILT_RAMDISK" \
    --os_version 16.0.0 \
    --os_patch_level "$MONTH" || exit 1

(
cd "$DLKM_RAMDISK_DIR"

find . | cpio --quiet -o -H newc -R root:root | lz4 -9cl > "../ramdisk_dlkm.lz4"
)

(
cd "$TMP_DIR/ramdisk_platform"

find . | cpio --quiet -o -H newc -R root:root | lz4 -9cl > "../ramdisk_platform.lz4"
)

echo "buildtime_bootconfig=enable" > "$TMP_DIR/bootconfig"

"$MKBOOTIMG" \
    --header_version 4 \
    --vendor_boot "$OUT_VENDORBOOTIMG" \
    --vendor_bootconfig "$TMP_DIR/bootconfig" \
    --dtb "$OUT_DTBIMAGE" \
    --vendor_ramdisk "$TMP_DIR/ramdisk_platform.lz4" \
    --ramdisk_type "dlkm" \
    --ramdisk_name "dlkm" \
    --vendor_ramdisk_fragment "$TMP_DIR/ramdisk_dlkm.lz4" \
    --os_version 16.0.0 \
    --os_patch_level "$MONTH" || exit 1

if [[ -f "$TAR" ]]; then
    rm -f "$TAR"
fi

(
cd "$DIR/build"

lz4 -c -12 -B6 --content-size "$OUT_BOOTIMG" > "boot.img.lz4" 2>/dev/null
lz4 -c -12 -B6 --content-size "$OUT_VENDORBOOTIMG" > "vendor_boot.img.lz4" 2>/dev/null
tar -cf "$TAR" "boot.img.lz4" "vendor_boot.img.lz4"
rm -f "boot.img.lz4" "vendor_boot.img.lz4"
)

if [[ -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
fi

if [[ -d "$MOD_OUTDIR" ]]; then
    rm -rf "$MOD_OUTDIR"
fi
