FROM neurodebian:buster-non-free

MAINTAINER Christian Rubbert <christian.rubbert@med.uni-duesseldorf.de>

ARG DEBIAN_FRONTEND="noninteractive"

#
# Set up the base system with dependencies
#
ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8

RUN set -eux \
  && apt-get update -qq \
  && apt-get -y upgrade \
  && apt-get install -y -q --no-install-recommends \
      apt-utils \
      bzip2 \
      ca-certificates \
      wget \
      locales \
      unzip \
      git \
  && apt-get clean \
  && rm -rf /tmp/hsperfdata* /var/*/apt/*/partial /var/lib/apt/lists/* /var/log/apt/term* \
  && sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
  && dpkg-reconfigure --frontend=noninteractive locales \
  && update-locale LANG="en_US.UTF-8"

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
  && rm -rf \
      /opt/mcr_install \
      /tmp/*

#
# Install CAT12 Standalone in /opt/cat12/
#
ENV CAT_VERSION 12
ENV CAT_REVISION latest
ENV SPM_HTML_BROWSER 0
ENV MCR_INHIBIT_CTF_LOCK 1

# Running SPM once with "function exit" tests the succesfull installation *and*
# extracts the ctf archive, which is necessary to make spm12/cat12 read-only to
# be able to set MCR_INHIBIT_CTF_LOCK
RUN set -eux \
  && wget \
      --progress=bar:force \
      -P /opt \
      http://www.neuro.uni-jena.de/cat${CAT_VERSION}/cat${CAT_VERSION}_${CAT_REVISION}_${MATLAB_VERSION}_MCR_Linux.zip \
  && unzip \
      -q /opt/cat${CAT_VERSION}_${CAT_REVISION}_${MATLAB_VERSION}_MCR_Linux.zip \
      -d /opt \
  && mv /opt/MCR_Linux /opt/cat${CAT_VERSION} \
  && rm -f /opt/cat${CAT_VERSION}_${CAT_REVISION}_${MATLAB_VERSION}_MCR_Linux.zip \
  && LD_LIBRARY_PATH=/opt/mcr-${MATLAB_VERSION}/${MCR_VERSION}/runtime/glnxa64:/opt/mcr-${MATLAB_VERSION}/${MCR_VERSION}/bin/glnxa64:/opt/mcr-${MATLAB_VERSION}/${MCR_VERSION}/sys/os/glnxa64:/opt/mcr-${MATLAB_VERSION}/${MCR_VERSION}/sys/opengl/lib/glnxa64:/opt/mcr-${MATLAB_VERSION}/${MCR_VERSION}/extern/bin/glnxa64 /opt/cat${CAT_VERSION}/spm${CAT_VERSION} function exit \
  && find /opt/cat${CAT_VERSION}/ -type d -exec chmod 555 {} \; \
  && find /opt/cat${CAT_VERSION}/spm${CAT_VERSION}_mcr -type f -exec chmod 444 {} \; \
  && chmod 555 /opt/cat${CAT_VERSION}/run_spm${CAT_VERSION}.sh /opt/cat${CAT_VERSION}/spm${CAT_VERSION} \
  && chmod -R u-w,g-w,o-w /opt/cat${CAT_VERSION}

#
# dcm2niix source install adapted from NeuroDocker (https://github.com/ReproNim/neurodocker)
#
ENV DCM2NIIX_VERSION v1.0.20201102
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
ENV FSL_VERSION 6.0.3
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
#  ImageMagick is not in use anymore
#  && sed \
#      -E 's/<policy domain="resource" name="(width|height)" value=".*"\/>/<policy domain="resource" name="\1" value="128KP"\/>/' \
#      -i /etc/ImageMagick-6/policy.xml

#
# Install BrainSTEM and init the needed submodules
#
ENV BIA_MODULE veganbagel

RUN set -eux \
  && git clone https://github.com/BrainImAccs/BrainSTEM.git /opt/BrainSTEM \
  && cd /opt/BrainSTEM \
  && git checkout docker-cat12.7-standalone \
  && git submodule update --init modules/${BIA_MODULE} \
  && cd /opt/BrainSTEM/modules/${BIA_MODULE} \
  && git checkout docker-cat12.7-standalone \
  && cp \
      /opt/BrainSTEM/setup.brainstem.bash-template \
      /opt/BrainSTEM/setup.brainstem.bash \
  && cat /opt/BrainSTEM/modules/${BIA_MODULE}/setup.${BIA_MODULE}.bash-template | \
      sed \
        -e "s%^SPMROOT=/path/to/cat12-standalone%SPMROOT=/opt/cat${CAT_VERSION}%" \
        -e "s%^MCRROOT=/path/to/mcr/v93%MCRROOT=/opt/mcr-${MATLAB_VERSION}/v93%" \
      > /opt/BrainSTEM/modules/${BIA_MODULE}/setup.${BIA_MODULE}.bash \
  && cp \
      /opt/BrainSTEM/tools/startJob.bash-template \
      /opt/BrainSTEM/tools/startJob.bash \
  && echo "\"\${__dir}/../modules/${BIA_MODULE}/${BIA_MODULE}.bash\" -i \"\$2\" --total-cleanup" >> /opt/BrainSTEM/tools/startJob.bash \
  && groupadd -r bia \
  && useradd -r -g bia -m bia \
  && chown bia:bia /opt/BrainSTEM/incoming -R \
  && chown bia:bia /opt/BrainSTEM/received -R \
  && echo '#!/usr/bin/env bash' >> /opt/entry.bash \
  && echo 'bash /opt/BrainSTEM/incoming/incoming-long.bash' >> /opt/entry.bash \
  && echo 'bash /opt/BrainSTEM/received/queue-long.bash' >> /opt/entry.bash \
  && echo 'sleep 5' >> /opt/entry.bash \
  && echo 'tail -f /opt/BrainSTEM/*/*.log' >> /opt/entry.bash \
  && chmod 755 /opt/entry.bash /opt/BrainSTEM/tools/startJob.bash

USER bia

EXPOSE 10105/tcp

ENTRYPOINT ["/opt/entry.bash"]
