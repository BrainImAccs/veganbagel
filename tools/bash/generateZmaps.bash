#!/usr/bin/env bash
#
# Genrate z-score maps (zmaps):
#
# 1. Subtract the mean template from the subject's pre-processed smoothed volume
# 2. Voxel-wise divide the data from 1. by the standard deviation template, which yields the voxel-wise z-map
# 3. Voxel-wise multiply the data from 3. by the gray matter mask (essentially to mask anything non-grey-matter, which is multiplied by 0)
#
# This will be done for all available age- and sex-matched templates.
# TODO: Add a switch to calculate only a single zmap
#

function getZmapNormalizedPath {
   echo ${output_dir}/$(basename "$1" | sed -e "s/\.nii$/_${2}${3}_zmap.nii/I")
}

function generateZmaps {
  # NIfTI input file (processed by CAT12 and smoothed)
  local processed_smoothed_nii="${1}"
  # Output directory
  local output_dir="${2}"
  # Directory of the normative cohort volume templates
  local templates="${3}"
  # Age of the current subject
  local age="${4}"
  # Sex of the current subject
  local sex="${5}"

  # Find minimum and maximum age in the given templates
  local min_template_age=$(find "${templates}" -name "*${sex}smwp1_mean.nii.gz" -printf "%f\n" | sort -n | cut -d"${sex}" -f1 | head -n1)
  local max_template_age=$(find "${templates}" -name "*${sex}smwp1_mean.nii.gz" -printf "%f\n" | sort -n | cut -d"${sex}" -f1 | tail -n1)

  for template_age in $(seq ${min_template_age} ${max_template_age}); do
    # Select age- and sex-specific template
    local mean_template="${templates}/${template_age}${sex}smwp1_mean.nii.gz"
    local std_template="${templates}/${template_age}${sex}smwp1_std.nii.gz"

    # Path to computed zmap
    local zmap_normalized=$(getZmapNormalizedPath "${processed_smoothed_nii}" ${template_age} ${sex})

    # Compute zmap using fslmaths in parallel
    # (instead of SPM12. FSL allows to use compressed templates.)
    LANG=C ${sem} -j+0 ${fslmaths} \
      "${processed_smoothed_nii}" \
      -sub "${mean_template}" \
      -div "${std_template}" \
      -mul "${gm_mask}" \
      "${zmap_normalized}"
  done

  sem --wait

  # Check, that each zmap was generated
  for template_age in $(seq ${min_template_age} ${max_template_age}); do
    local zmap_normalized=$(getZmapNormalizedPath "${processed_smoothed_nii}" ${template_age} ${sex})
    if [[ ! -f "${zmap_normalized}" ]]; then error "Could not find ${zmap_normalized}."; return 1; fi
  done

  return 0
}

# Export the function to be used when sourced, but do not allow the script to be called directly
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  export -f generateZmaps
else
  echo "generateZmaps is an internal function and cannot be called directly."
  exit 1
fi
