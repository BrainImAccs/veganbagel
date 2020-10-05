#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
anat_and_zmap_lut

Apply a coloured overlay (e.g. from a z-map) to another image (e.g. an anatomical T1w).

The very begining was inspired by https://gist.github.com/jcreinhold/01daf54a6002de7bd8d58bad78b4022b,
written by Jacob Reinhold (jacob.reinhold@jhu.edu)

Adapted by: Christian Rubbert (christian.rubbert@med.uni-duesseldorf.de)
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
    parser = argparse.ArgumentParser(description='Apply a coloured overlay (e.g. from a z-map) to another image (e.g. an anatomical T1w).')
    parser.add_argument('anat_file', type=str, 
                        help='Path to the anatomical NIfTI image')
    parser.add_argument('zmap_file', type=str, 
                        help='Path to the zmap NIfTI image')
    parser.add_argument('--zmin', type=float, default=2.5,
                        help='Minimum standard deviations to consider in the LUT (everything below will be transparent)')
    parser.add_argument('--zmax', type=float,  default=10,
                        help='Maximum standard deviations to consider in the LUT (everything above will just stay at the same colour)')
    parser.add_argument('--cool', type=str, default="cet_linear_blue_5_95_c73_r",
                        help='Colormap for negative values (default: cet_linear_blue_5_95_c73_r, https://colorcet.holoviz.org/user_guide/index.html#Complete-list)')
    parser.add_argument('--hot', type=str, default="cet_linear_kryw_0_100_c71",
                        help='Colormap for positive values (default: cet_linear_kryw_0-100_c71, https://colorcet.holoviz.org/user_guide/index.html#Complete-list)')
    parser.add_argument('--transparency', type=int, default=90, choices=range(0,101), metavar="[0-100]",
                        help='Transparency in percent (default: 90)')
    parser.add_argument('--anat-window-center', dest='wcenter', type=int,
                        help='Window center for anatomical images (optional, otherwise center of min/max will be used. Must be defined with --anat-window-width.')
    parser.add_argument('--anat-window-width', dest='wwidth', type=int,
                        help='Window width for anatomical images (optional, otherwise min/max will be used. Must be defined with --anat-window-center.')
    parser.add_argument('out_dir', type=str, 
                        help='path to output the corresponding tif image slices')
    return parser

