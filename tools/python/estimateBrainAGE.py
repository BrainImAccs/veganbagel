#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
estimateBrainAGE

Traverse a directory full of zmaps calculated with differently "aged" templates and calculate statistics to estimate BrainAGE.

Written by: Christian Rubbert (christian.rubbert@med.uni-duesseldorf.de)
"""

import argparse
import os
import sys
import glob

import numpy as np
import nibabel as nib

import matplotlib.pyplot as plt

def arg_parser():
    parser = argparse.ArgumentParser(description='Traverse a directory full of zmaps calculated with differently "aged" templates and calculate statistics to estimate BrainAGE.')
    parser.add_argument('zmaps_dir', type=str, 
                        help='Path to the directory with the zmaps')
    parser.add_argument('mask', type=str, 
                        help='Path to the gray matter mask')
    parser.add_argument('age', type=int, 
                        help='Age of subject/patient')
    parser.add_argument('--min-age', type=int, default=18,
                        help='Minimum age in the templates used for zmap generation (default: 18)')
    parser.add_argument('--max-age', type=int, default=75,
                        help='Maximum age in the templates used for zmap generation (default: 75)')
    parser.add_argument('out_dir', type=str, 
                        help='path to output the corresponding JPEG image slices')
    return parser

def getBrainAGE(data, stat, all_ages):
    if stat == "closest_zero":
        index = np.where(data == min(data, key = abs))
    elif stat == "min":
        index = np.where(data == min(data))
    elif stat == "max":
        index = np.where(data == max(data))
    else:
        raise Exception('Please specify statistic to estimate BrainAGE.')

    return np.array(all_ages)[tuple(index)]

def doPlot(data, age, all_ages, title, out_dir, first_slice, stat):
    second_slice = first_slice + 1

    # Calculate statistics
    means = np.mean(data, axis = 1)
    means_ages = getBrainAGE(means, stat, all_ages)

    medians = np.median(data, axis = 1)
    medians_ages = getBrainAGE(medians, stat, all_ages)

    stdev = np.std(data, axis = 1)

    cv = means / stdev
    cv_ages = getBrainAGE(cv, stat, all_ages)

    with np.errstate(all = 'ignore'):
        sos = np.sum(np.square(data - np.mean(data, axis = 1, keepdims = True)), axis = 1)
    sos_ages = getBrainAGE(sos, stat, all_ages)

    with np.errstate(all = 'ignore'):
        sols = np.sum(np.square(np.log10(np.abs(data)) - np.mean(np.log10(np.abs((data))), axis = 1, keepdims = True)), axis = 1)
    sols_ages = getBrainAGE(sols, stat, all_ages)

    # Plot statistics
    fig, ax = plt.subplots(nrows = 3, ncols = 2, squeeze = False, figsize = (18, 18))

    for row in ax:
        for col in row:
            col.axvline(age, color = 'green', linestyle = 'dotted', alpha = 0.7)
            col.set_xlabel('Age of subjects in template (± 2 years)')

    for means_age in means_ages:
        ax[0,0].axvline(means_age, color = 'black', alpha = 0.7)
        ax[0,0].text(means_age + 1, 0.025, means_age, transform = ax[0,0].get_xaxis_text1_transform(0)[0])
    ax[0,0].axhline(0, color = 'darkgrey', linestyle = 'dashed', alpha = 0.7)
    ax[0,0].plot(all_ages, means)
    ax[0,0].set_ylabel('Mean')
    ax[0,0].title.set_text('Mean')

    for medians_age in medians_ages:
        ax[0,1].axvline(medians_age, color = 'black', alpha = 0.7)
        ax[0,1].text(medians_age + 1, 0.025, medians_age, transform = ax[0,1].get_xaxis_text1_transform(0)[0])
    ax[0,1].axhline(0, color = 'darkgrey', linestyle = 'dashed', alpha = 0.7)
    ax[0,1].plot(all_ages, medians)
    ax[0,1].set_ylabel('Median')
    ax[0,1].title.set_text('Median')

    #ax[1,0].axhline(0, color = 'darkgrey', linestyle = 'dashed', alpha = 0.7)
    ax[1,0].plot(all_ages, stdev)
    ax[1,0].set_ylabel('Standard deviation')
    ax[1,0].title.set_text('Standard deviation')

    for cv_age in cv_ages:
        ax[1,1].axvline(cv_age, color = 'black', alpha = 0.7)
        ax[1,1].text(cv_age + 1, 0.025, cv_age, transform = ax[1,1].get_xaxis_text1_transform(0)[0])
    ax[1,1].axhline(0, color = 'darkgrey', linestyle = 'dashed', alpha = 0.7)
    ax[1,1].plot(all_ages, cv)
    ax[1,1].set_ylabel('Coefficient of variation')
    ax[1,1].title.set_text('Coefficient of variation')

    for sos_age in sos_ages:
        ax[2,0].axvline(sos_age, color = 'black', alpha = 0.7)
        ax[2,0].text(sos_age + 1, 0.025, sos_age, transform = ax[0,0].get_xaxis_text1_transform(0)[0])
    ax[2,0].axhline(0, color = 'darkgrey', linestyle = 'dashed', alpha = 0.7)
    ax[2,0].plot(all_ages, sos)
    ax[2,0].set_ylabel('Sum of squares')
    ax[2,0].title.set_text('Sum of squares')

    for sols_age in sols_ages:
        ax[2,1].axvline(sols_age, color = 'black', alpha = 0.7)
        ax[2,1].text(sols_age + 1, 0.025, sols_age, transform = ax[0,0].get_xaxis_text1_transform(0)[0])
    ax[2,1].axhline(0, color = 'darkgrey', linestyle = 'dashed', alpha = 0.7)
    ax[2,1].plot(all_ages, sols)
    ax[2,1].set_ylabel('Sum of log squares')
    ax[2,1].title.set_text('Sum of log squares')

    #fig.tight_layout(rect=[0, 0.03, 1, 0.95])
    fig.suptitle(title, y = 0.92)

    plt.savefig(out_dir + '/bia-slice' + f"{first_slice:03d}" + '.jpg', bbox_inches = 'tight', pad_inches = 0.1)

    # Plot raw z-scores
    fig, ax = plt.subplots(figsize = (18, 10))
    ax.axvline(all_ages.index(age), color = 'green', linestyle = 'dotted', alpha = 0.7)
    ax.axhline(0, color = 'darkgrey', linestyle = 'dashed', alpha = 0.7)
    ax.boxplot(data.tolist(), labels = all_ages)
    plt.ylabel('z-scores')
    plt.xlabel('Age of subjects in template (± 2 years)')

    #fig.tight_layout(rect=[0, 0.03, 1, 0.95])
    fig.suptitle(title, y = 0.92)

    plt.savefig(out_dir + '/bia-slice' + f"{second_slice:03d}" + '.jpg', bbox_inches = 'tight', pad_inches = 0.1)

def main():
    # Parse arguments
    args = arg_parser().parse_args()

    # Load mask and replace all zeros with NaN
    mask = nib.load(args.mask).get_fdata()
    mask[mask == 0] = np.nan

    # Available ages
    all_ages = range(args.min_age, args.max_age + 1)

    # Create an empty numpy array to fill with the z-scores
    # Shape: available ages / count of non-zero voxels in the gray matter mask
    zmaps = np.zeros([len(all_ages), np.count_nonzero(~np.isnan(mask))])

    # Traverse the directory with zmaps, as defined by all_ages
    i = 0
    for temp_age in all_ages:
        # Find zmap NIfTI and load zmap
        nii = glob.glob(args.zmaps_dir + '/smwp1*' + str(temp_age) + '[FM]_zmap.nii')[0]
        zmap = nib.load(nii).get_fdata()

        # Load masked zmap into numpy array
        zmaps[i] = zmap[~np.isnan(mask)]

        i = i + 1

    doPlot(zmaps, args.age, all_ages, 'z-scores', args.out_dir, 1, 'closest_zero')

    zmaps_abs = np.absolute(zmaps)
    doPlot(zmaps_abs, args.age, all_ages, 'Absolute z-scores', args.out_dir, 3, 'min')

    with np.errstate(divide = 'ignore'):   
        zmaps_abs_log10 = np.log10(zmaps_abs)
    doPlot(zmaps_abs_log10, args.age, all_ages, 'Log10 absolute z-scores', args.out_dir, 5, 'min')

if __name__ == "__main__":
    sys.exit(main())
