ARG BIA_MODULE=veganbagel

ARG DCM2NIIX_VERSION=v1.0.20210317

ARG MATLAB_VERSION=R2017b
ARG MCR_VERSION=v93
ARG MCRROOT=/opt/mcr/${MCR_VERSION}

ARG CAT_VERSION_MAJOR=12
ARG CAT_VERSION_MINOR=8.1
ARG CAT_REVISION=r1980

# ---- Start of the dcm2niix build stage ----
#
# dcm2niix source install adapted from NeuroDocker (https://github.com/ReproNim/neurodocker)
#
FROM neurodebian:bullseye-non-free AS dcm2niix-builder

ARG DCM2NIIX_VERSION
ENV DCM2NIIX_VERSION=${DCM2NIIX_VERSION}

RUN set -eux \
  && echo Building dcm2niix ${DCM2NIIX_VERSION} \
  && apt-get update -qq \
  && apt-get install -y -q --no-install-recommends \
      ca-certificates \
      cmake \
      g++ \
      gcc \
      git \
      make \
      pigz \
      zlib1g-dev \
  && git clone https://github.com/rordenlab/dcm2niix /tmp/dcm2niix \
  && cd /tmp/dcm2niix \
  && git fetch --tags \
  && git checkout ${DCM2NIIX_VERSION} \
  && mkdir /tmp/dcm2niix/build \
  && cd /tmp/dcm2niix/build \
  && cmake -DCMAKE_INSTALL_PREFIX:PATH=/opt/dcm2niix .. \
  && make \
  && make install
# ---- End of the dcm2niix build stage ----

# Following https://micromamba-docker.readthedocs.io/en/latest/advanced_usage.html#adding-micromamba-to-an-existing-docker-image
# bring in the micromamba image so we can copy files from it
FROM mambaorg/micromamba:1.5.1 as micromamba

# ---- Start of the main image ----

FROM neurodebian:bullseye-non-free
LABEL maintainer="Christian Rubbert <christian.rubbert@med.uni-duesseldorf.de>"
ARG DEBIAN_FRONTEND="noninteractive"

