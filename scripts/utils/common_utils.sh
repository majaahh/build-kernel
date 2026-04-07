#!/bin/bash
#
# SPDX-FileCopyrightText: Majaahh
# SPDX-License-Identifier: Apache-2.0
#

# [
# shellcheck disable=SC1091
source "$SRC_DIR/scripts/utils/log_utils.sh" || return 1

# https://github.com/salvogiangri/UN1CA/blob/3.0.0/scripts/utils/common_utils.sh#L21-L42
_CHECK_NON_EMPTY_PARAM()
{
    if [ ! "$2" ]; then
        echo -n -e '\033[0;31m' >&2

        local STACK_SIZE="${#FUNCNAME[@]}"
        if [[ "$STACK_SIZE" -gt "1" ]]; then
            echo -n "(" >&2
            if [[ "$STACK_SIZE" -gt "2" ]]; then
                echo -n "${BASH_SOURCE[2]//$SRC_DIR\//}:${BASH_LINENO[1]}:" >&2
            fi
            echo -n "${FUNCNAME[1]}) " >&2
        fi

        echo -n "$1 is not set!" >&2
        echo -e '\033[0m' >&2

        exit 1
    fi
}

# https://github.com/salvogiangri/UN1CA/blob/3.0.0/scripts/utils/common_utils.sh#L485
EVAL()
{
    local CMD="$1"

    local OUT
    OUT="$(eval "$CMD" 2>&1)"
    # shellcheck disable=SC2181,SC2291
    if [ $? -ne 0 ]; then
        LOGE "Command returned a non-zero exit code\n"
        echo -e    '\033[0;31m'"$CMD"'\033[0m\n' >&2
        echo -n -e '\033[0;33m' >&2
        echo -n    "$OUT" >&2
        echo -e    '\033[0m' >&2
        exit 1
    fi
}

CREATE_TAR_ARCHIVE()
{
    _CHECK_NON_EMPTY_PARAM "TAR_OUT" "$1" || return 1
    _CHECK_NON_EMPTY_PARAM "IMAGES" "$2" || return 1

    local TAR_OUT="$1"
    shift

    local IMAGES=("$@")

    if [[ -f "$TAR_OUT" ]]; then
        EVAL "rm -f \"$TAR_OUT\""
    fi

    EVAL "tar -cf \"$TAR_OUT\" --transform='s|.*/||' ${IMAGES[*]}" || return 1
}

GET_AOSP_CLANG()
{
    local AOSP_LIST
    local AOSP_ARCHIVE="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/mirror-goog-main-llvm-toolchain-source"
    local CURRENT_CLANG

    EVAL "mkdir -p \"$TOOLCHAIN_DIR\""

    AOSP_LIST="$(curl -s https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+/mirror-goog-main-llvm-toolchain-source)"
    CURRENT_CLANG="$(printf '%s\n' "$AOSP_LIST" | grep -oP 'href="[^"]*clang-r[0-9]+/' | grep -oP 'clang-r[0-9]+' | sort -V | tail -n1)"

    LOG_STEP_IN "- Latest AOSP Clang is $CURRENT_CLANG"
    LOG "- Downloading AOSP Clang"
    EVAL "wget -nv -O \"$CURRENT_CLANG.tar.gz\" \"$AOSP_ARCHIVE/$CURRENT_CLANG.tar.gz\"" || {
        LOGE "Failed to download latest AOSP Clang"
        EVAL "rm -rf \"$TOOLCHAIN_DIR\""
        return 1
    }

    LOG "- Extracting AOSP Clang"
    EVAL "tar -xf \"$CURRENT_CLANG.tar.gz\" -C \"$TOOLCHAIN_DIR\" && rm \"$CURRENT_CLANG.tar.gz\""

    EVAL "touch \"$TOOLCHAIN_DIR/bin/aarch64-linux-gnu-elfedit\" && chmod +x \"$TOOLCHAIN_DIR/bin/aarch64-linux-gnu-elfedit\""
    EVAL "touch \"$TOOLCHAIN_DIR/bin/arm-linux-gnueabi-elfedit\" && chmod +x \"$TOOLCHAIN_DIR/bin/arm-linux-gnueabi-elfedit\""
    LOG_STEP_OUT
}

UPLOAD()
{
    _CHECK_NON_EMPTY_PARAM "ARCHIVE" "$1" || return 1

    local ARCHIVE="$1"
    local ARCHIVE_NAME
    local TAG_NAME
    local REPO="majaahh/android_kernel_samsung_a53x"

    ARCHIVE_NAME="$(basename "$ARCHIVE")"
    TAG_NAME="UN1CA_Kernel-$(git rev-parse --short HEAD)"

    if ! git ls-remote --tags origin | grep -q "refs/tags/$TAG_NAME"; then
        LOG "- Creating tag"
        EVAL "git tag \"$TAG_NAME\""
        EVAL "git push origin --tags"
    fi

    if ! gh release view "$TAG_NAME" >/dev/null 2>&1; then
        LOG "- Creating release"
        EVAL "gh release create \"$TAG_NAME\" --title \"$TAG_NAME\""
    fi

    if [[ "$ARCHIVE_NAME" == UN1CA_Dtbo-* ]]; then
        local VARIANT="${ARCHIVE_NAME##*-}"
        local VARIANT="${VARIANT%.tar}"

        # shellcheck disable=SC2269
        VARIANT="$VARIANT" \
        gh release view "$TAG_NAME" --repo "$REPO" --json assets \
            --jq "
                .assets[].name
                | select(
                    startswith(\"UN1CA_Dtbo-\")
                    and endswith(env.VARIANT + \".tar\")
                )
            " | grep -q . && return 0
    fi

    LOG "- Uploading ${ARCHIVE//$SRC_DIR\//}"
    EVAL "gh release upload \"$TAG_NAME\" \"$ARCHIVE\" --clobber"
}
# ]
