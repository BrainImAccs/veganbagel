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

  # Start CAT12 segmentation
  ${SPMROOT}/standalone/cat_standalone.sh \
    -b "${__dir}/tools/cat12/segment.batch" \
    "${input_nii}" || error "CAT12 segmentation failed"

  # Path to the result of CAT12 standalone segmentation
  local processed_nii=$(dirname "${input_nii}")/mri/mwp1$(basename "${input_nii}")
  if [[ ! -f "${processed_nii}" ]]; then error "Could not find ${processed_nii}."; fi

  # Start CAT12 smoothing
  ${SPMROOT}/standalone/cat_standalone.sh \
    -b "${__dir}/tools/cat12/smooth.batch" \
    "${processed_nii}" || error "CAT12 smoothing failed"

  # Path to the result of CAT12 standalone smoothing
  local processed_smoothed_nii=$(dirname "${input_nii}")/mri/smwp1$(basename "${input_nii}")
  if [[ ! -f "${processed_smoothed_nii}" ]]; then error "Could not find ${processed_smoothed_nii}."; fi

  # Estimate the volume
  #
  # 1. Subtract the mean template from the subject's pre-processed smoothed volume
  # 2. Voxel-wise divide the data from 1. by the standard deviation template, which yields the voxel-wise z-map
  # 3. Voxel-wise multiply the data from 3. by the gray matter mask (essentially to mask anything non-grey-matter, which is multiplied by 0)
  #  
  local mean_template="${templates}/${age}${sex}smwp1_mean.nii.gz"
  local std_template="${templates}/${age}${sex}smwp1_std.nii.gz"

  # Path to normalized result
  local zmap_normalized=$(echo "${processed_smoothed_nii}" | sed -e 's/\.nii$/_zmap.nii/I')

  # Volume estimation using fslmaths instead of SPM12, which allows to use compressed templates
  ${fslmaths} \
    ${processed_smoothed_nii} \
    -sub ${mean_template} \
    -div ${std_template} \
    -mul ${gm_mask} \
    ${zmap_normalized}

  # Transform back to subject space
  local inverse_transformation_field=$(dirname "${input_nii}")/mri/iy_$(basename "${input_nii}")
  ${SPMROOT}/standalone/cat_standalone.sh \
    -b "${__dir}/tools/cat12/deformation.batch" \
    -a1 "${inverse_transformation_field}" \
    "${zmap_normalized}" || error "Transformation to subject space failed"

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