def main():
    try:
        # Parse arguments
        args = arg_parser().parse_args()

        # Load the anatomical and zmap NIfTI
        anat = nib.load(args.anat_file).get_fdata().astype(np.int16)
        zmap = nib.load(args.zmap_file).get_fdata().astype(np.float32)

        # Define the colormaps to be used from matplotlib
        # https://matplotlib.org/3.1.0/tutorials/colors/colormaps.html
        hot = plt.get_cmap(args.hot)
        cool = plt.get_cmap(args.cool)
        # In order to plot the anatomical slices with windowing, we need to apply the reverse Greys colormap
        grey = plt.get_cmap("Greys_r")

        # Window according to center and width, if supplied
        if args.wcenter and args.wwidth:
            lowest_visible_value = args.wcenter - (args.wwidth / 2)
            # Do not go below zero, which shouldn't happen in anatomical T1w MR images, anyway
            if lowest_visible_value < 0:
                anat[anat < lowest_visible_value] = 0
            else:
                anat[anat < lowest_visible_value] = lowest_visible_value

            highest_visible_value = args.wcenter + (args.wwidth / 2)
            anat[anat > highest_visible_value] = highest_visible_value

        # Create an array with all negative values
        neg = np.copy(zmap)
        # Ignore some negative values (derived from --zmin) in order to show "normal" z-scores as transparent 
        neg[zmap > (args.zmin * -1)] = float('nan')
        # Turn all remaining values positive and scale by --zmax
        neg = (neg * -1) / (args.zmax - args.zmin)
        # Aynthing greater than --zmax will have the same colour
        neg[neg > 1] = 1

        # Same approach as for negative values, but, well keeping it positive ;)
        pos = np.copy(zmap)
        pos[zmap < args.zmin] = float('nan')
        pos = pos / (args.zmax - args.zmin)
        pos[pos > 1] = 1

        # Create an "alpha channel" by combining the pos and neg array
        # Anything not a number (nan), which does not contain intersting values for the colour map will be 0
        alpha = np.nan_to_num(pos) + np.nan_to_num(neg)
        # Anything greater than 0 is therefore of interest, and will be shown
        # Transparency ranges from 0 (complete) to 255 (solid).
        # Keep some transparency for the colour map by multiplying 255 with a configurable value
        alpha[alpha > 0] = 255 * (args.transparency / 100)

        legend_hot = hot(np.linspace([1] * 40, [0] * 40, 75))
        legend_transparent = hot(np.full((75, 40), 0))
        legend_cool = cool(np.linspace([1] * 40, [0] * 40, 75))

        fnt = ImageFont.truetype('/usr/share/texmf/fonts/opentype/public/tex-gyre/texgyreheroscn-regular.otf', 14)
        L = Image.fromarray((np.vstack((legend_hot, legend_transparent, legend_cool)) * 255).astype(np.uint8))

        d = ImageDraw.Draw(L)
        w, h = d.textsize('+10', font = fnt, stroke_width = 1)
        d.text(((L.width - w)/2, 2), '+10', font = fnt, stroke_width = 1, stroke_fill = "black")
        w, h = d.textsize('0', font = fnt, stroke_width = 1)
        d.text(((L.width - w)/2, (L.height - h)/2), '0', font = fnt, stroke_width = 1, stroke_fill = "black")
        w, h = d.textsize('-10', font = fnt, stroke_width = 1)
        d.text(((L.width - w)/2, (L.height - 20)), '-10', font = fnt, stroke_width = 1, stroke_fill = "black")

        shrink_factor = (0.4 * anat.shape[0]) / L.height
        L = L.resize((int(L.width * shrink_factor), int(L.height * shrink_factor)))

        fnt = ImageFont.truetype('/usr/share/texmf/fonts/opentype/public/tex-gyre/texgyreheroscn-regular.otf', 6)

        for i in range(1, anat.shape[2]+1):
            # Read, min/max scale and colormap the anatomical slice
            anat_slice = grey(anat[:,:,i-1])
            sm = cm.ScalarMappable(cmap = grey)
            A = Image.fromarray(sm.to_rgba(anat[:,:,i-1], bytes=True))

            # Read and colormap the positive and negative values into a combined slice, create a RGBA-image
            cmap_slice = hot(pos[:,:,i-1]) + cool(neg[:,:,i-1])
            C = Image.fromarray((cmap_slice[:, :, :3] * 255).astype(np.uint8))

            # Use the previously defined alpha, turn it into an image and use it for 
            T = Image.fromarray(alpha[:,:,i-1].astype(np.uint8))
            C.putalpha(T)

            # Overlay the transparent colormap onto the anatomical images
            A.paste(C, (0, 0), C)
            # Rotate and mirror for radiological orientation
            A = ImageOps.mirror(A.rotate(90))
            # Add legend
            A.paste(L, (5, 5))

            # Add obligatory message "NOT FOR DIAGNOSTIC USE" to bottom center of the slice
            d = ImageDraw.Draw(A)
            msg = "NOT FOR DIAGNOSTIC USE"
            w, h = d.textsize(msg, font = fnt, stroke_width = 1)
            d.text(((A.width - w)/2, (A.height - 10)), msg, font = fnt, stroke_width = 1, stroke_fill = "black")

            A = A.convert("RGB")
            A.save(os.path.join(args.out_dir, f'bia-slice{i:03}.jpg'))
        return 0
    except Exception as e:
        print(e)
        return 1

if __name__ == "__main__":
    sys.exit(main())
