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
    parser.add_argument('--cool', type=str, default="cet_linear_blue_5_95_c73",
                        help='Colormap for negative values (default: cet_linear_blue_5_95_c73, https://colorcet.holoviz.org/usr_guide/index.html#Complete-list)')
    parser.add_argument('--hot', type=str, default="cet_linear_kryw_0_100_c71",
                        help='Colormap for positive values (default: cet_linear_kryw_0-100_c71, https://colorcet.holoviz.org/user_guide/index.html#Complete-list)')
    parser.add_argument('--transparency', type=int, default=25, choices=range(0,101), metavar="[0-100]",
                        help='Transparency of colour map in percent (default: 25)')
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

        # Define the colour map to be used from either
        # - https://matplotlib.org/3.1.0/tutorials/colors/colormaps.html
        # - https://colorcet.holoviz.org/usr_guide/index.html#Complete-list
        hot = plt.get_cmap(args.hot)
        cool = plt.get_cmap(args.cool)
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

        # Create an array with all negative z-scores
        neg = np.copy(zmap)
        # Set all z-scores greater than negative z-min to "not a number" (nan). Any nan's will be made transparent later.
        neg[zmap > (args.zmin * -1)] = float('nan')
        # All remaining z-scores (between --zmin and --zmax) will be scaled to 0-1
        neg = ((neg * -1) - args.zmin) / (args.zmax - args.zmin)
        # Aynthing greater than --zmax will have the same colour
        neg[neg > 1] = 1

        # Same approach as for negative values, just keeping it positive...
        pos = np.copy(zmap)
        pos[zmap < args.zmin] = float('nan')
        pos = (pos - args.zmin) / (args.zmax - args.zmin)
        pos[pos > 1] = 1

        # Create an "alpha channel" by combining the pos and neg array
        # Anything not a number (nan), which does not contain interesting values for the colour map, will be 0, i.e. transparent
        alpha = np.nan_to_num(pos) + np.nan_to_num(neg)
        # Anything greater than 0 is therefore of interest, and will be shown
        # Transparency ranges from 0 (complete) to 255 (solid) in the alpha channel.
        # Since we define the degree of transparency in percent (0-100), multiply 255 with the degree of "solidness"
        alpha[alpha > 0] = 255 * (1 - (args.transparency / 100))

        # Legend height is supposed to be 20% of the height of the image
        # Calculate a shrink factor to shrink each part of the legend (hot, center, cool)
        legend_height_shrink_factor = (0.3 * anat.shape[1]) / (args.zmax * 2 * 10)

        L = Image.new("RGBA", (20, 20))
        d = ImageDraw.Draw(L)
        fnt = ImageFont.truetype(os.path.dirname(os.path.realpath(__file__)) + "/fonts/Beef'd.ttf", 5)
        legend_text_width, legend_text_height = d.textsize('+' + str(int(args.zmax)), font = fnt)
        legend_text_width = legend_text_width
        legend_text_height = legend_text_height + 1

        legend_height_hotcool = int((args.zmax - args.zmin) * 10 * legend_height_shrink_factor)
        legend_height_center = int(args.zmin * 2 * 10 * legend_height_shrink_factor)
        legend_height = legend_height_center + (legend_height_hotcool * 2)
        # Make the legend width 20% of the height
        legend_width = int(0.3 * legend_height)
        if legend_width < legend_text_width:
            legend_width = legend_text_width

        legend_text = hot(np.full((legend_text_height, legend_width), 0))
        legend_hot = hot(np.linspace([1] * legend_width, [0] * legend_width, legend_height_hotcool))
        legend_transparent = hot(np.full((legend_height_center, legend_width), 0))
        legend_cool = cool(np.linspace([0] * legend_width, [1] * legend_width, legend_height_hotcool))

        L = Image.fromarray((np.vstack((legend_text, legend_hot, legend_transparent, legend_cool, legend_text)) * 255).astype(np.uint8))

        d = ImageDraw.Draw(L)
        w, h = d.textsize('+' + str(int(args.zmax)), font = fnt)
        d.text(((L.width - w)/2, 0), '+' + str(int(args.zmax)), font = fnt, fill = "#A9A9A9")
        #w, h = d.textsize('0', font = fnt, stroke_width = 1)
        #d.text(((L.width - w)/2+1, (L.height - h)/2), '0', font = fnt)
        w, h = d.textsize('-' + str(int(args.zmax)), font = fnt)
        d.text(((L.width - w)/2, (L.height - legend_text_height)), '-' + str(int(args.zmax)), font = fnt, fill = "#A9A9A9")

        for i in range(1, anat.shape[2]+1):
            # Read, min/max scale and colour map the anatomical slice
            anat_slice = grey(anat[:,:,i-1])
            sm = cm.ScalarMappable(cmap = grey)
            A = Image.fromarray(sm.to_rgba(anat[:,:,i-1], bytes=True))

            # Read and colour map the positive and negative values into a combined slice, create a RGBA-image
            cmap_slice = hot(pos[:,:,i-1]) + cool(neg[:,:,i-1])
            C = Image.fromarray((cmap_slice[:, :, :3] * 255).astype(np.uint8))

            # Use the previously defined alpha, turn it into an image and use it for 
            T = Image.fromarray(alpha[:,:,i-1].astype(np.uint8))
            C.putalpha(T)

            # Overlay the transparent colour map onto the anatomical images
            A.paste(C, (0, 0), C)
            # Rotate and mirror for radiological orientation
            A = ImageOps.mirror(A.transpose(Image.ROTATE_90))
            # Add legend
            A.paste(L, (5, 5))

            # Add obligatory message "NOT FOR DIAGNOSTIC USE" to bottom center of the slice
            d = ImageDraw.Draw(A)
            msg = "NOT FOR DIAGNOSTIC USE"
            w, h = d.textsize(msg, font = fnt)
            d.text(((A.width - w)/2, (A.height - 10)), msg, font = fnt, fill = "#A9A9A9")

            A = A.convert("RGB")
            A.save(os.path.join(args.out_dir, f'bia-slice{i:03}.jpg'), format = 'JPEG', subsampling = 0, quality = 100)
        return 0
    except Exception as e:
        print(e)
        return 1

if __name__ == "__main__":
    sys.exit(main())
