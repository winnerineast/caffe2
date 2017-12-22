#!/bin/bash

set -ex

LOCAL_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$LOCAL_DIR"/.. && pwd)

# Setup ccache symlinks
if which ccache > /dev/null; then
  mkdir -p ./ccache
  ln -sf "$(which ccache)" ./ccache/cc
  ln -sf "$(which ccache)" ./ccache/c++
  ln -sf "$(which ccache)" ./ccache/gcc
  ln -sf "$(which ccache)" ./ccache/g++
  export CCACHE_WRAPPER_DIR="$PWD/ccache"
  export PATH="$CCACHE_WRAPPER_DIR:$PATH"
fi

# Run build script from scripts if applicable
if [[ "${BUILD_ENVIRONMENT}" == *-android* ]]; then
  export ANDROID_NDK=/opt/ndk
  "${ROOT_DIR}/scripts/build_android.sh" "$@"
  exit 0
fi

# Run cmake from ./build directory
mkdir -p ./build
cd ./build

INSTALL_PREFIX="/usr/local/caffe2"
CMAKE_ARGS=("-DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX}")

# Explicitly set Python executable.
# On Ubuntu 16.04 the default Python is still 2.7.
PYTHON="$(which python)"
if [[ "${BUILD_ENVIRONMENT}" == py3* ]]; then
  PYTHON=/usr/bin/python3
  CMAKE_ARGS+=("-DPYTHON_EXECUTABLE=${PYTHON}")
fi

case "${BUILD_ENVIRONMENT}" in
  *-mkl)
    CMAKE_ARGS+=("-DBLAS=MKL")
    ;;
  *-cuda*)
    CMAKE_ARGS+=("-DUSE_CUDA=ON")
    CMAKE_ARGS+=("-DCUDA_ARCH_NAME=Maxwell")
    CMAKE_ARGS+=("-DUSE_NNPACK=OFF")

    # Add ccache symlink for nvcc
    ln -sf "$(which ccache)" "${CCACHE_WRAPPER_DIR}/nvcc"

    # Explicitly set path to NVCC such that the symlink to ccache is used
    CMAKE_ARGS+=("-DCUDA_NVCC_EXECUTABLE=${CCACHE_WRAPPER_DIR}/nvcc")

    # Ensure FindCUDA.cmake can infer the right path to the CUDA toolkit.
    # Setting PATH to resolve to the right nvcc alone isn't enough.
    # See /usr/share/cmake-3.5/Modules/FindCUDA.cmake, block at line 589.
    export CUDA_PATH="/usr/local/cuda"

    # Ensure the ccache symlink can still find the real nvcc binary.
    export PATH="/usr/local/cuda/bin:$PATH"
    ;;
esac

# Try to include Redis support for Linux builds
if [ "$(uname)" == "Linux" ]; then
  CMAKE_ARGS+=("-DUSE_REDIS=ON")
fi

# Configure
cmake "${ROOT_DIR}" ${CMAKE_ARGS[*]} "$@"

# Build
if [ "$(uname)" == "Linux" ]; then
  make "-j$(nproc)" install
else
  echo "Don't know how to build on $(uname)"
  exit 1
fi

# Symlink the caffe2 base python path into the system python path,
# so that we can import caffe2 without having to change $PYTHONPATH.
# Run in a subshell to contain environment set by /etc/os-release.
#
# This is only done when running on Jenkins!  We don't want to pollute
# the user environment with Python symlinks and ld.so.conf.d hacks.
#
if [ -n "${JENKINS_URL}" ]; then
  (
    source /etc/os-release

    function python_version() {
      "$PYTHON" -c 'import sys; print("python%d.%d" % sys.version_info[0:2])'
    }

    # Debian/Ubuntu
    if [[ "$ID_LIKE" == *debian* ]]; then
      python_path="/usr/local/lib/$(python_version)/dist-packages"
      sudo ln -sf "${INSTALL_PREFIX}/caffe2" "${python_path}"
    fi

    # RHEL/CentOS
    if [[ "$ID_LIKE" == *rhel* ]]; then
      python_path="/usr/lib64/$(python_version)/site-packages/"
      sudo ln -sf "${INSTALL_PREFIX}/caffe2" "${python_path}"
    fi

    # /etc/ld.so.conf.d is used on both Debian and RHEL
    echo "${INSTALL_PREFIX}/lib" | sudo tee /etc/ld.so.conf.d/caffe2.conf
    sudo ldconfig
  )
fi
