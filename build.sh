#!/bin/bash
#
# Builds libhdf5 and its JNI glue libhdf5_java from the official HDF5 source release
# inside a manylinux_2_28 container, so they run on glibc 2.28 and newer.
# The HDF Group only publishes Linux binaries built on Ubuntu 24.04, which need glibc 2.38.
#
# Usage:
#   docker run --rm -v "$PWD:/build:ro" -v "$PWD/dist:/dist" quay.io/pypa/manylinux_2_28_x86_64 /build/build.sh
# from this directory, use manylinux_2_28_aarch64 for ARM64
set -euo pipefail

HDF5_VERSION="${HDF5_VERSION:-2.2.0}"
HDF5_SHA256="${HDF5_SHA256:-1a1ab8209b35586fbc1aa279ba76d102130b95badcb20ca329587219112d8c16}"
HDF5_SOVERSION="${HDF5_SOVERSION:-320}"
MAX_GLIBC="2.28"
PLATFORM="manylinux_2_28_$(uname -m)"
DIST="${DIST:-/dist}"
WORK="$(mktemp -d)"

dnf install -y -q java-21-openjdk-devel
pipx install ninja
export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"

cd "$WORK"
curl -fsSL -o "hdf5-${HDF5_VERSION}.tar.gz" "https://github.com/HDFGroup/hdf5/releases/download/${HDF5_VERSION}/hdf5-${HDF5_VERSION}.tar.gz"
echo "${HDF5_SHA256}  hdf5-${HDF5_VERSION}.tar.gz" | sha256sum -c -
tar xzf "hdf5-${HDF5_VERSION}.tar.gz"
SRC="$(find "$WORK" -mindepth 1 -maxdepth 1 -type d -name 'hdf5*' | head -n 1)"

# Uses the ci-StdShar-GNUC preset of the official release,
# but only builds the shared C library and the JNI bindings.
cmake -S "$SRC" -B build --preset ci-StdShar-GNUC \
	-DCMAKE_INSTALL_PREFIX="$WORK/install" \
	-DCMAKE_INSTALL_LIBDIR=lib \
	-DCMAKE_INSTALL_RPATH='$ORIGIN' \
	-DBUILD_STATIC_LIBS=OFF \
	-DBUILD_TESTING=OFF \
	-DHDF5_BUILD_EXAMPLES=OFF \
	-DHDF5_PACK_EXAMPLES=OFF \
	-DHDF5_BUILD_TOOLS=OFF \
	-DHDF5_BUILD_UTILS=OFF \
	-DHDF5_BUILD_HL_LIB=OFF \
	-DHDF5_BUILD_CPP_LIB=OFF \
	-DHDF5_BUILD_FORTRAN=OFF \
	-DHDF5_BUILD_DOC=OFF \
	-DHDF5_ENABLE_PLUGIN_SUPPORT=OFF
cmake --build build --parallel "$(nproc)"
cmake --install build

OUT="$WORK/hdf5-${HDF5_VERSION}-${PLATFORM}"
mkdir -p "$OUT"
cp "$(readlink -f "$WORK/install/lib/libhdf5.so.${HDF5_SOVERSION}")" "$OUT/libhdf5.so.${HDF5_SOVERSION}"
cp "$(readlink -f "$WORK/install/lib/libhdf5_java.so")" "$OUT/libhdf5_java.so"
cp "$SRC/LICENSE" "$OUT/LICENSE"
strip --strip-unneeded "$OUT"/*.so*

{
	echo "HDF5 ${HDF5_VERSION} (${PLATFORM})"
	echo "Source: https://github.com/HDFGroup/hdf5/releases/download/${HDF5_VERSION}/hdf5-${HDF5_VERSION}.tar.gz"
	echo "Source SHA-256: ${HDF5_SHA256}"
	echo "Compiler: $(gcc --version | head -n 1)"
	echo "JDK: $(javac -version 2>&1)"
	for lib in "$OUT"/*.so*; do
		echo "$(basename "$lib"): $(readelf -d "$lib" | grep -E 'NEEDED|SONAME|RUNPATH' | sed -E 's/.*\((\w+)\).*\[(.*)\]/\1=\2/' | tr '\n' ' ')"
	done
} > "$OUT/BUILDINFO"
cat "$OUT/BUILDINFO"

mkdir -p "$DIST"
tar czf "$DIST/hdf5-${HDF5_VERSION}-${PLATFORM}.tar.gz" --owner=0 --group=0 --numeric-owner -C "$WORK" "$(basename "$OUT")"
