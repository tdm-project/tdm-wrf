#!/usr/bin/env python3

import re as _re
import os as _os
import sys as _sys
import glob as _glob
import numpy as _np
from socket import gethostname
import shutil as _shutil
import time as _time
import json as _json
import xarray as _xr
import yaml as _yaml
import tiledb as _tdb
import socket as _socket
import f90nml as _f90nml
import logging as _logging
import argparse as _argparse
import datetime as _datetime
from time import clock as _clock
from time import sleep as _sleep
from threading import Thread as _Thread
from multiprocessing import Process as _Process

# set logger
_logger = _logging.getLogger(__name__)
_formatter = _logging.Formatter('%(asctime)s %(levelname)5s %(name)s: %(message)s')

# defaults
COMMANDS = ("start", "wait")
DEFAULT_CONFIG_FILENAME = "/etc/wrf-writer/config.json"
HDFS_SITE_XML = "hdfs-site.xml"

# checkpoint
_CHECKPOINT_FILENAME = "checkpoint"
_CHECKPOINT_DATAFILES = "datafiles"
_CHECKPOINT_COMPLETION = "completed"

# wrf config files
WRF_CONFIG_FILE = 'wrf.yaml'
NAME_INPUT_LIST = 'namelist.input'


class Timer:
    def __enter__(self):
        self.start = _clock()
        return self

    def __exit__(self, *args):
        self.end = _clock()
        self.interval = self.end - self.start


def get_replica_id():
    _logger.debug("Extracting replica ID...")
    id_match = _re.search("worker-(\d+)", _socket.gethostname())
    if not id_match:
        replica_id = 1
    else:
        replica_id = id_match.group(1)
    _logger.debug("Replica ID: %d", replica_id)
    _logger.debug("Extracting replica ID: done!")
    return replica_id


def _get_logs_dir(config):
    try:
        logs_dir = config["persistence"]["log_data"]["path"]
    except KeyError as e:
        _logger.exception(e)
        _logger.warning("persistence.log_data.path not found on configuration file: "
                        "the PWD/logs will be used!")
        logs_dir = _os.path.join(_os.getcwd(), "logs")
    return logs_dir


def _init_local_logs_dir(config):
    logs_dir = _os.path.join(_get_logs_dir(config), gethostname())
    _os.makedirs(logs_dir, exist_ok=True)
    while not _os.path.exists(logs_dir):
        _time.sleep(2)
    return logs_dir


def _load_yaml_file(file_path) -> object:
    with open(file_path, 'r') as stream:
        return _yaml.safe_load(stream)


def _setup_logger(name, log_file=None, level=None, stdout=False):
    logger = _logging.getLogger(name)
    if log_file:
        handler = _logging.FileHandler(log_file)
        handler.setFormatter(_formatter)
        logger.addHandler(handler)
    if stdout:
        handler = _logging.StreamHandler(_sys.stdout)
        handler.setFormatter(_formatter)
        logger.addHandler(handler)
    logger.setLevel(_logger.getEffectiveLevel() if not level else level)
    return logger


def _to_datetime(date_time_str):
    return _datetime.datetime.strptime(date_time_str, "%Y-%m-%d_%H:%M:%S")


