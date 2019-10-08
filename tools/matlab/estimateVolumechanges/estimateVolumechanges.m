function estimateVolumechanges(niiInput, templatePath, sex, age);

  % Dissect path/filename.ext
  [niiPath, niiName, niiExt] = fileparts(niiInput);

  % Initialize SPM12
  spm defaults fmri;
  spm_jobman initcfg;
  spm_get_defaults('cmdline', true);

  % Pre-process the 3D volume
  preprocess3D(niiInput);

  %%%
  %%% Volume estimation
  %%%

  % Define the image volumes to be used
  imagelist = cell(3,1);
  % Subject's pre-processed and smoothed image volume
  imagelist{1} = fullfile(niiPath, 'mri', ['smwp1' niiName '.nii']);
  % Age and sex-matched mean volume template
  imagelist{2} = fullfile(templatePath, [int2str(age) sex 'smwp1_mean.nii']);
  % Age and sex-matched standard deviation volume template
  imagelist{3} = fullfile(templatePath, [int2str(age) sex 'smwp1_std.nii']);
  % Grey matter mask (assuming a voxel volume of 1.5 mm^3)
  imagelist{4} = fullfile(pwd, 'masks/GM_mask15.nii');

  % Load the defaults into matlabbatch
  load(fullfile(pwd, 'batches/imcalc.mat'));

  % Use the 4 images from above as input
  matlabbatch{1}.spm.util.imcalc.input = imagelist;
  % Desired output filename
  matlabbatch{1}.spm.util.imcalc.output = strcat(niiName, '_zmap.nii');
  % .. and output directory
  matlabbatch{1}.spm.util.imcalc.outdir = cellstr(fullfile(niiPath));
  % Do not read the images into a data matrix, read them in seperate variables (i1, i2, ..., iN)
  matlabbatch{1}.spm.util.imcalc.options.dmtx = 0;

  % Estimate the volume
  %
  % 1. Subtract the mean template from the subject's pre-processed smoothed volume
  % 2. Voxel-wise divide the data from 1. by the standard deviation template, which yields the voxel-wise z-map
  % 3. Voxel-wise multiply the data from 3. by the gray matter mask (essentially to mask anything non-grey-matter, which is multiplied by 0)
  %
  matlabbatch{1}.spm.util.imcalc.expression = '((i1 - i2) ./ i3) .* i4';
  spm_jobman('run', matlabbatch);

  %%%
  %%% Transform the z-map into the subject space
  %%%

  % Load the defaults into matlabbatch
  load (fullfile(pwd, 'batches/deformations.mat'));

  % Define the path/filename to the inverse deformation field (i.e. MNI space to subject space)
  matlabbatch{1}.spm.util.defs.comp{1}.def = cellstr(fullfile(niiPath, 'mri', ['iy_' niiName '.nii']));
  % The z-map to transform into subject space
  matlabbatch{1}.spm.util.defs.out{1}.pull.fnames = cellstr(fullfile(niiPath, [niiName, '_zmap.nii']));

  % Start the deformation
  spm_jobman('run', matlabbatch);
end
