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
from PIL import ImageFont, ImageDraw, ImageOps, ImageFilter

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

        # Normalize anat
        anat = (anat / np.max(anat)) * np.max(qc)

        # In order to plot the anatomical slices with windowing, we need to apply the reverse Greys "colour" map
        grey = plt.get_cmap("Greys_r")

        # Create an alpha channel for the quality control to highlight segmented areas
        # 0 = 100% transparency, 255 = 0% transparency/solid
        alpha_qc = np.copy(qc)
        alpha_qc[alpha_qc > 0] = 50
        alpha_qc[alpha_qc == 0] = 255 * (1 - (args.transparency / 100))

        # Create a binary mask of the QC volume for contour detection later on
        qc_binary = np.copy(qc)
        qc_binary[qc_binary > 0] = np.max(qc)

        # Default font and font colour
        fnt = ImageFont.truetype(os.path.dirname(os.path.realpath(__file__)) + "/fonts/Beef'd.ttf", 5)
        fnt_colour="#A9A9A9"

        # For each slice of the anatomical image:
        # - Overlay an image for quality checking
        # - Resize by a factor of 2 to make text more visually pleasing
        # - Add legend and text and save as JPEG
        #
        for i in range(1, anat.shape[2]+1):
            sm = cm.ScalarMappable(cmap = grey)

            # Read the anatomical slice, creating a min/max scaled grey RGBA image
            A = Image.fromarray(sm.to_rgba(anat[:,:,i-1], bytes=True))

            # Read the QC image slice, creating a min/max scalred grey RGBA image
            C = Image.fromarray(sm.to_rgba(qc[:,:,i-1], bytes=True))

            # Use the previously defined alpha map, turn it into an image and use it as the alpha channel on C
            T = Image.fromarray(alpha_qc[:,:,i-1].astype(np.uint8))
            C.putalpha(T)

            # Read the previously defined binary mask, then ...
            B = Image.fromarray(sm.to_rgba(qc_binary[:,:,i-1], bytes=True))
            # ... find the outer contours and invert black/white
            E = B.filter(ImageFilter.CONTOUR).convert('L')
            E = ImageOps.invert(E)
            # Crop the outer 1 px border (which would otherwise be white)
            E = ImageOps.crop(E, (1, 1))

            # Overlay the QC image onto the anatomical images
            A.paste(C, (0, 0), C)
            # Overlay the outer contour of the binary mask onto both images (note that we nudge by 1 px after cropping above)
            A.paste(E, (1, 1), E)
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
