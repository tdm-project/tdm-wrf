How to run an example
=====================

The general strategy is that all the needed computational steps -- e.g.,
extracting boundary conditions from grib files -- are encapsulated in stateless
docker containers.


Fully parametrized example
--------------------------

Run initialization
..................

The expected operation sequence is the following. The script
`scripts/prepare_input.sh` will do all the following data preparation steps.

 #. Prepare the run configuration file

    .. code-block:: bash
       $ cat param/run.cfg
       WPSPRD_DIR=WPSPRD_DIR
       YEAR=2018
       MONTH=6
       DAY=30
       HOUR=0
       END_HOUR=6
       REQUESTED_RESOLUTION=1p00
       GEOG_NAME="geog_minimum"
      
 #. Prepare, if needed, a data volume with the geographic information, most
    likely it exists already, so we should first check if it is already there
    (not shown). Note that the volume will be created on the fly by docker.

    .. code-block:: bash
       $ docker run -it --rm --mount source=${GEOG_NAME},destination=/geo \
                crs4/tdm-wrf-populate-geo:0.1 ${GEOG_NAME} /geo
       

 #. Download the global boundary condition dataset. The result is read-only. This
    is done by invoking `gfs_fetch` to download the requested dataset from NOAA.

    .. code-block:: bash
       $ printf -v NOAADATA "noaa-%4d%02d%02d_%02d%02d-%s" \
                $YEAR $MONTH $DAY $HOUR 0 ${REQUESTED_RESOLUTION}
       $ docker run --rm -it\
            --mount src=${NOAADATA},dst=/gfs\
            crs4/tdm-wrf-tools:0.1\
            gfs_fetch \
            --year ${YEAR} --month ${MONTH} --day ${DAY} --hour ${HOUR}\
            --target-directory /gfs/model_data\
            --requested-resolution ${REQUESTED_RESOLUTION}


 #. Prepare the geography configuration files in a new, run-specific, volume

    .. code-block:: bash
       $ RUNID=`date -u +"run-%F_%H-%M-%S"`
       $ docker run --rm --mount src=${RUNID},dst=/run\
            --mount type=bind,src=${PWD}/param,dst=/src\
            alpine cp /src/Vtable.GFS /run/Vtable; cp /src/wrf.yaml /run
       $ docker run --rm\
            --mount src=${RUNID},dst=/run\
            crs4/tdm-wrf-tools:0.1 wrf_configurator --target WPS\
            --config /run/wrf.yaml --ofile=/run/namelist.wps\
            -D"geometry.geog_data_path=/geo/"\
            -D"@base.timespan.start.year=${YEAR}"\
            -D"@base.timespan.start.month=${MONTH}"\
            -D"@base.timespan.start.day=${DAY}"\
            -D"@base.timespan.start.hour=${HOUR}"\
            -D"@base.timespan.end.year=${YEAR}"\
            -D"@base.timespan.end.month=${MONTH}"\
            -D"@base.timespan.end.day=${DAY}"\
            -D"@base.timespan.end.hour=${END_HOUR}"

 #. Prepare geography for this run.

    .. code-block:: bash
       $ docker run -it --rm\
           --mount src=${GEOG_NAME},dst=/geo\
           --mount src=${RUNID},dst=/run\
           crs4/tdm-wrf-wps:0.1 run_geogrid /run

 #. Link the boundary conditions files, ungrib and metgrid.

    .. code-block:: bash
       $ docker run -it --rm\
           --mount src=${NOAADATA},dst=/gfs\       
           --mount src=${RUNID},dst=/run\
           crs4/tdm-wrf-tools:0.1\
           link_grib /gfs/model_data /run
       $ docker run -it --rm\
           --mount src=${GEOG_NAME},dst=/geo\       
           --mount src=${NOAADATA},dst=/gfs\       
           --mount src=${RUNID},dst=/run\
           crs4/tdm-wrf-wps:0.1 run_ungrib /run
       $ docker run -it --rm\
           --mount src=${GEOG_NAME},dst=/geo\       
           --mount src=${NOAADATA},dst=/gfs\       
           --mount src=${RUNID},dst=/run\
           crs4/tdm-wrf-wps:0.1 run_metgrid /run

 #. Finalize global boundary information processing.

    .. code-block:: bash
       $ docker run --rm\
           --mount src=${RUNID},dst=/run\
           crs4/tdm-wrf-tools:0.1 wrf_configurator --target WRF\
           --config /run/wrf.yaml --ofile=/run/namelist.input\
           -D"geometry.geog_data_path=/geo/"\           
           -D"@base.timespan.start.year=${YEAR}"\
           -D"@base.timespan.start.month=${MONTH}"\
           -D"@base.timespan.start.day=${DAY}"\
           -D"@base.timespan.start.hour=${HOUR}"\
           -D"@base.timespan.end.year=${YEAR}"\
           -D"@base.timespan.end.month=${MONTH}"\
           -D"@base.timespan.end.day=${DAY}"\
           -D"@base.timespan.end.hour=${END_HOUR}"
       $ docker run -it --rm\
           --mount src=${RUNID},dst=/run\
           crs4/tdm-wrf-arw:0.1 run_real /run