#
# Set up the base system with dependencies
#
RUN set -eux \
  && apt-get update -qq \
  && apt-get -y upgrade \
  && apt-get install -y -q --no-install-recommends \
      apt-utils \
      bzip2 \
      ca-certificates \
      iproute2 \
      wget \
      locales \
      unzip \
      git \
      dcmtk=3.6.5-1 \
      nifti2dicom=0.4.11-3 \
      parallel \
      libjpeg-dev \
      fonts-texgyre \
      dateutils \
  && apt-get clean \
  && rm -rf /tmp/hsperfdata* /var/*/apt/*/partial /var/lib/apt/lists/* /var/log/apt/term* \
  && sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
  && dpkg-reconfigure --frontend=noninteractive locales \
  && update-locale LANG="en_US.UTF-8"

ENV LANGUAGE en_US
ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8

#
# Install dcm2niix
#
COPY --from=dcm2niix-builder /opt/dcm2niix /opt/dcm2niix
ENV PATH /opt/dcm2niix/bin:$PATH

#
# Install MATLAB Compile Runtime (MCR) in /opt/mcr/
# MCR & SPM12 install adapted for CAT12 from from https://hub.docker.com/r/spmcentral/spm/dockerfile
#
ARG MATLAB_VERSION
ENV MATLAB_VERSION=${MATLAB_VERSION}
ARG MCR_VERSION
ENV MCR_VERSION=${MCR_VERSION}
ARG MCRROOT
ENV MCRROOT=${MCRROOT}

RUN set -eux \
  && echo Building MATLAB ${MATLAB_VERSION} MCR ${MCR_VERSION} for ${MCRROOT} \
  && apt-get update -qq \
  && apt-get install -y -q --no-install-recommends \
      ca-certificates \
      wget \
      unzip \
      bc \
      libncurses5 \
      libxext6 \
      libxmu6 \
      libxpm-dev \
      libxt6 \
  && apt-get clean \
  && rm -rf /tmp/hsperfdata* /var/*/apt/*/partial /var/lib/apt/lists/* /var/log/apt/term* \
  && mkdir /opt/mcr_install \
  && mkdir /opt/mcr \
  && wget \
      --progress=bar:force \
      -P /opt/mcr_install \
       https://ssd.mathworks.com/supportfiles/downloads/${MATLAB_VERSION}/deployment_files/${MATLAB_VERSION}/installers/glnxa64/MCR_${MATLAB_VERSION}_glnxa64_installer.zip \
  && unzip \
      -q /opt/mcr_install/MCR_${MATLAB_VERSION}_glnxa64_installer.zip \
      -d /opt/mcr_install \
  && /opt/mcr_install/install \
      -destinationFolder /opt/mcr \
      -agreeToLicense yes \
      -mode silent \
  && rm \
      /opt/mcr/${MCR_VERSION}/bin/glnxa64/libfreetype.so.6 \
      /opt/mcr/${MCR_VERSION}/bin/glnxa64/libfreetype.so.6.11.1 \
  && rm -rf \
      /opt/mcr_install \
      /tmp/*

#
# Install CAT12 Standalone in /opt/cat12/
#
ARG CAT_VERSION_MAJOR
ENV CAT_VERSION_MAJOR=${CAT_VERSION_MAJOR}
ARG CAT_VERSION_MINOR
ENV CAT_VERSION_MINOR=${CAT_VERSION_MINOR}
ARG CAT_REVISION
ENV CAT_REVISION=${CAT_REVISION}
ENV SPM_HTML_BROWSER 0
ENV MCR_INHIBIT_CTF_LOCK 1

ARG MATLAB_VERSION
ENV MATLAB_VERSION=${MATLAB_VERSION}
ARG MCR_VERSION
ENV MCR_VERSION=${MCR_VERSION}
ARG MCRROOT
ENV MCRROOT=${MCRROOT}

# Running SPM once with "function exit" tests the succesfull installation *and*
# extracts the ctf archive, which is necessary to make spm12/cat12 read-only to
# be able to set MCR_INHIBIT_CTF_LOCK
RUN set -eux \
  && echo "Installing CAT${CAT_VERSION_MAJOR}.${CAT_VERSION_MINOR} (${CAT_REVISION})" \
  && wget \
      --progress=bar:force \
      -P /opt \
      http://www.neuro.uni-jena.de/cat${CAT_VERSION_MAJOR}/CAT${CAT_VERSION_MAJOR}.${CAT_VERSION_MINOR}_${CAT_REVISION}_${MATLAB_VERSION}_MCR_Linux.zip \
  && unzip \
      -q /opt/CAT${CAT_VERSION_MAJOR}.${CAT_VERSION_MINOR}_${CAT_REVISION}_${MATLAB_VERSION}_MCR_Linux.zip \
      -d /opt \
  && mv /opt/CAT${CAT_VERSION_MAJOR}.${CAT_VERSION_MINOR}_${CAT_REVISION}_${MATLAB_VERSION}_MCR_Linux /opt/cat${CAT_VERSION_MAJOR} \
  && rm -f /opt/CAT${CAT_VERSION_MAJOR}.${CAT_VERSION_MINOR}_${CAT_REVISION}_${MATLAB_VERSION}_MCR_Linux.zip \
  && LD_LIBRARY_PATH=/opt/mcr/${MCR_VERSION}/runtime/glnxa64:/opt/mcr/${MCR_VERSION}/bin/glnxa64:/opt/mcr/${MCR_VERSION}/sys/os/glnxa64:/opt/mcr/${MCR_VERSION}/sys/opengl/lib/glnxa64:/opt/mcr/${MCR_VERSION}/extern/bin/glnxa64 /opt/cat${CAT_VERSION_MAJOR}/spm${CAT_VERSION_MAJOR} function exit \
  && find /opt/cat${CAT_VERSION_MAJOR}/ -type d -exec chmod 555 {} \; \
  && find /opt/cat${CAT_VERSION_MAJOR}/spm${CAT_VERSION_MAJOR}_mcr -type f -exec chmod 444 {} \; \
  && chmod 555 /opt/cat${CAT_VERSION_MAJOR}/run_spm${CAT_VERSION_MAJOR}.sh /opt/cat${CAT_VERSION_MAJOR}/spm${CAT_VERSION_MAJOR} \
  && chmod -R u-w,g-w,o-w /opt/cat${CAT_VERSION_MAJOR}

# Following https://micromamba-docker.readthedocs.io/en/latest/advanced_usage.html#adding-micromamba-to-an-existing-docker-image
# if your image defaults to a non-root user, then you may want to make the
# next 3 ARG commands match the values in your image. You can get the values
# by running: docker run --rm -it my/image id -a

ARG MAMBA_USER=bia
ARG MAMBA_USER_ID=999
ARG MAMBA_USER_GID=999
ENV MAMBA_USER $MAMBA_USER
ENV MAMBA_ROOT_PREFIX "/opt/conda"
ENV MAMBA_EXE "/bin/micromamba"

ENV FSLDIR ${MAMBA_ROOT_PREFIX}
ENV FSLOUTPUTTYPE NIFTI
ENV FSLMULTIFILEQUIT TRUE
ENV PATH ${FSLDIR}/bin:$PATH

COPY --from=micromamba "$MAMBA_EXE" "$MAMBA_EXE"
COPY --from=micromamba /usr/local/bin/_activate_current_env.sh /usr/local/bin/_activate_current_env.sh
COPY --from=micromamba /usr/local/bin/_dockerfile_shell.sh /usr/local/bin/_dockerfile_shell.sh
COPY --from=micromamba /usr/local/bin/_entrypoint.sh /usr/local/bin/_entrypoint.sh
COPY --from=micromamba /usr/local/bin/_dockerfile_initialize_user_accounts.sh /usr/local/bin/_dockerfile_initialize_user_accounts.sh
COPY --from=micromamba /usr/local/bin/_dockerfile_setup_root_prefix.sh /usr/local/bin/_dockerfile_setup_root_prefix.sh

ENV FSL_CONDA_CHANNEL="https://fsl.fmrib.ox.ac.uk/fsldownloads/fslconda/public"

RUN set -eux \
  && /usr/local/bin/_dockerfile_initialize_user_accounts.sh \
  && /usr/local/bin/_dockerfile_setup_root_prefix.sh \
  && micromamba install --yes --name base --channel $FSL_CONDA_CHANNEL \
    fsl-avwutils=2209.2 \
    fsl-miscmaths=2203.2 \
    nibabel=5.1.0 \
    pydicom=2.4.3 \
    matplotlib=3.8.0 \
    pillow=10.0.1 \
    colorcet=3.0.1 \
    --channel conda-forge \
  && micromamba clean --all --yes

COPY --chown=$MAMBA_USER_ID:$MAMBA_USER_GID . /opt/bia

RUN set -eux \
  && micromamba env create --yes --file /opt/bia/external/brainage_estimation/requirements.yml \
  && micromamba clean --all --yes

USER bia

ARG BIA_MODULE
ENV BIA_MODULE=${BIA_MODULE}
ARG BIA_TSTAMP=${BIA_TSTAMP:-unknown}

RUN set -eux \
  && cat /opt/bia/setup.${BIA_MODULE}.bash-template | \
      sed \
        -e "s%^SPMROOT=/path/to/cat12-standalone%SPMROOT=/opt/cat${CAT_VERSION_MAJOR}%" \
        -e "s%^MCRROOT=/path/to/mcr/v93%MCRROOT=/opt/mcr/v93%" \
      > /opt/bia/setup.${BIA_MODULE}.bash \
  && cat /opt/bia/BrainSTEM/setup.brainstem.bash-template | \
      sed \
        -e "s%^FSLDIR=/path/to/fsl-.*%FSLDIR=${FSLDIR}%" \
      > /opt/bia/BrainSTEM/setup.brainstem.bash \
  && cp \
      /opt/bia/BrainSTEM/tools/startJob.bash-template \
      /opt/bia/BrainSTEM/tools/startJob.bash \
  && chmod 755 /opt/bia/BrainSTEM/tools/startJob.bash \
  && git config --global --add safe.directory /opt/bia \
  && (cd /opt/bia && git describe --always) >> /opt/bia/version \
  && rm -rf /opt/bia/.git

EXPOSE 10105/tcp

SHELL ["/usr/local/bin/_dockerfile_shell.sh"]
ENTRYPOINT ["/usr/local/bin/_entrypoint.sh", "/opt/bia/tools/bash/docker_entry_point.bash"]
