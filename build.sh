#!/bin/bash
set -e

# Create output directory
out_dir=out
rm -rf $out_dir
mkdir -p $out_dir

# Load versions from versions.txt
declare -A versions
while IFS='=' read -r key value; do
  # Skip comments and empty lines
  [[ $key == \#* || -z $key ]] && continue
  versions["$key"]="$value"
done <versions.txt

echo "Building with versions:"
for key in "${!versions[@]}"; do
  echo "  $key: ${versions[$key]}"
done

build() {
  local repo="$1"
  local version="$2"
  local name="$3"
  local build_cmd="$4"
  local is_dependency="${5:-false}" # Whether this is a dependency (not to be released)

  echo "--- Building $name (version: $version) ---"

  mkdir -p build
  cd build

  if [ ! -d "$name" ]; then
    echo "Cloning $name..."
    if [ "$version" != "latest" ]; then
      # Clone with full history when specific version is needed
      git clone "$repo" "$name"
    else
      # Use shallow clone for latest version
      git clone --depth 1 "$repo" "$name"
    fi
    cd "$name"
  else
    echo "Updating $name..."
    cd "$name"
    git fetch
  fi

  # Checkout specific version if not "latest"
  if [ "$version" != "latest" ]; then
    echo "Checking out version: $version"
    git checkout "$version"
  else
    echo "Using latest version"
    git pull
  fi

  # Initialize and update submodules
  echo "Initializing submodules for $name"
  git submodule update --init --recursive

  # Build the project
  eval "$build_cmd"

  if [[ "$is_dependency" != "true" ]]; then
    # Copy built libraries directly to output directory
    echo "Copying $name libraries to $out_dir"
    find "build" -name "*.so" -exec cp {} "../../$out_dir/" \;
  fi

  cd ../..
}

echo "Installing FFmpeg (apt version is out of date)"

FFMPEG_URL="https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl-shared.tar.xz"
OUT_DIR="/tmp/ffmpeg-build"

wget -qO /tmp/ffmpeg.tar.xz "$FFMPEG_URL"
mkdir -p "$OUT_DIR"
tar -xf /tmp/ffmpeg.tar.xz -C "$OUT_DIR"

sudo cp -r "$OUT_DIR/ffmpeg-master-latest-linux64-gpl-shared/bin/"* /usr/local/bin/
sudo cp -r "$OUT_DIR/ffmpeg-master-latest-linux64-gpl-shared/lib/"* /usr/local/lib/
sudo cp -r "$OUT_DIR/ffmpeg-master-latest-linux64-gpl-shared/include/"* /usr/local/include/

sudo ldconfig

echo "FFmpeg installed successfully"

echo "Installing Vapoursynth"

# Build VapourSynth as a dependency (not included in release)
if [ -n "${versions[vapoursynth]}" ]; then
  pip install cython

  build "https://github.com/vapoursynth/vapoursynth.git" \
    "${versions[vapoursynth]}" \
    "vapoursynth" \
    "
    ./autogen.sh
    ./configure
    make
    sudo make install
    " \
    "true"
fi

# Build bestsource
if [ -n "${versions[bestsource]}" ]; then
  build "https://github.com/vapoursynth/bestsource.git" \
    "${versions[bestsource]}" \
    "bestsource" \
    "meson setup build && ninja -C build"
fi

# Build mvtools
if [ -n "${versions[mvtools]}" ]; then
  build "https://github.com/dubhater/vapoursynth-mvtools.git" \
    "${versions[mvtools]}" \
    "mvtools" \
    "meson setup build && ninja -C build"
fi

# Build akarin
if [ -n "${versions[akarin]}" ]; then
  build "https://github.com/Jaded-Encoding-Thaumaturgy/akarin-vapoursynth-plugin.git" \
    "${versions[akarin]}" \
    "akarin" \
    "meson build && ninja -C build"
fi

# Build akarin arm
if [ -n "${versions[akarin-arm]}" ]; then
  build "https://github.com/f0e/akarin-arm.git" \
    "${versions[akarin]}" \
    "akarin-arm" \
    "meson build && ninja -C build"
fi

echo "Build complete. All plugin libraries are in $out_dir directory"
