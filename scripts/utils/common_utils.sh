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

        return 1
    fi
}

BUILD_KERNEL()
{
    local CMD
    local PATH="$PATH"

    # TODO
    if [[ "$TARGET_TOOLCHAIN" == "gcc" ]]; then
        LOGE "Kernel build without clang is not supported"
        return 1
    fi

    if [[ "$TARGET_TOOLCHAIN" == "clang"* ]]; then
        PATH="$PATH:$CLANG_DIR/bin"
    fi

    if [[ "$TARGET_TOOLCHAIN" == *"gcc" ]]; then
        PATH="$PATH:$GCC_DIR_32/bin:$GCC_DIR_64/bin"
    fi

    CMD+="make "
    CMD+="-C \"$KERNEL_DIR\" "
    CMD+="-j\"$(nproc --all)\" "
    CMD+="ARCH=\"arm64\" "
    CMD+="CC=\"clang\" "
    CMD+="KBUILD_BUILD_USER=\"Majaahh\" "
    CMD+="KBUILD_BUILD_HOST=\"PC\" "
    if [[ "$TARGET_TOOLCHAIN" == "clang" ]]; then
        CMD+="LLVM=1 "
        CMD+="LLVM_IAS=1 "
    fi
    CMD+="O=\"$BUILD_DIR\" "
    if [[ "$TARGET_TOOLCHAIN" == *"gcc" ]]; then
        CMD+="CLANG_TRIPLE=\"aarch64-linux-gnu-\" "
        CMD+="CROSS_COMPILE=\"aarch64-linux-android-\" "
        CMD+="CROSS_COMPILE_ARM32=\"arm-linux-androidkernel-\" "
        CMD+="CROSS_COMPILE_COMPAT=\"arm-linux-androidkernel-\" "
    fi
    if [[ -n "$1" ]]; then
        CMD+="$1 "
    fi
    CMD+="> /dev/null"

    if [[ "$*" != "-"* ]]; then
        if [[ -z "$1" ]]; then
            LOG "- Building kernel image"
        else
            if [[ "$1" == *"_defconfig" ]]; then
                LOG "- Generating configuration"
            elif [[ "$1" == *"modules_install" ]]; then
                LOG "- Installing modules"
            else
                if [[ "$2" == "-m" ]] || [[ "$2" == "--merge" ]]; then
                    LOG "- Merging ${1/\.config} fragment"
                else
                    LOG "- Building $1"
                fi
            fi
        fi
    fi

    EVAL "$CMD" || return 1
}

COMPARE_KERNEL_VERSION()
{
    _CHECK_NON_EMPTY_PARAM "COMPARISON" "$1" || return 1
    _CHECK_NON_EMPTY_PARAM "VERSION" "$2" || return 1

    local COMPARISON="$1"
    local TARGET_VERSION="$2"
    local KERNEL_VERSION
    local VERSION PATCHLEVEL SUBLEVEL
    local LOWER HIGHER

    KERNEL_VERSION="$(GET_KERNEL_VERSION)" || return 1

    IFS='.' read -r VERSION PATCHLEVEL SUBLEVEL <<< "$TARGET_VERSION"
    TARGET_VERSION="$VERSION.$PATCHLEVEL.$SUBLEVEL"

    LOWER="$(echo -e "$KERNEL_VERSION\n$TARGET_VERSION" | sort -V | head -n1)"
    HIGHER="$(echo -e "$KERNEL_VERSION\n$TARGET_VERSION" | sort -V | tail -n1)"

    if [[ "$COMPARISON" == "newer" ]] || [[ "$COMPARISON" == "higher" ]]; then
        [[ "$KERNEL_VERSION" != "$TARGET_VERSION" ]] && [[ "$HIGHER" == "$KERNEL_VERSION" ]]
    elif [[ "$COMPARISON" == "older" ]] || [[ "$COMPARISON" == "lower" ]]; then
        [[ "$KERNEL_VERSION" != "$TARGET_VERSION" ]] && [[ "$LOWER" == "$KERNEL_VERSION" ]]
    else
        LOGE "Invalid comparison: $COMPARISON"
        return 1
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
        EVAL "rm -f \"$TAR_OUT\"" || return 1
    fi

    EVAL "tar -cf \"$TAR_OUT\" --transform='s|.*/||' ${IMAGES[*]}" || return 1
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
    EVAL "curl -L -o \"$OUTPUT\" \"$URL\"" || return 1
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
        return 1
    fi
}

