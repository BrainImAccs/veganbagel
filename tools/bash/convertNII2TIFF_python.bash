#!/usr/bin/env bash
#
# A wrapper for a python script to convert a NIfTI file into TIFF images
#

function convertNII2TIFF_python {
  # Input NIfTI file
  local input_nii="${1}"
  # Desired output directory
  local output="${2}"

  info "convertNII2TIFF_python start"

  # Use the nii_to_tif Python script to convert a NIfTI file into TIFF images
  "${__dir}/tools/python/nii_to_tif.py" \
    "${input_nii}" \
    "${output}" || error "convertNII2TIFF_python failed"

  info "convertNII2TIFF_python done"
}

# Export the function to be used when sourced, but do not allow the script to be called directly
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  export -f convertNII2TIFF_python
else
  echo "convertNII2TIFF_python is an internal function and cannot be called directly."
  exit 1
fi
