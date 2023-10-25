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

  # Split the full path to the NIfTI file in filename and dirname
  local name_nii=$(basename "${input_nii}")
  local dir_processed=$(dirname "${input_nii}")/mri/

  # Start CAT12 segmentation
  info "  Segmentation start"
  ${SPMROOT}/standalone/cat_standalone.sh \
    -b "${__dir}/tools/cat12/segment.batch" \
    "${input_nii}" || error "CAT12 segmentation failed"

  # Export the variable processed_nii, which contains the path to the result of the CAT12 standalone segmentation
  export processed_nii="${dir_processed}/mwp1${name_nii}"
  if [[ ! -f "${processed_nii}" ]]; then error "Could not find ${processed_nii}."; fi
  info "  Segmentation done"

  # Start smoothing
  info "  Smoothing start"
  ${SPMROOT}/standalone/cat_standalone.sh \
    -b "${__dir}/tools/cat12/smooth.batch" \
    "${processed_nii}" || error "CAT12 smoothing failed"

  # Path to the result of CAT12 standalone smoothing
  local processed_smoothed_nii="${dir_processed}/smwp1${name_nii}"
  if [[ ! -f "${processed_smoothed_nii}" ]]; then error "Could not find ${processed_smoothed_nii}."; fi
  info "  Smoothing done"

  # Estimate the volume
  #
  # 1. Subtract the mean template from the subject's pre-processed smoothed volume
  # 2. Voxel-wise divide the data from 1. by the standard deviation template, which yields the voxel-wise z-map
  # 3. Voxel-wise multiply the data from 3. by the gray matter mask (essentially to mask anything non-grey-matter, which is multiplied by 0)
  #  
  info "  zmap generation start"
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
  if [[ ! -f "${zmap_normalized}" ]]; then error "Could not find ${zmap_normalized}."; fi
  info "  zmap generation done"

  # Transform back to subject space
  info "  Inverse transformation start"
  ${SPMROOT}/standalone/cat_standalone.sh \
    -b "${__dir}/tools/cat12/deformation.batch" \
    -a1 "{'${dir_processed}/iy_${name_nii}'}" \
    "${zmap_normalized}" || error "Transformation to subject space failed"

  # Export the variable zmap, which contains the path and filename to the generated zmap for the subject
  export zmap="${dir_processed}/wsmwp1$(echo ${name_nii} | sed -e 's/\.nii$/_zmap.nii/I')"
  if [[ ! -f "${zmap}" ]]; then error "Could not find ${zmap}."; fi
  info "  Inverse transformation done"
  
  info "estimateVolumechanges done"
}

# Export the function to be used when sourced, but do not allow the script to be called directly
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  export -f estimateVolumechanges
else
  echo "estimageVolumechanges is an internal function and cannot be called directly."
  exit 1
fi
