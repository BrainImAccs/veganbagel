function nii2tiff(niiInput, outputPath)

% Load the NIfTI file
image = load_nii(fullfile(niiInput));

% For each axial slice ...
for slice_id = 1 : image.hdr.dime.dim(4)
    % Read the slice's content
    slice = image.img(:, :, slice_id);

    % In order to facilitate the colour-coding of the zmap later, we first scale by 1000. Furthermore, ImageMagick
    % cannot handle negative pixel values, so, assuming we're dealing with a 16 bit file, we add (65536/2)-1 to
    % each voxel
    slice = uint16((slice * 1000) + 32767);

    % Write out the TIFF file (in the filename format of med2img, see BrainSTEM's convertIMG2DCM.bash)
    imwrite(slice, fullfile(outputPath, strcat('bia-slice', num2str(slice_id, '%03.f'), '.tiff')))
end
