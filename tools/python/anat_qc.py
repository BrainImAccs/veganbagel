#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
anat_and_zmap_lut

Overlay a QC image (e.g. CAT12 p0 images) onto another image (e.g. an anatomical T1w), while highlighting the segmentation using transparency.

Christian Rubbert (christian.rubbert@med.uni-duesseldorf.de)
"""

import argparse
import os
import sys

from PIL import Image
from PIL import ImageFont, ImageDraw, ImageOps

import nibabel as nib
import numpy as np

import matplotlib.pyplot as plt
import matplotlib.pylab as pla
import matplotlib.cm as cm

import colorcet as cc

def arg_parser():
    parser = argparse.ArgumentParser(description='Overlay a quality control (QC) image (e.g. CAT12 p0 images) onto another image (e.g. an anatomical T1w), while highlighting the segmentation using transparency.')
    parser.add_argument('anat_file', type=str, 
                        help='Path to the anatomical NIfTI image')
    parser.add_argument('qc_file', type=str, 
                        help='Path to the quality control (QC) NIfTI image')
    parser.add_argument('--transparency', type=int, default=25, choices=range(0,101), metavar="[0-100]",
                        help='Transparency of colour map in percent (default: 25)')
    parser.add_argument('--anat-window-center', dest='wcenter', type=int,
                        help='Window center for anatomical images (optional, otherwise center of min/max will be used. Must be defined with --anat-window-width.')
    parser.add_argument('--anat-window-width', dest='wwidth', type=int,
                        help='Window width for anatomical images (optional, otherwise min/max will be used. Must be defined with --anat-window-center.')
    parser.add_argument('out_dir', type=str, 
                        help='path to output the corresponding JPEG image slices')
    return parser

def main():
    try:
        # Parse arguments
        args = arg_parser().parse_args()

        # Load the anatomical and zmap NIfTI
        anat = nib.load(args.anat_file).get_fdata()
        qc = nib.load(args.qc_file).get_fdata()

        # In order to plot the anatomical slices with windowing, we need to apply the reverse Greys "colour" map
        grey = plt.get_cmap("Greys_r")

        # Window according to center and width, if supplied
        if args.wcenter and args.wwidth:
            # The lowest visible value should be window center minus half the window width
            lowest_visible_value = args.wcenter - (args.wwidth / 2)
            # Do not go below zero, which shouldn't happen in anatomical T1w MR images, anyway
            if lowest_visible_value < 0:
                anat[anat < lowest_visible_value] = 0
            else:
                # Set all pixel values lower than the lowest visible value, as derived above, to the lowest visible value
                anat[anat < lowest_visible_value] = int(lowest_visible_value)

            # Set all pixel values abive the highest visible value (window center plus half the window width) to the highest visible value
            highest_visible_value = args.wcenter + (args.wwidth / 2)
            anat[anat > highest_visible_value] = int(highest_visible_value)

        # Create an alpha channel for the quality control to highlight segmented areas
        alpha_qc = np.copy(qc)
        alpha_qc[alpha_qc > 0] = 255 * (1 - (args.transparency / 100))

        # Default font colour
        fnt_colour="#A9A9A9"

        # For each slice of the anatomical image:
        # - Overlay an image for quality checking
        # - Resize by a factor of 2 to make text more visually pleasing
        # - Add legend and text and save as JPEG
        #
        for i in range(1, anat.shape[2]+1):
            # Read, min/max scale and colour map the anatomical slice
            anat_slice = grey(anat[:,:,i-1])
            sm = cm.ScalarMappable(cmap = grey)
            A = Image.fromarray(sm.to_rgba(anat[:,:,i-1], bytes=True))

            # Read the QC image slice, create a RGBA-image
            qc_slice = grey(qc[:,:,i-1])
            C = Image.fromarray((qc_slice[:, :, :3] * 255).astype(np.uint8))

            # Use the previously defined alpha, turn it into an image and use it for 
            T = Image.fromarray(alpha_qc[:,:,i-1].astype(np.uint8))
            C.putalpha(T)

            # Overlay the transparent colour map onto the anatomical images
            A.paste(C, (0, 0), C)
            # Rotate and mirror for radiological orientation
            A = ImageOps.mirror(A.transpose(Image.ROTATE_90))
            # Resize by a factor of two to make the legend text drawn on the image more visually pleasing
            A = A.resize((A.width * 2, A.height * 2))

            # Add obligatory message "NOT FOR DIAGNOSTIC USE" to bottom center of the slice
            d = ImageDraw.Draw(A)
            msg = "Not for diagnostic use"
            w, h = d.textsize(msg, font = fnt)
            d.text(((A.width - w)/2, (A.height - 10)), msg, font = fnt, fill = fnt_colour)

            # Convert to RGB (from RGBA) and write the resulting image as JPEG
            A = A.convert("RGB")
            A.save(os.path.join(args.out_dir, f'bia-slice{i:03}.jpg'), format = 'JPEG', subsampling = 0, quality = 100)
        return 0
    except Exception as e:
        print(e)
        return 1

if __name__ == "__main__":
    sys.exit(main())