Running a run
.............

 #. Constants

    .. code-block:: bash
    $ NUMPROC=2
    $ NUMTILES=4
    $ NUMSLOTS=4
    

 #. Setting up run parameters.

    .. code-block:: bash
                    
       $ docker run --rm\
           --mount src=${RUNID},dst=/run\
           crs4/tdm-wrf-tools:0.1 wrf_configurator --target WRF\
           --config /run/wrf.yaml --ofile=/run/namelist.input\
           -D"geometry.geog_data_path=/geo/"\           
           -D"@base.timespan.start.year=${YEAR}"\
           -D"@base.timespan.start.month=${MONTH}"\
           -D"@base.timespan.start.day=${DAY}"\
           -D"@base.timespan.start.hour=${HOUR}"\
           -D"@base.timespan.end.year=${YEAR}"\
           -D"@base.timespan.end.month=${MONTH}"\
           -D"@base.timespan.end.day=${DAY}"\
           -D"@base.timespan.end.hour=${END_HOUR}"\
           -D"running.parallel.numtiles=${NUMTILES}"

 #. Setting up mpi hosts file

    .. code-block:: bash

       $ cat > hosts <<EOF
         127.0.0.1 4
         EOF
       $ docker run --rm\
            --mount src=${RUNID},dst=/run\
            --mount type=bind,src=${PWD},dst=/src\
            alpine cp /src/hosts /run/hosts

 #. Running!

    .. code-block:: bash

       $ docker run -it --rm\
            --mount src=${RUNID},dst=/run\       
           crs4/tdm-wrf-arw:0.1 run_wrf /run ${NUMPROC} ${NUMTILES} /run/hosts



           
zag@pflip (ompi-param)$ ls -l ssh/root/
total 12
-rw-r--r-- 1 zag zag  391 Jul 13 23:40 authorized_keys
-rw------- 1 zag zag 1679 Jul 13 20:15 id_rsa
-rw-r--r-- 1 zag zag  391 Jul 13 20:15 id_rsa.pub

zag@pflip (ompi-param)$ docker run -p 2022:2022 -it --rm --mount type=bind,src=${PWD}/ssh,dst=/ssh-key crs4/tdm-wrf-arw:0.1 bash
[root@3864c78302db wrf]# /start_sshd.sh



minikube stop
minikube delete
minikube start
minikube dashboard
kubectl create clusterrolebinding serviceaccounts-cluster-admin   --clusterrole=cluster-admin   --group=system:serviceaccounts
helm template chart --namespace $KUBE_NAMESPACE --name $MPI_CLUSTER_NAME -f values.yaml -f ssh-key.yaml | kubectl -n $KUBE_NAMESPACE create -f -


running on minikube
-------------------




running on aws
--------------


Before you can use an EBS volume with a Pod, you need to create it.

aws ec2 create-volume --availability-zone=eu-west-1a --size=10 --volume-type=g

AWS EBS Example configuration

apiVersion: v1
kind: Pod
metadata:
  name: test-ebs
spec:
  containers:
  - image: k8s.gcr.io/test-webserver
    name: test-container
    volumeMounts:
    - mountPath: /test-ebs
      name: test-volume
  volumes:
  - name: test-volume
    # This AWS EBS volume must already exist.
    awsElasticBlockStore:
      volumeID: <volume-id>
      fsType: ext4


running on ostack
-----------------

cephfs

A cephfs volume allows an existing CephFS volume to be mounted into your
Pod. Unlike emptyDir, which is erased when a Pod is removed, the contents of a
cephfs volume are preserved and the volume is merely unmounted. This means that
a CephFS volume can be pre-populated with data, and that data can be “handed
off” between Pods. CephFS can be mounted by multiple writers simultaneously.

https://github.com/kubernetes/examples/tree/master/staging/volumes/cephfs/
           
Data analysis
-------------

running on sardinia_hires

docker run -it --rm --mount src=run-2018-07-12_09-21-53,dst=/run crs4/tdm-wrf-arw:0.1 run_wrf /run 8 4 /run/hosts ====> 10:23 -> 10:56

|procs|tiles|time(min)|
|-----|-----|---------|
| 8   |  1  |      |
| 8   |  4  |      |
| 8   |  8  |      |
| 4   |  8  |      |
| 5   |  8  |      |
| 10  |  4  |  29  |
| 20  |  2  |  32  |
| 40  |  1  |  24  |





# docker run -i -t -p 8888:8888 crs4/tdm-wrf-analyze /bin/bash -c
# "/opt/conda/bin/jupyter notebook --notebook-dir=/opt/notebooks --ip='*'
#  --port=8888 --no-browser"
