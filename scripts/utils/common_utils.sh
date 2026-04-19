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

BUILD_KERNEL()
{
    local CMD

    CMD+="make "
    CMD+="-C \"$KERNEL_DIR\" "
    CMD+="-j\"$(nproc --all)\" "
    CMD+="ARCH=\"arm64\" "
    CMD+="CC=\"clang\" "
    CMD+="KBUILD_BUILD_USER=\"Majaahh\" "
    CMD+="KBUILD_BUILD_HOST=\"PC\" "
    CMD+="LLVM=1 "
    CMD+="LLVM_IAS=1 "
    CMD+="O=\"$BUILD_DIR\" "
    if [[ -n "$1" ]]; then
        CMD+="$1 "
    fi
    CMD+="> /dev/null"

    EVAL "$CMD" || return 1
}

# https://github.com/salvogiangri/UN1CA/blob/3.0.0/scripts/utils/module_utils.sh#L79
# DOWNLOAD_FILE "<url>" "<output path>"
# Downloads the file from the provided URL and stores it in the desidered output path.
DOWNLOAD_FILE()
{
    _CHECK_NON_EMPTY_PARAM "URL" "$1" || return 1
    _CHECK_NON_EMPTY_PARAM "OUTPUT" "$2" || return 1

    local URL="$1"
    local OUTPUT="$2"

    EVAL "mkdir -p \"$(dirname "$OUTPUT")\""
    EVAL "curl -L -o \"$OUTPUT\" \"$URL\""
    return $?
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
    local AOSP_ARCHIVE="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/mirror-goog-main-llvm-toolchain-source"
    local CLANG_URL
    local LATEST_AOSP_CLANG
    local ATTEMPT=0

    until [[ -n "$LATEST_AOSP_CLANG" ]]; do
        LATEST_AOSP_CLANG="$(GET_LATEST_AOSP_CLANG)"
        if [[ -z "$LATEST_AOSP_CLANG" ]]; then
            ATTEMPT=$((ATTEMPT + 1))
            if [[ "$ATTEMPT" -ge 5 ]]; then
                LOGE "Failed to fetch latest AOSP Clang version (5/5)"
                return 1
            fi
            LOG "\033[0;33m! Failed to fetch latest AOSP Clang version ($ATTEMPT/5)\033[0m"
            sleep 5
        fi
    done

    CLANG_URL="$AOSP_ARCHIVE/$LATEST_AOSP_CLANG.tar.gz"

    if [[ -d "$TMP_DIR" ]]; then
        EVAL "mkdir -p \"$TMP_DIR\""
    fi

    LOG_STEP_IN "- Latest AOSP Clang is ${LATEST_AOSP_CLANG//clang-/}"
    LOG "- Downloading AOSP Clang"
    DOWNLOAD_FILE "$CLANG_URL" "$TMP_DIR/$(basename "$CLANG_URL")" || {
        LOGE "Failed to download latest AOSP Clang"
        EVAL "rm -rf \"$TMP_DIR\""
        EVAL "rm -rf \"$TOOLCHAIN_DIR\""
        return 1
    }

    if [[ -d "$TOOLCHAIN_DIR" ]]; then
        EVAL "rm -rf \"$TOOLCHAIN_DIR\""
    fi
    EVAL "mkdir -p \"$TOOLCHAIN_DIR\""

    LOG "- Extracting AOSP Clang"
    EVAL "tar -xf \"$TMP_DIR/$(basename "$CLANG_URL")\" -C \"$TOOLCHAIN_DIR\" && rm \"$TMP_DIR/$(basename "$CLANG_URL")\""

    EVAL "touch \"$TOOLCHAIN_DIR/bin/aarch64-linux-gnu-elfedit\" && chmod +x \"$TOOLCHAIN_DIR/bin/aarch64-linux-gnu-elfedit\""
    EVAL "touch \"$TOOLCHAIN_DIR/bin/arm-linux-gnueabi-elfedit\" && chmod +x \"$TOOLCHAIN_DIR/bin/arm-linux-gnueabi-elfedit\""

    EVAL "rm -rf \"$TMP_DIR\""
    LOG_STEP_OUT
}

GET_LATEST_AOSP_CLANG()
{
    local AOSP_LIST
    local CURRENT_CLANG

    AOSP_LIST="$(curl -s https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+/mirror-goog-main-llvm-toolchain-source)"
    CURRENT_CLANG="$(printf '%s\n' "$AOSP_LIST" | grep -oP 'href="[^"]*clang-r[0-9]+/' | grep -oP 'clang-r[0-9]+' | sort -V | tail -n1)"

    echo "$CURRENT_CLANG"
}

UPLOAD()
{
    _CHECK_NON_EMPTY_PARAM "ARCHIVE" "$1" || return 1

    local ARCHIVE="$1"
    local ARCHIVE_NAME
    local TAG_NAME
    local REPO
    local FORCE="${3:-}"

    ARCHIVE_NAME="$(basename "$ARCHIVE")"
    TAG_NAME="UN1CA_Kernel-$(git rev-parse --short HEAD)"
    REPO="$(git -C "$KERNEL_DIR" remote get-url origin | sed -Ee 's#.*/([^/]+/[^/]+)(\.git)?$#\1#' -e 's/^[^:]*://' -e 's/\.git//')"

    if ! git ls-remote --tags origin | grep -q "refs/tags/$TAG_NAME"; then
        LOG "- Creating tag"
        EVAL "git tag \"$TAG_NAME\""
        EVAL "git push origin --tags"
    fi

    if ! gh release view "$TAG_NAME" >/dev/null 2>&1; then
        LOG "- Creating release"
        EVAL "gh release create \"$TAG_NAME\" --title \"$TAG_NAME\""
    fi

    if [[ "$FORCE" != "-f" ]]; then
        if [[ "$ARCHIVE_NAME" == UN1CA_Kernel-* ]]; then
            local VARIANT="${ARCHIVE_NAME##*-}"
            local VARIANT="${VARIANT%.tar}"

            # shellcheck disable=SC2269
            VARIANT="$VARIANT" \
            gh release view "$TAG_NAME" --repo "$REPO" --json assets \
                --jq "
                    .assets[].name
                    | select(
                        startswith(\"UN1CA_Kernel-\")
                        and endswith(env.VARIANT + \".tar\")
                    )
                " | grep -q . && return 0
        fi

        if [[ "$ARCHIVE_NAME" == UN1CA_DTBO-* ]]; then
            local VARIANT="${ARCHIVE_NAME##*-}"
            local VARIANT="${VARIANT%.tar}"

            # shellcheck disable=SC2269
            VARIANT="$VARIANT" \
            gh release view "$TAG_NAME" --repo "$REPO" --json assets \
                --jq "
                    .assets[].name
                    | select(
                        startswith(\"UN1CA_DTBO-\")
                        and endswith(env.VARIANT + \".tar\")
                    )
                " | grep -q . && return 0
        fi
    fi

    LOG "- Uploading ${ARCHIVE//$SRC_DIR\//}"
    EVAL "gh release upload \"$TAG_NAME\" \"$ARCHIVE\" --clobber"
}
# ]