class Simulation(object):

    def __init__(self, config_filepath) -> None:
        super().__init__()
        self._config_filepath = config_filepath
        self._datafiles = set()
        self._global_configuration = None
        self._namelist = None

    def _load_general_configuration(self):
        self._global_configuration = _load_yaml_file(self._config_filepath)
        _logger.debug("Loaded configuration: %s", _json.dumps(self._global_configuration, indent=4, sort_keys=True))

    @property
    def configuration(self):
        if not self._global_configuration:
            self._load_general_configuration()
        return self._global_configuration

    def wait_for_data(self):
        while not _os.path.exists(self.run_dir):
            _time.sleep(2)

    @property
    def run_id(self):
        try:
            return self.configuration['global']['running']['id']
        except KeyError:
            _logger.warning("Property 'global.running.id' not found in the configuration file."
                            "A random number will be used.")
            run_id = str(_time.time())
            self.configuration['global']['running']['id'] = run_id
            return run_id

    @property
    def run_dir(self):
        return self.configuration['persistence']['run_data']['path']

    @property
    def data_dir(self):
        return self.configuration['persistence']['out_data']['path']

    @property
    def time_step(self):
        return self.configuration['global']['running']['time_step']

    @property
    def domains(self) -> list:
        return self.configuration["domains"].keys()

    def geometry(self, domain='base') -> tuple:
        return self.configuration['domains'][domain]['geometry']

    def frames_per_outfile(self, domain: object = 'base') -> int:
        return self.configuration['domains'][domain]['running']['output']['frames_per_outfile']

    def get_master_log_file(self):
        # TODO: check whether file pattern is OK
        return _os.path.join(self.run_dir, "rsl.out.0000")

    def get_namelist_file(self):
        return _os.path.join(self.run_dir, "namelist.input")

    def get_namelist(self):
        if not self._namelist:
            _logger.debug("Loading namelist.input...")
            self._namelist = _f90nml.read(self.get_namelist_file())
        return self._namelist

    def get_simulation_duration(self):
        # TODO: probably we need only the namelist.wps file
        namelist = self.get_namelist()
        return _np.datetime64(_to_datetime(namelist["share"]["start_date"])), \
               _np.datetime64(_to_datetime(namelist["share"]["end_date"]))

    def get_data_dir(self):
        return _os.path.join(self.data_dir)

    def get_data_file_pattern(self):
        return _os.path.join(self.data_dir, 'wrfout*')

    def get_all_variables(self):
        data_files = _glob.glob(self.get_data_file_pattern())
        if len(data_files) == 0:
            _logger.warning("No datafile found")
            return None
        return [v for v in _xr.open_dataset(data_files[0])]

    def get_datafile_names(self):
        return set(_glob.glob(self.get_data_file_pattern()))

    def _get_datetime_by_prefix(self, data, prefix):
        return (data["{}_year".format(prefix)], data["{}_month".format(prefix)], data["{}_day".format(prefix)],
                data["{}_hour".format(prefix)], data["{}_minute".format(prefix)], data["{}_second".format(prefix)])

    def to_step_number(self, frame_datetime):
        namelist = self.get_namelist()
        time_control = namelist["time_control"]
        domains = namelist["domains"]

        start_time = _datetime.datetime(*self._get_datetime_by_prefix(time_control, "start"))
        result = int((frame_datetime - start_time).seconds / 60 / domains["time_step"])
        _logger.debug("Time control: %r", time_control)
        _logger.debug("Datetime by prefix: %r", self._get_datetime_by_prefix(time_control, "start"))
        _logger.debug("Start TIme: %r", start_time)
        _logger.debug("TimeStep: %r", result)
        return result

    def get_dimension_domains(self):
        namelist = self.get_namelist()

        time_control = namelist["time_control"]
        domains = namelist["domains"]

        start_time = _datetime.datetime(*self._get_datetime_by_prefix(time_control, "start"))
        end_time = _datetime.datetime(*self._get_datetime_by_prefix(time_control, "end"))
        steps = (end_time - start_time).seconds / 60 / domains["time_step"]

        return {
            "Time": (0, steps),
            "bottom_top": (0, domains["num_metgrid_levels"] - 1),
            "bottom_top_stag": (0, domains["num_metgrid_levels"]),
            "soil_layers_stag": (0, domains["num_metgrid_soil_levels"]),
            "south_north": (0, domains["e_sn"] - 1),
            "south_north_stag": (0, domains["e_sn"]),
            "west_east": (0, domains["e_we"] - 1),
            "west_east_stag": (0, domains["e_we"]),
        }

    def check_simulation_completed(self):
        master_log_file = self.get_master_log_file()
        if _os.path.exists(master_log_file):
            return "SUCCESS COMPLETE WRF" in open(self.get_master_log_file()).read()
        return False


