FROM neurodebian:bullseye-non-free

MAINTAINER Christian Rubbert <christian.rubbert@med.uni-duesseldorf.de>

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
  && apt-get clean \
  && rm -rf /tmp/hsperfdata* /var/*/apt/*/partial /var/lib/apt/lists/* /var/log/apt/term* \
  && sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
  && dpkg-reconfigure --frontend=noninteractive locales \
  && update-locale LANG="en_US.UTF-8"

ENV LANGUAGE en_US
ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8

#
# MCR & SPM12 install adapted for CAT12 from from https://hub.docker.com/r/spmcentral/spm/dockerfile
#
# Install MATLAB Compile Runtime (MCR) in /opt/mcr-${MATLAB_VERSION}/
#
ENV MATLAB_VERSION R2017b
ENV MCR_VERSION v93
ENV MCRROOT /opt/mcr-${MATLAB_VERSION}/${MCR_VERSION}

RUN set -eux \
  && apt-get update -qq \
  && apt-get install -y -q --no-install-recommends \
      bc \
      libncurses5 \
      libxext6 \
      libxmu6 \
      libxpm-dev \
      libxt6 \
  && apt-get clean \
  && rm -rf /tmp/hsperfdata* /var/*/apt/*/partial /var/lib/apt/lists/* /var/log/apt/term* \
  && mkdir /opt/mcr_install \
  && mkdir /opt/mcr-${MATLAB_VERSION} \
  && wget \
      --progress=bar:force \
      -P /opt/mcr_install \
       https://ssd.mathworks.com/supportfiles/downloads/${MATLAB_VERSION}/deployment_files/${MATLAB_VERSION}/installers/glnxa64/MCR_${MATLAB_VERSION}_glnxa64_installer.zip \
  && unzip \
      -q /opt/mcr_install/MCR_${MATLAB_VERSION}_glnxa64_installer.zip \
      -d /opt/mcr_install \
  && /opt/mcr_install/install \
      -destinationFolder /opt/mcr-${MATLAB_VERSION} \
      -agreeToLicense yes \
      -mode silent \
  && mv \
      /opt/mcr-R2017b/v93/bin/glnxa64/libfreetype.so.6 \
      /opt/mcr-R2017b/v93/bin/glnxa64/libfreetype.so.6.bak \
  && mv \
      /opt/mcr-R2017b/v93/bin/glnxa64/libfreetype.so.6.11.1 \
      /opt/mcr-R2017b/v93/bin/glnxa64/libfreetype.so.6.11.1.bak \
  && rm -rf \
      /opt/mcr_install \
      /tmp/*

#
# Install CAT12 Standalone in /opt/cat12/
#
ENV CAT_VERSION_MAJOR 12
ENV CAT_VERSION_MINOR 7
ENV CAT_REVISION r1743
ENV SPM_HTML_BROWSER 0
ENV MCR_INHIBIT_CTF_LOCK 1

# Running SPM once with "function exit" tests the succesfull installation *and*
# extracts the ctf archive, which is necessary to make spm12/cat12 read-only to
# be able to set MCR_INHIBIT_CTF_LOCK
RUN set -eux \
  && wget \
      --progress=bar:force \
      -P /opt \
      http://www.neuro.uni-jena.de/cat${CAT_VERSION_MAJOR}/CAT${CAT_VERSION_MAJOR}.${CAT_VERSION_MINOR}_${CAT_REVISION}_${MATLAB_VERSION}_MCR_Linux.zip \
  && unzip \
      -q /opt/CAT${CAT_VERSION_MAJOR}.${CAT_VERSION_MINOR}_${CAT_REVISION}_${MATLAB_VERSION}_MCR_Linux.zip \
      -d /opt \
  && mv /opt/CAT${CAT_VERSION_MAJOR}.${CAT_VERSION_MINOR}_${CAT_REVISION}_${MATLAB_VERSION}_MCR_Linux /opt/cat${CAT_VERSION_MAJOR} \
  && rm -f /opt/CAT${CAT_VERSION_MAJOR}.${CAT_VERSION_MINOR}_${CAT_REVISION}_${MATLAB_VERSION}_MCR_Linux.zip \
  && LD_LIBRARY_PATH=/opt/mcr-${MATLAB_VERSION}/${MCR_VERSION}/runtime/glnxa64:/opt/mcr-${MATLAB_VERSION}/${MCR_VERSION}/bin/glnxa64:/opt/mcr-${MATLAB_VERSION}/${MCR_VERSION}/sys/os/glnxa64:/opt/mcr-${MATLAB_VERSION}/${MCR_VERSION}/sys/opengl/lib/glnxa64:/opt/mcr-${MATLAB_VERSION}/${MCR_VERSION}/extern/bin/glnxa64 /opt/cat${CAT_VERSION_MAJOR}/spm${CAT_VERSION_MAJOR} function exit \
  && find /opt/cat${CAT_VERSION_MAJOR}/ -type d -exec chmod 555 {} \; \
  && find /opt/cat${CAT_VERSION_MAJOR}/spm${CAT_VERSION_MAJOR}_mcr -type f -exec chmod 444 {} \; \
  && chmod 555 /opt/cat${CAT_VERSION_MAJOR}/run_spm${CAT_VERSION_MAJOR}.sh /opt/cat${CAT_VERSION_MAJOR}/spm${CAT_VERSION_MAJOR} \
  && chmod -R u-w,g-w,o-w /opt/cat${CAT_VERSION_MAJOR}

#
# dcm2niix source install adapted from NeuroDocker (https://github.com/ReproNim/neurodocker)
#
ENV DCM2NIIX_VERSION v1.0.20210317
ENV PATH /opt/dcm2niix-${DCM2NIIX_VERSION}/bin:$PATH

RUN set -eux \
  && apt-get update -qq \
  && apt-get install -y -q --no-install-recommends \
      cmake \
      g++ \
      gcc \
      git \
      make \
      pigz \
      zlib1g-dev \
  && apt-get clean \
  && rm -rf /tmp/hsperfdata* /var/*/apt/*/partial /var/lib/apt/lists/* /var/log/apt/term* \
  && git clone https://github.com/rordenlab/dcm2niix /tmp/dcm2niix \
  && cd /tmp/dcm2niix \
  && git fetch --tags \
  && git checkout ${DCM2NIIX_VERSION} \
  && mkdir /tmp/dcm2niix/build \
  && cd /tmp/dcm2niix/build \
  && cmake -DCMAKE_INSTALL_PREFIX:PATH=/opt/dcm2niix-${DCM2NIIX_VERSION} .. \
  && make \
  && make install \
  && rm -rf /tmp/dcm2niix

#
# FSL install adapted from NeuroDocker (https://github.com/ReproNim/neurodocker)
#
ENV FSL_VERSION 6.0.4
ENV FSLDIR /opt/fsl-${FSL_VERSION}
ENV FSLOUTPUTTYPE NIFTI
ENV FSLMULTIFILEQUIT TRUE
ENV FSLTCLSH /opt/fsl-${FSL_VERSION}/bin/fsltclsh
ENV FSLWISH /opt/fsl-${FSL_VERSION}/bin/fslwish
ENV PATH /opt/fsl-${FSL_VERSION}/bin:$PATH

RUN set -eux \
  && apt-get update -qq \
  && apt-get install -y -q --no-install-recommends \
      bc \
      dc \
      file \
      libfontconfig1 \
      libfreetype6 \
      libgl1-mesa-dev \
      libgl1-mesa-dri \
      libglu1-mesa-dev \
      libgomp1 \
      libice6 \
      libxcursor1 \
      libxft2 \
      libxinerama1 \
      libxrandr2 \
      libxrender1 \
      libxt6 \
      sudo \
      wget \
  && apt-get clean \
  && rm -rf /tmp/hsperfdata* /var/*/apt/*/partial /var/lib/apt/lists/* /var/log/apt/term* \
  && mkdir -p /opt/fsl-${FSL_VERSION} \
  && wget \
      --progress=bar:force \
      -O - \
      https://fsl.fmrib.ox.ac.uk/fsldownloads/fsl-${FSL_VERSION}-centos6_64.tar.gz | \
        tar \
          -xz \
          -C /opt/fsl-${FSL_VERSION} \
          --strip-components 1 \
  && bash /opt/fsl-${FSL_VERSION}/etc/fslconf/fslpython_install.sh -f /opt/fsl-${FSL_VERSION}

#
# Install BrainImAccs veganbagel dependencies
#
RUN set -eux \
  && apt-get update -qq \
  && apt-get install -y -q --no-install-recommends \
      bc \
      dcmtk \
      nifti2dicom \
      parallel \
      libjpeg-dev \
      imagemagick \
      fonts-texgyre \
      python3-pip \
      python3-setuptools \
  && apt-get clean \
  && rm -rf /tmp/hsperfdata* /var/*/apt/*/partial /var/lib/apt/lists/* /var/log/apt/term* \
  && pip3 install --no-cache-dir \
      nibabel \
      pydicom \
      matplotlib \
      pillow \
      colorcet

#
# Install BrainSTEM and init the needed submodules
#
ENV BIA_MODULE veganbagel

ARG BIA_TSTAMP=${BIA_TSTAMP:-unknown}
ARG BIA_GITHUB_USER_BRAINSTEM=${BIA_GITHUB_USER_BRAINSTEM:-BrainImAccs}
ARG BIA_BRANCH_BRAINSTEM=${BIA_BRANCH_BRAINSTEM:-main}
ARG BIA_GITHUB_USER_MODULE=${BIA_GITHUB_USER_MODULE:-BrainImAccs}
ARG BIA_BRANCH_MODULE=${BIA_BRANCH_MODULE:-main}
RUN set -eux \
  && git clone https://github.com/${BIA_GITHUB_USER_BRAINSTEM}/BrainSTEM.git /opt/BrainSTEM \
  && cd /opt/BrainSTEM \
  && git checkout ${BIA_BRANCH_BRAINSTEM} \
  && git config submodule.modules/fatbACPC.url https://github.com/${BIA_GITHUB_USER_MODULE}/${BIA_MODULE}.git \
  && git submodule update --init modules/${BIA_MODULE} \
  && cd /opt/BrainSTEM/modules/${BIA_MODULE} \
  && git checkout ${BIA_BRANCH_MODULE} \
  && cat /opt/BrainSTEM/modules/${BIA_MODULE}/setup.${BIA_MODULE}.bash-template | \
      sed \
        -e "s%^SPMROOT=/path/to/cat12-standalone%SPMROOT=/opt/cat${CAT_VERSION_MAJOR}%" \
        -e "s%^MCRROOT=/path/to/mcr/v93%MCRROOT=/opt/mcr-${MATLAB_VERSION}/v93%" \
      > /opt/BrainSTEM/modules/${BIA_MODULE}/setup.${BIA_MODULE}.bash \
  && cat /opt/BrainSTEM/setup.brainstem.bash-template | \
      sed \
        -e "s%^FSLDIR=/path/to/fsl-.*%FSLDIR=/opt/fsl-${FSL_VERSION}%" \
      > /opt/BrainSTEM/setup.brainstem.bash \
  && cp \
      /opt/BrainSTEM/tools/startJob.bash-template \
      /opt/BrainSTEM/tools/startJob.bash \
  && useradd --system --user-group --create-home --uid 999 bia \
  && echo '#!/usr/bin/env bash' >> /opt/entry.bash \
  && echo 'bash /opt/BrainSTEM/incoming/incoming.bash &' >> /opt/entry.bash \
  && echo 'bash /opt/BrainSTEM/received/queue.bash &' >> /opt/entry.bash \
  && echo 'wait' >> /opt/entry.bash \
  && chmod 755 /opt/entry.bash /opt/BrainSTEM/tools/startJob.bash \
  && chown bia:bia /opt/BrainSTEM/incoming /opt/BrainSTEM/received

USER bia

EXPOSE 10105/tcp

ENTRYPOINT ["/opt/entry.bash"]
