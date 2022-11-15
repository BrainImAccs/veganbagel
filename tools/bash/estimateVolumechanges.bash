#!/usr/bin/env bash
#
# A wrapper for the estimateVolumechanges MATLAB function
#

function estimateVolumechanges {
  # Original NIfTI input file
  local input_nii="${1}"
  # Processed and smoothed NIfTI input file
  local processed_smoothed_nii="${2}"
  # Output and working directory
  local output_dir=$(echo ${3} | sed -e 's%/$%%')
  # Directory of the calculated age- and sex-specific template(s)
  local zmaps="${4}"
  # Age of the current subject
  local age="${5}"
  # Sex of the current subject
  local sex="${6}"
  # Reference DICOM
  local ref_dcm="${7}"

  # Source the colourLUT function, if necessary
  if [[ ! "$(type -t colourLUT)" = "function" ]]; then
    source "${__dir}/tools/bash/colourLUT.bash"
  fi

  # Source the qcOverlay function, if necessary
  if [[ ! "$(type -t qcOverlay)" = "function" ]]; then
    source "${__dir}/tools/bash/qcOverlay.bash"
  fi

  info "estimateVolumechanges start"

  # Supress output of CAT12 unless -d (debug mode) has been specified
  local redirect=""
  if [[ "$LOG_LEVEL" == "4" ]]; then
    redirect=/dev/stderr
  else
    redirect=/dev/null
  fi

  # Split the full path to the NIfTI file in filename and dirname
  local name_input_nii=$(basename "${input_nii}")
  local name_processed_smoothed_nii=$(basename "${processed_smoothed_nii}")
  local dir_processed_smoothed=$(dirname "${processed_smoothed_nii}")

  # Define path to the age- and sex-specific zmap for the current subject
  local zmap_normalized=${zmaps}/$(echo "${name_processed_smoothed_nii}" | sed -e "s/\.nii$/_${age}${sex}_zmap.nii/I")

  # Transform back to subject space
  info "  Inverse transformation start"
  "${SPMROOT}/standalone/cat_standalone.sh" \
    -b "${__dir}/tools/cat12/deformation.batch" \
    -a1 "{'${dir_processed_smoothed}/iy_${name_input_nii}'}" \
    "${zmap_normalized}" 1> ${redirect} || error "Transformation to subject space failed"

  local zmap="${zmaps}"/wsmwp1$(echo ${name_input_nii} | sed -e "s/\.nii$/_${age}${sex}_zmap.nii/I")
  if [[ ! -f "${zmap}" ]]; then error "Could not find ${zmap}."; return 1; fi
  info "  Inverse transformation done"

  ### Generate and apply colour lookup tables to the zmap, then merge with the original scan
  mkdir "${output_dir}-cmap-out"
  if ! colourLUT "${input_nii}" "${zmap}" "${output_dir}-cmap-out" "${ref_dcm}"; then
    error "colorLUT failed"
    return 1
  fi

  ### Generate and apply colour lookup tables to the zmap, then merge with the original scan
  mkdir "${output_dir}-qc-out"
  local qc="${dir_processed_smoothed}/p0${name_input_nii}"
  if ! qcOverlay "${input_nii}" "${qc}" "${output_dir}-qc-out" "${ref_dcm}"; then
    error "qcOverlay failed"
    return 1
  fi
  
  info "estimateVolumechanges done"

  return 0
}

# Export the function to be used when sourced, but do not allow the script to be called directly
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  export -f estimateVolumechanges
else
  echo "estimateVolumechanges is an internal function and cannot be called directly."
  exit 1
fi
