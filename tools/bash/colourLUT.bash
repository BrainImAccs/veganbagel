#!/usr/bin/env bash
#
# Takes greyscale input images (in this case the TIFF files generated from the zmap) and uses a colour lookup
# table (LUT) to colour them. Then, these images are merged on top of the structural greyscale images in a
# semi-transparent fashion. 
#
# In setup.veganbagel.sh a threshold can be defined below which full transparency will be enforced (e.g.
# everything 2.5 standard deviations from the mean will be transparent). Also, a maximum threshold is used
# above which everything is solidly coloured (e.g. everything >10 standard deviations from the mean).
#
# A legend/scale will be generated and displayed in the top left of the image.
#

function colourLUT {
  # Input TIFF files (i.e. greyscale structural T1w images generated from the NIfTI file)
  local input_nii="${1}"
  # Input greyscale z-maps, already converted to TIFF
  local input_zmap="${2}"
  # Desired output directory
  local output_dir="${3}"
  # Reference DICOM (for window center/width)
  local ref_dcm="${4}"

  info "colorLUT start"

  # Source the getDCMTag function, if necessary
  if [[ ! "$(type -t getDCMTag)" = "function" ]]; then
    source "${__dir}/../../tools/bash/getDCMTag.bash"
  fi

  # Use the nii_to_tif Python script to convert a NIfTI file into TIFF images
  local __dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  "${__dir}/../python/anat_and_zmap_lut.py" \
    --cool ${colours_negative_lut} \
    --hot ${colours_positive_lut} \
    --zmin ${z_min} \
    --zmax ${z_max} \
    "${input_nii}" \
    "${input_zmap}" \
    "${output_dir}" || error "convertNII2TIFF failed"

  info "colourLUT done"
}

# Export the function to be used when sourced, but do not allow the script to be called directly
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  export -f colourLUT
else
  echo "colourLUT is an internal function and cannot be called directly."
  exit 1

  # For debugging purposes it might be handy to call colourLUT.bash directly.
  #export __dir="$(cd "$(dirname "${BASH_SOURCE[${__b3bp_tmp_source_idx:-0}]}")" && pwd)/../../"
  #. ${__dir}/setup.veganbagel.bash
  #colourLUT "${@}"
  #exit ${?}
fi
