# Pinned external dependencies for VK-GL-CTS (Vulkan Conformance Test Suite)
# Extracted from upstream fetch_sources.py for vulkan-cts-1.4.5.0
# See: https://github.com/KhronosGroup/VK-GL-CTS/blob/main/external/fetch_sources.py
{ fetchurl, fetchFromGitHub, libpng ? null, zlib ? null }:
rec {
  amber = fetchFromGitHub {
    owner = "google";
    repo = "amber";
    rev = "9482448393f3f1f75067cc6ba8ad77fda48691c6";
    hash = "sha256-NiJkSvmo/AvtDCJtbWzIvaDy1DqhUvASxznosM2XS3M=";
  };

  glslang = fetchFromGitHub {
    owner = "KhronosGroup";
    repo = "glslang";
    rev = "7a47e2531cb334982b2a2dd8513dca0a3de4373d";
    hash = "sha256-BXfe5SgjPy5a+FJh4KIe5kwvKVBvo773OfIZpOsDBLo=";
  };

  jsoncpp = fetchFromGitHub {
    owner = "open-source-parsers";
    repo = "jsoncpp";
    rev = "9059f5cad030ba11d37818847443a53918c327b1";
    hash = "sha256-m0tz8w8HbtDitx3Qkn3Rxj/XhASiJVkThdeBxIwv3WI=";
  };

  spirv-headers = fetchFromGitHub {
    owner = "KhronosGroup";
    repo = "SPIRV-Headers";
    rev = "b824a462d4256d720bebb40e78b9eb8f78bbb305";
    hash = "sha256-HjJjMuqTrYv5LUOWcexzPHb8nhOT4duooDAhDsd44Zo=";
  };

  spirv-tools = fetchFromGitHub {
    owner = "KhronosGroup";
    repo = "SPIRV-Tools";
    rev = "8a67272ca6c266b21dd0a9548471756a237ebbef";
    hash = "sha256-VLiIcVNlE7GhquAsEhPLYuBSNOAvhGIjR4zJ1QlPqvI=";
  };

  video_generator = fetchFromGitHub {
    owner = "Igalia";
    repo = "video_generator";
    rev = "426300e12a5cc5d4676807039a1be237a2b68187";
    hash = "sha256-zdYYpX3hed7i5onY7c60LnM/e6PLa3VdrhXTV9oSlvg=";
  };

  vulkan-docs = fetchFromGitHub {
    owner = "KhronosGroup";
    repo = "Vulkan-Docs";
    rev = "60a4ad187cf3be4ede658f0fae7dd392192a314b";
    hash = "sha256-x/ijivXfzDRP6eCWF4rkL6MBiiIITh8vzcTuXQwbHlE=";
  };

  vulkan-validationlayers = fetchFromGitHub {
    owner = "KhronosGroup";
    repo = "Vulkan-ValidationLayers";
    rev = "0a11cf1257471c22b9e7d620ab48057fb2f53cf9";
    hash = "sha256-Qhi+xjFpuL/bQcHqmY8vSZXVf8xuJbrF+0QfgL3120k=";
  };

  vulkan-video-samples = fetchFromGitHub {
    owner = "KhronosGroup";
    repo = "Vulkan-Video-Samples";
    rev = "v0.3.9";
    hash = "sha256-SyW/OzDGPdRPYGG7jgFMp8AkvpZq8Yi/7QZKZugXKho=";
  };

  renderdoc = fetchurl {
    url = "https://raw.githubusercontent.com/baldurk/renderdoc/v1.1/renderdoc/api/app/renderdoc_app.h";
    hash = "sha256-57XwqlsbDq3GOhxiTAyn9a8TOqhX1qQnGw7z0L22ho4=";
  };

  zlib-src =
    if zlib != null && zlib ? src then zlib.src else fetchurl {
      url = "https://github.com/madler/zlib/releases/download/v1.2.13/zlib-1.2.13.tar.gz";
      sha256 = "b3a24de97a8fdbc835b9833169501030b8977031bcb54b3b3ac13740f846ab30";
    };

  libpng-src =
    if libpng != null && libpng ? src then libpng.src else fetchurl {
      url = "https://github.com/pnggroup/libpng/archive/refs/tags/v1.6.50.tar.gz";
      sha256 = "71158e53cfdf2877bc99bcab33641d78df3f48e6e0daad030afe9cb8c031aa46";
    };

  shaderc-src = fetchFromGitHub {
    owner = "google";
    repo = "shaderc";
    tag = "v2024.4";
    hash = "sha256-DIpgHiYAZlCIQ/uCZ3qSucPUZ1j3tKg0VgZVun+1UnI=";
  };

  prePatch = ''
    copy_or_extract() {
      local src="$1"
      local dst="$2"
      mkdir -p "$dst"
      if [ -d "$src" ]; then
        cp -r "$src"/. "$dst"/
      elif [ -f "$src" ]; then
        case "$src" in
          *.tar.gz|*.tgz) tar -xzf "$src" -C "$dst" --strip-components=1 ;;
          *.tar.xz|*.txz) tar -xJf "$src" -C "$dst" --strip-components=1 ;;
          *.tar.bz2|*.tbz2) tar -xjf "$src" -C "$dst" --strip-components=1 ;;
          *) tar -xf "$src" -C "$dst" --strip-components=1 ;;
        esac
      else
        echo "ERROR: expected source path '$src' to be a file or directory" >&2
        exit 1
      fi
    }

    mkdir -p external/renderdoc/src
    cp -r ${renderdoc} external/renderdoc/src/renderdoc_app.h

    mkdir -p external/amber external/glslang external/jsoncpp external/spirv-headers external/spirv-tools external/video_generator external/vulkan-docs external/vulkan-validationlayers external/vulkan-video-samples external/zlib external/libpng

    cp -r ${amber} external/amber/src
    cp -r ${glslang} external/glslang/src
    cp -r ${jsoncpp} external/jsoncpp/src
    cp -r ${spirv-headers} external/spirv-headers/src
    cp -r ${spirv-tools} external/spirv-tools/src
    cp -r ${video_generator} external/video_generator/src
    cp -r ${vulkan-docs} external/vulkan-docs/src
    cp -r ${vulkan-validationlayers} external/vulkan-validationlayers/src
    cp -r ${vulkan-video-samples} external/vulkan-video-samples/src

    # zlib and libpng (required for iOS/Android when FindPackage doesn't find system libs)
    mkdir -p external/zlib external/libpng/src
    copy_or_extract ${zlib-src} external/zlib
    copy_or_extract ${libpng-src} external/libpng/src
    # zlib 1.2.13 uses cmake_minimum_required(VERSION 2.4.4); modern CMake requires 3.5+
    sed 's/cmake_minimum_required(VERSION 2.4.4)/cmake_minimum_required(VERSION 3.5)/' external/zlib/CMakeLists.txt > external/zlib/CMakeLists.txt.tmp && mv external/zlib/CMakeLists.txt.tmp external/zlib/CMakeLists.txt
    if [ -f external/libpng/src/scripts/pnglibconf.h.prebuilt ]; then
      cp external/libpng/src/scripts/pnglibconf.h.prebuilt external/libpng/src/pnglibconf.h
    fi

    chmod u+w -R external
  '';
}
