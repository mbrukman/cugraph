# Copyright (c) 2019, NVIDIA CORPORATION.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

from c_sssp cimport *
from c_graph cimport *
from libcpp cimport bool
from libc.stdint cimport uintptr_t
from libc.stdlib cimport calloc, malloc, free
from libc.float cimport FLT_MAX_EXP
import cudf
from librmm_cffi import librmm as rmm
#from pygdf import Column
import numpy as np

gdf_to_np_dtypes = {GDF_INT32:np.int32, GDF_INT64:np.int64, GDF_FLOAT32:np.float32, GDF_FLOAT64:np.float64}

cpdef sssp(G, source):
    """
    Compute the distance from the specified source to all vertices in the connected component.  The distances column will
    store the distance from the source to each vertex.
    
    Parameters
    ----------
    graph : cuGraph.Graph                  
       cuGraph graph descriptor, should contain the connectivity information as an edge list (edge weights are not used for this algorithm). 
       The transposed adjacency list will be computed if not already present.
    source : int                  
       Index of the source vertex

    Returns
    -------
    distances : 
        GPU data frame containing two cudf.Series of size V: the vertex identifiers and the corresponding SSSP distances.
    
    Examples
    --------
    >>> M = ReadMtxFile(graph_file)
    >>> sources = cudf.Series(M.row)
    >>> destinations = cudf.Series(M.col)
    >>> G = cuGraph.Graph()
    >>> G.add_edge_list(sources,destinations,None)
    >>> distances = cuGraph.sssp(G, source)
    """

    cdef uintptr_t graph = G.graph_ptr
    err = gdf_add_transpose(<gdf_graph*>graph)
    cudf.bindings.cudf_cpp.check_gdf_error(err)

    cdef gdf_graph* g = <gdf_graph*>graph

    data_type = np.float32
    if g.transposedAdjList.edge_data:
        data_type = gdf_to_np_dtypes[g.transposedAdjList.edge_data.dtype]

    df = cudf.DataFrame()
    df['vertex'] = cudf.Series(np.zeros(g.transposedAdjList.offsets.size-1,dtype=np.int32))
    cdef uintptr_t identifier_ptr = create_column(df['vertex'])
    df['distance'] = cudf.Series(np.zeros(g.transposedAdjList.offsets.size-1,dtype=data_type))
    cdef uintptr_t distance_ptr = create_column(df['distance'])

    err = g.transposedAdjList.get_vertex_identifiers(<gdf_column*>identifier_ptr)
    cudf.bindings.cudf_cpp.check_gdf_error(err)

    cdef int[1] sources
    sources[0] = source
    err = gdf_sssp_nvgraph(<gdf_graph*>graph, sources, <gdf_column*>distance_ptr)
    cudf.bindings.cudf_cpp.check_gdf_error(err)

    return df

