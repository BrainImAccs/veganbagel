#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
nii_to_tif

command line executable to convert 3d nifti images to 
individual tiff images along a user-specified axis

call as: python nii_to_tif.py /path/to/nifti-file /path/to/tif-output-dir
(append optional arguments to the call as desired)

Author: Jacob Reinhold (jacob.reinhold@jhu.edu)
Source: https://gist.github.com/jcreinhold/01daf54a6002de7bd8d58bad78b4022b

Adapted by: Christian Rubbert (christian.rubbert@med.uni-duesseldorf.de)
"""

import argparse
from glob import glob
import os
import sys

from PIL import Image
import nibabel as nib
import numpy as np

import png

def arg_parser():
    parser = argparse.ArgumentParser(description='split 3d image into multiple 2d images')
    parser.add_argument('img_file', type=str, 
                        help='path to nifti image')
    parser.add_argument('out_dir', type=str, 
                        help='path to output the corresponding tif image slices')
    parser.add_argument('-a', '--axis', type=int, default=2, 
                        help='axis of the 3d image array on which to sample the slices')
    return parser


def split_filename(filepath):
    path = os.path.dirname(filepath)
    filename = os.path.basename(filepath)
    base, ext = os.path.splitext(filename)
    if ext == '.gz':
        base, ext2 = os.path.splitext(base)
        ext = ext2 + ext
    return path, base, ext


def main():
    try:
        args = arg_parser().parse_args()
        _, base, ext = split_filename(args.img_file)
        img = nib.casting.float_to_int(nib.load(args.img_file).get_fdata(), np.uint16)
        img = (img * 1000) + 32767
        if img.ndim != 3:
            print(f'Only 3D data supported. File {base}{ext} has dimension {img.ndim}. Skipping.')
            return 1
        for i in range(1, img.shape[args.axis]+1):
            I = Image.fromarray(img[i-1,:,:], mode='I;16') if args.axis == 0 else \
                Image.fromarray(img[:,i-1,:], mode='I;16') if args.axis == 1 else \
                Image.fromarray(img[:,:,i-1], mode='I;16')
            I.save(os.path.join(args.out_dir, f'bia-slice{i:03}.tiff'))
        return 0
    except Exception as e:
        print(e)
        return 1


if __name__ == "__main__":
    sys.exit(main())
