function jc_estimateVolumechanges(parentdir, filename, gender, age)
  jc_preprocess3D(fullfile(parentdir, 'nii-in'), filename);

  load(fullfile(pwd, 'jc_imcalc.mat'));
  imagelist=cell(3,1);
  imagelist{1}=fullfile(parentdir,'nii-in','mri',['smwp1' filename '.nii']);
  imagelist{2}=fullfile(pwd, 'AgeTemplates', [int2str(age) gender 'smwp1_mean.nii']);
  imagelist{3}=fullfile(pwd, 'AgeTemplates', [int2str(age) gender 'smwp1_std.nii']);
  imagelist{4}=fullfile(pwd, 'GM_mask15.nii');
  matlabbatch{1}.spm.util.imcalc.input = imagelist;
  matlabbatch{1}.spm.util.imcalc.output = strcat(filename, '_zmap.nii');
  matlabbatch{1}.spm.util.imcalc.outdir = cellstr(fullfile(parentdir, 'nii-in'));
  matlabbatch{1}.spm.util.imcalc.options.dmtx = 0;
  %matlabbatch{1}.spm.util.imcalc.expression = '(i1 - i2) ./ i3';
  matlabbatch{1}.spm.util.imcalc.expression = '((i1 - i2) ./ i3) .* i4';
  spm_jobman('run',matlabbatch)

  load (fullfile(pwd, 'jc_deformations.mat'));
  matlabbatch{1}.spm.util.defs.comp{1}.def = cellstr(fullfile(parentdir, 'nii-in', 'mri', ['iy_' filename '.nii']));
  matlabbatch{1}.spm.util.defs.out{1}.pull.fnames = cellstr(fullfile(parentdir, 'nii-in', [filename, '_zmap.nii']));
  spm_jobman('run',matlabbatch)
end
