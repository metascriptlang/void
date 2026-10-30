#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d11.h>
#include <d3d11_1.h>
#include <d3dcompiler.h>
#include <float.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "d3d11.h"

#define DEVICE(d) ((ID3D11Device *)(d))
#define CONTEXT(c) ((ID3D11DeviceContext *)(c))

D3dDevice d3dDeviceFrom(void *native) { return (D3dDevice)native; }
D3dContext d3dContextFrom(void *native) { return (D3dContext)native; }
D3dRtv d3dRtvFrom(void *native) { return (D3dRtv)native; }
D3dDsv d3dDsvFrom(void *native) { return (D3dDsv)native; }
void *d3dTextureNative(D3dTexture texture) { return texture; }
D3dTexture d3dRtvTexture(D3dRtv view) {
	if (!view) return NULL;
	ID3D11Resource *resource = NULL;
	ID3D11View_GetResource((ID3D11View *)view, &resource);
	if (resource) ID3D11Resource_Release(resource);
	return (D3dTexture)resource;
}

void d3dRelease(void *object) { if (object) IUnknown_Release((IUnknown *)object); }

D3dBuffer d3dCreateBuffer(D3dDevice device, int64_t bytes, int32_t usage, int32_t bindFlags, int32_t cpuAccess, int32_t miscFlags) {
	D3D11_BUFFER_DESC desc = {0};
	desc.ByteWidth = (UINT)bytes;
	desc.Usage = (D3D11_USAGE)usage;
	desc.BindFlags = (UINT)bindFlags;
	desc.CPUAccessFlags = (UINT)cpuAccess;
	desc.MiscFlags = (UINT)miscFlags;
	ID3D11Buffer *buffer = NULL;
	HRESULT hr = ID3D11Device_CreateBuffer(DEVICE(device), &desc, NULL, &buffer);
	return SUCCEEDED(hr) ? (D3dBuffer)buffer : NULL;
}

D3dSrv d3dCreateBufferSrv(D3dDevice device, D3dBuffer buffer, int64_t offset, int64_t bytes) {
	D3D11_SHADER_RESOURCE_VIEW_DESC desc = {0};
	desc.Format = DXGI_FORMAT_R32_TYPELESS;
	desc.ViewDimension = D3D11_SRV_DIMENSION_BUFFEREX;
	desc.BufferEx.FirstElement = (UINT)(offset / 4);
	desc.BufferEx.NumElements = (UINT)(bytes / 4);
	desc.BufferEx.Flags = D3D11_BUFFEREX_SRV_FLAG_RAW;
	ID3D11ShaderResourceView *view = NULL;
	HRESULT hr = ID3D11Device_CreateShaderResourceView(DEVICE(device), (ID3D11Resource *)buffer, &desc, &view);
	return SUCCEEDED(hr) ? (D3dSrv)view : NULL;
}

D3dUav d3dCreateBufferUav(D3dDevice device, D3dBuffer buffer, int64_t offset, int64_t bytes) {
	D3D11_UNORDERED_ACCESS_VIEW_DESC desc = {0};
	desc.Format = DXGI_FORMAT_R32_TYPELESS;
	desc.ViewDimension = D3D11_UAV_DIMENSION_BUFFER;
	desc.Buffer.FirstElement = (UINT)(offset / 4);
	desc.Buffer.NumElements = (UINT)(bytes / 4);
	desc.Buffer.Flags = D3D11_BUFFER_UAV_FLAG_RAW;
	ID3D11UnorderedAccessView *view = NULL;
	HRESULT hr = ID3D11Device_CreateUnorderedAccessView(DEVICE(device), (ID3D11Resource *)buffer, &desc, &view);
	return SUCCEEDED(hr) ? (D3dUav)view : NULL;
}

D3dUav d3dCreateTextureUav(D3dDevice device, D3dTexture texture, int32_t format, int32_t dimension, int32_t mip, int32_t layer, int32_t layerCount) {
	D3D11_UNORDERED_ACCESS_VIEW_DESC desc = {0};
	desc.Format = (DXGI_FORMAT)format;
	if (dimension == D3D_VIEW_3D) {
		desc.ViewDimension = D3D11_UAV_DIMENSION_TEXTURE3D;
		desc.Texture3D.MipSlice = (UINT)mip;
		desc.Texture3D.FirstWSlice = 0;
		desc.Texture3D.WSize = (UINT)-1;
	} else if (dimension == D3D_VIEW_2D_ARRAY) {
		desc.ViewDimension = D3D11_UAV_DIMENSION_TEXTURE2DARRAY;
		desc.Texture2DArray.MipSlice = (UINT)mip;
		desc.Texture2DArray.FirstArraySlice = (UINT)layer;
		desc.Texture2DArray.ArraySize = (UINT)layerCount;
	} else {
		desc.ViewDimension = D3D11_UAV_DIMENSION_TEXTURE2D;
		desc.Texture2D.MipSlice = (UINT)mip;
	}
	ID3D11UnorderedAccessView *view = NULL;
	HRESULT hr = ID3D11Device_CreateUnorderedAccessView(DEVICE(device), (ID3D11Resource *)texture, &desc, &view);
	return SUCCEEDED(hr) ? (D3dUav)view : NULL;
}

int32_t d3dMapWrite(D3dContext context, D3dBuffer buffer, int32_t mapType, int64_t offset, void *data, int64_t bytes) {
	D3D11_MAPPED_SUBRESOURCE mapped;
	HRESULT hr = ID3D11DeviceContext_Map(CONTEXT(context), (ID3D11Resource *)buffer, 0, (D3D11_MAP)mapType, 0, &mapped);
	if (FAILED(hr)) return 0;
	memcpy((uint8_t *)mapped.pData + offset, data, (size_t)bytes);
	ID3D11DeviceContext_Unmap(CONTEXT(context), (ID3D11Resource *)buffer, 0);
	return 1;
}

void d3dUpdateBuffer(D3dContext context, D3dBuffer buffer, int64_t offset, void *data, int64_t bytes) {
	D3D11_BOX box = { (UINT)offset, 0, 0, (UINT)(offset + bytes), 1, 1 };
	ID3D11DeviceContext_UpdateSubresource(CONTEXT(context), (ID3D11Resource *)buffer, 0, &box, data, 0, 0);
}

void d3dCopyBuffer(D3dContext context, D3dBuffer destination, int64_t destinationOffset, D3dBuffer source, int64_t sourceOffset, int64_t bytes) {
	D3D11_BOX box = { (UINT)sourceOffset, 0, 0, (UINT)(sourceOffset + bytes), 1, 1 };
	ID3D11DeviceContext_CopySubresourceRegion(CONTEXT(context), (ID3D11Resource *)destination, 0, (UINT)destinationOffset, 0, 0, (ID3D11Resource *)source, 0, &box);
}

int32_t d3dReadBuffer(D3dContext context, D3dBuffer buffer, int64_t offset, void *out, int64_t bytes) {
	D3D11_MAPPED_SUBRESOURCE mapped;
	HRESULT hr = ID3D11DeviceContext_Map(CONTEXT(context), (ID3D11Resource *)buffer, 0, D3D11_MAP_READ, 0, &mapped);
	if (FAILED(hr)) return 0;
	memcpy(out, (uint8_t *)mapped.pData + offset, (size_t)bytes);
	ID3D11DeviceContext_Unmap(CONTEXT(context), (ID3D11Resource *)buffer, 0);
	return 1;
}

int32_t d3dUpdateIfChanged(D3dContext context, D3dBuffer buffer, uint8_t *cache, int64_t cacheOffset, uint8_t *data, int64_t dataOffset, int64_t bytes, int32_t force) {
	uint8_t *block = cache + cacheOffset;
	uint8_t *source = data + dataOffset;
	if (!force && memcmp(block, source, (size_t)bytes) == 0) return 0;
	memcpy(block, source, (size_t)bytes);
	ID3D11DeviceContext_UpdateSubresource(CONTEXT(context), (ID3D11Resource *)buffer, 0, NULL, block, 0, 0);
	return 1;
}

