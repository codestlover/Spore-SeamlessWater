
#pragma once
#include <Windows.h>
#include <cstdint>

struct UniformSpec {
    int16_t index, alias, count, reg;
    uint32_t flags;
};

struct ShaderSpec {
    const char* name;
    bool vertex;
    BYTE signature[32];
    unsigned signatureSize;
    BYTE originalHash[32];
    unsigned originalSize;
    BYTE patchedHash[32];
    const DWORD* code;
    unsigned codeSize;
    unsigned uniformCount;
    UniformSpec uniforms[8];
    int registers[8];
    uint32_t flags;
    const DWORD* reflection;
    unsigned reflectionSize;
};

