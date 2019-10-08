function preprocess3D(inputNii)

  % Dissect path/filename.ext
  [niiPath, niiName, niiExt] = fileparts(inputNii);

  % Initialize SPM12
  spm defaults fmri;
  spm_jobman initcfg;
  spm_get_defaults('cmdline', true);

  %%%
  %%% Preprocessing
  %%%

  % Load the defaults
  load(fullfile(pwd,'batches/cat12.mat'));

  % Adjust the location of some files according to the SPM12 install path (expects a default install)
  matlabbatch{1}.spm.tools.cat.estwrite.opts.tpm = cellstr(strcat(fullfile(spm('Dir'), "/tpm/TPM.nii"), ',1'));
  matlabbatch{1}.spm.tools.cat.estwrite.extopts.registration.darteltpm = cellstr(strcat(fullfile(spm('Dir'), "/toolbox/cat12/templates_1.50mm/Template_1_IXI555_MNI152.nii"), ',1'));
  matlabbatch{1}.spm.tools.cat.estwrite.extopts.registration.shootingtpm = cellstr(strcat(fullfile(spm('Dir'), "/toolbox/cat12/templates_1.50mm/Template_0_IXI555_MNI152_GS.nii"), ',1'));

  % Insert path to the NIfTI to be processed
  matlabbatch{1}.spm.tools.cat.estwrite.data = {};
  matlabbatch{1}.spm.tools.cat.estwrite.data = cellstr(fullfile(inputNii));

  % Start preprocessing
  spm_jobman('run', matlabbatch);

  %%%
  %%% Smoothing
  %%%

  % Load the defaults
  load(fullfile(pwd,'batches/smooth.mat'));

  % Define the output directory
  matlabbatch{1}.spm.spatial.smooth.data = {};
  matlabbatch{1}.spm.spatial.smooth.data = cellstr(fullfile(niiPath, 'mri', ['mwp1' niiName niiExt]));

  % Start smoothing
  spm_jobman('run', matlabbatch)
end
