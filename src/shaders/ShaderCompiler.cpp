
#include <Windows.h>
#include <wincrypt.h>
#include <d3dcompiler.h>
#include "shaders/ShaderManifest.hpp"
#include <cstdio>
#include <cstring>
#include <cwchar>

namespace {
struct Program {
    DWORD size;
    BYTE digest[32];
    DWORD reflectionSize;
};

constexpr char PlainReflection[] = "float3 ApplyWaterReflection(float3 color, samplerCUBE sky, float3x3 frame, "
                                   "float3 normal, float3 toEye, float3 bump, float radius) { return color; }";

class ShaderInclude final : public ID3DInclude {
public:
    ShaderInclude(const wchar_t* directory, bool reflection) : folder(directory), reflected(reflection) {}

    HRESULT __stdcall Open(D3D_INCLUDE_TYPE, LPCSTR name, LPCVOID, LPCVOID* data, UINT* bytes) noexcept override {
        if (!reflected) {
            *data = PlainReflection;
            *bytes = UINT(sizeof(PlainReflection) - 1);
            return S_OK;
        }
        wchar_t path[2048];
        swprintf_s(path, L"%s/%hs", folder, name);
        DWORD size = 0;
        char* source = Read(path, size);
        if (!source)
            return E_FAIL;
        *data = source;
        *bytes = size;
        return S_OK;
    }

    HRESULT __stdcall Close(LPCVOID data) noexcept override {
        if (data != PlainReflection)
            HeapFree(GetProcessHeap(), 0, const_cast<void*>(data));
        return S_OK;
    }

