function jc_preprocess3D(inputdir, filename)

load(fullfile(pwd,'jc_cat12.mat'));
matlabbatch{1}.spm.tools.cat.estwrite.data = {};
matlabbatch{1}.spm.tools.cat.estwrite.data{1,1} = fullfile(inputdir,[filename '.nii']);
spm_jobman('run',matlabbatch)

load(fullfile(pwd,'jc_smooth.mat'));
matlabbatch{1}.spm.spatial.smooth.data = {};
matlabbatch{1}.spm.spatial.smooth.data{1,1} = fullfile(inputdir,'mri',['mwp1' filename '.nii']);
%matlabbatch{1}.spm.spatial.smooth.data{2,1} = fullfile(inputdir,'mri',['mwp2' filename '.nii']);
spm_jobman('run',matlabbatch)

%delete(fullfile(inputdir,[filename '_seg8.mat']));
%delete(fullfile(inputdir,['p' filename '_seg8.txt']));