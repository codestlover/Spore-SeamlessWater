
#include <Windows.h>
#include <wincrypt.h>
#include <d3d9.h>
#include "core/Addresses.hpp"
#include "core/Name.hpp"
#include "core/ReflectionLink.hpp"
#include "core/ShaderTypes.hpp"
#include "WaterShaders.hpp"
#include <cstddef>
#include <cstdint>
#include <cstring>

namespace ModAPI {
typedef void (*InitFunction)();
__declspec(dllimport) void AddPostInitFunction(InitFunction);
__declspec(dllimport) void AddDisposeFunction(InitFunction);
}

namespace {
struct NamedUniform {
    BYTE name[16];
    UniformSpec data;
};

struct Record {
    BYTE signature[32];
    IUnknown* shader;
    int unknown;
    unsigned count;
    NamedUniform* uniforms[32];
    int registers[32];
    uint32_t flags;
};

struct Records {
    Record* begin;
    Record* end;
    Record* capacity;
};

static_assert(sizeof(void*) == 4 && sizeof(Record) == 0x130 && offsetof(Record, registers) == 0xac);

struct Change {
    Record* record;
    IUnknown* original;
    IUnknown* replacement;
    const ShaderSpec* spec;
};

constexpr unsigned MaxShaders = 16;

uintptr_t gameBase;
Change changes[MaxShaders]{};
unsigned changeCount;
SeamlessWaterShader reflections[MaxShaders]{};
SeamlessWaterLink link{ReflectionContract, 0, reflections};

void* At(uint32_t address) {
    return reinterpret_cast<void*>(gameBase + address - 0x400000);
}

void OfferReflection(IUnknown* shader, const ShaderSpec& spec) {
    if (!spec.vertex && spec.reflection && link.count < MaxShaders)
        reflections[link.count++] = {spec.name, static_cast<IDirect3DPixelShader9*>(shader), spec.reflection,
                                     spec.reflectionSize};
}

bool Readable(const void* p, size_t bytes, bool writable = false) {
    uintptr_t cursor = reinterpret_cast<uintptr_t>(p), end = cursor + bytes;
    if (!p || end < cursor)
        return false;
    while (cursor < end) {
        MEMORY_BASIC_INFORMATION info{};
        if (!VirtualQuery(reinterpret_cast<void*>(cursor), &info, sizeof(info)) || info.State != MEM_COMMIT ||
            (info.Protect & (PAGE_NOACCESS | PAGE_GUARD)))
            return false;
        if (writable &&
            !(info.Protect & (PAGE_READWRITE | PAGE_WRITECOPY | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY)))
            return false;
        uintptr_t next = reinterpret_cast<uintptr_t>(info.BaseAddress) + info.RegionSize;
        if (next <= cursor)
            return false;
        cursor = next;
    }
    return true;
}

bool Hash(const void* bytes, DWORD size, BYTE result[32]) {
    HCRYPTPROV provider = 0;
    HCRYPTHASH hash = 0;
    DWORD length = 32;
    bool ok = CryptAcquireContextW(&provider, nullptr, nullptr, PROV_RSA_AES, CRYPT_VERIFYCONTEXT | CRYPT_SILENT) &&
              CryptCreateHash(provider, CALG_SHA_256, 0, 0, &hash) &&
              CryptHashData(hash, static_cast<const BYTE*>(bytes), size, 0) &&
              CryptGetHashParam(hash, HP_HASHVAL, result, &length, 0) && length == 32;
    if (hash)
        CryptDestroyHash(hash);
    if (provider)
        CryptReleaseContext(provider, 0);
    return ok;
}

bool Fingerprint(IUnknown* shader, bool vertex, BYTE result[32], UINT& size) {
    if (!Readable(shader, sizeof(void*)))
        return false;
    void* table = *reinterpret_cast<void**>(shader);
    if (!Readable(table, 5 * sizeof(void*)))
        return false;
    size = 0;
    HRESULT hr = vertex ? static_cast<IDirect3DVertexShader9*>(shader)->GetFunction(nullptr, &size)
                        : static_cast<IDirect3DPixelShader9*>(shader)->GetFunction(nullptr, &size);
    if (FAILED(hr) || size < 8 || size > 1024 * 1024)
        return false;
    void* code = HeapAlloc(GetProcessHeap(), 0, size);
    if (!code)
        return false;
    UINT capacity = size;
    hr = vertex ? static_cast<IDirect3DVertexShader9*>(shader)->GetFunction(code, &capacity)
                : static_cast<IDirect3DPixelShader9*>(shader)->GetFunction(code, &capacity);
    bool ok = SUCCEEDED(hr) && capacity == size && Hash(code, size, result);
    HeapFree(GetProcessHeap(), 0, code);
    return ok;
}

bool LayoutMatches(const Record& r, const ShaderSpec& s) {
    if (r.count != s.uniformCount || r.flags != s.flags)
        return false;
    for (unsigned i = 0; i < r.count; ++i)
        if (r.registers[i] != s.registers[i] || !Readable(r.uniforms[i], sizeof(NamedUniform)) ||
            memcmp(&r.uniforms[i]->data, &s.uniforms[i], sizeof(UniformSpec)))
            return false;
    return true;
}

bool ValidTable(const Records& t) {
    uintptr_t begin = reinterpret_cast<uintptr_t>(t.begin), end = reinterpret_cast<uintptr_t>(t.end),
              capacity = reinterpret_cast<uintptr_t>(t.capacity);
    return begin && end >= begin && capacity >= end && end - begin <= 16384 * sizeof(Record) &&
           (end - begin) % sizeof(Record) == 0 && Readable(t.begin, end - begin, true);
}

bool Water(const Record& r, bool vertex) {
    for (const auto& s : kSpecs)
        if (s.vertex == vertex && !memcmp(r.signature, s.signature, s.signatureSize))
            return true;
    return false;
}

const ShaderSpec* Known(const Record& r, bool vertex, const BYTE hash[32], UINT size, bool& already) {
    for (const auto& s : kSpecs) {
        if (s.vertex != vertex || memcmp(r.signature, s.signature, s.signatureSize))
            continue;
        if (size == s.originalSize && !memcmp(hash, s.originalHash, 32))
            return &s;
        if (size == s.codeSize && !memcmp(hash, s.patchedHash, 32)) {
            already = true;
            return &s;
        }
    }
    return nullptr;
}

IUnknown* Create(IDirect3DDevice9* device, const ShaderSpec& spec, bool vertex) {
    IUnknown* replacement = nullptr;
    HRESULT hr;
    if (vertex) {
        IDirect3DVertexShader9* shader = nullptr;
        hr = device->CreateVertexShader(spec.code, &shader);
        replacement = shader;
    } else {
        IDirect3DPixelShader9* shader = nullptr;
        hr = device->CreatePixelShader(spec.code, &shader);
        replacement = shader;
    }
    BYTE hash[32];
    UINT size = 0;
    if (SUCCEEDED(hr) && replacement && Fingerprint(replacement, vertex, hash, size) && size == spec.codeSize &&
        !memcmp(hash, spec.patchedHash, 32))
        return replacement;
    if (replacement)
        replacement->Release();
    return nullptr;
}

bool Apply(IDirect3DDevice9* device, const Records& vertices, const Records& pixels) {
    if (!device || changeCount || !ValidTable(vertices) || !ValidTable(pixels))
        return false;
    Change pending[MaxShaders]{};
    unsigned count = 0, candidates = 0, vertexCount = 0, pixelCount = 0;
    bool good = true;
    for (int stage = 0; stage < 2 && good; ++stage) {
        bool vertex = stage == 0;
        const Records& table = vertex ? vertices : pixels;
        for (Record* r = table.begin; r < table.end && good; ++r) {
            if (!Water(*r, vertex))
                continue;
            ++candidates;
            ++(vertex ? vertexCount : pixelCount);
            BYTE hash[32];
            UINT size = 0;
            bool already = false;
            const ShaderSpec* match =
                Fingerprint(r->shader, vertex, hash, size) ? Known(*r, vertex, hash, size, already) : nullptr;
            if (!match || !LayoutMatches(*r, *match) || (!already && count >= MaxShaders)) {
                good = false;
                break;
            }
            if (already) {
                OfferReflection(r->shader, *match);
                continue;
            }
            IUnknown* replacement = Create(device, *match, vertex);
            if (!replacement) {
                good = false;
                break;
            }
            pending[count++] = {r, r->shader, replacement, match};
        }
    }
    if (!good || !vertexCount || !pixelCount || candidates > MaxShaders) {
        for (unsigned i = 0; i < count; ++i)
            pending[i].replacement->Release();
        link.count = 0;
        return false;
    }
    for (unsigned i = 0; i < count; ++i) {
        Change& c = pending[i];
        c.record->shader = c.replacement;
        changes[changeCount++] = c;
        OfferReflection(c.replacement, *c.spec);
    }
    return true;
}

void Restore() {
    link.count = 0;
    for (unsigned i = 0; i < changeCount; ++i) {
        Change& c = changes[i];
        if (Readable(c.record, sizeof(Record), true) && c.record->shader == c.replacement) {
            c.record->shader = c.original;
            c.replacement->Release();
        } else {
            c.original->Release();
        }
    }
    changeCount = 0;
}

bool HostMatches() {
    auto* dos = reinterpret_cast<IMAGE_DOS_HEADER*>(gameBase);
    auto* nt = reinterpret_cast<IMAGE_NT_HEADERS*>(gameBase + dos->e_lfanew);
    return nt->FileHeader.Machine == IMAGE_FILE_MACHINE_I386 && nt->OptionalHeader.SizeOfImage == HostImageSize &&
           nt->FileHeader.TimeDateStamp == HostTimestamp;
}

void Init() {
    gameBase = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    bool host = HostMatches();
    if (host) {
        auto* vertices = static_cast<Records*>(At(VertexShaderTable));
        auto* pixels = static_cast<Records*>(At(PixelShaderTable));
        auto* device = static_cast<IDirect3DDevice9**>(At(DeviceGlobal));
        if (Apply(*device, *vertices, *pixels))
            return;
    }
    const wchar_t* text =
        !host ? L"" SEAMLESS_WATER_NAME " could not start: this version of Spore is not supported. Planet water keeps "
                L"its seams.\n\n" SEAMLESS_WATER_NAME " supports only Spore Galactic Adventures with the March 2017 "
                L"patch (SporeApp_ModAPIFix.exe)."
              : L"" SEAMLESS_WATER_NAME " could not start: the game's planet water shaders are not the ones it knows, "
                L"most likely because another mod has replaced them. Planet water keeps that mod's look.";
    MessageBoxW(nullptr, text, ModNameWide, MB_OK | MB_ICONERROR);
}

void Dispose() {
    Restore();
}
}

extern "C" __declspec(dllexport) const SeamlessWaterLink* __cdecl SeamlessWater_Link() {
    return link.count ? &link : nullptr;
}

BOOL WINAPI DllMain(HMODULE h, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(h);
        ModAPI::AddPostInitFunction(Init);
        ModAPI::AddDisposeFunction(Dispose);
    }
    return TRUE;
}