D3dContext1 d3dUniformOffsetting(D3dDevice device, D3dContext context) {
	D3D11_FEATURE_DATA_D3D11_OPTIONS options = {0};
	ID3D11DeviceContext1 *context1 = NULL;
	if (FAILED(ID3D11DeviceContext_QueryInterface(CONTEXT(context), &IID_ID3D11DeviceContext1, (void **)&context1))) return NULL;
	if (FAILED(ID3D11Device_CheckFeatureSupport(DEVICE(device), D3D11_FEATURE_D3D11_OPTIONS, &options, sizeof options)) ||
		!options.ConstantBufferOffsetting || !options.ConstantBufferPartialUpdate ||
		!options.MapNoOverwriteOnDynamicConstantBuffer) {
		ID3D11DeviceContext1_Release(context1);
		return NULL;
	}
	return (D3dContext1)context1;
}

void d3dSetConstantBufferRange(D3dContext1 context1, int32_t vertexStage, int32_t slot, D3dBuffer buffer, int64_t firstConstant, int64_t numConstants) {
	ID3D11Buffer *buffers[1] = { (ID3D11Buffer *)buffer };
	UINT first = (UINT)firstConstant, count = (UINT)numConstants;
	ID3D11DeviceContext1 *native = (ID3D11DeviceContext1 *)context1;
	if (vertexStage) ID3D11DeviceContext1_VSSetConstantBuffers1(native, (UINT)slot, 1, buffers, &first, &count);
	else ID3D11DeviceContext1_PSSetConstantBuffers1(native, (UINT)slot, 1, buffers, &first, &count);
}

void d3dCopyBytes(void *destination, int64_t destinationOffset, void *source, int64_t bytes) {
	memcpy((uint8_t *)destination + destinationOffset, source, (size_t)bytes);
}

D3dTexture d3dCreateTexture2D(
	D3dDevice device,
	int32_t width,
	int32_t height,
	int32_t mipLevels,
	int32_t arraySize,
	int32_t cube,
	int32_t format,
	int32_t usage,
	int32_t bindFlags,
	int32_t cpuAccess,
	int32_t sampleCount) {
	D3D11_TEXTURE2D_DESC desc = {0};
	desc.Width = (UINT)width;
	desc.Height = (UINT)height;
	desc.MipLevels = (UINT)mipLevels;
	desc.ArraySize = (UINT)arraySize;
	desc.Format = (DXGI_FORMAT)format;
	desc.BindFlags = (UINT)bindFlags;
	desc.Usage = (D3D11_USAGE)usage;
	desc.CPUAccessFlags = (UINT)cpuAccess;
	desc.SampleDesc.Count = (UINT)sampleCount;
	desc.SampleDesc.Quality = sampleCount > 1 ? (UINT)D3D11_STANDARD_MULTISAMPLE_PATTERN : 0;
	desc.MiscFlags = cube ? D3D11_RESOURCE_MISC_TEXTURECUBE : 0;
	ID3D11Texture2D *texture = NULL;
	HRESULT hr = ID3D11Device_CreateTexture2D(DEVICE(device), &desc, NULL, &texture);
	return SUCCEEDED(hr) ? (D3dTexture)texture : NULL;
}

D3dTexture d3dCreateTexture3D(
	D3dDevice device,
	int32_t width,
	int32_t height,
	int32_t depth,
	int32_t mipLevels,
	int32_t format,
	int32_t usage,
	int32_t bindFlags) {
	D3D11_TEXTURE3D_DESC desc = {0};
	desc.Width = (UINT)width;
	desc.Height = (UINT)height;
	desc.Depth = (UINT)depth;
	desc.MipLevels = (UINT)mipLevels;
	desc.Format = (DXGI_FORMAT)format;
	desc.BindFlags = (UINT)bindFlags;
	desc.Usage = (D3D11_USAGE)usage;
	ID3D11Texture3D *texture = NULL;
	HRESULT hr = ID3D11Device_CreateTexture3D(DEVICE(device), &desc, NULL, &texture);
	return SUCCEEDED(hr) ? (D3dTexture)texture : NULL;
}

void d3dUpdateTexture(
	D3dContext context,
	D3dTexture texture,
	void *data,
	int64_t offset,
	int32_t sourceRowPitch,
	int32_t sourceDepthPitch,
	int32_t subresource,
	int32_t x,
	int32_t y,
	int32_t z,
	int32_t width,
	int32_t height,
	int32_t depth) {
	D3D11_BOX box = { (UINT)x, (UINT)y, (UINT)z, (UINT)(x + width), (UINT)(y + height), (UINT)(z + depth) };
	ID3D11DeviceContext_UpdateSubresource(CONTEXT(context), (ID3D11Resource *)texture, (UINT)subresource, &box, (const uint8_t *)data + offset, (UINT)sourceRowPitch, (UINT)sourceDepthPitch);
}

void d3dCopyTexture(
	D3dContext context,
	D3dTexture destination,
	int32_t destinationSubresource,
	int32_t destinationX,
	int32_t destinationY,
	int32_t destinationZ,
	D3dTexture source,
	int32_t sourceSubresource,
	int32_t sourceX,
	int32_t sourceY,
	int32_t sourceZ,
	int32_t width,
	int32_t height,
	int32_t depth) {
	D3D11_BOX box = { (UINT)sourceX, (UINT)sourceY, (UINT)sourceZ, (UINT)(sourceX + width), (UINT)(sourceY + height), (UINT)(sourceZ + depth) };
	ID3D11DeviceContext_CopySubresourceRegion(CONTEXT(context), (ID3D11Resource *)destination, (UINT)destinationSubresource, (UINT)destinationX, (UINT)destinationY, (UINT)destinationZ, (ID3D11Resource *)source, (UINT)sourceSubresource, &box);
}

int32_t d3dCopyTextureToBuffer(
	D3dDevice device,
	D3dContext context,
	D3dTexture texture,
	int32_t subresource,
	int32_t x,
	int32_t y,
	int32_t width,
	int32_t height,
	D3dBuffer buffer,
	int64_t offset,
	int32_t bytesPerRow,
	int32_t rowBytes) {
	D3D11_TEXTURE2D_DESC desc;
	ID3D11Texture2D_GetDesc((ID3D11Texture2D *)texture, &desc);
	UINT mip = (UINT)subresource % desc.MipLevels;
	UINT mipWidth = desc.Width >> mip ? desc.Width >> mip : 1;
	UINT mipHeight = desc.Height >> mip ? desc.Height >> mip : 1;
	int whole = x == 0 && y == 0 && (UINT)width == mipWidth && (UINT)height == mipHeight;
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
	if (FAILED(ID3D11Device_CreateTexture2D(DEVICE(device), &desc, NULL, &staging))) return 0;
	D3D11_BOX box = { (UINT)x, (UINT)y, 0, (UINT)(x + width), (UINT)(y + height), 1 };
	ID3D11DeviceContext_CopySubresourceRegion(CONTEXT(context), (ID3D11Resource *)staging, 0, 0, 0, 0, (ID3D11Resource *)texture, (UINT)subresource, whole ? NULL : &box);
	D3D11_MAPPED_SUBRESOURCE source;
	D3D11_MAPPED_SUBRESOURCE target;
	int32_t ok = 0;
	if (SUCCEEDED(ID3D11DeviceContext_Map(CONTEXT(context), (ID3D11Resource *)staging, 0, D3D11_MAP_READ, 0, &source))) {
		if (SUCCEEDED(ID3D11DeviceContext_Map(CONTEXT(context), (ID3D11Resource *)buffer, 0, D3D11_MAP_READ_WRITE, 0, &target))) {
			for (int32_t row = 0; row < height; row++) {
				memcpy((uint8_t *)target.pData + offset + (size_t)row * (size_t)bytesPerRow, (uint8_t *)source.pData + (size_t)row * source.RowPitch, (size_t)rowBytes);
			}
			ID3D11DeviceContext_Unmap(CONTEXT(context), (ID3D11Resource *)buffer, 0);
			ok = 1;
		}
		ID3D11DeviceContext_Unmap(CONTEXT(context), (ID3D11Resource *)staging, 0);
	}
	ID3D11Texture2D_Release(staging);
	return ok;
}

