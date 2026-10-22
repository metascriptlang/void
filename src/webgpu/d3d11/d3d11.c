#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d11.h>
#include <d3d11_1.h>
#include <d3dcompiler.h>
#include <float.h>
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

void d3dReleaseBuffer(D3dBuffer buffer) { if (buffer) ID3D11Buffer_Release((ID3D11Buffer *)buffer); }

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
	if (dimension == 4) {
		desc.ViewDimension = D3D11_UAV_DIMENSION_TEXTURE3D;
		desc.Texture3D.MipSlice = (UINT)mip;
		desc.Texture3D.FirstWSlice = 0;
		desc.Texture3D.WSize = (UINT)-1;
	} else if (dimension == 1) {
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

void d3dReleaseUav(D3dUav view) { if (view) ID3D11UnorderedAccessView_Release((ID3D11UnorderedAccessView *)view); }

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

static ID3D11DeviceContext1 *context1;

int32_t d3dUniformOffsetting(D3dDevice device, D3dContext context) {
	D3D11_FEATURE_DATA_D3D11_OPTIONS options = {0};
	if (context1) return 1;
	if (FAILED(ID3D11DeviceContext_QueryInterface(CONTEXT(context), &IID_ID3D11DeviceContext1, (void **)&context1))) return 0;
	if (FAILED(ID3D11Device_CheckFeatureSupport(DEVICE(device), D3D11_FEATURE_D3D11_OPTIONS, &options, sizeof options)) ||
		!options.ConstantBufferOffsetting || !options.ConstantBufferPartialUpdate ||
		!options.MapNoOverwriteOnDynamicConstantBuffer) {
		ID3D11DeviceContext1_Release(context1);
		context1 = NULL;
		return 0;
	}
	return 1;
}

void d3dReleaseUniformOffsetting(void) {
	if (context1) ID3D11DeviceContext1_Release(context1);
	context1 = NULL;
}

void d3dVsSetConstantBufferRange(int32_t slot, D3dBuffer buffer, int64_t firstConstant, int64_t numConstants) {
	ID3D11Buffer *buffers[1] = { (ID3D11Buffer *)buffer };
	UINT first = (UINT)firstConstant, count = (UINT)numConstants;
	ID3D11DeviceContext1_VSSetConstantBuffers1(context1, (UINT)slot, 1, buffers, &first, &count);
}

void d3dPsSetConstantBufferRange(int32_t slot, D3dBuffer buffer, int64_t firstConstant, int64_t numConstants) {
	ID3D11Buffer *buffers[1] = { (ID3D11Buffer *)buffer };
	UINT first = (UINT)firstConstant, count = (UINT)numConstants;
	ID3D11DeviceContext1_PSSetConstantBuffers1(context1, (UINT)slot, 1, buffers, &first, &count);
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

void d3dReleaseTexture(D3dTexture texture) { if (texture) IUnknown_Release((IUnknown *)texture); }

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
	ID3D11DeviceContext_CopySubresourceRegion(CONTEXT(context), (ID3D11Resource *)staging, 0, 0, 0, 0, (ID3D11Resource *)texture, (UINT)subresource, &box);
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
	int32_t rowBytes,
	D3dTexture texture,
	int32_t subresource,
	int32_t x,
	int32_t y,
	int32_t width,
	int32_t height) {
	D3D11_MAPPED_SUBRESOURCE source;
	if (FAILED(ID3D11DeviceContext_Map(CONTEXT(context), (ID3D11Resource *)buffer, 0, D3D11_MAP_READ, 0, &source))) return 0;
	uint8_t *packed = (uint8_t *)malloc((size_t)rowBytes * (size_t)height);
	if (!packed) {
		ID3D11DeviceContext_Unmap(CONTEXT(context), (ID3D11Resource *)buffer, 0);
		return 0;
	}
	for (int32_t row = 0; row < height; row++) {
		memcpy(packed + (size_t)row * (size_t)rowBytes, (uint8_t *)source.pData + offset + (size_t)row * (size_t)bytesPerRow, (size_t)rowBytes);
	}
	ID3D11DeviceContext_Unmap(CONTEXT(context), (ID3D11Resource *)buffer, 0);
	D3D11_BOX box = { (UINT)x, (UINT)y, 0, (UINT)(x + width), (UINT)(y + height), 1 };
	ID3D11DeviceContext_UpdateSubresource(CONTEXT(context), (ID3D11Resource *)texture, (UINT)subresource, &box, packed, (UINT)rowBytes, 0);
	free(packed);
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
	} else if (dimension == 0) {
		desc.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2D;
		desc.Texture2D.MostDetailedMip = (UINT)baseMip;
		desc.Texture2D.MipLevels = (UINT)mipCount;
	} else if (dimension == 1) {
		desc.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2DARRAY;
		desc.Texture2DArray.MostDetailedMip = (UINT)baseMip;
		desc.Texture2DArray.MipLevels = (UINT)mipCount;
		desc.Texture2DArray.FirstArraySlice = (UINT)baseLayer;
		desc.Texture2DArray.ArraySize = (UINT)layerCount;
	} else if (dimension == 2) {
		desc.ViewDimension = D3D11_SRV_DIMENSION_TEXTURECUBE;
		desc.TextureCube.MostDetailedMip = (UINT)baseMip;
		desc.TextureCube.MipLevels = (UINT)mipCount;
	} else if (dimension == 3) {
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

void d3dReleaseSrv(D3dSrv view) { if (view) ID3D11ShaderResourceView_Release((ID3D11ShaderResourceView *)view); }
void d3dReleaseRtv(D3dRtv view) { if (view) ID3D11RenderTargetView_Release((ID3D11RenderTargetView *)view); }
void d3dReleaseDsv(D3dDsv view) { if (view) ID3D11DepthStencilView_Release((ID3D11DepthStencilView *)view); }

void d3dResolveSubresource(D3dContext context, D3dTexture destination, D3dTexture source, int32_t format) {
	ID3D11DeviceContext_ResolveSubresource(CONTEXT(context), (ID3D11Resource *)destination, 0, (ID3D11Resource *)source, 0, (DXGI_FORMAT)format);
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

void d3dReleaseSampler(D3dSampler sampler) { if (sampler) ID3D11SamplerState_Release((ID3D11SamplerState *)sampler); }

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
	return (D3dBlob)output;
}

const char *d3dCompileLog(void) { return s_compileLog; }

void d3dReleaseBlob(D3dBlob blob) { if (blob) ID3D10Blob_Release((ID3DBlob *)blob); }

D3dVertexShader d3dCreateVertexShader(D3dDevice device, D3dBlob blob) {
	ID3DBlob *code = (ID3DBlob *)blob;
	ID3D11VertexShader *shader = NULL;
	HRESULT hr = ID3D11Device_CreateVertexShader(DEVICE(device), ID3D10Blob_GetBufferPointer(code), ID3D10Blob_GetBufferSize(code), NULL, &shader);
	return SUCCEEDED(hr) ? (D3dVertexShader)shader : NULL;
}

D3dPixelShader d3dCreatePixelShader(D3dDevice device, D3dBlob blob) {
	ID3DBlob *code = (ID3DBlob *)blob;
	ID3D11PixelShader *shader = NULL;
	HRESULT hr = ID3D11Device_CreatePixelShader(DEVICE(device), ID3D10Blob_GetBufferPointer(code), ID3D10Blob_GetBufferSize(code), NULL, &shader);
	return SUCCEEDED(hr) ? (D3dPixelShader)shader : NULL;
}

D3dComputeShader d3dCreateComputeShader(D3dDevice device, D3dBlob blob) {
	ID3DBlob *code = (ID3DBlob *)blob;
	ID3D11ComputeShader *shader = NULL;
	HRESULT hr = ID3D11Device_CreateComputeShader(DEVICE(device), ID3D10Blob_GetBufferPointer(code), ID3D10Blob_GetBufferSize(code), NULL, &shader);
	return SUCCEEDED(hr) ? (D3dComputeShader)shader : NULL;
}

void d3dReleaseComputeShader(D3dComputeShader shader) { if (shader) ID3D11ComputeShader_Release((ID3D11ComputeShader *)shader); }

void d3dReleaseVertexShader(D3dVertexShader shader) { if (shader) ID3D11VertexShader_Release((ID3D11VertexShader *)shader); }
void d3dReleasePixelShader(D3dPixelShader shader) { if (shader) ID3D11PixelShader_Release((ID3D11PixelShader *)shader); }

static D3D11_INPUT_ELEMENT_DESC s_inputElements[D3D11_IA_VERTEX_INPUT_STRUCTURE_ELEMENT_COUNT];

void d3dInputElement(
	int32_t index,
	int32_t semanticIndex,
	int32_t format,
	int32_t slot,
	int32_t offset,
	int32_t perInstance) {
	D3D11_INPUT_ELEMENT_DESC *element = &s_inputElements[index];
	element->SemanticName = "TEXCOORD";
	element->SemanticIndex = (UINT)semanticIndex;
	element->Format = (DXGI_FORMAT)format;
	element->InputSlot = (UINT)slot;
	element->AlignedByteOffset = (UINT)offset;
	element->InputSlotClass = perInstance ? D3D11_INPUT_PER_INSTANCE_DATA : D3D11_INPUT_PER_VERTEX_DATA;
	element->InstanceDataStepRate = perInstance ? 1 : 0;
}

D3dInputLayout d3dCreateInputLayout(D3dDevice device, int32_t count, D3dBlob vertexBlob) {
	ID3DBlob *code = (ID3DBlob *)vertexBlob;
	ID3D11InputLayout *layout = NULL;
	HRESULT hr = ID3D11Device_CreateInputLayout(DEVICE(device), s_inputElements, (UINT)count,
		ID3D10Blob_GetBufferPointer(code), ID3D10Blob_GetBufferSize(code), &layout);
	return SUCCEEDED(hr) ? (D3dInputLayout)layout : NULL;
}

void d3dReleaseInputLayout(D3dInputLayout layout) { if (layout) ID3D11InputLayout_Release((ID3D11InputLayout *)layout); }

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

void d3dReleaseRasterizerState(D3dRasterizerState state) { if (state) ID3D11RasterizerState_Release((ID3D11RasterizerState *)state); }

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

void d3dReleaseDepthStencilState(D3dDepthStencilState state) { if (state) ID3D11DepthStencilState_Release((ID3D11DepthStencilState *)state); }

static D3D11_BLEND_DESC s_blend;
static int s_blendReady;

static void resetBlendTargets(void) {
	memset(&s_blend, 0, sizeof s_blend);
	s_blend.IndependentBlendEnable = TRUE;
	for (int i = 0; i < 8; i++) {
		D3D11_RENDER_TARGET_BLEND_DESC *target = &s_blend.RenderTarget[i];
		target->BlendEnable = FALSE;
		target->SrcBlend = target->SrcBlendAlpha = D3D11_BLEND_ONE;
		target->DestBlend = target->DestBlendAlpha = D3D11_BLEND_ZERO;
		target->BlendOp = target->BlendOpAlpha = D3D11_BLEND_OP_ADD;
		target->RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_ALL;
	}
	s_blendReady = 1;
}

void d3dBlendTarget(
	int32_t index,
	int32_t enabled,
	int32_t sourceColor,
	int32_t destinationColor,
	int32_t operationColor,
	int32_t sourceAlpha,
	int32_t destinationAlpha,
	int32_t operationAlpha,
	int32_t writeMask) {
	if (!s_blendReady) resetBlendTargets();
	D3D11_RENDER_TARGET_BLEND_DESC *target = &s_blend.RenderTarget[index];
	target->BlendEnable = enabled ? TRUE : FALSE;
	target->SrcBlend = (D3D11_BLEND)sourceColor;
	target->DestBlend = (D3D11_BLEND)destinationColor;
	target->BlendOp = (D3D11_BLEND_OP)operationColor;
	target->SrcBlendAlpha = (D3D11_BLEND)sourceAlpha;
	target->DestBlendAlpha = (D3D11_BLEND)destinationAlpha;
	target->BlendOpAlpha = (D3D11_BLEND_OP)operationAlpha;
	target->RenderTargetWriteMask = (UINT8)writeMask;
}

D3dBlendState d3dCreateBlendState(D3dDevice device) {
	if (!s_blendReady) resetBlendTargets();
	ID3D11BlendState *state = NULL;
	HRESULT hr = ID3D11Device_CreateBlendState(DEVICE(device), &s_blend, &state);
	s_blendReady = 0;
	return SUCCEEDED(hr) ? (D3dBlendState)state : NULL;
}

void d3dReleaseBlendState(D3dBlendState state) { if (state) ID3D11BlendState_Release((ID3D11BlendState *)state); }

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

void d3dVsSetConstantBuffer(D3dContext context, int32_t slot, D3dBuffer buffer) {
	ID3D11Buffer *buffers[1] = { (ID3D11Buffer *)buffer };
	ID3D11DeviceContext_VSSetConstantBuffers(CONTEXT(context), (UINT)slot, 1, buffers);
}

void d3dPsSetConstantBuffer(D3dContext context, int32_t slot, D3dBuffer buffer) {
	ID3D11Buffer *buffers[1] = { (ID3D11Buffer *)buffer };
	ID3D11DeviceContext_PSSetConstantBuffers(CONTEXT(context), (UINT)slot, 1, buffers);
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

void d3dVsSetShaderResource(D3dContext context, int32_t slot, D3dSrv view) {
	ID3D11ShaderResourceView *views[1] = { (ID3D11ShaderResourceView *)view };
	ID3D11DeviceContext_VSSetShaderResources(CONTEXT(context), (UINT)slot, 1, views);
}

void d3dPsSetShaderResource(D3dContext context, int32_t slot, D3dSrv view) {
	ID3D11ShaderResourceView *views[1] = { (ID3D11ShaderResourceView *)view };
	ID3D11DeviceContext_PSSetShaderResources(CONTEXT(context), (UINT)slot, 1, views);
}

void d3dVsSetSampler(D3dContext context, int32_t slot, D3dSampler sampler) {
	ID3D11SamplerState *samplers[1] = { (ID3D11SamplerState *)sampler };
	ID3D11DeviceContext_VSSetSamplers(CONTEXT(context), (UINT)slot, 1, samplers);
}

void d3dPsSetSampler(D3dContext context, int32_t slot, D3dSampler sampler) {
	ID3D11SamplerState *samplers[1] = { (ID3D11SamplerState *)sampler };
	ID3D11DeviceContext_PSSetSamplers(CONTEXT(context), (UINT)slot, 1, samplers);
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

void d3dCsSetConstantBuffer(D3dContext context, int32_t slot, D3dBuffer buffer) {
	ID3D11Buffer *buffers[1] = { (ID3D11Buffer *)buffer };
	ID3D11DeviceContext_CSSetConstantBuffers(CONTEXT(context), (UINT)slot, 1, buffers);
}

void d3dCsSetConstantBufferRange(int32_t slot, D3dBuffer buffer, int64_t firstConstant, int64_t numConstants) {
	ID3D11Buffer *buffers[1] = { (ID3D11Buffer *)buffer };
	UINT first = (UINT)firstConstant, count = (UINT)numConstants;
	ID3D11DeviceContext1_CSSetConstantBuffers1(context1, (UINT)slot, 1, buffers, &first, &count);
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

static const GUID debugObjectName = { 0x429b8c22, 0x9188, 0x4b0c, { 0x87, 0x42, 0xac, 0xb0, 0xbf, 0x85, 0xc2, 0x00 } };

void d3dSetName(void *object, const char *name) {
	ID3D11DeviceChild_SetPrivateData((ID3D11DeviceChild *)object, &debugObjectName, (UINT)strlen(name), name);
}

int32_t d3dFormatCaps(D3dDevice device, int32_t format) {
	UINT support = 0;
	if (FAILED(ID3D11Device_CheckFormatSupport(DEVICE(device), (DXGI_FORMAT)format, &support))) return 0;
	return ((support & D3D11_FORMAT_SUPPORT_SHADER_SAMPLE) ? 1 : 0) | ((support & D3D11_FORMAT_SUPPORT_RENDER_TARGET) ? 2 : 0) |
		((support & D3D11_FORMAT_SUPPORT_BLENDABLE) ? 4 : 0);
}

static ID3DUserDefinedAnnotation *annotation;
static const GUID annotationIid = { 0xb2daad8b, 0x03d4, 0x4dbf, { 0x95, 0xeb, 0x32, 0xab, 0x4b, 0x63, 0xd0, 0xab } };

static int annotationOf(D3dContext context) {
	if (!annotation) ID3D11DeviceContext_QueryInterface(CONTEXT(context), &annotationIid, (void **)&annotation);
	return annotation != NULL;
}

static wchar_t *widen(const char *text) {
	int count = MultiByteToWideChar(CP_UTF8, 0, text, -1, NULL, 0);
	wchar_t *wide = (wchar_t *)malloc((size_t)(count > 0 ? count : 1) * sizeof(wchar_t));
	if (count > 0) MultiByteToWideChar(CP_UTF8, 0, text, -1, wide, count);
	else wide[0] = 0;
	return wide;
}

int32_t d3dBeginEvent(D3dContext context, const char *label) {
	if (!annotationOf(context)) return -1;
	wchar_t *wide = widen(label);
	int32_t depth = (int32_t)ID3DUserDefinedAnnotation_BeginEvent(annotation, wide);
	free(wide);
	return depth;
}

int32_t d3dEndEvent(D3dContext context) {
	if (!annotationOf(context)) return -1;
	return (int32_t)ID3DUserDefinedAnnotation_EndEvent(annotation);
}

void d3dSetMarker(D3dContext context, const char *label) {
	if (!annotationOf(context)) return;
	wchar_t *wide = widen(label);
	ID3DUserDefinedAnnotation_SetMarker(annotation, wide);
	free(wide);
}

void d3dReleaseAnnotation(void) {
	if (annotation) ID3DUserDefinedAnnotation_Release(annotation);
	annotation = NULL;
}

static D3D11_QUERY_DESC queryDesc(int32_t kind) {
	D3D11_QUERY_DESC desc = {0};
	desc.Query = kind == 0 ? D3D11_QUERY_OCCLUSION : kind == 1 ? D3D11_QUERY_TIMESTAMP : D3D11_QUERY_TIMESTAMP_DISJOINT;
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

void d3dReleaseQuery(D3dQuery query) { if (query) ID3D11Query_Release((ID3D11Query *)query); }

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

uint64_t d3dTicksToNanoseconds(uint64_t ticks, uint64_t frequency) {
	return (ticks / frequency) * 1000000000ULL + (ticks % frequency) * 1000000000ULL / frequency;
}
