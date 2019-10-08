#!/usr/bin/env bash
#
# A wrapper for the estimateVolumechanges MATLAB function
#

function estimateVolumechanges {
  # NIfTI input file
  local input_nii="${1}"
  # Directory of the normative cohort volume templates
  local templates="${2}"
  # Age of the current subject
  local age="${3}"
  # Sex of the current subject
  local sex="${4}"

  info "estimageVolumechanges start"

  # Start the estimateVolumechanges MATLAB script
  ( \
    cd "${__dir}/tools/matlab/estimateVolumechanges/"
    MATLABPATH=${spm12} ${matlab} \
      -nodesktop \
      -r "try estimateVolumechanges('${input_nii}', '${templates}', '${sex}', ${age}); catch; exit(1); end; exit;" \
  ) || error "estimateVolumechanges failed"
  
  # Export the variable zmap, which contains the path and filename to the generated zmap for the subject
  export zmap=$(echo $(dirname "${input_nii}")/w$(basename "${input_nii}" | sed -e 's/\.nii$/_zmap.nii/I'))

  info "estimateVolumechanges done"
}

# Export the function to be used when sourced, but do not allow the script to be called directly
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  export -f estimateVolumechanges
else
  echo "estimageVolumechanges is an internal function and cannot be called directly."
  exit 1
fi