int32_t d3dCopyBufferToTexture(
	D3dContext context,
	D3dBuffer buffer,
	int64_t offset,
	int32_t bytesPerRow,
	D3dTexture texture,
	int32_t subresource,
	int32_t x,
	int32_t y,
	int32_t width,
	int32_t height) {
	D3D11_MAPPED_SUBRESOURCE source;
	if (FAILED(ID3D11DeviceContext_Map(CONTEXT(context), (ID3D11Resource *)buffer, 0, D3D11_MAP_READ, 0, &source))) return 0;
	D3D11_BOX box = { (UINT)x, (UINT)y, 0, (UINT)(x + width), (UINT)(y + height), 1 };
	ID3D11DeviceContext_UpdateSubresource(CONTEXT(context), (ID3D11Resource *)texture, (UINT)subresource, &box, (uint8_t *)source.pData + offset, (UINT)bytesPerRow, 0);
	ID3D11DeviceContext_Unmap(CONTEXT(context), (ID3D11Resource *)buffer, 0);
	return 1;
}

D3dSrv d3dCreateSrv(
	D3dDevice device,
	D3dTexture texture,
	int32_t format,
	int32_t multisampled,
	int32_t dimension,
	int32_t baseMip,
	int32_t mipCount,
	int32_t baseLayer,
	int32_t layerCount) {
	D3D11_SHADER_RESOURCE_VIEW_DESC desc = {0};
	desc.Format = (DXGI_FORMAT)format;
	if (multisampled) {
		desc.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2DMS;
	} else if (dimension == D3D_VIEW_2D) {
		desc.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2D;
		desc.Texture2D.MostDetailedMip = (UINT)baseMip;
		desc.Texture2D.MipLevels = (UINT)mipCount;
	} else if (dimension == D3D_VIEW_2D_ARRAY) {
		desc.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2DARRAY;
		desc.Texture2DArray.MostDetailedMip = (UINT)baseMip;
		desc.Texture2DArray.MipLevels = (UINT)mipCount;
		desc.Texture2DArray.FirstArraySlice = (UINT)baseLayer;
		desc.Texture2DArray.ArraySize = (UINT)layerCount;
	} else if (dimension == D3D_VIEW_CUBE) {
		desc.ViewDimension = D3D11_SRV_DIMENSION_TEXTURECUBE;
		desc.TextureCube.MostDetailedMip = (UINT)baseMip;
		desc.TextureCube.MipLevels = (UINT)mipCount;
	} else if (dimension == D3D_VIEW_CUBE_ARRAY) {
		desc.ViewDimension = D3D11_SRV_DIMENSION_TEXTURECUBEARRAY;
		desc.TextureCubeArray.MostDetailedMip = (UINT)baseMip;
		desc.TextureCubeArray.MipLevels = (UINT)mipCount;
		desc.TextureCubeArray.First2DArrayFace = (UINT)baseLayer;
		desc.TextureCubeArray.NumCubes = (UINT)(layerCount / 6);
	} else {
		desc.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE3D;
		desc.Texture3D.MostDetailedMip = (UINT)baseMip;
		desc.Texture3D.MipLevels = (UINT)mipCount;
	}
	ID3D11ShaderResourceView *view = NULL;
	HRESULT hr = ID3D11Device_CreateShaderResourceView(DEVICE(device), (ID3D11Resource *)texture, &desc, &view);
	return SUCCEEDED(hr) ? (D3dSrv)view : NULL;
}

D3dRtv d3dCreateRtv(D3dDevice device, D3dTexture texture, int32_t format, int32_t multisampled, int32_t arrayed, int32_t mip, int32_t layer) {
	D3D11_RENDER_TARGET_VIEW_DESC desc = {0};
	desc.Format = (DXGI_FORMAT)format;
	if (multisampled) {
		desc.ViewDimension = D3D11_RTV_DIMENSION_TEXTURE2DMS;
	} else if (arrayed) {
		desc.ViewDimension = D3D11_RTV_DIMENSION_TEXTURE2DARRAY;
		desc.Texture2DArray.MipSlice = (UINT)mip;
		desc.Texture2DArray.FirstArraySlice = (UINT)layer;
		desc.Texture2DArray.ArraySize = 1;
	} else {
		desc.ViewDimension = D3D11_RTV_DIMENSION_TEXTURE2D;
		desc.Texture2D.MipSlice = (UINT)mip;
	}
	ID3D11RenderTargetView *view = NULL;
	HRESULT hr = ID3D11Device_CreateRenderTargetView(DEVICE(device), (ID3D11Resource *)texture, &desc, &view);
	return SUCCEEDED(hr) ? (D3dRtv)view : NULL;
}

D3dRtv d3dCreateRtv3d(D3dDevice device, D3dTexture texture, int32_t format, int32_t mip, int32_t slice) {
	D3D11_RENDER_TARGET_VIEW_DESC desc = {0};
	desc.Format = (DXGI_FORMAT)format;
	desc.ViewDimension = D3D11_RTV_DIMENSION_TEXTURE3D;
	desc.Texture3D.MipSlice = (UINT)mip;
	desc.Texture3D.FirstWSlice = (UINT)slice;
	desc.Texture3D.WSize = 1;
	ID3D11RenderTargetView *view = NULL;
	HRESULT hr = ID3D11Device_CreateRenderTargetView(DEVICE(device), (ID3D11Resource *)texture, &desc, &view);
	return SUCCEEDED(hr) ? (D3dRtv)view : NULL;
}

D3dDsv d3dCreateDsv(D3dDevice device, D3dTexture texture, int32_t format, int32_t multisampled, int32_t arrayed, int32_t mip, int32_t layer) {
	D3D11_DEPTH_STENCIL_VIEW_DESC desc = {0};
	desc.Format = (DXGI_FORMAT)format;
	if (multisampled) {
		desc.ViewDimension = D3D11_DSV_DIMENSION_TEXTURE2DMS;
	} else if (arrayed) {
		desc.ViewDimension = D3D11_DSV_DIMENSION_TEXTURE2DARRAY;
		desc.Texture2DArray.MipSlice = (UINT)mip;
		desc.Texture2DArray.FirstArraySlice = (UINT)layer;
		desc.Texture2DArray.ArraySize = 1;
	} else {
		desc.ViewDimension = D3D11_DSV_DIMENSION_TEXTURE2D;
		desc.Texture2D.MipSlice = (UINT)mip;
	}
	ID3D11DepthStencilView *view = NULL;
	HRESULT hr = ID3D11Device_CreateDepthStencilView(DEVICE(device), (ID3D11Resource *)texture, &desc, &view);
	return SUCCEEDED(hr) ? (D3dDsv)view : NULL;
}

void d3dResolveSubresource(D3dContext context, D3dTexture destination, int32_t destinationSubresource, D3dTexture source, int32_t format) {
	ID3D11DeviceContext_ResolveSubresource(CONTEXT(context), (ID3D11Resource *)destination, (UINT)destinationSubresource, (ID3D11Resource *)source, 0, (DXGI_FORMAT)format);
}

void d3dResolveViews(D3dContext context, D3dRtv destination, D3dRtv source, int32_t format) {
	ID3D11Resource *destinationResource = NULL;
	ID3D11Resource *sourceResource = NULL;
	ID3D11View_GetResource((ID3D11View *)destination, &destinationResource);
	ID3D11View_GetResource((ID3D11View *)source, &sourceResource);
	ID3D11DeviceContext_ResolveSubresource(CONTEXT(context), destinationResource, 0, sourceResource, 0, (DXGI_FORMAT)format);
	ID3D11Resource_Release(destinationResource);
	ID3D11Resource_Release(sourceResource);
}

