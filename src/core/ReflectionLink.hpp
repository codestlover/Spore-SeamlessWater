
#pragma once
#include <d3d9.h>

constexpr unsigned ReflectionContract = 2;

struct SeamlessWaterShader {
    const char* name;
    IDirect3DPixelShader9* shader;
    const DWORD* reflection;
    unsigned reflectionSize;
};

struct SeamlessWaterLink {
    unsigned contract;
    unsigned count;
    const SeamlessWaterShader* shaders;
};

