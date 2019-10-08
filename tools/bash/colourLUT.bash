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
  local input_dir="${1}"
  # Input greyscale z-maps, already converted to TIFF
  local input_dir_zmap="${2}"
  # Desired output directly
  local output_dir="${3}"
  # Reference DICOM file
  local ref_dcm="${4}"

  info "colourLUT start"

  # Bit-depth of the LUT to be generated
  local depth=16
  # ... which is that number of pixels
  local pixels=65536

  # Get the number of colours in the "negative", i.e. below mean, i.e. "atrophied voxels" lookup table by counting the lines
  local colours_negative_no=$(cat "${colours_negative_lut}" | wc -l | cut -d' ' -f1)
  # Convert the colours into a format to be used later by ImageMagick
  # Note: The order of the LUT is reverted to account for the negative/below the mean aspect
  local colours_negative=$(cat "${colours_negative_lut}" | tac | while IFS=',' read r g b; do echo -n "'xc:icc-color(rgb, ${r}, ${g}, ${b})' "; done)
  # This colour (first line of the lookup table) will be used for every voxel smaller -${z_max} from setup.veganbagel.sh
  local othercolours_negative=$(head -n1 "${colours_negative_lut}" | while IFS=',' read r g b; do echo -n "'xc:icc-color(rgb, ${r}, ${g}, ${b})' "; done)

  # Get the number of colours in the "positive", i.e. above mean, i.e. "hypertrophied voxels" lookup table by counting the lines
  local colours_positive_no=$(cat "${colours_positive_lut}" | wc -l | cut -d' ' -f1)
  # Convert the colours into a format to be used later by ImageMagick
  local colours_positive=$(cat "${colours_positive_lut}" | while IFS=',' read r g b; do echo -n "'xc:icc-color(rgb, ${r}, ${g}, ${b})' "; done)
  # This colour (last line of the lookup table) will be used for every voxel greater than ${z_max} from setup.veganbagel.sh
  local othercolours_positive=$(tail -n1 "${colours_positive_lut}" | while IFS=',' read r g b; do echo -n "'xc:icc-color(rgb, ${r}, ${g}, ${b})' "; done)

  # We need a colour not in the lookup table for the center bit of the scale
  # Every voxel coloured in this colour (i.e. -${zmin} < mean < ${z_min}, see setup.veganbagel.sh) will be transparent later.
  local center_colour="xc:green"
  local center_colour_no=$(echo "($z_min * 2 * 1000) + 1" | bc)
  local pixels_lut_one_side_no=$(echo "($z_max - $z_min) * 1000" | bc)

  local center_colours="$colours_negative $center_colour $colours_positive"
  local center_colours_no=$(echo "$colours_negative_no + $center_colour_no + $colours_positive_no" | bc)
  local othercolours_no=$(echo ${pixels} - ${center_colours_no} | bc)
  local pixelstop_no=$(echo "((${othercolours_no} - 1) / 2) - 1" | bc)
  local pixelsbottom_no=$(echo "((${othercolours_no} - 1) / 2) + 1" | bc)
  local pixelstotal_no=$(echo "${pixelstop_no} + ${center_colours_no} + ${pixelsbottom_no}" | bc)

  # Folder for the colour lookup tables
  mkdir "${output_dir}/clut"

  # In the next steps a 1-pixel-wide colour lookup table (image) is generated to be later used to colour the zmap
  #
  cmd="${convert} -depth ${depth} \
    ${othercolours_negative} \
    -resize ${pixelstop_no}x1\! -rotate 90 '${output_dir}/clut/negative_other.tiff'"
  eval $cmd

  cmd="${convert} -depth ${depth} \
    ${colours_negative} \
    +append -resize $(echo ${pixels_lut_one_side_no} | bc)x1\! -rotate 90 '${output_dir}/clut/negative_colour.tiff'"
  eval $cmd

  cmd="${convert} -depth ${depth} \
    ${center_colour} \
    +append -resize ${center_colour_no}x1\! -rotate 90 '${output_dir}/clut/center.png'"
  eval $cmd

  cmd="${convert} -depth ${depth} \
    ${colours_positive} \
    +append -resize $(echo "${pixels_lut_one_side_no}" | bc)x1\! -rotate 90 '${output_dir}/clut/positive_colour.tiff'"
  eval $cmd

  cmd="${convert} -depth ${depth} \
    ${othercolours_positive} \
    +append -resize ${pixelsbottom_no}x1\! -rotate 90 '${output_dir}/clut/positive_other.tiff'"
  eval $cmd

  # Combine the bits of the colour lookup table into a single image
  ${convert} \
    -depth ${depth} \
    "${output_dir}/clut/negative_other.tiff" \
    "${output_dir}/clut/negative_colour.tiff" \
    "${output_dir}/clut/center.png" \
    "${output_dir}/clut/positive_colour.tiff" \
    "${output_dir}/clut/positive_other.tiff" \
    -append \
    "${output_dir}/clut/clut.tiff"

  # Generation of the legend to be shown in the top left of the resulting image
  #
  local cmd="${convert} -depth ${depth} \
    ${colours_positive} \
    +append -resize $(echo "(${pixels_lut_one_side_no}) / ${legend_height_shrink_factor}" | bc)x${legend_width_max}\! -rotate 270 '${output_dir}/clut/legend_top.tiff'"
  eval $cmd

  local cmd="${convert} -depth ${depth} \
    ${center_colour} \
    +append -resize $(echo "${center_colour_no} / ${legend_height_shrink_factor}" | bc)x${legend_width_max}\! -rotate 90 '${output_dir}/clut/legend_center.tiff'"
  eval $cmd

  local cmd="${convert} -depth ${depth} \
    ${colours_negative} \
    +append -resize $(echo "(${pixels_lut_one_side_no}) / ${legend_height_shrink_factor}" | bc)x${legend_width_max}\! -rotate 270 '${output_dir}/clut/legend_bottom.tiff'"
  eval $cmd

  # The image width of the reference DICOM file is established. The legend width will be 7% of that.
  local width_dcm=$(${identify} -format "%[fx:w]" ${ref_dcm})
  local legend_width=$(LANG=C printf "%.0f" $(echo "$width_dcm * 0.07" | bc))

  # Combine the bits of the legend and make the center colour transparent
  ${convert} \
    -depth ${depth} \
    "${output_dir}/clut/legend_top.tiff" \
    "${output_dir}/clut/legend_center.tiff" \
    "${output_dir}/clut/legend_bottom.tiff" \
    -append \
    -fuzz 0.012% -transparent $(echo ${center_colour} | sed -e 's/^xc://') \
    "${output_dir}/clut/legend_colours.tiff"

  # Place text labels on top of the legend
  # Note: The legend will be mirrored (flop'ed) to later maintain radiological orientation
  ${convert} \
    "${output_dir}/clut/legend_colours.tiff" \
    -gravity north  -font TeXGyreHeros -pointsize 10 -fill black -annotate +0+0 "+${z_max}" \
    -gravity center -font TeXGyreHeros -pointsize 10 -fill white -annotate +1-1 '0' \
    -gravity south  -font TeXGyreHeros -pointsize 10 -fill black -annotate +0+0 "-${z_max}" \
    -flop \
    -resize ${legend_width}\> \
    "${output_dir}/clut/legend.tiff"

  # Some more output directories
  mkdir "${output_dir}/tiff" "${output_dir}/jpg"

  # For every zmap TIFF...
  # TODO: Use GNU parallel's sem to parallelize the loop
  for tiff in "${input_dir_zmap}"/*; do
    # Colour code the zmap using the lookup table
    ${convert} \
      -depth ${depth} \
      "${tiff}" \
      -rotate -90 \
      "${output_dir}/clut/clut.tiff" \
      -clut "${output_dir}/clut/clutted.tiff"

    # Make the "center colour" transparent
    ${convert} \
      -depth ${depth} \
      "${output_dir}/clut/clutted.tiff" \
      -fuzz 0.013% -transparent $(echo ${center_colour} | sed -e 's/^xc://') \
      "${output_dir}/clut/clutted_center_transparent.tiff"

    # Merge the coloured zmap with the original structural image from ${input_dir}
    # (we're relying on the filenames being the same)
    # 
    # While merging, apply a bit of transparency to the colour coded zmap
    ${convert} \
      -depth ${depth} \
      "${input_dir}/$(basename ${tiff})" \
      "${output_dir}/clut/clutted_center_transparent.tiff" \
      -compose dissolve -define compose:args=75,100 -composite "${output_dir}/clut/clutted_center_transparent_merged.tiff"

    # Add the legend
    # Noted the already mirrored legend will be added to the top right (with a 10% margin), so that it will appear
    # on the top left after mirroring the whole image in the next step in order to maintain radiological orientation
    ${composite} \
      -depth ${depth} \
      -gravity northeast \
      -geometry +10%+10% \
      "${output_dir}/clut/legend.tiff" \
      "${output_dir}/clut/clutted_center_transparent_merged.tiff" \
      "${output_dir}/tiff/$(basename ${tiff})"

    # In the last step we generate a mirrored (see above) full-quality JPG and add the text "NOT FOR DIAGNOSTIC USE"
    jpg="${output_dir}/jpg/$(echo $(basename $tiff) | sed -e 's/\.tiff$/.jpg/')"
    ${convert} \
      "${output_dir}/tiff/$(basename ${tiff})" \
      -flop \
      -quality 100 \
      -gravity south -font TeXGyreHeros -pointsize 9 -fill white -annotate +1+0 "NOT FOR DIAGNOSTIC USE" \
      "${jpg}"
  done

  info "colourLUT done"
}

# Export the function to be used when sourced, but do not allow the script to be called directly
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  export -f colourLUT
else
  echo "colourLUT is an internal function and cannot be called directly."
  exit 1

  # For debugging purposes it might be handy to call colourLUT.bash directly.
  #export __dir="$(cd "$(dirname "${BASH_SOURCE[${__b3bp_tmp_source_idx:-0}]}")" && pwd)/.."
  #. ${__dir}/setup.veganbagel.bash
  #colourLUT "${@}"
  #exit ${?}
fi
