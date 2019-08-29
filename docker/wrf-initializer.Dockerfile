ARG WRF_BASE_IMAGE
FROM ${WRF_BASE_IMAGE}

#LABEL maintainer="Gianluigi Zanetti <zag@crs4.it>"

# Based on Jamie Wolff <jwolff@ucar.edu> and Michelle Harrold <harrold@ucar.edu>
# wps_wrf_upp Dockerfile

# Update environment
ENV LD_LIBRARY_PATH /usr/lib64/lib
ENV PATH  /usr/lib64/bin:$PATH
ENV NETCDF /wrf/netcdf_links
ENV JASPERINC /usr/include/jasper/
ENV JASPERLIB /usr/lib64/

# Compile WRF
RUN cd /wrf/WRF \
  && ./configure <<< $'32\r1\r' \
  && /bin/csh ./compile em_real > compile_wrf_arw_opt32.1.log 2>&1 \
  && curl -SL https://github.com/wrf-model/WPS/archive/v${WRF_VERSION}.tar.gz | tar zxC /wrf \
  && cd /wrf && ln -s WPS-${WRF_VERSION} WPS && cd WPS \
  && ./configure <<< $'1\r' \
  && sed -i -e 's/-L$(NETCDF)\/lib/-L$(NETCDF)\/lib -lnetcdff /' ./configure.wps \
  && /bin/csh ./compile > compile_wps.log 2>&1

# Install python requirements
RUN yum -y install  https://centos7.iuscommunity.org/ius-release.rpm \
  && yum -y update \
  && yum -y install git libtool eccodes-devel udunits2 udunits2-devel \
  && yum -y install python36u python36u-devel python36u-pip \
  && yum clean all \
  && rm -rf /var/cache/yum \
  && rm -rf /var/tmp/yum-*
  
# Compile and install gdal 
RUN cd /opt \
    && wget http://download.osgeo.org/gdal/2.2.3/gdal-2.2.3.tar.gz \
    && tar xzvf gdal-2.2.3.tar.gz \
    && cd gdal-2.2.3 \
    && ./configure --libdir=/usr/lib64 --with-proj=/usr/local/lib --with-threads --with-libtiff=internal --with-geotiff=internal --with-jpeg=internal --with-gif=internal --with-png=internal --with-libz=internal \
    && make && make install 

# Compile and install CDO
RUN cd /opt \
    && wget https://code.mpimet.mpg.de/attachments/download/18264/cdo-1.9.5.tar.gz \
    && tar -xvzf cdo-1.9.5.tar.gz \
    && cd cdo-1.9.5 \
    && ./configure CFLAGS=-fPIC --with-eccodes --with-jasper --with-hdf5 --with-netcdf=${NETCDF}} \
    && make -j$(grep -c ^processor /proc/cpuinfo) && make check && make install \
    && rm -rf cdo-1.9.5

# Set python3 as default
RUN update-alternatives --install /usr/bin/python python /usr/bin/python2 50 \
  && update-alternatives --install /usr/bin/python python /usr/bin/python3.6 60 \
  && update-alternatives --install /usr/bin/pip pip /usr/bin/pip3.6 60

# Install python requirements
RUN  pip install --upgrade pip \
  && pip install --no-cache-dir \
          Cython \
          numpy && \
          CFLAGS="$(gdal-config --cflags) -I/usr/include/udunits2/" \
          pip install --no-cache-dir \
          gdal==2.2.3 \          
          cf-units \
          cdo \
          imageio \
          netCDF4 \
          pyyaml \
          scipy \
          xarray \
          requests \
          requests-html

# Install TDM tools
RUN pushd /tmp \
    && git clone --depth 1 --single-branch -b feature/http_gfs_fetch https://github.com/kikkomep/tdm-tools.git \        
    && cd tdm-tools \
    && python setup.py install \
    && popd \
    && rm -rf tdm-tools

COPY populate finalize.sh link_details.sh \
     run_geogrid run_ungrib run_metgrid run_real \
     /usr/bin/

RUN chmod +x /usr/bin/populate \
             /usr/bin/link_details.sh \
             /usr/bin/run_geogrid  \
             /usr/bin/run_ungrib \
             /usr/bin/run_real \
             /usr/bin/run_metgrid \
             /usr/bin/finalize.sh