class DataFile(object):

    def __init__(self, filename) -> None:
        super().__init__()
        self.filename = filename
        self._data = None

    def is_first_data_file(self):
        return self.datetime == self.simulation_start_time and "0000" in self.filename

    @property
    def domain(self):
        r = _re.search(".*_d(\d+)_.*", self.filename)
        return r.group(1) if r else None

    @property
    def process(self):
        r = _re.search(".*_(\d+)$", self.filename)
        return r.group(1) if r else None

    @property
    def simulation_start_time(self):
        return _datetime.datetime.strptime(self.data.attrs["SIMULATION_START_DATE"], "%Y-%m-%d_%H:%M:%S")

    @property
    def datetime(self):
        r = _re.search(".*_(\d{4}-\d{2}-\d{2}_\d{2}:\d{2}:\d{2}).*", self.filename)
        return _datetime.datetime.strptime(r.group(1), "%Y-%m-%d_%H:%M:%S") if r else None

    @property
    def data(self):
        if not self._data:
            self._data = _xr.open_dataset(self.filename)
        return self._data

    def get_global_dimension_size(self, dim):
        ncdata = self.data
        if dim in ("Time", "soil_layers_stag"):
            if "soil" in dim:
                return 0, ncdata.dims[dim] - 1
            return 0, ncdata.dims[dim]
        unstag = 0 if _re.search("stag", dim) else 1
        dim_name = "{}_GRID_DIMENSION".format(dim.replace("_stag", "").replace("_", "-").upper())
        return 0, ncdata.attrs[dim_name] - unstag

    def get_dimension_size(self, dim):
        ncdata = self.data
        if dim in ("Time", "soil_layers_stag"):
            return 1, ncdata.dims[dim]
        stag = _re.search("stag", dim)
        dim_base_name = dim.replace("_stag", "").replace("_", "-").upper()
        dim_start_name = "{}{}{}".format(dim_base_name, "_PATCH_START", "_STAG" if stag else "_UNSTAG")
        dim_end_name = "{}{}{}".format(dim_base_name, "_PATCH_END", "_STAG" if stag else "_UNSTAG")
        return ncdata.attrs[dim_start_name], ncdata.attrs[dim_end_name]

    def get_slice_dimension_size(self, dim):
        ncdata = self.data
        if dim in ("Time", "soil_layers_stag"):
            return slice(0, ncdata.dims[dim])
        stag = _re.search("stag", dim)
        dim_base_name = dim.replace("_stag", "").replace("_", "-").upper()
        dim_start_name = "{}{}{}".format(dim_base_name, "_PATCH_START", "_STAG" if stag else "_UNSTAG")
        dim_end_name = "{}{}{}".format(dim_base_name, "_PATCH_END", "_STAG" if stag else "_UNSTAG")
        return slice(ncdata.attrs[dim_start_name] - 1, ncdata.attrs[dim_end_name])