D3dSampler d3dCreateSampler(
	D3dDevice device,
	int32_t filter,
	int32_t addressU,
	int32_t addressV,
	int32_t addressW,
	int32_t maxAnisotropy,
	int32_t comparison,
	double minLod,
	double maxLod) {
	D3D11_SAMPLER_DESC desc = {0};
	desc.Filter = (D3D11_FILTER)filter;
	desc.AddressU = (D3D11_TEXTURE_ADDRESS_MODE)addressU;
	desc.AddressV = (D3D11_TEXTURE_ADDRESS_MODE)addressV;
	desc.AddressW = (D3D11_TEXTURE_ADDRESS_MODE)addressW;
	desc.MaxAnisotropy = (UINT)maxAnisotropy;
	desc.ComparisonFunc = (D3D11_COMPARISON_FUNC)comparison;
	desc.BorderColor[3] = 1.0f;
	desc.MinLOD = (FLOAT)minLod;
	desc.MaxLOD = (FLOAT)maxLod;
	ID3D11SamplerState *sampler = NULL;
	HRESULT hr = ID3D11Device_CreateSamplerState(DEVICE(device), &desc, &sampler);
	return SUCCEEDED(hr) ? (D3dSampler)sampler : NULL;
}

/* The bytes of one compiled stage, owned: a D3DCompile output or a caller's precompiled DXBC copy. */
struct D3dBlobImpl {
	ID3DBlob *compiled;
	void *bytes;
	size_t size;
};

static HMODULE s_compilerDll;
static pD3DCompile s_compile;
static char s_compileLog[4096];

D3dBlob d3dCompile(const char *source, const char *entryPoint, const char *target) {
	s_compileLog[0] = 0;
	if (!s_compile) {
		if (!s_compilerDll) s_compilerDll = LoadLibraryA("d3dcompiler_47.dll");
		if (!s_compilerDll) {
			strcpy(s_compileLog, "d3dcompiler_47.dll did not load");
			return NULL;
		}
		s_compile = (pD3DCompile)(void *)GetProcAddress(s_compilerDll, "D3DCompile");
		if (!s_compile) {
			strcpy(s_compileLog, "d3dcompiler_47.dll has no D3DCompile");
			return NULL;
		}
	}
	ID3DBlob *output = NULL;
	ID3DBlob *messages = NULL;
	HRESULT hr = s_compile(source, strlen(source), NULL, NULL, D3D_COMPILE_STANDARD_FILE_INCLUDE, entryPoint, target,
		D3DCOMPILE_PACK_MATRIX_COLUMN_MAJOR | D3DCOMPILE_OPTIMIZATION_LEVEL3, 0, &output, &messages);
	if (messages) {
		strncpy(s_compileLog, (const char *)ID3D10Blob_GetBufferPointer(messages), sizeof s_compileLog - 1);
		s_compileLog[sizeof s_compileLog - 1] = 0;
		ID3D10Blob_Release(messages);
	}
	if (FAILED(hr)) {
		if (output) ID3D10Blob_Release(output);
		return NULL;
	}
	D3dBlob blob = (D3dBlob)calloc(1, sizeof *blob);
	if (!blob) {
		ID3D10Blob_Release(output);
		return NULL;
	}
	blob->compiled = output;
	blob->bytes = ID3D10Blob_GetBufferPointer(output);
	blob->size = ID3D10Blob_GetBufferSize(output);
	return blob;
}

D3dBlob d3dBlobCopy(const uint8_t *bytes, int64_t size) {
	D3dBlob blob = (D3dBlob)calloc(1, sizeof *blob);
	if (!blob) return NULL;
	blob->bytes = malloc((size_t)size);
	if (!blob->bytes) {
		free(blob);
		return NULL;
	}
	memcpy(blob->bytes, bytes, (size_t)size);
	blob->size = (size_t)size;
	return blob;
}

int64_t d3dBlobRead(D3dBlob blob, uint8_t *out, int64_t capacity) {
	if (!blob || (int64_t)blob->size > capacity) return -1;
	memcpy(out, blob->bytes, blob->size);
	return (int64_t)blob->size;
}

void d3dBlobFree(D3dBlob blob) {
	if (!blob) return;
	if (blob->compiled) ID3D10Blob_Release(blob->compiled);
	else free(blob->bytes);
	free(blob);
}

const char *d3dCompileLog(void) { return s_compileLog; }

D3dVertexShader d3dCreateVertexShader(D3dDevice device, D3dBlob blob) {
	ID3D11VertexShader *shader = NULL;
	HRESULT hr = ID3D11Device_CreateVertexShader(DEVICE(device), blob->bytes, blob->size, NULL, &shader);
	return SUCCEEDED(hr) ? (D3dVertexShader)shader : NULL;
}

D3dPixelShader d3dCreatePixelShader(D3dDevice device, D3dBlob blob) {
	ID3D11PixelShader *shader = NULL;
	HRESULT hr = ID3D11Device_CreatePixelShader(DEVICE(device), blob->bytes, blob->size, NULL, &shader);
	return SUCCEEDED(hr) ? (D3dPixelShader)shader : NULL;
}

D3dComputeShader d3dCreateComputeShader(D3dDevice device, D3dBlob blob) {
	ID3D11ComputeShader *shader = NULL;
	HRESULT hr = ID3D11Device_CreateComputeShader(DEVICE(device), blob->bytes, blob->size, NULL, &shader);
	return SUCCEEDED(hr) ? (D3dComputeShader)shader : NULL;
}

enum { INPUT_ELEMENT_INTS = 5 };

/* elements: count records of { semanticIndex, format, slot, offset, perInstance } */
D3dInputLayout d3dCreateInputLayout(D3dDevice device, const int32_t *elements, int32_t count, D3dBlob vertexBlob) {
	D3D11_INPUT_ELEMENT_DESC descs[D3D11_IA_VERTEX_INPUT_STRUCTURE_ELEMENT_COUNT];
	if (count < 0 || count > D3D11_IA_VERTEX_INPUT_STRUCTURE_ELEMENT_COUNT) return NULL;
	for (int i = 0; i < count; i++) {
		const int32_t *e = &elements[i * INPUT_ELEMENT_INTS];
		descs[i].SemanticName = "TEXCOORD";
		descs[i].SemanticIndex = (UINT)e[0];
		descs[i].Format = (DXGI_FORMAT)e[1];
		descs[i].InputSlot = (UINT)e[2];
		descs[i].AlignedByteOffset = (UINT)e[3];
		descs[i].InputSlotClass = e[4] ? D3D11_INPUT_PER_INSTANCE_DATA : D3D11_INPUT_PER_VERTEX_DATA;
		descs[i].InstanceDataStepRate = e[4] ? 1 : 0;
	}
	ID3D11InputLayout *layout = NULL;
	HRESULT hr = ID3D11Device_CreateInputLayout(DEVICE(device), descs, (UINT)count,
		vertexBlob->bytes, vertexBlob->size, &layout);
	return SUCCEEDED(hr) ? (D3dInputLayout)layout : NULL;
}

D3dRasterizerState d3dCreateRasterizerState(
	D3dDevice device,
	int32_t cullMode,
	int32_t frontCounterClockwise,
	int32_t multisample,
	int32_t depthBias,
	double slopeScaledDepthBias,
	double depthBiasClamp) {
	D3D11_RASTERIZER_DESC desc = {0};
	desc.FillMode = D3D11_FILL_SOLID;
	desc.CullMode = (D3D11_CULL_MODE)cullMode;
	desc.FrontCounterClockwise = frontCounterClockwise ? TRUE : FALSE;
	desc.DepthBias = (INT)depthBias;
	desc.DepthBiasClamp = (FLOAT)depthBiasClamp;
	desc.SlopeScaledDepthBias = (FLOAT)slopeScaledDepthBias;
	desc.DepthClipEnable = TRUE;
	desc.ScissorEnable = TRUE;
	desc.MultisampleEnable = multisample ? TRUE : FALSE;
	ID3D11RasterizerState *state = NULL;
	HRESULT hr = ID3D11Device_CreateRasterizerState(DEVICE(device), &desc, &state);
	return SUCCEEDED(hr) ? (D3dRasterizerState)state : NULL;
}

