# Brain Imaging Accessoires: Volumetric estimation of gross atrophy and brain age longitudinally (veganbagel)

Estimating regional deviations of brain volume is challenging and entails immense inter-reader variation. We propose an automated workflow for sex- and age-dependent estimation of brain volume changes relative to a normative population.

Please note, this software is research-only and is not intended for clinical decisions/diagnosis.

# Details

veganbagel takes non-enhanced 3D T1-weighted structural MR brain scan as input and generates a map of regional volume changes in relation to an age- and sex-matched cohort of pre-processed normal scans.

Sex- and age-dependent gray-matter (GM) templates based on T1w MRIs of 1,112 healthy subjects between 16 and 77 years of age from the [Enhanced Nathan Kline Institute - Rockland Sample](http://fcon_1000.projects.nitrc.org/indi/enhanced/) were used. Preprocessing using [CAT12](http://www.neuro.uni-jena.de/cat/) for [SPM12](https://www.fil.ion.ucl.ac.uk/spm/software/spm12/) entailed GM-segmentation, normalization to MNI152, 8 mm smoothing and modulation. For each sex and age between 18 and 75 voxel-wise mean and standard deviation template maps were generated with the respective age +/-2 years.

These templates can then be used to generate atrophy maps for out-of-sample subjects. Preprocessing is done with the same preprocessing pipeline. Voxel-wise Z-value maps are generated, transformed back into the subject space, colour-coded and merged with the original structural MR brain scan.

By default, veganbagel starts a DICOM listener to which you can send images from e.g. a PACS. Results are sent back to the PACS. It is also possible to process locally stored DICOM or NIfTI files.

![The veganbagel workflow and resulting fused atrophy maps of a 68 year old male from the Alzheimer‘s Disease Neuroimaging Initiative](img/veganbagel_workflow.jpg "The veganbagel workflow and resulting fused atrophy maps of a 68 year old male from the Alzheimer‘s Disease Neuroimaging Initiative")

# Installation

We recommend installing veganbagel using [Docker](https://www.docker.com). The container will expose a DICOM listener, which will accept 3D T1w brain images.

The results will be sent back to a DICOM node. You can for example use [Horos](https://horosproject.org) to send and receive DICOM files.

To build veganbagel, please:

```bash
$ git clone --recurse-submodules https://github.com/BrainImAccs/veganbagel.git
$ cd veganbagel
$ docker build -t veganbagel ./
```

# Running

## Server mode

Environment variables may be used to configure aspects of BrainSTEM and veganbagel (please see (`setup.(brainstem|veganbagel).bash`) (see also [BrainSTEM](https://github.com/BrainImAccs/BrainSTEM)). For example, to have the results sent back to IP `192.168.0.27`, port `11112` (AE Title `destination`), you may execute the container as follows:

```bash
$ docker run -it \
	-p 10105:10105/tcp \
	--env called_aetitle=destination \
	--env peer=192.168.0.27 \
	--env port=11112 \
	veganbagel
```

The DICOM node in the container listens on port `10105/tcp` by default.

## Local processing

You can directly process a directory with DICOM files (of a single subject) or a single NIfTI file.

In order to directly process subjects (without sending/receiving DICOM files), you'll need to mount a directory from the host system into the container. If you are not familiar with the peculiarities of Linux file system permissions, or would like to use veganbagel on a HPC system, using an [Apptainer (Singularity)](https://apptainer.org/) container is strongly recommended.

To build a Singularity container from Docker:

```bash
$ singularity build \
	veganbagel.sif \
	docker-daemon://veganbagel:latest
```

### Local NIfTI files

Since a NIfTI file does not contain any non-imaging information, you'll need to specify sex and age on the command line:

```bash
$ singularity run \
	--bind /path/to/data:/data \
	veganbagel.sif \
	--date-of-birth 19700101 \
	--study-date 20240114 \
	--sex F \
	--input /data/t1.nii.gz
```

When processing a NIfTI file, no DICOM files will be created or sent. The temporary workdir, including all intermediary files and final results, will be saved in the directory of the NIfTI file.

As an alternative to providing `--date-of-birth` and `--study-date` in the `YYYYMMDD` format, you may define the age using `--age`, e.g. `--age=54.0342231348`.

### Local DICOM files

You may also process a DICOM directory on your local file system and both send the results to your PACS and keep the results locally, e.g.:

```bash
$ called_aetitle=destination
  peer=192.168.0.27 \
  port=11112 \
  singularity run \
	--bind /path/to/data:/data \
	veganbagel.sif \
	--keep-workdir \
	--input /data
```

# Acknowledgements

The main scripts are based on the [BASH3 Boilerplate](http://bash3boilerplate.sh).
