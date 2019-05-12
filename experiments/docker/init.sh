#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail
set -o errtrace


# portable version of abspath
function abspath() {
    local path="${*}"
    
    if [[ -d "${path}" ]]; then
        echo "$( cd "${path}" >/dev/null && pwd )"
    else
        echo "$( cd "$( dirname "${path}" )" >/dev/null && pwd )/$(basename "${path}")"
    fi
}

function script_dir() {
  echo "$(dirname $(abspath ${BASH_SOURCE[0]}))"
}

function log() {
    echo -e "${@}" >&2
}

function debug_log() {
    if [[ -n "${DEBUG:-}" ]]; then
        echo -e "DEBUG: ${@}" >&2
    fi
}

function log_allowed_environment_config_properties() {
    if [[ -n ${DEBUG:-} ]]; then
        debug_log "\nAllowed config properties..."
        for param in ${gek8s_allowed_config_properties}; do    
            debug_log "${param} => ${!param}"
        done
        debug_log "DONE"
    fi
}

function error_log() {
    echo -e "ERROR: ${@}" >&2
}

function error_trap() {
    error_log "Error at line ${BASH_LINENO[1]} running the following command:\n\n\t${BASH_COMMAND}\n\n"
    error_log "Stack trace:"
    for (( i=1; i < ${#BASH_SOURCE[@]}; ++i)); do
        error_log "$(printf "%$((4*$i))s %s:%s\n" " " "${BASH_SOURCE[$i]}" "${BASH_LINENO[$i]}")"
    done
    exit 2
}

trap error_trap ERR

function usage_error() {
    if [[ $# > 0 ]]; then
        echo -e "ERROR: ${@}" >&2
    fi
    help
    exit 2
}

# show help
function help() {
    local script_name=$(basename "$0")
    echo -e "\nUsage: ${script_name}  <EXPERIMENTS_BASE_HDFS_PATH> <CONFIGURATION_FILE_PATH>">&2
}

# check arguments
if [[ $# -lt 2 ]]; then
    usage_error
fi

# set and create the experiment path on HDFS
EXPERIMENTS_BASE_HDFS_PATH="${1}"
hdfs dfs -mkdir -p ${EXPERIMENTS_BASE_HDFS_PATH}
if [[ $? -ne 0 ]]; then
    error_log "Experiment data folder creation failed!"
    exit 2
fi

# set the config file and check if exists 
CONFIGURATION_FILE_PATH="${2}"
if [[ ! -f "${CONFIGURATION_FILE_PATH}" ]]; then
    error_log "Experiment configuration file '${CONFIGURATION_FILE_PATH}' doesn't exists!"
    exit 2
fi

# intialize 
python3 app.py --debug -f "${CONFIGURATION_FILE_PATH}" initialize