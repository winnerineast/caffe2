#!/bin/bash

# Install script for Anaconda environments with CUDA on linux
# This script is not supposed to be called directly, but should be run by:
#
# $ cd <path to caffe2, e.g. ~/caffe2>
# $ conda build conda/cuda_full
#
# If you're debugging this, it may be useful to use the env that conda build is
# using:
# $ cd <anaconda_root>/conda-bld/caffe2_<timestamp>
# $ source activate _h_env_... # some long path with lots of placeholders
#
# Also, failed builds will accumulate those caffe2_<timestamp> directories. You
# can remove them after a succesfull build with
# $ conda build purge
#

set -ex

echo "Installing caffe2 to ${PREFIX}"

PYTHON_ARGS="$(python ./scripts/get_python_cmake_flags.py)"

# Build with a big suite of libraries
CMAKE_ARGS=()
CMAKE_ARGS+=("-DUSE_CUDA=ON")
CMAKE_ARGS+=("-DUSE_GFLAGS=ON")
CMAKE_ARGS+=("-DUSE_GLOG=ON")
CMAKE_ARGS+=("-DUSE_GLOO=ON")
CMAKE_ARGS+=("-DUSE_LMBD=ON")
CMAKE_ARGS+=("-DUSE_NCCL=ON")
CMAKE_ARGS+=("-DUSE_OPENCV=ON")
CMAKE_ARGS+=("-DUSE_REDIS=ON")

# Explicitly turn unused packages off to prevent cmake from trying to find
# system libraries
CMAKE_ARGS+=("-DUSE_LEVELDB=OFF")
CMAKE_ARGS+=("-DUSE_ROCKSDB=OFF")

# Install under specified prefix
CMAKE_ARGS+=("-DCMAKE_INSTALL_PREFIX=$PREFIX")
CMAKE_ARGS+=("-DCMAKE_PREFIX_PATH=$PREFIX")

CMAKE_ARGS+=("-DCMAKE_CXX_FLAGS=-D__GLIBCXX_USE_CXX11_ABI=0")

mkdir -p build
cd build
cmake "${CMAKE_ARGS[@]}"  $CONDA_CMAKE_ARGS $PYTHON_ARGS ..
make VERBOSE=1 "-j$(nproc)"

make install/fast