    static char* Read(const wchar_t* path, DWORD& size) {
        HANDLE file =
            CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (file == INVALID_HANDLE_VALUE)
            return nullptr;
        size = GetFileSize(file, nullptr);
        DWORD read = 0;
        char* source = size == INVALID_FILE_SIZE ? nullptr : static_cast<char*>(HeapAlloc(GetProcessHeap(), 0, size));
        bool loaded = source && ReadFile(file, source, size, &read, nullptr) && read == size;
        CloseHandle(file);
        if (loaded)
            return source;
        if (source)
            HeapFree(GetProcessHeap(), 0, source);
        return nullptr;
    }

private:
    const wchar_t* folder;
    bool reflected;
};

bool Write(const wchar_t* path, const void* bytes, DWORD size) {
    HANDLE f = CreateFileW(path, GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (f == INVALID_HANDLE_VALUE)
        return false;
    DWORD written = 0;
    bool result = WriteFile(f, bytes, size, &written, nullptr) && written == size;
    CloseHandle(f);
    return result;
}

bool Hash(const void* data, DWORD size, BYTE digest[32]) {
    HCRYPTPROV provider = 0;
    HCRYPTHASH hash = 0;
    DWORD count = 32;
    bool ok = CryptAcquireContextW(&provider, nullptr, nullptr, PROV_RSA_AES, CRYPT_VERIFYCONTEXT | CRYPT_SILENT) &&
              CryptCreateHash(provider, CALG_SHA_256, 0, 0, &hash) &&
              CryptHashData(hash, static_cast<const BYTE*>(data), size, 0) &&
              CryptGetHashParam(hash, HP_HASHVAL, digest, &count, 0) && count == 32;
    if (hash)
        CryptDestroyHash(hash);
    if (provider)
        CryptReleaseContext(provider, 0);
    return ok;
}

template <class T> void Numbers(FILE* header, const T* values, unsigned count) {
    fputc('{', header);
    for (unsigned i = 0; i < count; ++i)
        fprintf(header, "%s%ld", i ? "," : "", long(values[i]));
    fputc('}', header);
}

void Words(FILE* header, const char* prefix, const char* name, const void* code, DWORD size) {
    fprintf(header, "static const DWORD %s%s[] = {", prefix, name);
    const DWORD* words = static_cast<const DWORD*>(code);
    for (DWORD n = 0; n < size / 4; ++n)
        fprintf(header, "%s%lu", n ? "," : "", words[n]);
    fprintf(header, "};\n");
}

bool Messages(const wchar_t* output, const char* name, ID3DBlob* messages) {
    if (!messages)
        return true;
    wchar_t path[2048];
    swprintf_s(path, L"%s/%hs.compiler.txt", output, name);
    bool saved = Write(path, messages->GetBufferPointer(), DWORD(messages->GetBufferSize()));
    messages->Release();
    return saved;
}
}

int wmain(int argc, wchar_t** argv) {
    if (argc != 4)
        return 2;
    HMODULE library = LoadLibraryW(argv[3]);
    if (!library)
        return 3;
    auto compile = reinterpret_cast<pD3DCompile>(reinterpret_cast<void*>(GetProcAddress(library, "D3DCompile")));
    if (!compile)
        return 3;
    CreateDirectoryW(argv[2], nullptr);
    wchar_t path[2048], temporary[2048];
    swprintf_s(temporary, L"%s/WaterShaders.hpp.tmp", argv[2]);
    FILE* header = nullptr;
    if (_wfopen_s(&header, temporary, L"wb") || !header)
        return 4;
    Program programs[_countof(kBuildSpecs)]{};
    for (unsigned i = 0; i < _countof(kBuildSpecs); ++i) {
        const auto& definition = kBuildSpecs[i];
        const auto& layout = definition.layout;
        swprintf_s(path, L"%s/%hs", argv[1], definition.source);
        DWORD size = 0;
        char* source = ShaderInclude::Read(path, size);
        if (!source) {
            fclose(header);
            return 5;
        }
        ID3DBlob* code = nullptr;
        ID3DBlob* messages = nullptr;
        ShaderInclude plain(argv[1], false);
        HRESULT hr = compile(source, size, "SeamlessWater.hlsl", nullptr, &plain, "main", definition.profile,
                             D3DCOMPILE_OPTIMIZATION_LEVEL3, 0, &code, &messages);
        bool good = Messages(argv[2], layout.name, messages) && SUCCEEDED(hr) && code;
        Program& program = programs[i];
        if (good) {
            program.size = DWORD(code->GetBufferSize());
            swprintf_s(path, L"%s/%hs.bin", argv[2], layout.name);
            good = program.size % 4 == 0 && Hash(code->GetBufferPointer(), program.size, program.digest) &&
                   Write(path, code->GetBufferPointer(), program.size);
            if (good)
                Words(header, "code_", layout.name, code->GetBufferPointer(), program.size);
        }
        if (code)
            code->Release();
        if (good && !layout.vertex && !strcmp(definition.profile, "ps_3_0")) {
            ShaderInclude include(argv[1], true);
            ID3DBlob* reflected = nullptr;
            ID3DBlob* notes = nullptr;
            hr = compile(source, size, "SeamlessWater.hlsl", nullptr, &include, "main", definition.profile,
                         D3DCOMPILE_OPTIMIZATION_LEVEL3, 0, &reflected, &notes);
            if (notes)
                notes->Release();
            good = SUCCEEDED(hr) && reflected;
            if (good) {
                program.reflectionSize = DWORD(reflected->GetBufferSize());
                swprintf_s(path, L"%s/%hs.reflection.bin", argv[2], layout.name);
                good = program.reflectionSize % 4 == 0 &&
                       Write(path, reflected->GetBufferPointer(), program.reflectionSize);
                if (good)
                    Words(header, "reflection_", layout.name, reflected->GetBufferPointer(), program.reflectionSize);
            }
            if (reflected)
                reflected->Release();
        }
        HeapFree(GetProcessHeap(), 0, source);
        if (!good) {
            fclose(header);
            return 6;
        }
    }
    fprintf(header, "static const ShaderSpec kSpecs[] = {\n");
    for (unsigned i = 0; i < _countof(kBuildSpecs); ++i) {
        const auto& s = kBuildSpecs[i].layout;
        const Program& p = programs[i];
        fprintf(header, "{\"%s\",%s,", s.name, s.vertex ? "true" : "false");
        Numbers(header, s.signature, s.signatureSize);
        fprintf(header, ",%u,", s.signatureSize);
        Numbers(header, s.originalHash, 32);
        fprintf(header, ",%u,", s.originalSize);
        Numbers(header, p.digest, 32);
        fprintf(header, ",code_%s,%lu,%u,{", s.name, p.size, s.uniformCount);
        for (unsigned u = 0; u < s.uniformCount; ++u) {
            const auto& uniform = s.uniforms[u];
            fprintf(header, "%s{%d,%d,%d,%d,%lu}", u ? "," : "", uniform.index, uniform.alias, uniform.count,
                    uniform.reg, static_cast<unsigned long>(uniform.flags));
        }
        fprintf(header, "},");
        Numbers(header, s.registers, s.uniformCount);
        fprintf(header, ",%lu,", static_cast<unsigned long>(s.flags));
        if (p.reflectionSize)
            fprintf(header, "reflection_%s,%lu},\n", s.name, p.reflectionSize);
        else
            fprintf(header, "nullptr,0},\n");
    }
    fprintf(header, "};\n");
    bool saved = fclose(header) == 0;
    FreeLibrary(library);
    swprintf_s(path, L"%s/WaterShaders.hpp", argv[2]);
    if (!saved || !MoveFileExW(temporary, path, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
        return 7;
    return 0;
}

