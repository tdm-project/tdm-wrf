#
# This is simply the base centos system and the WRF source
#
# Based on the  wps_wrf_upp Dockerfile
# by Jamie Wolff <jwolff@ucar.edu> adn Michelle Harrold <harrold@ucar.edu>

ARG WRF_BASE_IMAGE
FROM ${WRF_BASE_IMAGE}

ARG OPENMPI_VERSION

#WORKDIR /wrf  # Inherited from BASE image

# GNU (gfortran/gcc) options
# CMODE=32 serial, CMODE=33 DMPAR,  CMODE=34 SMPAR, CMODE=35 DMPAR + SMPAR
# NEST=0 plain, NEST=1 nested, ...
ARG CMODE
ARG NEST

ENV CMODE ${CMODE:-32}
ENV NEST  ${NEST:-0}

# Install required packages
RUN yum -y update \
    && yum -y install \
        netcdf-openmpi-devel.x86_64 \
        netcdf-fortran-openmpi-devel.x86_64 \
        netcdf-fortran-openmpi.x86_64 \
        hdf5-openmpi.x86_64 \
        openmpi.x86_64 openmpi-devel.x86_64 \
        openssh-clients openssh-server net-tools ca-certificates \
    && rm -rf /var/cache/yum \
    && rm -rf /var/tmp/yum-* \
    && rm -rf netcdf_links && mkdir netcdf_links \
    && ln -sf /usr/include/openmpi-x86_64/ netcdf_links/include \
    && ln -sf /usr/lib64/openmpi/lib netcdf_links/lib

# Update environment
ENV LD_LIBRARY_PATH /usr/lib64/openmpi/lib:${LD_LIBRARY_PATH}
ENV PATH /usr/lib64/openmpi/bin:${PATH}
ENV NETCDF /wrf/netcdf_links
ENV JASPERINC /usr/include/jasper/
ENV JASPERLIB /usr/lib64/

# Compile WRF
RUN cd ./WRF \
   && printf "${CMODE}\n${NEST}" |./configure \
   && sed -i -e '/^DM_CC/ s/$/ -DMPI2_SUPPORT/' ./configure.wrf \
   && /bin/csh ./compile em_real > compile_wrf_opt${CMODE}.${NEST}.log 2>&1

COPY run-wrf.sh /usr/local/bin/run-wrf
RUN chmod +x /usr/local/bin/run-wrf

# Create ssh user(openmpi) and setup ssh key dir
# - ssh identity file and authorized key file is expected to
#   be mounted at /ssh-keys/$SSH_USER
ARG SSH_USER=openmpi
ENV SSH_USER=$SSH_USER
ARG SSH_UID=1000
ARG SSH_GID=1000
ARG HOME=/home/$SSH_USER

RUN groupadd --gid $SSH_GID ${SSH_USER} \
    && adduser -c "" --uid $SSH_UID --gid $SSH_GID $SSH_USER \
    && passwd -d ${SSH_USER} \
    && mkdir -p /ssh-key/$SSH_USER && chown -R $SSH_USER:$SSH_USER /ssh-key/$SSH_USER \
    && mkdir -p /.sshd/host_keys \
    && chown -R $SSH_USER:$SSH_USER /.sshd/host_keys && chmod 700 /.sshd/host_keys \
    && mkdir -p /.sshd/user_keys/$SSH_USER \
    && chown -R $SSH_USER:$SSH_USER /.sshd/user_keys/$SSH_USER \
    && chmod 700 /.sshd/user_keys/$SSH_USER \
    && mkdir -p $HOME && chown $SSH_USER:$SSH_USER $HOME && chmod 755 $HOME

COPY kube-openmpi-rootfs /

VOLUME /ssh-key/$SSH_USER
VOLUME $HOME

EXPOSE 2022

# sshd can be run either by root or $SSH_USER
CMD ["/init.sh"]