D3dDepthStencilState d3dCreateDepthStencilState(
	D3dDevice device,
	int32_t depthWrite,
	int32_t compare,
	int32_t stencilEnabled,
	int32_t stencilReadMask,
	int32_t stencilWriteMask,
	int32_t frontFail,
	int32_t frontDepthFail,
	int32_t frontPass,
	int32_t frontCompare,
	int32_t backFail,
	int32_t backDepthFail,
	int32_t backPass,
	int32_t backCompare) {
	D3D11_DEPTH_STENCIL_DESC desc = {0};
	desc.DepthEnable = TRUE;
	desc.DepthWriteMask = depthWrite ? D3D11_DEPTH_WRITE_MASK_ALL : D3D11_DEPTH_WRITE_MASK_ZERO;
	desc.DepthFunc = (D3D11_COMPARISON_FUNC)compare;
	desc.StencilEnable = stencilEnabled ? TRUE : FALSE;
	desc.StencilReadMask = (UINT8)stencilReadMask;
	desc.StencilWriteMask = (UINT8)stencilWriteMask;
	desc.FrontFace.StencilFailOp = (D3D11_STENCIL_OP)frontFail;
	desc.FrontFace.StencilDepthFailOp = (D3D11_STENCIL_OP)frontDepthFail;
	desc.FrontFace.StencilPassOp = (D3D11_STENCIL_OP)frontPass;
	desc.FrontFace.StencilFunc = (D3D11_COMPARISON_FUNC)frontCompare;
	desc.BackFace.StencilFailOp = (D3D11_STENCIL_OP)backFail;
	desc.BackFace.StencilDepthFailOp = (D3D11_STENCIL_OP)backDepthFail;
	desc.BackFace.StencilPassOp = (D3D11_STENCIL_OP)backPass;
	desc.BackFace.StencilFunc = (D3D11_COMPARISON_FUNC)backCompare;
	ID3D11DepthStencilState *state = NULL;
	HRESULT hr = ID3D11Device_CreateDepthStencilState(DEVICE(device), &desc, &state);
	return SUCCEEDED(hr) ? (D3dDepthStencilState)state : NULL;
}

enum { BLEND_TARGET_INTS = 9 };

/* targets: count records of { index, enabled, srcColor, dstColor, opColor, srcAlpha, dstAlpha, opAlpha, writeMask }; unlisted targets stay disabled */
D3dBlendState d3dCreateBlendState(D3dDevice device, const int32_t *targets, int32_t count) {
	D3D11_BLEND_DESC desc = {0};
	desc.IndependentBlendEnable = TRUE;
	for (int i = 0; i < 8; i++) {
		D3D11_RENDER_TARGET_BLEND_DESC *target = &desc.RenderTarget[i];
		target->BlendEnable = FALSE;
		target->SrcBlend = target->SrcBlendAlpha = D3D11_BLEND_ONE;
		target->DestBlend = target->DestBlendAlpha = D3D11_BLEND_ZERO;
		target->BlendOp = target->BlendOpAlpha = D3D11_BLEND_OP_ADD;
		target->RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_ALL;
	}
	for (int i = 0; i < count; i++) {
		const int32_t *t = &targets[i * BLEND_TARGET_INTS];
		if (t[0] < 0 || t[0] >= 8) return NULL;
		D3D11_RENDER_TARGET_BLEND_DESC *target = &desc.RenderTarget[t[0]];
		target->BlendEnable = t[1] ? TRUE : FALSE;
		target->SrcBlend = (D3D11_BLEND)t[2];
		target->DestBlend = (D3D11_BLEND)t[3];
		target->BlendOp = (D3D11_BLEND_OP)t[4];
		target->SrcBlendAlpha = (D3D11_BLEND)t[5];
		target->DestBlendAlpha = (D3D11_BLEND)t[6];
		target->BlendOpAlpha = (D3D11_BLEND_OP)t[7];
		target->RenderTargetWriteMask = (UINT8)t[8];
	}
	ID3D11BlendState *state = NULL;
	HRESULT hr = ID3D11Device_CreateBlendState(DEVICE(device), &desc, &state);
	return SUCCEEDED(hr) ? (D3dBlendState)state : NULL;
}

void d3dSetRenderTargets(D3dContext context, D3dRtv color0, D3dRtv color1, D3dRtv color2, D3dRtv color3, D3dDsv depth) {
	ID3D11RenderTargetView *views[4] = {
		(ID3D11RenderTargetView *)color0,
		(ID3D11RenderTargetView *)color1,
		(ID3D11RenderTargetView *)color2,
		(ID3D11RenderTargetView *)color3,
	};
	ID3D11DeviceContext_OMSetRenderTargets(CONTEXT(context), 4, views, (ID3D11DepthStencilView *)depth);
}

void d3dSetViewport(D3dContext context, double x, double y, double width, double height, double minDepth, double maxDepth) {
	D3D11_VIEWPORT viewport = {0};
	viewport.TopLeftX = (FLOAT)x;
	viewport.TopLeftY = (FLOAT)y;
	viewport.Width = (FLOAT)width;
	viewport.Height = (FLOAT)height;
	viewport.MinDepth = (FLOAT)minDepth;
	viewport.MaxDepth = (FLOAT)maxDepth;
	ID3D11DeviceContext_RSSetViewports(CONTEXT(context), 1, &viewport);
}

void d3dSetScissorRect(D3dContext context, int32_t left, int32_t top, int32_t right, int32_t bottom) {
	D3D11_RECT rect = { left, top, right, bottom };
	ID3D11DeviceContext_RSSetScissorRects(CONTEXT(context), 1, &rect);
}

void d3dClearRtv(D3dContext context, D3dRtv view, double r, double g, double b, double a) {
	const FLOAT color[4] = { (FLOAT)r, (FLOAT)g, (FLOAT)b, (FLOAT)a };
	ID3D11DeviceContext_ClearRenderTargetView(CONTEXT(context), (ID3D11RenderTargetView *)view, color);
}

void d3dClearDsv(D3dContext context, D3dDsv view, int32_t flags, double depth, int32_t stencil) {
	ID3D11DeviceContext_ClearDepthStencilView(CONTEXT(context), (ID3D11DepthStencilView *)view, (UINT)flags, (FLOAT)depth, (UINT8)stencil);
}

void d3dClearState(D3dContext context) { ID3D11DeviceContext_ClearState(CONTEXT(context)); }

void d3dRsSetState(D3dContext context, D3dRasterizerState state) {
	ID3D11DeviceContext_RSSetState(CONTEXT(context), (ID3D11RasterizerState *)state);
}

void d3dOmSetDepthStencilState(D3dContext context, D3dDepthStencilState state, int32_t stencilReference) {
	ID3D11DeviceContext_OMSetDepthStencilState(CONTEXT(context), (ID3D11DepthStencilState *)state, (UINT)stencilReference);
}

void d3dOmSetBlendState(D3dContext context, D3dBlendState state, double r, double g, double b, double a) {
	const FLOAT blendFactor[4] = { (FLOAT)r, (FLOAT)g, (FLOAT)b, (FLOAT)a };
	ID3D11DeviceContext_OMSetBlendState(CONTEXT(context), (ID3D11BlendState *)state, blendFactor, 0xFFFFFFFF);
}

void d3dIaSetPrimitiveTopology(D3dContext context, int32_t topology) {
	ID3D11DeviceContext_IASetPrimitiveTopology(CONTEXT(context), (D3D11_PRIMITIVE_TOPOLOGY)topology);
}

void d3dIaSetInputLayout(D3dContext context, D3dInputLayout layout) {
	ID3D11DeviceContext_IASetInputLayout(CONTEXT(context), (ID3D11InputLayout *)layout);
}

void d3dVsSetShader(D3dContext context, D3dVertexShader shader) {
	ID3D11DeviceContext_VSSetShader(CONTEXT(context), (ID3D11VertexShader *)shader, NULL, 0);
}

void d3dPsSetShader(D3dContext context, D3dPixelShader shader) {
	ID3D11DeviceContext_PSSetShader(CONTEXT(context), (ID3D11PixelShader *)shader, NULL, 0);
}

void d3dSetConstantBuffer(D3dContext context, int32_t vertexStage, int32_t slot, D3dBuffer buffer) {
	ID3D11Buffer *buffers[1] = { (ID3D11Buffer *)buffer };
	if (vertexStage) ID3D11DeviceContext_VSSetConstantBuffers(CONTEXT(context), (UINT)slot, 1, buffers);
	else ID3D11DeviceContext_PSSetConstantBuffers(CONTEXT(context), (UINT)slot, 1, buffers);
}

