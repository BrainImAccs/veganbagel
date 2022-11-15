#!/usr/bin/env bash
#
# Traverse a directory full of zmaps calculated with differently "aged" templates and calculate 
# statistics to estimate BrainAGE.
#
#

function estimateBrainAGE {
  # The directory with all the zmaps
  local zmaps_dir="${1}"
  # The gray matter mask (ideally the mask used in estimateVolumechanges)
  local mask="${2}"
  # Age of the subject/patient
  local age="${3}"
  # Desired output directory
  local output_dir="${4}"

  info "estimateBrainAGE start"

  # Use the anat_qc Python script to overlay QC onto structural images and export JPEG files
  local __dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  "${__dir}/../python/estimateBrainAGE.py" \
    "${zmaps_dir}" \
    "${mask}" \
    "${age}" \
    "${output_dir}" || error "estimateBrainAGE failed"

  info "estimateBrainAGE done"
}

# Export the function to be used when sourced, but do not allow the script to be called directly
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  export -f estimateBrainAGE
else
  echo "estimateBrainAGE is an internal function and cannot be called directly."
  exit 1

  # For debugging purposes it might be handy to call estimateBrainAGE.bash directly.
  #export __dir="$(cd "$(dirname "${BASH_SOURCE[${__b3bp_tmp_source_idx:-0}]}")" && pwd)/../../"
  #. ${__dir}/setup.veganbagel.bash
  #estimateBrainAGE "${@}"
  #exit ${?}
fi
