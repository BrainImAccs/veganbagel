#!/usr/bin/env bash

### Acknowledgements
##############################################################################
#
# This script is based on a template by BASH3 Boilerplate v2.3.0
# http://bash3boilerplate.sh/#authors
#
# The BASH3 Boilerplate is under the MIT License (MIT) and is
# Copyright (c) 2013 Kevin van Zonneveld and contributors


### Command line options
##############################################################################

# shellcheck disable=SC2034
read -r -d '' __usage <<-'EOF' || true # exits non-zero when EOF encountered
  -i --input [arg]    Directory containing the DICOM input files. Optional. If not supplied, container will start in DICOM listening/queueing mode.
  -a --age [arg]      Subject's age. Optional. Otherwise extracted from the DICOMs. Ignored in daemon mode.
  -s --sex [arg]      Subject's sex. Optional. Otherwise extracted from the DICOMs. Ignored in daemon mode.
  -v                  Enable verbose mode, print script as it is executed.
  -d --debug          Enables debug mode.
  -h --help           This page.
EOF

# shellcheck disable=SC2034
read -r -d '' __helptext <<-'EOF' || true # exits non-zero when EOF encountered
 This scripts takes a directory with DICOM files of a 3D T1w structural MRI brain
 scan and generates a map of regional volume changes in relation to an age- and
 sex-matched cohort of pre-processed normal scans.

 When no input is specified, the container will start in daemon mode and listen
 for incoming DICOM connections.
EOF

# shellcheck source=b3bp.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../BrainSTEM/tools/b3bp.bash"


### Command-line argument switches
##############################################################################

# help mode
if [[ "${arg_h:?}" = "1" ]]; then
  # Help exists with code 1
  help "Help using ${0}"
fi


### Validation. Error out if the things required for your script are not present
##############################################################################

[[ "${LOG_LEVEL:-}" ]] || error "Cannot continue without LOG_LEVEL."

# Check if the input/source directory exists
if [[ ! "${arg_i:-}" ]]; then
  info "Starting daemon mode..."
  bash "${__dir}/../../BrainSTEM/incoming/incoming.bash" &
  bash "${__dir}/../../BrainSTEM/received/queue.bash" &
  wait
fi 

# Get absolute path of the input directory (just in case) and exit if directory is empty
source_dir=$(realpath "${arg_i}")
if [[ "x"$(ls -1A "${source_dir}") = "x" ]]; then
  error "Directory \"${source_dir}\" is empty."
fi 

sex=""
if [[ "${arg_s:?}" ]]; then
  if [[ ! "${arg_s}" =~ ^(M|F)$ ]]; then
    error "Subject's sex has to be either F or M."
  else
    sex="--sex ${arg_s}"
fi

age=""
if [[ "${arg_a:?}" ]]; then
  if [[ ! "${arg_a}" =~ ^[0-9]+$ ]]; then
    error "Subject's age has to be an integer."
  else
    age="--age ${arg_a}"
fi

verbose=""
if [[ "${arg_v:?}" = "1" ]]; then
  verbose="-v"
fi

debug=""
if [[ "${arg_d:?}" = "1" ]]; then
  verbose="--debug"
fi

../../veganbagel.bash \
  --input "${source_dir}" \
  ${sex} \
  ${age} \
  ${verbose} \
  ${debug} \
  --keep-workdir \
  --no-pacs