GET_AOSP_CLANG()
{
    local AOSP_ARCHIVE="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/mirror-goog-main-llvm-toolchain-source"
    local CLANG_URL
    local LATEST_AOSP_CLANG

    # shellcheck disable=SC2119
    LATEST_AOSP_CLANG="$(GET_LATEST_AOSP_CLANG)"
    CLANG_URL="$AOSP_ARCHIVE/$LATEST_AOSP_CLANG.tar.gz"

    if [[ -d "$TMP_DIR" ]]; then
        EVAL "mkdir -p \"$TMP_DIR\""
    fi

    LOG_STEP_IN "- Latest AOSP Clang is ${LATEST_AOSP_CLANG//clang-/}"
    LOG "- Downloading AOSP Clang"
    DOWNLOAD_FILE "$CLANG_URL" "$TMP_DIR/$(basename "$CLANG_URL")" || {
        LOGE "Failed to download latest AOSP Clang"
        EVAL "rm -rf \"$TMP_DIR\""
        EVAL "rm -rf \"$CLANG_DIR\""
        return 1
    }

    if [[ -d "$CLANG_DIR" ]]; then
        EVAL "rm -rf \"$CLANG_DIR\""
    fi
    EVAL "mkdir -p \"$CLANG_DIR\""

    LOG "- Extracting AOSP Clang"
    EVAL "tar -xf \"$TMP_DIR/$(basename "$CLANG_URL")\" -C \"$CLANG_DIR\" && rm \"$TMP_DIR/$(basename "$CLANG_URL")\"" || return 1
    EVAL "touch \"$CLANG_DIR/bin/aarch64-linux-gnu-elfedit\" && chmod +x \"$CLANG_DIR/bin/aarch64-linux-gnu-elfedit\"" || return 1
    EVAL "touch \"$CLANG_DIR/bin/arm-linux-gnueabi-elfedit\" && chmod +x \"$CLANG_DIR/bin/arm-linux-gnueabi-elfedit\"" || return 1

    EVAL "rm -rf \"$TMP_DIR\"" || return 1
    LOG_STEP_OUT
}

GET_KERNEL_VERSION()
{
    if [[ ! -f "$KERNEL_DIR/Makefile" ]]; then
        LOGE "Kernel Makefile was not found: ${KERNEL_DIR//$SRC_DIR\//}"
        return 1
    fi

    awk '
        /^VERSION[[:space:]]*=/     { v=$3 }
        /^PATCHLEVEL[[:space:]]*=/  { p=$3 }
        /^SUBLEVEL[[:space:]]*=/    { s=$3 }
        END { print v "." p "." s }
    ' "$KERNEL_DIR/Makefile"
}

# shellcheck disable=SC2120
GET_LATEST_AOSP_CLANG()
{
    local AOSP_LIST
    local CURRENT_CLANG
    local ATTEMPT=0
    local CURRENT_TAG

    until [[ -n "$AOSP_LIST" ]]; do
        AOSP_LIST="$(curl -s "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+/mirror-goog-main-llvm-toolchain-source")"
        if [[ -z "$AOSP_LIST" ]]; then
            ATTEMPT=$((ATTEMPT + 1))
            if [[ "$ATTEMPT" -ge 5 ]]; then
                LOGE "Failed to fetch AOSP Clang list (5/5)"
                return 1
            fi
            LOG "\033[0;33m! Failed to fetch AOSP Clang list ($ATTEMPT/5)\033[0m"
            sleep 5
        fi
    done

    CURRENT_CLANG="$(printf '%s\n' "$AOSP_LIST" | grep -oP 'href="[^"]*clang-r[0-9]+/' | grep -oP 'clang-r[0-9]+' | sort -V | tail -n1)"

    if [[ "$1" == "--compare" ]]; then
        if [[ -d "$CLANG_DIR" ]]; then
            CURRENT_TAG="$(awk -F'"' '/"tag"/ {print $4}' "$CLANG_DIR/BUILD_INFO")"

            if [[ "${CURRENT_CLANG//clang-/}" != "$CURRENT_TAG" ]]; then
                LOG "\033[0;33m! Newer AOSP Clang is available ($CURRENT_TAG -> ${CURRENT_CLANG//clang-/})\033[0m"
            fi
        else
            LOGW "Toolchain dir does not exist"
        fi
        return 0
    fi

    echo "$CURRENT_CLANG"
}

UPLOAD()
{
    _CHECK_NON_EMPTY_PARAM "ARCHIVE" "$1" || return 1

    local ARCHIVE="$1"
    local ARCHIVE_NAME
    local TAG_NAME
    local FORCE="$3"

    if [[ "$TARGET_KERNEL_URL" != *"github.com"* ]]; then
        LOGE "Uploading is only supported for GitHub sources"
        return 1
    fi

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

    if [[ "$FORCE" != "-f" ]]; then
        if [[ "$ARCHIVE_NAME" == UN1CA_Kernel-* ]]; then
            local VARIANT="${ARCHIVE_NAME##*-}"
            local VARIANT="${VARIANT%.tar}"

            # shellcheck disable=SC2269
            VARIANT="$VARIANT" \
            gh release view "$TAG_NAME" --repo "$TARGET_KERNEL_REPO" --json assets \
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
            gh release view "$TAG_NAME" --repo "$TARGET_KERNEL_REPO" --json assets \
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
