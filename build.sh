#!/bin/bash
set -e

# Create output directory
out_dir=out
rm -rf $out_dir
mkdir -p $out_dir

# Get submodule information
echo "Checking submodules:"
git submodule status --recursive | while read line; do
  echo "  $line"
done

# Initialize and update all submodules
echo "Initializing and updating submodules..."
git submodule update --init --recursive

build() {
  local submodule_path="$1"
  local name="$2"
  local build_cmd="$3"
  local is_dependency="${4:-false}" # Whether this is a dependency (not to be released)

  if [ ! -d "$submodule_path" ]; then
    echo "Error: Submodule $submodule_path not found. Make sure it's properly added and initialized."
    return 1
  fi

  local commit_hash=$(git -C "$submodule_path" rev-parse HEAD)
  echo "--- Building $name (commit: ${commit_hash:0:8}) ---"

  cd "$submodule_path"

  # Initialize and update any nested submodules within this submodule
  echo "Initializing nested submodules for $name"
  git submodule update --init --recursive

  # Build the project
  eval "$build_cmd"

  if [[ "$is_dependency" != "true" ]]; then
    # Copy built libraries directly to output directory
    echo "Copying $name libraries to $out_dir"
    find "build" -name "*.so" -exec cp {} "../$out_dir/$name" \;
  fi

  cd ..
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

# Build VapourSynth
echo "Building & installing Vapoursynth"

pip install cython

build "vapoursynth" \
  "vapoursynth" \
  "./autogen.sh
  ./configure
  make
  sudo make install" \
  "true"

echo "Building plugins"

# Build akarin
build "akarin" \
  "akarin" \
  "meson build && ninja -C build"

# Build akarin arm
build "akarin-arm" \
  "akarin-arm" \
  "meson build && ninja -C build"

# Build bestsource
build "bestsource" \
  "bestsource" \
  "meson setup build && ninja -C build"

# Build mvtools
build "mvtools" \
  "mvtools" \
  "meson setup build && ninja -C build"

echo "Build complete. All plugin libraries are in $out_dir directory"