ARG CENTOS_BASED_BASE_IMAGE=centos:centos7
FROM ${CENTOS_BASED_BASE_IMAGE}

#LABEL maintainer="Gianluigi Zanetti <zag@crs4.it>"


# This is simply the base centos system and the WRF source
#
# Based on the  wps_wrf_upp Dockerfile
# by Jamie Wolff <jwolff@ucar.edu> adn Michelle Harrold <harrold@ucar.edu>

ARG WRF_VERSION
ENV WRF_VERSION ${WRF_VERSION:-4.0.3}

WORKDIR /wrf

RUN yum -y update \
  && yum -y install \
           file \
           yum-utils \
           bzip2 \
           libxml2-devel \
           gcc gcc-gfortran gcc-c++ glibc.i686 libgcc.i686 \
           libpng-devel jasper jasper-devel ksh hostname m4 make perl tar tcsh time \
           wget which zlib zlib-devel epel-release \
           && yum -y install \
           netcdf-devel.x86_64 netcdf-fortran-devel.x86_64 \
           netcdf-fortran.x86_64 hdf5.x86_64 \
  && yum clean all \
  && rm -rf /var/cache/yum \
  && rm -rf /var/tmp/yum-* \
  && curl -SL https://github.com/wrf-model/WRF/archive/v${WRF_VERSION}.tar.gz | tar  xzC /wrf \
  && cd /wrf && ln -s WRF-${WRF_VERSION} WRF \
  && mkdir netcdf_links \
  && ln -sf /usr/include/ netcdf_links/include \
  && ln -sf /usr/lib64 netcdf_links/lib \
  && ln -sf /usr/lib64/gfortran/modules/netcdf.mod netcdf_links/include \
  && mkdir /WPSRUN