void d3dIaSetVertexBuffer(D3dContext context, int32_t slot, D3dBuffer buffer, int32_t stride, int32_t offset) {
	ID3D11Buffer *buffers[1] = { (ID3D11Buffer *)buffer };
	UINT strides[1] = { (UINT)stride };
	UINT offsets[1] = { (UINT)offset };
	ID3D11DeviceContext_IASetVertexBuffers(CONTEXT(context), (UINT)slot, 1, buffers, strides, offsets);
}

void d3dIaSetIndexBuffer(D3dContext context, D3dBuffer buffer, int32_t format, int32_t offset) {
	ID3D11DeviceContext_IASetIndexBuffer(CONTEXT(context), (ID3D11Buffer *)buffer, (DXGI_FORMAT)format, (UINT)offset);
}

void d3dSetShaderResource(D3dContext context, int32_t vertexStage, int32_t slot, D3dSrv view) {
	ID3D11ShaderResourceView *views[1] = { (ID3D11ShaderResourceView *)view };
	if (vertexStage) ID3D11DeviceContext_VSSetShaderResources(CONTEXT(context), (UINT)slot, 1, views);
	else ID3D11DeviceContext_PSSetShaderResources(CONTEXT(context), (UINT)slot, 1, views);
}

void d3dSetSampler(D3dContext context, int32_t vertexStage, int32_t slot, D3dSampler sampler) {
	ID3D11SamplerState *samplers[1] = { (ID3D11SamplerState *)sampler };
	if (vertexStage) ID3D11DeviceContext_VSSetSamplers(CONTEXT(context), (UINT)slot, 1, samplers);
	else ID3D11DeviceContext_PSSetSamplers(CONTEXT(context), (UINT)slot, 1, samplers);
}

void d3dDraw(D3dContext context, int32_t vertexCount, int32_t firstVertex) {
	ID3D11DeviceContext_Draw(CONTEXT(context), (UINT)vertexCount, (UINT)firstVertex);
}

void d3dDrawInstanced(D3dContext context, int32_t vertexCount, int32_t instanceCount, int32_t firstVertex, int32_t firstInstance) {
	ID3D11DeviceContext_DrawInstanced(CONTEXT(context), (UINT)vertexCount, (UINT)instanceCount, (UINT)firstVertex, (UINT)firstInstance);
}

void d3dDrawIndexed(D3dContext context, int32_t indexCount, int32_t firstIndex, int32_t baseVertex) {
	ID3D11DeviceContext_DrawIndexed(CONTEXT(context), (UINT)indexCount, (UINT)firstIndex, baseVertex);
}

void d3dDrawIndexedInstanced(
	D3dContext context,
	int32_t indexCount,
	int32_t instanceCount,
	int32_t firstIndex,
	int32_t baseVertex,
	int32_t firstInstance) {
	ID3D11DeviceContext_DrawIndexedInstanced(CONTEXT(context), (UINT)indexCount, (UINT)instanceCount, (UINT)firstIndex, baseVertex, (UINT)firstInstance);
}

void d3dCsSetShader(D3dContext context, D3dComputeShader shader) {
	ID3D11DeviceContext_CSSetShader(CONTEXT(context), (ID3D11ComputeShader *)shader, NULL, 0);
}

void d3dCsSetShaderResource(D3dContext context, int32_t slot, D3dSrv view) {
	ID3D11ShaderResourceView *views[1] = { (ID3D11ShaderResourceView *)view };
	ID3D11DeviceContext_CSSetShaderResources(CONTEXT(context), (UINT)slot, 1, views);
}

void d3dCsSetUnorderedAccessView(D3dContext context, int32_t slot, D3dUav view) {
	ID3D11UnorderedAccessView *views[1] = { (ID3D11UnorderedAccessView *)view };
	ID3D11DeviceContext_CSSetUnorderedAccessViews(CONTEXT(context), (UINT)slot, 1, views, NULL);
}

void d3dCsSetSampler(D3dContext context, int32_t slot, D3dSampler sampler) {
	ID3D11SamplerState *samplers[1] = { (ID3D11SamplerState *)sampler };
	ID3D11DeviceContext_CSSetSamplers(CONTEXT(context), (UINT)slot, 1, samplers);
}

void d3dCsClearViews(D3dContext context) {
	ID3D11ShaderResourceView *srvs[D3D11_COMMONSHADER_INPUT_RESOURCE_SLOT_COUNT] = {0};
	ID3D11UnorderedAccessView *uavs[D3D11_PS_CS_UAV_REGISTER_COUNT] = {0};
	ID3D11DeviceContext_CSSetShaderResources(CONTEXT(context), 0, D3D11_COMMONSHADER_INPUT_RESOURCE_SLOT_COUNT, srvs);
	ID3D11DeviceContext_CSSetUnorderedAccessViews(CONTEXT(context), 0, D3D11_PS_CS_UAV_REGISTER_COUNT, uavs, NULL);
}

void d3dDispatch(D3dContext context, int32_t x, int32_t y, int32_t z) {
	ID3D11DeviceContext_Dispatch(CONTEXT(context), (UINT)x, (UINT)y, (UINT)z);
}

void d3dDispatchIndirect(D3dContext context, D3dBuffer arguments, int64_t offset) {
	ID3D11DeviceContext_DispatchIndirect(CONTEXT(context), (ID3D11Buffer *)arguments, (UINT)offset);
}

void d3dDrawIndexedInstancedIndirect(D3dContext context, D3dBuffer arguments, int64_t offset) {
	ID3D11DeviceContext_DrawIndexedInstancedIndirect(CONTEXT(context), (ID3D11Buffer *)arguments, (UINT)offset);
}

static const GUID debugObjectName = { 0x429b8c22, 0x9188, 0x4b0c, { 0x87, 0x42, 0xac, 0xb0, 0xbf, 0x85, 0xc2, 0x00 } };

void d3dSetName(void *object, const char *name) {
	ID3D11DeviceChild_SetPrivateData((ID3D11DeviceChild *)object, &debugObjectName, (UINT)strlen(name), name);
}

int32_t d3dFormatCaps(D3dDevice device, int32_t format) {
	UINT support = 0;
	if (FAILED(ID3D11Device_CheckFormatSupport(DEVICE(device), (DXGI_FORMAT)format, &support))) return 0;
	return ((support & D3D11_FORMAT_SUPPORT_SHADER_SAMPLE) ? D3D_FORMAT_CAP_SAMPLE : 0) | ((support & D3D11_FORMAT_SUPPORT_RENDER_TARGET) ? D3D_FORMAT_CAP_RENDER : 0) |
		((support & D3D11_FORMAT_SUPPORT_BLENDABLE) ? D3D_FORMAT_CAP_BLEND : 0);
}

static ID3DUserDefinedAnnotation *annotation;
static const GUID annotationIid = { 0xb2daad8b, 0x03d4, 0x4dbf, { 0x95, 0xeb, 0x32, 0xab, 0x4b, 0x63, 0xd0, 0xab } };

static int annotationOf(D3dContext context) {
	if (!annotation) ID3D11DeviceContext_QueryInterface(CONTEXT(context), &annotationIid, (void **)&annotation);
	return annotation != NULL;
}

static int widen(const char *text, wchar_t *out) {
	return MultiByteToWideChar(CP_UTF8, 0, text, -1, out, D3D_LABEL_MAX) > 0;
}

int32_t d3dBeginEvent(D3dContext context, const char *label) {
	if (!annotationOf(context)) return -1;
	wchar_t wide[D3D_LABEL_MAX];
	if (!widen(label, wide)) return D3D_LABEL_TOO_LONG;
	return (int32_t)ID3DUserDefinedAnnotation_BeginEvent(annotation, wide);
}

int32_t d3dEndEvent(D3dContext context) {
	if (!annotationOf(context)) return -1;
	return (int32_t)ID3DUserDefinedAnnotation_EndEvent(annotation);
}

int32_t d3dSetMarker(D3dContext context, const char *label) {
	if (!annotationOf(context)) return -1;
	wchar_t wide[D3D_LABEL_MAX];
	if (!widen(label, wide)) return D3D_LABEL_TOO_LONG;
	ID3DUserDefinedAnnotation_SetMarker(annotation, wide);
	return 0;
}

