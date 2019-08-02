import os
import sys
import unittest
import f90nml
import tiledb
import xarray
import logging
import numpy as np

sys.path.insert(0, '../')

from writer import DataFile
from writer import WrfConfiguration

_logger = logging.getLogger()
logging.basicConfig(level=logging.DEBUG)

run_id = "run01"
run_dir = "data/run_dir/run01"
data_path = "data/data_dir/all"
arrays_path = "/tmp/wrf-experiments/run01"

check_variables = []


class TestWriter(unittest.TestCase):

    def test_written_data(self):
        simulation = WrfConfiguration(run_id, run_dir, data_path)
        datafiles = simulation.get_datafile_names()
        dimension_info = simulation.get_dimension_domains()
        variables = check_variables \
            if check_variables and len(check_variables) > 0 else simulation.get_all_variables()
        for p, domains in datafiles.items():
            for d, data_files in domains.items():
                for v in variables:
                    variable_array_name = os.path.join(arrays_path, "variables", v)
                    if tiledb.object_type(variable_array_name):
                        with tiledb.DenseArray(variable_array_name) as V:
                            for df in data_files:
                                _logger.info("Checking values on %s", df.filename)
                                nc_data = df.data
                                dimensions = {
                                    dim: tiledb.Dim(dim, domain=dimension_info[dim], dtype=np.int32, tile=size)
                                    for dim, size in nc_data.dims.items()}

                                dom = tiledb.Domain(*list(map(lambda x: dimensions[x], nc_data[v].dims)))
                                _logger.debug("Domain %r", dom)
                                _logger.debug("Dims: %r", nc_data[v].dims)

                                for frame in range(simulation.frames_per_outfile()):
                                    slices = []
                                    _logger.debug("Frame %r", frame)
                                    step = simulation.to_step_number(df.datetime) + frame
                                    time_slice = slice(step, step + 1)
                                    for ndim in range(0, dom.ndim):
                                        if dom.dim(ndim).name == "Time":
                                            slices.append(time_slice)
                                            _logger.debug("Time slice %r", time_slice)
                                        else:
                                            sl = df.get_slice_dimension_size(dom.dim(ndim).name)
                                            _logger.debug("Slice %s: %r", dom.dim(ndim).name, sl)
                                            slices.append(sl)
                                    self.assertTrue(np.array_equal(V[tuple(slices)][v], nc_data[v].data),
                                                    "Correct copy of variable data '%s' (slice: %r) ".format(v, sl))


if __name__ == '__main__':
    unittest.main()