class Writer(object):

    def __init__(self, simulation, datafile) -> None:
        """

        :param config:
        :type simulation: Simulation
        :param simulation:
        :type datafile: DataFile
        :param datafile:
        """

        super().__init__()
        # _Thread.__init__(self)
        self.run_id = simulation.run_id
        self.config = simulation.configuration  # TODO: change to persistence
        self.datafile = datafile
        self.simulation = simulation

        # define a name for this writer
        self.name = "{}-{}.log".format(self.run_id, _os.path.basename(self.datafile.filename))

        # logger
        logs_dir = _init_local_logs_dir(self.config)
        logs_filename = _os.path.join(logs_dir, self.name)
        _logger.debug("Logfile name for %s: %s", self.name, logs_filename)
        self.logger = _setup_logger(self.name, log_file=logs_filename, stdout=True, level=_logger.getEffectiveLevel())

        # tiledb commons
        self._tiledb_ctx = None
        self._tiledb_config = None
        self._dimensions = None

        # set variables to be skipped
        self.variable_filter = None
        try:
            self.variable_filter = self.simulation.configuration["persistence"]["out_data"]["variables"].split(',')
            _logger.debug("Variable filter: %r", self.variable_filter)
        except KeyError:
            _logger.warning("Variable filter empty")

        # set attributes to be skipped
        try:
            self.attribute_filter = self.simulation.configuration["persistence"]["out_data"]["attributes"].split(',')
            _logger.debug("Variable filter: %r", self.attribute_filter)
        except KeyError:
            _logger.warning("Attribute filter empty")

        # define name of arrays
        try:
            self.base_path = self.config["persistence"]["out_data"]["path"] \
                if "persistence" in self.config else _os.getcwd()
        except KeyError as e:
            _logger.exception(e)
            _logger.warning(
                "'persistence.out_data.path' not found on WRF configuration file: "
                "the current working dir will be used")
        self.simulation_base_path = _os.path.join(self.base_path, simulation.run_id)
        self._variables_array_path = _os.path.join(self.simulation_base_path, "variables")
        self._attributes_array_name = _os.path.join(self.simulation_base_path, "attributes")
        self._dimensions_array_name = _os.path.join(self.simulation_base_path, "dimensions")
        self._coords_array_name = _os.path.join(self.simulation_base_path, "coords")

    def get_tiledb_context(self):
        if not self._tiledb_ctx:
            params = {}
            if "hdfs" in self.config["persistence"]["out_data"]:
                config = self.config["persistence"]["out_data"]["hdfs"]
                params["vfs.hdfs.username"] = config['user']
                params["vfs.hdfs.name_node_uri"] = config['namenode_uri']
            self._tiledb_ctx = _tdb.Ctx(params)
        self.logger.debug("TileDB Context parameters: %r", self.config)
        return self._tiledb_ctx

    def wait_for_array(self, array_name):
        while True:
            try:
                self.logger.debug("Checking if array '%s' exists: %r", array_name, _tdb.object_type(array_name))
                if _tdb.object_type(array_name):
                    self.logger.debug("Array '%s' initialized", array_name)
                    return True
            except Exception as e:
                self.logger.error(e)
                if self.logger.isEnabledFor(_logging.DEBUG):
                    self.logger.exception(e)
            _sleep(2)

    @property
    def global_attributes_array_name(self):
        return self._attributes_array_name

    @property
    def dimensions_array_name(self):
        return self._dimensions_array_name

    @property
    def coords_array_name(self):
        return self._coords_array_name

    def _get_attribute_type(self, t):
        if t == '<M8[ns]':
            return '|U48'
        return t

    def _create_folders(self, cleanup=False):
        ctx = self.get_tiledb_context()
        if not _tdb.object_type(self.base_path, ctx=ctx):
            _tdb.group_create(self.base_path, ctx=ctx)
        if _tdb.object_type(self.simulation_base_path, ctx=ctx) and cleanup:
            _tdb.remove(self.simulation_base_path, ctx=ctx)
        if not _tdb.object_type(self.simulation_base_path, ctx=ctx):
            _tdb.group_create(self.simulation_base_path, ctx=ctx)
        if not _tdb.object_type(self._variables_array_path, ctx=ctx):
            _tdb.group_create(self._variables_array_path, ctx=ctx)
        if not _tdb.object_type(self._attributes_array_name, ctx=ctx):
            _tdb.group_create(self._attributes_array_name, ctx=ctx)

    def get_dimensions(self):
        if not self._dimensions:
            dimension_info = self.simulation.get_dimension_domains()
            self._dimensions = {dim: _tdb.Dim(dim, domain=dimension_info[dim], dtype=_np.int32, tile=size)
                                for dim, size in self.datafile.data.dims.items()}
        return self._dimensions

    def initialize_arrays(self, cleanup=False):
        _logger.debug("Initializing arrays...")

        # init folders
        self._create_folders(cleanup)

        # tileDB ctx
        ctx = self.get_tiledb_context()
        self.logger.debug("Context configured!")

        # create KV array for global attributes
        self.logger.debug("Initializing global attributes array...")
        attributes_schema = _tdb.KVSchema(attrs=[_tdb.Attr(name="global_attribute", dtype=bytes, ctx=ctx)])
        _tdb.KV.create(self.global_attributes_array_name, attributes_schema, ctx=ctx)
        self.logger.info("Created global attributes array: %s", self.global_attributes_array_name)
        # create KV array for dimensions
        self.logger.debug("Initializing global dimensions array...")
        dimensions_schema = _tdb.KVSchema(attrs=[_tdb.Attr(name="dimension", dtype=bytes, ctx=ctx)])
        _tdb.KV.create(self.dimensions_array_name, dimensions_schema, ctx=ctx)
        self.logger.info("Created dimensions array: %s", self.dimensions_array_name)
        # create KV array for coords
        self.logger.debug("Initializing global coords array...")
        coords_schema = _tdb.KVSchema(attrs=[_tdb.Attr(name="coord", dtype=bytes, ctx=ctx)])
        _tdb.KV.create(self.coords_array_name, coords_schema, ctx=ctx)
        self.logger.info("Created coords array: %s", self.coords_array_name)

        # represents dimensions
        ncdata = self.datafile.data
        dimension_info = self.simulation.get_dimension_domains()
        self.logger.debug("Dimension info: %r", dimension_info)
        dimensions = {dim: _tdb.Dim(dim, domain=dimension_info[dim], dtype=_np.int32, tile=size)
                      for dim, size in ncdata.dims.items()}
        self.logger.debug("dimensions: %r", dimensions)

        for cname, var in ncdata.variables.items():

            if self.variable_filter and cname not in self.variable_filter:
                self.logger.info("Skipping variable %s", cname)
                continue

            self.logger.info("Initializing arrays for variable '%s'...", cname)

            # store variable attributes (as KV)
            attributes_array_name = _os.path.join(self._attributes_array_name, cname)
            self.logger.info("Initializing array "
                             "for variable attributes '%s' (array: '%s')...", cname, attributes_array_name)
            attributes_schema = _tdb.KVSchema(attrs=[_tdb.Attr(name=cname, dtype=bytes, ctx=ctx)])
            if not _tdb.object_type(attributes_array_name, ctx=ctx):
                _tdb.KV.create(attributes_array_name, attributes_schema, ctx=ctx)
                self.logger.info("Created array for attributes of variable %s", cname)

            # store variable data
            dom = _tdb.Domain(*list(map(lambda x: dimensions[x], var.dims)), ctx=ctx)
            variable_array_name = _os.path.join(self._variables_array_path, cname)
            self.logger.info("Initializing array "
                             "for variable '%s' (array: '%s')...", cname, variable_array_name)
            self.logger.debug("Configuring variable %s", cname)
            self.logger.debug("Dom ndim %r" % dom.ndim)
            self.logger.debug("Domain: %r", dom)
            self.logger.debug("Defining variable %s (%r)", cname, var.dtype)
            attribute = _tdb.Attr(name=cname, dtype=self._get_attribute_type(var.dtype), ctx=ctx)
            variable_schema = _tdb.ArraySchema(domain=dom, sparse=False, attrs=[attribute], ctx=ctx)
            self.logger.debug("Schema... %r", variable_schema)
            if not _tdb.object_type(variable_array_name, ctx=ctx):
                _tdb.DenseArray.create(variable_array_name, variable_schema)
                self.logger.info("Created array for variable %s", cname)

    def consolidate_arrays(self):
        config = _tdb.Config()
        # global attributes
        _tdb.consolidate(config=config, uri=self.global_attributes_array_name)
        self.logger.info("Consolidated global attributes array: %s", self.global_attributes_array_name)
        # dimensions
        _tdb.consolidate(config=config, uri=self.dimensions_array_name)
        self.logger.info("Consolidated dimensions array: %s", self.dimensions_array_name)
        # coords
        _tdb.consolidate(config=config, uri=self.coords_array_name)
        self.logger.info("Consolidated coords array: %s", self.coords_array_name)
        # variables and their attributes
        ncdata = self.datafile.data
        for cname, var in ncdata.variables.items():
            # store variable attributes (as KV)
            attributes_array_name = _os.path.join(self._attributes_array_name, cname)
            _tdb.consolidate(config=config, uri=attributes_array_name)
            self.logger.info("Consolidated array for attributes of variable %s", cname)
            # variable array
            variable_array_name = _os.path.join(self._variables_array_path, cname)
            _tdb.consolidate(config=config, uri=variable_array_name)
            self.logger.info("Consolidated array for variable %s", cname)

    def write_global_attributes(self):
        ctx = self.get_tiledb_context()
        ncdata = self.datafile.data

        self.wait_for_array(self.global_attributes_array_name)
        with _tdb.KV(self.global_attributes_array_name, 'w', ctx=ctx) as KV:
            for n, v in ncdata.attrs.items():
                # filter out variables
                if self.attribute_filter and n not in self.attribute_filter:
                    self.logger.info("Skipping attribute %s", n)
                    continue
                self.logger.debug("Writing attribute %r --> %s (%r)", n, v, type(v))
                KV[n] = str(v)
            # KV.consolidate()
        # check  FIXME: to be removed
        with _tdb.KV(self.global_attributes_array_name, mode='r', ctx=ctx) as KV:
            for k in KV:
                self.logger.debug(k)

        # store attributes
        self.wait_for_array(self.dimensions_array_name)
        with _tdb.KV(self.dimensions_array_name, 'w', ctx=ctx) as KV:
            for n, v in ncdata.dims.items():
                self.logger.debug("Writing dimension %r --> %s (%r)", n, v, type(v))
                KV[n] = str(v)
            # KV.consolidate()
        with _tdb.KV(self._dimensions_array_name, mode='r', ctx=ctx) as KV:
            for k in KV:
                self.logger.debug(k)

        # store coords
        self.wait_for_array(self.coords_array_name)
        with _tdb.KV(self.coords_array_name, 'w', ctx=ctx) as KV:
            for n in ncdata.coords.keys():
                self.logger.debug("Writing dimension %r --> %s (%r)", n, v, type(v))
                KV[n] = n
            # KV.consolidate()
        with _tdb.KV(self.coords_array_name, mode='r', ctx=ctx) as KV:
            for k in KV:
                self.logger.debug(k)

    def write_array_attributes(self, var, cname):
        ctx = self.get_tiledb_context()
        attributes_array_name = _os.path.join(self._attributes_array_name, cname)
        self.wait_for_array(attributes_array_name)
        with _tdb.KV(attributes_array_name, 'w', ctx=ctx) as KV:
            for n, v in var.attrs.items():
                # filter out variables
                if self.attribute_filter and n not in self.attribute_filter:
                    self.logger.info("Skipping attribute %s", n)
                    continue
                self.logger.debug("Writing attribute %r --> %s (%r)", n, v, type(v))
                KV[n] = str(v) if v else "None"
            KV.consolidate()

    def get_domain(self, var):
        ctx = self.get_tiledb_context()
        dimensions = self.get_dimensions()
        return _tdb.Domain(*list(map(lambda x: dimensions[x], var.dims)), ctx=ctx)

    def get_slices(self, cname, dom, frame, var):
        slices = []
        step = self.simulation.to_step_number(self.datafile.datetime) + frame
        time_slice = slice(step, step + 1)
        for ndim in range(0, dom.ndim):
            self.logger.debug("Variable name: %s", cname)
            self.logger.debug("Domain: %r", dom)
            self.logger.debug("Variable: %r", var)
            if dom.dim(ndim).name == "Time":
                slices.append(time_slice)
                self.logger.debug("Time slice %r", time_slice)
            else:
                slices.append(self.datafile.get_slice_dimension_size(dom.dim(ndim).name))
        return slices

    def write_array_frame(self, cname, frame, var, dom):

        ctx = self.get_tiledb_context()

        variable_array_name = _os.path.join(self._variables_array_path, cname)
        self.logger.debug("Writing variable %s", variable_array_name)
        self.wait_for_array(variable_array_name)

        self.logger.debug("Defining variable %s (%r)", cname, var.dtype)

        slices = self.get_slices(cname, dom, frame, var)

        try:
            with _tdb.DenseArray(variable_array_name, 'w', ctx=ctx) as A:
                self.logger.debug(slices)
                self.logger.debug("Writing data of variable '%s':", cname)
                self.logger.info("Slices: %r", tuple(slices))
                A[tuple(slices)] = {cname: var.data}
        except Exception as e:
            self.logger.error(e)
            self.logger.error(e)
            if self.logger.isEnabledFor(_logging.DEBUG):
                self.logger.exception(e)

    def write_file_frames(self):
        self.logger.info("Triggered write frames on file '%s' @ start '%s'",
                         self.datafile.filename, self.datafile.datetime)

        ctx = self.get_tiledb_context()
        ncdata = self.datafile.data

        self.logger.debug("Is the first datafile: %s", self.datafile.is_first_data_file())
        if self.datafile.is_first_data_file():
            #
            self.initialize_arrays()
            # store global attributes
            self.write_global_attributes()

        # set time delta
        delta_time = _datetime.timedelta(seconds=self.simulation.time_step)
        self.logger.debug("delta time: '%s'", delta_time)

        try:

            # represents dimensions
            skipped = []
            self.logger.debug("Number of frames per outfile: %s", self.simulation.frames_per_outfile())

            for cname, var in ncdata.variables.items():

                # filter out variables
                if self.variable_filter and cname not in self.variable_filter:
                    self.logger.info("Skipping variable %s", cname)
                    continue

                # write array attributes
                self.write_array_attributes(var, cname)

                for frame in range(self.simulation.frames_per_outfile()):
                    self.logger.debug("Step: %d", frame)

                    dom = self.get_domain(var)
                    self.logger.debug("Dom ndim %r" % dom.ndim)


                    # write array frame
                    self.write_array_frame(cname, frame, var, dom)

        except Exception as e:
            self.logger.error(e)
            if self.logger.isEnabledFor(_logging.DEBUG):
                self.logger.exception(e)

    def run(self):
        _logger.debug("Starting writer thread %s", self.name)
        self.write_file_frames()
        _logger.debug("Finished writer thread %s", self.name)


