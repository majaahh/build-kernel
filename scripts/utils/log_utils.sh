#!/bin/bash
#
# SPDX-FileCopyrightText: Majaahh
# SPDX-License-Identifier: Apache-2.0
#

# Initial util was taken from https://github.com/salvogiangri/UN1CA/blob/3.1.0/scripts/utils/log_utils.sh#L29-L86

# LOG <message>
# Prints a log message in the build output.
LOG()
{
    local INDENT="${INDENT_LEVEL:=0}"

    echo -e "$(printf "%*s%s" "$INDENT" "" "$1")"
}

# LOGE <message>
# Prints an error log message in the build output.
LOGE()
{
    local RED="\033[0;31m"
    local RESET="\033[0m"

    echo -e "${RED}! ${1}${RESET}" >&2
}

# LOGW <message>
# Prints a warning log message in the build output.
LOGW()
{
    local YELLOW="\033[0;33m"
    local RESET="\033[0m"

    echo -e "${YELLOW}! ${1}${RESET}" >&2
}

# LOG_STEP_IN <bold> <message>
# Increments the output indentation, additionally prints a log message if supplied.
LOG_STEP_IN()
{
    local BOLD
    local RESET="\033[0m"

    if [[ "$1" == "true" ]]; then
        BOLD="\033[1;37m"
        shift
    fi

    if [ "$1" ]; then
        LOG "${BOLD}${1}${RESET}"
    fi

    local INDENT="${INDENT_LEVEL:=0}"
    export INDENT_LEVEL="$((INDENT + 2))"
}

# LOG_STEP_OUT
# Reduces the output indentation.
LOG_STEP_OUT()
{
    local INDENT="${INDENT_LEVEL:=0}"
    if [ "$INDENT_LEVEL" -gt 0 ]; then
        export INDENT_LEVEL=$((INDENT - 2))
    fi
}
