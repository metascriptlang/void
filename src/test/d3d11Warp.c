#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <string.h>
#include "d3d11Warp.h"

static ID3D11Device *device;
static ID3D11DeviceContext *context;

static void warpCreate(void) {
    if (device) return;
    D3D_FEATURE_LEVEL levels[] = { D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0 };
    HRESULT hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_WARP, NULL, D3D11_CREATE_DEVICE_BGRA_SUPPORT,
        levels, 2, D3D11_SDK_VERSION, &device, NULL, &context);
    if (FAILED(hr)) {
        hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_WARP, NULL, D3D11_CREATE_DEVICE_BGRA_SUPPORT,
            levels + 1, 1, D3D11_SDK_VERSION, &device, NULL, &context);
    }
    if (FAILED(hr)) { device = NULL; context = NULL; }
}

void *warpDevice(void) { warpCreate(); return device; }
void *warpContext(void) { warpCreate(); return context; }

int32_t warpReadback(void *texture, void *pixels, int32_t width, int32_t height) {
    D3D11_TEXTURE2D_DESC desc;
    ID3D11Texture2D_GetDesc((ID3D11Texture2D *)texture, &desc);
    desc.Width = (UINT)width;
    desc.Height = (UINT)height;
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.SampleDesc.Count = 1;
    desc.SampleDesc.Quality = 0;
    desc.Usage = D3D11_USAGE_STAGING;
    desc.BindFlags = 0;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    desc.MiscFlags = 0;
    ID3D11Texture2D *staging = NULL;
    if (FAILED(ID3D11Device_CreateTexture2D(device, &desc, NULL, &staging))) return 0;
    ID3D11DeviceContext_CopyResource(context, (ID3D11Resource *)staging, (ID3D11Resource *)texture);
    D3D11_MAPPED_SUBRESOURCE mapped;
    if (FAILED(ID3D11DeviceContext_Map(context, (ID3D11Resource *)staging, 0, D3D11_MAP_READ, 0, &mapped))) {
        ID3D11Texture2D_Release(staging);
        return 0;
    }
    for (int32_t row = 0; row < height; row++) {
        memcpy((uint8_t *)pixels + (size_t)row * (size_t)width * 4, (uint8_t *)mapped.pData + (size_t)row * mapped.RowPitch,
            (size_t)width * 4);
    }
    ID3D11DeviceContext_Unmap(context, (ID3D11Resource *)staging, 0);
    ID3D11Texture2D_Release(staging);
    return 1;
}

int32_t warpReadbackSubresource(void *texture, int32_t subresource, void *pixels, int32_t width, int32_t height) {
    D3D11_TEXTURE2D_DESC desc;
    ID3D11Texture2D_GetDesc((ID3D11Texture2D *)texture, &desc);
    desc.Width = (UINT)width;
    desc.Height = (UINT)height;
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.SampleDesc.Count = 1;
    desc.SampleDesc.Quality = 0;
    desc.Usage = D3D11_USAGE_STAGING;
    desc.BindFlags = 0;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    desc.MiscFlags = 0;
    ID3D11Texture2D *staging = NULL;
    if (FAILED(ID3D11Device_CreateTexture2D(device, &desc, NULL, &staging))) return 0;
    ID3D11DeviceContext_CopySubresourceRegion(context, (ID3D11Resource *)staging, 0, 0, 0, 0, (ID3D11Resource *)texture, (UINT)subresource, NULL);
    D3D11_MAPPED_SUBRESOURCE mapped;
    if (FAILED(ID3D11DeviceContext_Map(context, (ID3D11Resource *)staging, 0, D3D11_MAP_READ, 0, &mapped))) {
        ID3D11Texture2D_Release(staging);
        return 0;
    }
    for (int32_t row = 0; row < height; row++) {
        memcpy((uint8_t *)pixels + (size_t)row * (size_t)width * 4, (uint8_t *)mapped.pData + (size_t)row * mapped.RowPitch,
            (size_t)width * 4);
    }
    ID3D11DeviceContext_Unmap(context, (ID3D11Resource *)staging, 0);
    ID3D11Texture2D_Release(staging);
    return 1;
}

int32_t warpObjectName(void *object, uint8_t *out, int32_t size) {
    static const GUID name = { 0x429b8c22, 0x9188, 0x4b0c, { 0x87, 0x42, 0xac, 0xb0, 0xbf, 0x85, 0xc2, 0x00 } };
    UINT bytes = (UINT)size;
    if (FAILED(ID3D11DeviceChild_GetPrivateData((ID3D11DeviceChild *)object, &name, &bytes, out))) return -1;
    return (int32_t)bytes;
}

int32_t warpReadback3d(void *texture, int32_t mip, int32_t slice, void *pixels, int32_t width, int32_t height) {
    D3D11_TEXTURE3D_DESC desc;
    ID3D11Texture3D_GetDesc((ID3D11Texture3D *)texture, &desc);
    UINT depth = desc.Depth >> mip;
    desc.Width = (UINT)width;
    desc.Height = (UINT)height;
    desc.Depth = depth ? depth : 1;
    desc.MipLevels = 1;
    desc.Usage = D3D11_USAGE_STAGING;
    desc.BindFlags = 0;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    desc.MiscFlags = 0;
    ID3D11Texture3D *staging = NULL;
    if (FAILED(ID3D11Device_CreateTexture3D(device, &desc, NULL, &staging))) return 0;
    ID3D11DeviceContext_CopySubresourceRegion(context, (ID3D11Resource *)staging, 0, 0, 0, 0, (ID3D11Resource *)texture, (UINT)mip, NULL);
    D3D11_MAPPED_SUBRESOURCE mapped;
    if (FAILED(ID3D11DeviceContext_Map(context, (ID3D11Resource *)staging, 0, D3D11_MAP_READ, 0, &mapped))) {
        ID3D11Texture3D_Release(staging);
        return 0;
    }
    for (int32_t row = 0; row < height; row++) {
        memcpy((uint8_t *)pixels + (size_t)row * (size_t)width * 4,
            (uint8_t *)mapped.pData + (size_t)slice * mapped.DepthPitch + (size_t)row * mapped.RowPitch, (size_t)width * 4);
    }
    ID3D11DeviceContext_Unmap(context, (ID3D11Resource *)staging, 0);
    ID3D11Texture3D_Release(staging);
    return 1;
}

void *warpTarget(int32_t width, int32_t height, int32_t sampleCount) {
    D3D11_TEXTURE2D_DESC desc = {0};
    desc.Width = (UINT)width;
    desc.Height = (UINT)height;
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    desc.SampleDesc.Count = (UINT)sampleCount;
    desc.SampleDesc.Quality = sampleCount > 1 ? (UINT)D3D11_STANDARD_MULTISAMPLE_PATTERN : 0;
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_RENDER_TARGET;
    ID3D11Texture2D *texture = NULL;
    if (FAILED(ID3D11Device_CreateTexture2D(device, &desc, NULL, &texture))) return NULL;
    return texture;
}

void *warpTargetView(void *texture) {
    ID3D11RenderTargetView *view = NULL;
    if (FAILED(ID3D11Device_CreateRenderTargetView(device, (ID3D11Resource *)texture, NULL, &view))) return NULL;
    return view;
}

void warpRelease(void) {
    if (context) { ID3D11DeviceContext_ClearState(context); ID3D11DeviceContext_Release(context); }
    if (device) ID3D11Device_Release(device);
    context = NULL;
    device = NULL;
}