class WriterManager(object):

    def __init__(self, simulation):
        self.simulation = simulation
        self.writers = {}
        self.base_logs_dir = _get_logs_dir(simulation.configuration)
        self.local_logs_dir = _init_local_logs_dir(simulation.configuration)
        self.checkpoint_file = _os.path.join(self.local_logs_dir, _CHECKPOINT_FILENAME)
        self._datafiles = set()
        self.checkpoint = {}
        self._load_checkpoint()
        self._init_checkpoint()

    def _init_checkpoint(self):
        if _CHECKPOINT_COMPLETION not in self.checkpoint:
            self.checkpoint[_CHECKPOINT_COMPLETION] = False
        if _CHECKPOINT_DATAFILES not in self.checkpoint:
            self.checkpoint[_CHECKPOINT_DATAFILES] = {}

    def _load_checkpoint(self):
        if _os.path.exists(self.checkpoint_file):
            with open(self.checkpoint_file) as f:
                self.checkpoint = _json.load(f)
                self._datafiles = set(
                    {df for df in self.checkpoint[_CHECKPOINT_DATAFILES] if self.checkpoint[_CHECKPOINT_DATAFILES][df]})
                _logger.debug("Loaded checkpoint %s", _json.dumps(self.checkpoint))

    def _update_datafile_checkpoint(self, data_filename, processed=False):
        if data_filename:
            if _CHECKPOINT_DATAFILES not in self.checkpoint:
                self.checkpoint[_CHECKPOINT_DATAFILES] = {}
            self.checkpoint[_CHECKPOINT_DATAFILES][data_filename] = processed
            self._datafiles.add(data_filename)
            self._update_checkpoint()

    def _update_checkpoint(self, completed=False):
        self.checkpoint[_CHECKPOINT_COMPLETION] = completed
        with open(self.checkpoint_file, 'w') as f:
            _json.dump(self.checkpoint, f)

    def _is_processed(self, data_filename):
        return data_filename in self.checkpoint[_CHECKPOINT_DATAFILES] \
               and self.checkpoint[_CHECKPOINT_DATAFILES][data_filename]

    def _check_for_new_datafiles(self):
        _logger.debug("Checking for new files...")
        _logger.debug("Set of processed datafiles %r", self._datafiles)
        current_set = self.simulation.get_datafile_names()
        _logger.debug("Current datafiles set: %r", current_set)
        new_datafiles = current_set.difference(self._datafiles)
        for f in current_set:
            _logger.debug("{} in set".format(f) if f in self._datafiles else "{} not in set".format(f))
        _logger.debug("Set of new datafiles : %r", new_datafiles)
        return new_datafiles if len(new_datafiles) > 0 else None

    @staticmethod
    def to_data_files_map(datafile_names):
        data_files = list(map(lambda x: DataFile(x), datafile_names))
        data_file_map = {
            p: {
                d: sorted(list(filter(lambda z: z.process == p and z.domain == d, data_files)),
                          key=lambda k: k.filename, reverse=True)
                for d in map(lambda y: y.domain, data_files)
            } for p in sorted(map(lambda x: x.process, data_files))
        }

        for process, domains in data_file_map.items():
            for domain, file_list in domains.items():
                _logger.debug("Process %s (domain %s): %r", process, domain, [f.filename for f in file_list])
        return data_file_map

    @staticmethod
    def start_writer_thread(simulation, datafile):
        writer = Writer(simulation, datafile)
        writer.write_file_frames()

    def start_writer(self, datafile, multiprocessing=False):
        """
        
        :type datafile: DataFile
        :param datafile: 
        :param multiprocessing: 
        :return: 
        """""
        p = None
        _logger.debug("%r", self.checkpoint)
        if not self._is_processed(datafile.filename):
            _logger.debug("Writing data file '%s' of process '%s' on domain '%s'",
                          datafile.filename, datafile.process, datafile.domain)
            self._update_datafile_checkpoint(datafile.filename)
            writer = Writer(self.simulation, datafile)
            if multiprocessing:
                # p = _Process(target=writer.write_file_frames, args=(), name=writer.name)
                # self.writers[datafile.filename] = p
                # p.start()
                # _logger.info("Writer %s (pid: %d) started", p.name, p.pid)
                # p = _Thread(target=WriterManager.start_writer_thread,
                #             args=(self.simulation, datafile), name=datafile.filename)
                # self.writers[datafile.filename] = p
                # p.start()
                # _logger.info("Writer %s started", writer.name)
                raise Exception("Multiprocessing unsupported yet!!!")
            else:
                _logger.debug("Is the first datafile: %s", writer.datafile.is_first_data_file())
                writer.write_file_frames()
                self._update_datafile_checkpoint(writer.datafile.filename, True)
                _logger.info("Writer %s finished!", writer.name)
        else:
            _logger.debug("Datafile %s already processed", datafile.filename)
        return p

    def start_writers(self, multiprocessing=True):
        _logger.debug('Starting writers...')
        while True:
            completed = self.simulation.check_simulation_completed()
            current_datafile_names = self._check_for_new_datafiles()
            if current_datafile_names:
                _logger.debug("New files found!!!")
                for process, domains in WriterManager.to_data_files_map(current_datafile_names).items():
                    for domain, file_list in domains.items():
                        while len(file_list) > 1:
                            data_file = file_list.pop()
                            self.start_writer(data_file, multiprocessing)
                        if len(file_list) != 1:
                            _logger.error("Expected last file not found (process: %s, domain: %s) !!!", process, domain)
                        if completed:
                            data_file = file_list[0]
                            _logger.debug("Processing last file '%s' of process: %s (domain: %s) !!!",
                                          data_file.filename, process, domain)
                            self.start_writer(data_file, multiprocessing)
            if completed:
                _logger.info("Simulation completed")
                # wait until writer finish
                for data_filename, process in self.writers.items():
                    # _logger.info("Waiting for writer '%s' (pid: %d) to finish...", process.name, process.pid)
                    _logger.info("Waiting for writer '%s' to finish...", process.name)
                    process.join()
                    # _logger.info("Writer %s (pid: %d) finished", process.name, process.pid)
                    _logger.info("Writer %s finished", process.name)
                _logger.debug("New files? %r", self._check_for_new_datafiles())
                if not self._check_for_new_datafiles():
                    _logger.info("No new file found: writer has finished!")
                    self._update_checkpoint(True)
                    _time.sleep(3600)

            # wait before checking for new datafile
            _time.sleep(5)
        # _logger.debug('Stopped writers!!!')

    def check_writers_completion(self):
        _logger.debug("Checking checkpoints...")
        checkpoint_files = [_os.path.join(p, _CHECKPOINT_FILENAME) for p in _os.listdir(self.base_logs_dir) if
                            _os.path.isdir(p)]
        for f in checkpoint_files:
            with open(f) as fp:
                checkpoint = _json.load(fp)
                if checkpoint and not checkpoint[_CHECKPOINT_COMPLETION]:
                    _logger.debug("Completion on '%s': False", f)
                    return False
        return True

    def wait_for_finish(self):
        """
        :type simulation: Simulation
        :param simulation:
        :return:
        """
        # set base logs folder
        logs_dir = _get_logs_dir(self.simulation.configuration)
        # wait until simulation has finished!
        _logger.info("Waiting for simulation to finish...")
        while not self.simulation.check_simulation_completed():
            _logger.debug("Simulation has not finished yet... (wait 5 sec.)")
            _time.sleep(5)
        _logger.info("Simulation has finished!")
        # detect writers checkpoints
        while not self.check_writers_completion():
            _time.sleep(5)


