FROM crs4/hadoopclient:3.2.0-ubuntu

#FROM hd311
# LABEL maintainer="gianluigi.zanetti@crs4.it"

ARG tiledb_version="1.5.0"
ARG tiledbpy_version="0.4.1"


RUN echo 'APT::Get::Assume-Yes "true";' >> /etc/apt/apt.conf.d/99yes && \
    apt update && \
    apt upgrade && \
    apt install \
      cmake \
      gcc \
      m4 \
      g++ \
      git \
      make \
      python3-dev \
      python3-pip \
      wget && \
    apt-get clean

RUN git clone --depth 1 --single-branch --branch ${tiledb_version} https://github.com/TileDB-Inc/TileDB.git && \
    cd TileDB && \
    mkdir build && \
    cd build && \
    ../bootstrap --prefix=/usr --enable-hdfs --enable-verbose && \
    make  && \
    make install-tiledb && \
    cd ../.. && \
    rm -rf TileDB

RUN git clone --depth 1 --single-branch --branch ${tiledbpy_version} https://github.com/TileDB-Inc/TileDB-Py.git && \
    cd TileDB-Py && \
    pip3 install --no-cache-dir -r requirements_dev.txt && \
    python3 setup.py build_ext --inplace && \
    python3 setup.py install && \
    cd .. && \
    rm -rf TileDB-Py

RUN CLASSPATH=`/opt/hadoop/bin/hadoop classpath --glob` && \
    echo "export CLASSPATH=\"${CLASSPATH}\"" >> /etc/profile.d/hadoop.sh && \
    echo "export HADOOP_HOME=/opt/hadoop" >> /etc/profile.d/hadoop.sh && \
    echo  /usr/lib/jvm/jre/lib/amd64/server > /etc/ld.so.conf.d/jvm.conf && \
    ldconfig

# copy init scripts
COPY init.sh /init.sh
COPY app.py /app.py
# set permissions
RUN chmod +x /init.*