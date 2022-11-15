#!/usr/bin/env bash
#
# Takes quality control (QC) input images and merge them on top of the structural greyscale images using
# transparency to highlight the segmented areas.
#

function qcOverlay {
  # Input greyscale structural T1w images in the NIfTI format
  local input_nii="${1}"
  # Input quality controly (QC) image volume in the NIfTI format
  local input_qc="${2}"
  # Desired output directory
  local output_dir="${3}"
  # Reference DICOM (for window center/width)
  local ref_dcm="${4}"

  info "qcOverlay start"

  # Use the anat_qc Python script to overlay QC onto structural images and export JPEG files
  local __dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  "${__dir}/../python/anat_qc.py" \
    "${input_nii}" \
    "${input_qc}" \
    "${output_dir}" || error "anat_qc failed"

  info "qcOverlay done"
}

# Export the function to be used when sourced, but do not allow the script to be called directly
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  export -f qcOverlay
else
  echo "qcOverlay is an internal function and cannot be called directly."
  exit 1

  # For debugging purposes it might be handy to call qcOverlay.bash directly.
  #export __dir="$(cd "$(dirname "${BASH_SOURCE[${__b3bp_tmp_source_idx:-0}]}")" && pwd)/../../"
  #. ${__dir}/setup.veganbagel.bash
  #qcOverlay "${@}"
  #exit ${?}
fi
