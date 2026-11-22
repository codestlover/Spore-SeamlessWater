
#pragma once
#include <cstdint>

constexpr unsigned HostImageSize = 26271744;
// Steam's SporeApp.exe is the same build with SteamStub's section on top: the same time stamp, a larger image.
constexpr unsigned SteamHostImageSize = 26443776;
constexpr unsigned HostTimestamp = 1727737552;

constexpr uint32_t VertexShaderTable = 0x1628c20;
constexpr uint32_t PixelShaderTable = 0x16198a0;
constexpr uint32_t DeviceGlobal = 0x16f89d0;

