#!/usr/bin/env bash
#
# Process (i.e. segment gray matter) the original NIfTI using CAT12 and smooth the result
#

function catSegmentSmooth {
  # NIfTI input file
  local input_nii="${1}"

  info "catSegmentSmooth start"

  # Supress output of CAT12 unless -d (debug mode) has been specified
  local redirect=""
  if [[ "$LOG_LEVEL" == "4" ]]; then
    redirect=/dev/stderr
  else
    redirect=/dev/null
  fi

  # Split the full path to the NIfTI file in filename and dirname
  local name_nii=$(basename "${input_nii}")
  local dir_processed=$(dirname "${input_nii}")/mri/

  # Start CAT12 segmentation
  info "  Segmentation start"
  ${SPMROOT}/standalone/cat_standalone.sh \
    -b "${__dir}/tools/cat12/segment.batch" \
    "${input_nii}" 1> $redirect || error "CAT12 segmentation failed"

  # Path to the result of CAT12 standalone segmentation
  local processed_nii="${dir_processed}/mwp1${name_nii}"
  if [[ ! -f "${processed_nii}" ]]; then error "Could not find ${processed_nii}."; return 1; fi
  info "  Segmentation done"

  # Start smoothing
  info "  Smoothing start"
  ${SPMROOT}/standalone/cat_standalone.sh \
    -b "${__dir}/tools/cat12/smooth.batch" \
    "${processed_nii}" 1> ${redirect} || error "CAT12 smoothing failed"

  # Return the path to the result of CAT12 standalone smoothing
  local processed_smoothed_nii="${dir_processed}/smwp1${name_nii}"
  if [[ ! -f "${processed_smoothed_nii}" ]]; then error "Could not find ${processed_smoothed_nii}."; return 1; fi
  echo ${processed_smoothed_nii}

  info "  Smoothing done"
  
  info "catSegmentSmooth done"

  return 0
}

# Export the function to be used when sourced, but do not allow the script to be called directly
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  export -f catSegmentSmooth
else
  echo "catSegmentSmooth is an internal function and cannot be called directly."
  exit 1
fi