void d3dReleaseAnnotation(void) {
	if (annotation) ID3DUserDefinedAnnotation_Release(annotation);
	annotation = NULL;
}

static D3D11_QUERY_DESC queryDesc(int32_t kind) {
	D3D11_QUERY_DESC desc = {0};
	desc.Query = kind == D3D_QUERY_OCCLUSION ? D3D11_QUERY_OCCLUSION : kind == D3D_QUERY_TIMESTAMP ? D3D11_QUERY_TIMESTAMP : D3D11_QUERY_TIMESTAMP_DISJOINT;
	return desc;
}

int32_t d3dQuerySupported(D3dDevice device, int32_t kind) {
	D3D11_QUERY_DESC desc = queryDesc(kind);
	return ID3D11Device_CreateQuery(DEVICE(device), &desc, NULL) == S_FALSE;
}

D3dQuery d3dCreateQuery(D3dDevice device, int32_t kind) {
	D3D11_QUERY_DESC desc = queryDesc(kind);
	ID3D11Query *query = NULL;
	return SUCCEEDED(ID3D11Device_CreateQuery(DEVICE(device), &desc, &query)) ? (D3dQuery)query : NULL;
}

void d3dQueryBegin(D3dContext context, D3dQuery query) {
	ID3D11DeviceContext_Begin(CONTEXT(context), (ID3D11Asynchronous *)query);
}

void d3dQueryEnd(D3dContext context, D3dQuery query) {
	ID3D11DeviceContext_End(CONTEXT(context), (ID3D11Asynchronous *)query);
}

static int32_t queryData(D3dContext context, D3dQuery query, void *out, UINT bytes) {
	ULONGLONG deadline = GetTickCount64() + 5000;
	for (;;) {
		HRESULT hr = ID3D11DeviceContext_GetData(CONTEXT(context), (ID3D11Asynchronous *)query, out, bytes, 0);
		if (hr == S_OK) return 1;
		if (FAILED(hr) || GetTickCount64() > deadline) return 0;
		ID3D11DeviceContext_Flush(CONTEXT(context));
		Sleep(0);
	}
}

int32_t d3dQueryTicks(D3dContext context, D3dQuery query, uint64_t *out) {
	return queryData(context, query, out, sizeof(uint64_t));
}

int32_t d3dQueryFrequency(D3dContext context, D3dQuery query, uint64_t *out) {
	D3D11_QUERY_DATA_TIMESTAMP_DISJOINT data;
	if (!queryData(context, query, &data, sizeof data)) return 0;
	if (data.Disjoint) return -1;
	*out = data.Frequency;
	return 1;
}

typedef struct { const char *name; int32_t value; } DriverConstant;

#define DRIVER(name) { #name, (int32_t)(name) }
#define DRIVER_IN(prefix, name) { #prefix #name, (int32_t)prefix##name }

