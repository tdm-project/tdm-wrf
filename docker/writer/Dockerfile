ARG WRF_WRITER_BASE_IMAGE
FROM ${WRF_WRITER_BASE_IMAGE}

ARG TILEDB_VERSION="1.5.0"
ARG TILEDB_PY_VERSION="0.4.1"

ENV DEBIAN_FRONTEND noninteractive

RUN echo 'APT::Get::Assume-Yes "true";' >> /etc/apt/apt.conf.d/99yes && \
    apt update && \
    apt install \
      cmake \
      gcc \
      m4 \
      g++ \
      git \
      make \
      wget \
      python3-dev \
      python3-pip && \      
    pip3 install xarray netCDF4 && \
    apt-get clean

RUN git clone --depth 1 --single-branch --branch ${TILEDB_VERSION} https://github.com/TileDB-Inc/TileDB.git && \
    cd TileDB && \
    mkdir build && \
    cd build && \
    ../bootstrap --prefix=/usr --enable-hdfs --enable-verbose && \
    make  && \
    make install-tiledb && \
    cd ../.. && \
    rm -rf TileDB

RUN git clone --depth 1 --single-branch --branch ${TILEDB_PY_VERSION} https://github.com/TileDB-Inc/TileDB-Py.git && \
    cd TileDB-Py && \
    pip3 install --no-cache-dir -r requirements_dev.txt && \    
    python3 setup.py build_ext --inplace && \
    python3 setup.py install && \
    cd .. && \
    rm -rf TileDB-Py

RUN pip3 install --upgrade numpy>=1.12.0 && \
    pip3 install pyyaml f90nml

RUN CLASSPATH=`/opt/hadoop/bin/hadoop classpath --glob` && \
    echo "export CLASSPATH=\"${CLASSPATH}\"" >> /etc/profile.d/hadoop.sh && \
    echo "export HADOOP_HOME=/opt/hadoop" >> /etc/profile.d/hadoop.sh && \
    echo  /usr/lib/jvm/jre/lib/amd64/server > /etc/ld.so.conf.d/jvm.conf && \
    ldconfig

# copy writer script
COPY writer.py /usr/bin/writer.py

# set permissions
RUN chmod +x /usr/bin/writer.py

RUN pip3 install ipython
