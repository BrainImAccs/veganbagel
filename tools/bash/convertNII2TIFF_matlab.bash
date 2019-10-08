#!/usr/bin/env bash
#
# A wrapper for the nii2tiff MATLAB script to convert a NIfTI file into TIFF images
#

function convertNII2TIFF_matlab {
  # Input NIfTI file
  local input_nii="${1}"
  # Desired output directory
  local output="${2}"

  info "convertNII2TIFF start"

  # Use the nii2tiff MATLAB script to convert a NIfTI file into TIFF images
  ( \
    cd "${__dir}/tools/matlab/nii2tiff/"
    ${matlab} \
      -nodesktop \
      -r "try nii2tiff('${input_nii}', '${output}'); catch; exit(1); end; exit;" \
  ) || error "convertNII2TIFF_matlab failed"

  info "convertNII2TIFF_matlab done"
}

# Export the function to be used when sourced, but do not allow the script to be called directly
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  export -f convertNII2TIFF_matlab
else
  echo "convertNII2TIFF_matlab is an internal function and cannot be called directly."
  exit 1
fi