static const DriverConstant driverConstants[] = {
	DRIVER(D3D11_REQ_CONSTANT_BUFFER_ELEMENT_COUNT),
	DRIVER(D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT),
	DRIVER(D3D11_COMMONSHADER_INPUT_RESOURCE_SLOT_COUNT),
	DRIVER(D3D11_COMMONSHADER_SAMPLER_SLOT_COUNT),
	DRIVER(D3D11_PS_CS_UAV_REGISTER_COUNT),
	DRIVER(D3D11_CS_DISPATCH_MAX_THREAD_GROUPS_PER_DIMENSION),
	DRIVER(D3D11_REQ_TEXTURE1D_U_DIMENSION),
	DRIVER(D3D11_REQ_TEXTURE2D_U_OR_V_DIMENSION),
	DRIVER(D3D11_REQ_TEXTURE3D_U_V_OR_W_DIMENSION),
	DRIVER(D3D11_REQ_TEXTURE2D_ARRAY_AXIS_DIMENSION),
	DRIVER(D3D11_CS_THREAD_GROUP_MAX_X),
	DRIVER(D3D11_CS_THREAD_GROUP_MAX_Y),
	DRIVER(D3D11_CS_THREAD_GROUP_MAX_Z),
	DRIVER(D3D11_CS_THREAD_GROUP_MAX_THREADS_PER_GROUP),
	DRIVER(D3D11_MAX_MAXANISOTROPY),
	DRIVER(INPUT_ELEMENT_INTS),
	DRIVER(BLEND_TARGET_INTS),
	DRIVER(D3D_FORMAT_CAP_SAMPLE),
	DRIVER(D3D_FORMAT_CAP_RENDER),
	DRIVER(D3D_FORMAT_CAP_BLEND),
	DRIVER(D3D_VIEW_2D),
	DRIVER(D3D_VIEW_2D_ARRAY),
	DRIVER(D3D_VIEW_CUBE),
	DRIVER(D3D_VIEW_CUBE_ARRAY),
	DRIVER(D3D_VIEW_3D),
	DRIVER(D3D_QUERY_OCCLUSION),
	DRIVER(D3D_QUERY_TIMESTAMP),
	DRIVER(D3D_QUERY_DISJOINT),
	DRIVER(D3D_LABEL_MAX - 1),
	DRIVER(D3D_LABEL_TOO_LONG),
	DRIVER_IN(DXGI_FORMAT_, UNKNOWN),
	DRIVER_IN(DXGI_FORMAT_, R32G32B32A32_FLOAT),
	DRIVER_IN(DXGI_FORMAT_, R32G32B32A32_UINT),
	DRIVER_IN(DXGI_FORMAT_, R32G32B32A32_SINT),
	DRIVER_IN(DXGI_FORMAT_, R32G32B32_FLOAT),
	DRIVER_IN(DXGI_FORMAT_, R32G32B32_UINT),
	DRIVER_IN(DXGI_FORMAT_, R32G32B32_SINT),
	DRIVER_IN(DXGI_FORMAT_, R16G16B16A16_FLOAT),
	DRIVER_IN(DXGI_FORMAT_, R16G16B16A16_UNORM),
	DRIVER_IN(DXGI_FORMAT_, R16G16B16A16_UINT),
	DRIVER_IN(DXGI_FORMAT_, R16G16B16A16_SNORM),
	DRIVER_IN(DXGI_FORMAT_, R16G16B16A16_SINT),
	DRIVER_IN(DXGI_FORMAT_, R32G32_FLOAT),
	DRIVER_IN(DXGI_FORMAT_, R32G32_UINT),
	DRIVER_IN(DXGI_FORMAT_, R32G32_SINT),
	DRIVER_IN(DXGI_FORMAT_, R32G8X24_TYPELESS),
	DRIVER_IN(DXGI_FORMAT_, D32_FLOAT_S8X24_UINT),
	DRIVER_IN(DXGI_FORMAT_, R32_FLOAT_X8X24_TYPELESS),
	DRIVER_IN(DXGI_FORMAT_, R10G10B10A2_UNORM),
	DRIVER_IN(DXGI_FORMAT_, R11G11B10_FLOAT),
	DRIVER_IN(DXGI_FORMAT_, R8G8B8A8_TYPELESS),
	DRIVER_IN(DXGI_FORMAT_, R8G8B8A8_UNORM),
	DRIVER_IN(DXGI_FORMAT_, R8G8B8A8_UNORM_SRGB),
	DRIVER_IN(DXGI_FORMAT_, R8G8B8A8_UINT),
	DRIVER_IN(DXGI_FORMAT_, R8G8B8A8_SNORM),
	DRIVER_IN(DXGI_FORMAT_, R8G8B8A8_SINT),
	DRIVER_IN(DXGI_FORMAT_, R16G16_FLOAT),
	DRIVER_IN(DXGI_FORMAT_, R16G16_UNORM),
	DRIVER_IN(DXGI_FORMAT_, R16G16_UINT),
	DRIVER_IN(DXGI_FORMAT_, R16G16_SNORM),
	DRIVER_IN(DXGI_FORMAT_, R16G16_SINT),
	DRIVER_IN(DXGI_FORMAT_, R32_TYPELESS),
	DRIVER_IN(DXGI_FORMAT_, D32_FLOAT),
	DRIVER_IN(DXGI_FORMAT_, R32_FLOAT),
	DRIVER_IN(DXGI_FORMAT_, R32_UINT),
	DRIVER_IN(DXGI_FORMAT_, R32_SINT),
	DRIVER_IN(DXGI_FORMAT_, R8G8_UNORM),
	DRIVER_IN(DXGI_FORMAT_, R8G8_UINT),
	DRIVER_IN(DXGI_FORMAT_, R8G8_SNORM),
	DRIVER_IN(DXGI_FORMAT_, R8G8_SINT),
	DRIVER_IN(DXGI_FORMAT_, R16_TYPELESS),
	DRIVER_IN(DXGI_FORMAT_, R16_FLOAT),
	DRIVER_IN(DXGI_FORMAT_, D16_UNORM),
	DRIVER_IN(DXGI_FORMAT_, R16_UNORM),
	DRIVER_IN(DXGI_FORMAT_, R16_UINT),
	DRIVER_IN(DXGI_FORMAT_, R8_UNORM),
	DRIVER_IN(DXGI_FORMAT_, B8G8R8A8_UNORM),
	DRIVER_IN(DXGI_FORMAT_, B8G8R8A8_TYPELESS),
	DRIVER_IN(DXGI_FORMAT_, B8G8R8A8_UNORM_SRGB),
	DRIVER_IN(D3D11_USAGE_, DEFAULT),
	DRIVER_IN(D3D11_USAGE_, DYNAMIC),
	DRIVER_IN(D3D11_USAGE_, STAGING),
	DRIVER_IN(D3D11_BIND_, VERTEX_BUFFER),
	DRIVER_IN(D3D11_BIND_, INDEX_BUFFER),
	DRIVER_IN(D3D11_BIND_, CONSTANT_BUFFER),
	DRIVER_IN(D3D11_BIND_, SHADER_RESOURCE),
	DRIVER_IN(D3D11_BIND_, RENDER_TARGET),
	DRIVER_IN(D3D11_BIND_, DEPTH_STENCIL),
	DRIVER_IN(D3D11_BIND_, UNORDERED_ACCESS),
	DRIVER_IN(D3D11_RESOURCE_MISC_, DRAWINDIRECT_ARGS),
	DRIVER_IN(D3D11_RESOURCE_MISC_, BUFFER_ALLOW_RAW_VIEWS),
	DRIVER_IN(D3D11_CPU_ACCESS_, WRITE),
	DRIVER_IN(D3D11_CPU_ACCESS_, READ),
	DRIVER_IN(D3D11_MAP_, WRITE),
	DRIVER_IN(D3D11_MAP_, WRITE_DISCARD),
	DRIVER_IN(D3D11_MAP_, WRITE_NO_OVERWRITE),
	DRIVER_IN(D3D11_CLEAR_, DEPTH),
	DRIVER_IN(D3D11_CLEAR_, STENCIL),
	DRIVER_IN(D3D_PRIMITIVE_TOPOLOGY_, POINTLIST),
	DRIVER_IN(D3D_PRIMITIVE_TOPOLOGY_, LINELIST),
	DRIVER_IN(D3D_PRIMITIVE_TOPOLOGY_, LINESTRIP),
	DRIVER_IN(D3D_PRIMITIVE_TOPOLOGY_, TRIANGLELIST),
	DRIVER_IN(D3D_PRIMITIVE_TOPOLOGY_, TRIANGLESTRIP),
	DRIVER_IN(D3D11_CULL_, NONE),
	DRIVER_IN(D3D11_CULL_, FRONT),
	DRIVER_IN(D3D11_CULL_, BACK),
	DRIVER_IN(D3D11_FILTER_, MIN_MAG_POINT_MIP_LINEAR),
	DRIVER_IN(D3D11_FILTER_, MIN_POINT_MAG_LINEAR_MIP_POINT),
	DRIVER_IN(D3D11_FILTER_, MIN_LINEAR_MAG_MIP_POINT),
	DRIVER_IN(D3D11_FILTER_, COMPARISON_MIN_MAG_MIP_POINT),
	DRIVER_IN(D3D11_FILTER_, ANISOTROPIC),
	DRIVER_IN(D3D11_TEXTURE_ADDRESS_, WRAP),
	DRIVER_IN(D3D11_TEXTURE_ADDRESS_, MIRROR),
	DRIVER_IN(D3D11_TEXTURE_ADDRESS_, CLAMP),
	DRIVER_IN(D3D11_BLEND_, ZERO),
	DRIVER_IN(D3D11_BLEND_, ONE),
	DRIVER_IN(D3D11_BLEND_, SRC_COLOR),
	DRIVER_IN(D3D11_BLEND_, INV_SRC_COLOR),
	DRIVER_IN(D3D11_BLEND_, SRC_ALPHA),
	DRIVER_IN(D3D11_BLEND_, INV_SRC_ALPHA),
	DRIVER_IN(D3D11_BLEND_, DEST_ALPHA),
	DRIVER_IN(D3D11_BLEND_, INV_DEST_ALPHA),
	DRIVER_IN(D3D11_BLEND_, DEST_COLOR),
	DRIVER_IN(D3D11_BLEND_, INV_DEST_COLOR),
	DRIVER_IN(D3D11_BLEND_, SRC_ALPHA_SAT),
	DRIVER_IN(D3D11_BLEND_, BLEND_FACTOR),
	DRIVER_IN(D3D11_BLEND_, INV_BLEND_FACTOR),
	DRIVER_IN(D3D11_COLOR_WRITE_, ENABLE_ALL),
	DRIVER_IN(D3D11_COMPARISON_, NEVER),
	DRIVER_IN(D3D11_COMPARISON_, NEVER),
	DRIVER_IN(D3D11_COMPARISON_, LESS),
	DRIVER_IN(D3D11_COMPARISON_, EQUAL),
	DRIVER_IN(D3D11_COMPARISON_, LESS_EQUAL),
	DRIVER_IN(D3D11_COMPARISON_, GREATER),
	DRIVER_IN(D3D11_COMPARISON_, NOT_EQUAL),
	DRIVER_IN(D3D11_COMPARISON_, GREATER_EQUAL),
	DRIVER_IN(D3D11_COMPARISON_, ALWAYS),
	DRIVER_IN(D3D11_BLEND_OP_, ADD),
	DRIVER_IN(D3D11_BLEND_OP_, SUBTRACT),
	DRIVER_IN(D3D11_BLEND_OP_, REV_SUBTRACT),
	DRIVER_IN(D3D11_BLEND_OP_, MIN),
	DRIVER_IN(D3D11_BLEND_OP_, MAX),
	DRIVER_IN(D3D11_STENCIL_OP_, KEEP),
	DRIVER_IN(D3D11_STENCIL_OP_, ZERO),
	DRIVER_IN(D3D11_STENCIL_OP_, REPLACE),
	DRIVER_IN(D3D11_STENCIL_OP_, INCR_SAT),
	DRIVER_IN(D3D11_STENCIL_OP_, DECR_SAT),
	DRIVER_IN(D3D11_STENCIL_OP_, INVERT),
	DRIVER_IN(D3D11_STENCIL_OP_, INCR),
	DRIVER_IN(D3D11_STENCIL_OP_, DECR),
};

static char s_constantsDisagreement[256];

const char *d3dConstantsDisagreement(const int32_t *values, int32_t count) {
	int32_t known = (int32_t)(sizeof driverConstants / sizeof driverConstants[0]);
	s_constantsDisagreement[0] = 0;
	if (count != known) {
		snprintf(s_constantsDisagreement, sizeof s_constantsDisagreement, "backend.ms lists %d constants and d3d11.c checks %d", (int)count, (int)known);
		return s_constantsDisagreement;
	}
	for (int32_t i = 0; i < known; i++) {
		if (values[i] == driverConstants[i].value) continue;
		snprintf(s_constantsDisagreement, sizeof s_constantsDisagreement, "entry %d: %s is %d in the driver and %d in backend.ms",
			(int)i, driverConstants[i].name, (int)driverConstants[i].value, (int)values[i]);
		break;
	}
	return s_constantsDisagreement;
}