def _make_parser():
    parser = _argparse.ArgumentParser(add_help=True)
    parser.add_argument("cmd", metavar='CMD',
                        help="Command", choices=COMMANDS)
    parser.add_argument('-f', '--file', default=DEFAULT_CONFIG_FILENAME,
                        help='Path the of json configuration of the experiment)'.format(DEFAULT_CONFIG_FILENAME))
    parser.add_argument('--debug', help='Enable debug mode',
                        action='store_true', default=None)
    parser.add_argument('-m', '--multiprocessing', help='Enable multiprocessing for parallel writes',
                        action='store_true', default=False)
    return parser


def _parse_cli_arguments(parser, cmd_args):
    args = parser.parse_args(cmd_args)
    # check if file exists
    if not _os.path.isfile(args.file):
        parser.error(
            "Test configuration file {} doesn't exist or isn't a file".format(args.file))
    return args


def main():
    try:
        # parse arguments
        parser = _make_parser()
        options = _parse_cli_arguments(parser, _sys.argv[1:])

        # setup logging
        handler = _logging.StreamHandler(_sys.stdout)
        handler.setFormatter(_formatter)
        logger = _logging.getLogger(__name__)
        logger.setLevel(_logging.DEBUG if options.debug else _logging.INFO)
        logger.addHandler(handler)

        # load wrf configuration
        simulation = Simulation(options.file)
        simulation.wait_for_data()

        # launch user command
        if options.cmd == COMMANDS[0]:
            mgt = WriterManager(simulation)
            mgt.start_writers(options.multiprocessing)
        elif options.cmd == COMMANDS[1]:
            mgt = WriterManager(simulation)
            mgt.wait_for_finish()
        else:
            _logger.error("Unsupported command ", options.cmd)

    except KeyboardInterrupt:
        _logger.info("Interrupted by user")
    except Exception as e:
        _logger.error(e)
        if _logger.isEnabledFor(_logging.DEBUG):
            _logger.exception(e)
        _sys.exit(99)


if __name__ == "__main__":
    main()
