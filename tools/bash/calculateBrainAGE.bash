#!/usr/bin/env bash
#
# Uses brainage_estimation (https://github.com/juaml/brainage_estimation) to calculate the Brain Age Gap Estimation (BrainAGE)
#
# More, S. et al. Brain-age prediction: A systematic comparison of machine learning workflows. NeuroImage 270, 119947 (2023).
# https://doi.org/10.1016/j.neuroimage.2023.119947
#

function calculateBrainAGE {
  # Input greyscale structural T1w images in the NIfTI format
  local input_mwp1=${1}
  # Desired output directory
  local output_dir="${2}"
  # Duration between patientBirthDate and studyDate in decimal years
  local age_years_dec="${3}"

  info "calculateBrainAGE start"

  # Use the anat_qc Python script to overlay QC onto structural images and export JPEG files
  local __dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  (
    eval "$(micromamba shell hook --shell bash)" &&
    micromamba activate brainage_estimation && \
    python3 "${__dir}/../../external/brainage_estimation/codes/predict_age.py" \
      --features_path "${output_dir}/features" \
      --subject_filepaths <(echo "${input_mwp1}") \
      --output_path "${output_dir}" \
      --mask_file "${__dir}/../../external/brainage_estimation/masks/brainmask_12.8.nii" \
      --smooth_fwhm 4 \
      --resample_size 4 \
      --model_file "${__dir}/../../external/brainage_estimation/trained_models/1_4sites.S4_R4_pca.gauss.models"
  ) > "${output_dir}/brainage_estimation_log" || error "calculateBrainAGE failed"

  # Export the variable brainage_estimation, which contains the prediction of the model
  export brainage_estimation=$(tail -n1 "${output_dir}/brainage_estimation_log" | sed -e 's/0\s\+//')
  echo ${brainage_estimation} > "${output_dir}/brainage_estimation"
  # Expport the variable BrainAGE, which contains the Brain Age Gap Estimation
  export BrainAGE=$(echo "${brainage_estimation} - ${age_years_dec}" | bc -l)
  echo ${BrainAGE} > "${output_dir}/BrainAGE"

  info "calculateBrainAGE done"
}

# Export the function to be used when sourced, but do not allow the script to be called directly
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  export -f calculateBrainAGE
else
  echo "calculateBrainAGE is an internal function and cannot be called directly."
  exit 1

  # For debugging purposes it might be handy to call qcOverlay.bash directly.
  #calculateBrainAGE "${@}"
  #exit ${?}
fi
