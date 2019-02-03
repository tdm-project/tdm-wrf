TDM WRF components
==================

Docker images
-------------

The general strategy is that all the needed computational steps -- e.g.,
extracting boundary conditions from grib files -- are encapsulated in stateless
docker containers.


Our containerization of WRF is based on the following subdivision. See the WRF
`User Manual`_.

 #. `tdm/wrf-base` starting from a centos image (ARG VERSION, default=latest)
    install the compilation environment needed, downloads and unpack the
    required (ARG WRF_VERSION >= 4.0, default 4.0.3) version of WRF from
    github. Note that it does not compile WRF. The main purpose of this image is
    to insure that a consistent version of WRF is used across this docker images
    cluster.

 #. `tdm/wrf-wsp` starting from `tdm/wrf-base` (arg BASE_VERSION,
    default=latest) it downloads the WPS matching the WRF version contained in
    `tdm/wrf-base` and compiles (serial version, as suggested by the manual)
    first WRF and then WPS. All WPS related activities can be perfomed using
    this container.

  #. `tdm/wrf-wrf` starting from `tdm/wrf-base` (arg BASE_VERSION,
    default=latest) it compiles WRF with (arg CMODE, default=32) and (arg NEST,
    default=0)  CMODE=33 DMPAR, CMODE=34 SMPAR, CMODE=35 DMPAR + SMPAR
    NEST=0 plain, NEST=1 nested, see the WRF `User Manual`_.



Kubernetes
----------

See the discussion on StackHPC_ and github for ideas.
    

.. _User Manual: http://www2.mmm.ucar.edu/wrf/users/docs/user_guide_v4/v4.0/users_guide_chap2.html#_Building_the_WRF_1

.. _StackHPC: https://www.stackhpc.com/k8s-mpi.html

    
