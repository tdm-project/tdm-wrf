
import os as _os
import json as _json
import tiledb as _tdb
import socket as _socket
import math
import sys as _sys
import numpy as _np
from time import sleep as _sleep
import logging as _logging
import argparse as _argparse
import xml.etree.ElementTree as ET


# set logger
_logger = _logging.getLogger(__name__)

# defaults
COMMANDS = ("initialize", "start")
DEFAULT_CONFIG_FILENAME = "/etc/experiments/config.json"
HDFS_SITE_XML = "hdfs-site.xml"

# load hdfs configuration
# we assume the HADOOP_CONF_DIR is set


def load_hdfs_configutarion(configuration):
    # TODO: fix static HDFS configuration
    # conf_dir = _os.environ["HADOOP_CONF_DIR"]
    # hdfs_conf = _os.path.join(conf_dir, HDFS_SITE_XML)
    # if not _os.path.exists(HDFS_SITE_XML):
    #     raise "Unable to find hdfs configuration, i.e., '%s'".format(hdfs_conf)

    # root = ET.parse(hdfs_conf).getroot()
    # configuration["hdfs"]["namenode_uri"] =
    pass


# load json configuration
def load_configuration(filename):
    _logger.debug("Loading configuration file: %s", filename)
    with open(filename) as f:
        configuration = _json.load(f)
        load_hdfs_configutarion(configuration)
        _logger.debug("Loaded configuration: %s", _json.dumps(
            configuration, indent=4, sort_keys=True))
        return configuration


def wait_for_array(array_name):    
    try:
        _logger.info("Checking if array '%s' exists", array_name)
        while not _tdb.object_type(array_name):        
            _logger.debug("Array '%s' not initialized", array_name)
            _sleep(2)            
    except Exception as e:
        _logger.error(e)
        if _logger.isEnabledFor(_logging.DEBUG):
            _logger.exception(e)
        
# initialize HDFS
def initialize_hdfs(configuration):
    ctx = _tdb.Ctx({
        'vfs.hdfs.username': configuration['hdfs']['user'],
        'vfs.hdfs.name_node_uri': configuration['hdfs']['namenode_uri']})
    array_name = 'hdfs://' + \
        _os.path.join(configuration['hdfs']
                      ['base_dir'], configuration['test_id'])

    tdim = _tdb.Dim(ctx=ctx, name='time', domain=(
        0, configuration['t_size']), dtype=_np.int32, tile=configuration['t_tile'])
    xdim = _tdb.Dim(ctx=ctx, name='X', domain=(
        0, configuration['x_size']), dtype=_np.int32, tile=configuration['x_tile'])
    ydim = _tdb.Dim(ctx=ctx, name='Y', domain=(
        0, configuration['y_size']), dtype=_np.int32, tile=configuration['y_tile'])

    dom = _tdb.Domain(tdim, xdim, ydim, ctx=ctx)
    p = _tdb.Attr(ctx=ctx, name='precipitation', dtype=_np.float32)
    schema = _tdb.ArraySchema(ctx=ctx, domain=dom, sparse=False, attrs=[p])

    try:
        if not _tdb.object_type(array_name):
            _tdb.DenseArray.create(array_name, schema)
    except Exception as e:
        _logger.error(e)
        if _logger.isEnabledFor(_logging.DEBUG):
            _logger.exception(e)


def find_region(replica_id, configuration):
    try:
        n = int(math.sqrt(configuration["replicas"] + 0.001))
        dx = int(configuration["x_size"] // n)
        dy = int(configuration["y_size"] // n)
        i = int(replica_id % n)
        j = int(replica_id // n)
        return slice(i*dx, (i+1)*dx), slice(j*dy, (j+1)*dy)
    except Exception as e:
        _logger.error(e)
        if _logger.isEnabledFor(_logging.DEBUG):
            _logger.exception(e)


def get_replica_id():
    h = _socket.gethostname()
    return int(h.split("-")[2])


def start_writer(configuration):
    random_number = _np.random.rand()
    ctx = _tdb.Ctx({
        'vfs.hdfs.username': configuration['hdfs']['user'],
        'vfs.hdfs.name_node_uri': configuration['hdfs']['namenode_uri']})
    array_name = 'hdfs://' + \
        _os.path.join(configuration['hdfs']
                      ['base_dir'], configuration['test_id'])

    xslice, yslice = find_region(get_replica_id(), configuration)

    data = _np.zeros((xslice.stop-xslice.start, yslice.stop -
                      yslice.start), dtype=_np.float32)

    wait_for_array(array_name)

    for i in range(configuration["t_size"]):
        if configuration["delta_t"] > 0:
            _sleep(_np.random.normal(
                configuration["delta_t"], configuration["delta_t"]*configuration["delta_t_factor"]))
            _logger.info("Mi sono svegliato al passo: %d!!!", i)
        data[:, :] = i * random_number
        with _tdb.DenseArray(ctx=ctx, uri=array_name, mode='w') as A:
            try:
                A[i:(i+1), xslice, yslice] = data
                _logger.info("Ho scritto al passo %d!!!", i)
            except Exception as e:
                _logger.error(e)
                if _logger.isEnabledFor(_logging.DEBUG):
                    _logger.exception(e)


def _make_parser():
    parser = _argparse.ArgumentParser(add_help=True)
    parser.add_argument("cmd",  metavar='CMD',
                        help="Command", choices=COMMANDS)
    parser.add_argument('-f', '--file', default=DEFAULT_CONFIG_FILENAME,
                        help='Path the of json configuration of the experiment)'.format(DEFAULT_CONFIG_FILENAME))
    parser.add_argument('--debug', help='Enable debug mode',
                        action='store_true', default=None)

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
        _logging.basicConfig(
            level=_logging.DEBUG if options.debug else _logging.INFO)

        # load configuration
        configuration = load_configuration(options.file)

        # load configuration
        if options.cmd == COMMANDS[0]:
            initialize_hdfs(configuration)
        else:
            start_writer(configuration)

    except Exception as e:
        _logger.error(e)
        if _logger.isEnabledFor(_logging.DEBUG):
            _logger.exception(e)
        _sys.exit(99)


if __name__ == "__main__":
    main()
