
# Seamless Water

A small *Spore* mod that removes the seams in planet water: the waves, foam and surface pattern on seas and lakes no
longer break off along lines across the planet.

Current version: **1.1.0**. Download `SeamlessWater.sporemod` from the
[Seamless Water 1.1.0](../../releases/tag/v1.1.0) release.

## What it changes

Spore builds a planet from six square faces bent into a sphere. Its water shaders lay the wave texture, the foam and
the surface pattern over each face by that face's own texture coordinates, so where two faces meet the pattern breaks
off along a visible line.

Seamless Water replaces the game's planet water shaders with versions that sample those textures by the direction from
the planet's centre instead: three projections, one along each axis, blended by how the surface faces them. The wave
direction is then laid flat on the sphere at that point. At low water quality, where the game moves the surface with a
simple wave, the ripples are computed from the same direction. The pattern is continuous everywhere on the planet.
Everything else the water shaders do stays as in the game: colour, depth, the shine of the sky, refraction, shadows
and the three quality levels.

The change applies to planet water in every stage that shows a planet: creature, tribe, civilization, space and
adventures.

## What it does not change

- **The cell stage** uses other shaders and is not touched.
- **Lava and ice planets** are drawn with other shaders and keep the game's look.
- **Textures, the wave animation speed and the water colour** come from the game as before.

## Performance

The textures of the water are sampled three times instead of once, so water costs a little more on the video card.
This has not been measured.

## Installation

1. Install the [Spore ModAPI Launcher Kit](https://davoonline.com/sporemodder/rob55rod/ModAPI/Public/index.html)
   if you do not have it yet.
2. Open `SeamlessWater.sporemod` with **Spore ModAPI Easy Installer**.
3. Start the game with **Spore ModAPI Launcher**. If the game was already running, restart it completely.

To remove the mod, use **Spore ModAPI Easy Uninstaller → Seamless Water**. The mod stores nothing in saves.

Seamless Water supports *Spore Galactic Adventures* with the March 2017 patch (`SporeApp_ModAPIFix.exe`, the version
the ModAPI Launcher Kit runs). On any other game build it changes nothing and shows a message instead. It also
shows a message when it finds water shaders it does not know, and then leaves the water as it is.

## Other mods

Seamless Water only exchanges the game's water shader objects; it hooks no game functions. When another mod has
already replaced the same water shaders with ones Seamless Water does not know, it leaves all of them alone and says
so in a message. [Truely!NO-LOD](https://github.com/codestlover/Spore-TruelyNoLOD) works together with it.

Truely!NO-LOD:Enchanted, the edition of that mod with real reflections in the water, is linked to this one. The water
shaders of the usual graphics path call the reflection from `src/shaders/WaterReflection.hlsli`. Each is built twice
from the same source: once with a stand-in for that file that leaves the colour as it is, which gives byte for byte
the shader tried in the game, and once with the reflection. The exported function `SeamlessWater_Link` hands the
second versions over with a contract number, so a change to the water here reaches the reflections by itself, in any
load order. Alone, Seamless Water draws exactly what it did before.

## How it works

The mod is a 32-bit DLL loaded by the ModAPI Launcher. After the game has finished starting up it:

- checks the game executable by its time stamp and image size;
- finds the planet water shaders in the game's vertex and pixel shader tables by their names, and checks each
  original by the SHA-256 of its bytecode and by the layout of its shader constants;
- creates its own versions of those shaders with Direct3D, checks the bytecode of each created shader by SHA-256
  again, and only then swaps all of them into the tables at once. If any shader is unknown or any step fails, it
  changes none of them and shows a message; and
- puts the original shaders back when the game shuts down.

The shaders are written in HLSL in [`src/shaders`](src/shaders) and compiled into the DLL when it is built.

## Building from source (Linux)

> **A note from the author:** I build and test this mod only on Linux, and I cannot help with a Windows build.
> To play the mod you don't need to build anything: just use the `.sporemod` from Releases.

The build is the same as for [Civ Challenge](https://github.com/codestlover/Spore-CivChallenge) and
[Truely!NO-LOD](https://github.com/codestlover/Spore-TruelyNoLOD), and the scripts in `cmake/` are shared with them,
which is why their settings start with `CIV_`. You need LLVM (`clang-cl`, `lld-link`, `llvm-lib`, `llvm-mt`,
`llvm-rc`), CMake 3.20 or newer, `make`, GNU `bash` 4.4 or newer, coreutils, findutils, grep with `-P`, `git`, `curl`,
`unzip`, `tar` and `jq`, and Wine with Microsoft's 32-bit `d3dcompiler_47.dll` for the shaders.

```sh
git clone https://github.com/codestlover/Spore-SeamlessWater.git && cd Spore-SeamlessWater
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE=cmake/toolchain-clangcl-i686.cmake \
    -DCIV_ACCEPT_MSVC_LICENSE=ON -DSEAMLESS_D3DCOMPILER=/path/to/x86/d3dcompiler_47.dll
cmake --build build
```

This produces `build/bin/SeamlessWater.dll`. The first `cmake` run downloads the dependencies into `deps/` with
`cmake/setup.sh`; Seamless Water itself needs `SporeModAPI.lib` (v2.5.559) and, with xwin, the MSVC CRT and Windows
SDK from them, which come under the Microsoft license and are not redistributed. `-DCIV_ACCEPT_MSVC_LICENSE=ON` means you accept that license. If you
already prepared these dependencies for Civ Challenge or Truely!NO-LOD, set `CIV_DEPS` to that `deps` folder (an
absolute path) before the first `cmake` run to reuse them.

The shaders in `src/shaders` are compiled during the build by `src/shaders/ShaderCompiler.cpp`, a small Windows
program that runs under Wine and loads the `d3dcompiler_47.dll` given with `SEAMLESS_D3DCOMPILER`. That DLL is not
redistributed. If a shader does not compile, the compiler's messages are in `build/generated/<shader>.compiler.txt`.
The release was built with version 10.0.22621.3233; with CMake 3.27 or newer and that compiler the build is
reproducible and gives the same DLL as the one in the release.

Every text file starts with exactly one empty line and ends with exactly two; `cmake/layout.sh` checks this on each
build, and `bash cmake/layout.sh --fix` fixes it.

## Testing

Releases are checked with tests that are not part of this repository:

- the compiled shaders must be byte for byte the ones that were tried in the game;
- a Wine test loads the DLL with a stand-in `SporeModAPI.dll`, checks that it registers its start and shutdown,
  refuses another executable with its message and offers no reflections; and
- a Direct3D 9 test under Wine and DXVK, from Truely!NO-LOD:Enchanted, draws water with the versions that carry the
  reflection and checks that the reflection reaches them and that at strength 0 the picture is the original one.

The fix has been confirmed in the game in the space stage; the other stages use the same shaders but were not played
through separately.

## Credits and license

Seamless Water is licensed under **GPL-3.0-or-later** (see [`LICENSE`](LICENSE)).

Full notices are in [`NOTICE.md`](NOTICE.md). Spore and Galactic Adventures belong to Electronic Arts/Maxis. The
repository and the release contain no game executables or save data. The shaders in `src/shaders` are the exception
among game assets: they are the game's own planet water shaders, from the shader fragments Spore ships, with the
seamless wave sampling added.

