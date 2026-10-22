#pragma once
#include <stdint.h>

typedef struct D3dDeviceImpl *D3dDevice;
typedef struct D3dContextImpl *D3dContext;
typedef struct D3dBufferImpl *D3dBuffer;
typedef struct D3dTextureImpl *D3dTexture;
typedef struct D3dSrvImpl *D3dSrv;
typedef struct D3dRtvImpl *D3dRtv;
typedef struct D3dDsvImpl *D3dDsv;
typedef struct D3dSamplerImpl *D3dSampler;
typedef struct D3dBlobImpl *D3dBlob;
typedef struct D3dVertexShaderImpl *D3dVertexShader;
typedef struct D3dPixelShaderImpl *D3dPixelShader;
typedef struct D3dInputLayoutImpl *D3dInputLayout;
typedef struct D3dRasterizerStateImpl *D3dRasterizerState;
typedef struct D3dDepthStencilStateImpl *D3dDepthStencilState;
typedef struct D3dBlendStateImpl *D3dBlendState;

D3dDevice d3dDeviceFrom(void *native);
D3dContext d3dContextFrom(void *native);
D3dRtv d3dRtvFrom(void *native);
D3dDsv d3dDsvFrom(void *native);
void *d3dTextureNative(D3dTexture texture);

D3dBuffer d3dCreateBuffer(D3dDevice device, int64_t bytes, int32_t usage, int32_t bindFlags, int32_t cpuAccess);
void d3dReleaseBuffer(D3dBuffer buffer);
int32_t d3dMapWrite(D3dContext context, D3dBuffer buffer, int32_t mapType, int64_t offset, void *data, int64_t bytes);
int32_t d3dUpdateIfChanged(D3dContext context, D3dBuffer buffer, uint8_t *cache, int64_t cacheOffset, uint8_t *data, int64_t dataOffset, int64_t bytes, int32_t force);
int32_t d3dUniformOffsetting(D3dDevice device, D3dContext context);
void d3dReleaseUniformOffsetting(void);
void d3dVsSetConstantBufferRange(int32_t slot, D3dBuffer buffer, int64_t firstConstant, int64_t numConstants);
void d3dPsSetConstantBufferRange(int32_t slot, D3dBuffer buffer, int64_t firstConstant, int64_t numConstants);
void d3dCopyBytes(void *destination, int64_t destinationOffset, void *source, int64_t bytes);

D3dTexture d3dCreateTexture2D(
	D3dDevice device,
	int32_t width,
	int32_t height,
	int32_t format,
	int32_t usage,
	int32_t bindFlags,
	int32_t cpuAccess,
	int32_t sampleCount);
void d3dReleaseTexture(D3dTexture texture);
void d3dUpdateTexture(
	D3dContext context,
	D3dTexture texture,
	void *data,
	int64_t offset,
	int32_t sourceRowPitch,
	int32_t x,
	int32_t y,
	int32_t width,
	int32_t height);
D3dSrv d3dCreateSrv(D3dDevice device, D3dTexture texture, int32_t format, int32_t multisampled);
D3dRtv d3dCreateRtv(D3dDevice device, D3dTexture texture, int32_t format, int32_t multisampled);
D3dDsv d3dCreateDsv(D3dDevice device, D3dTexture texture, int32_t format, int32_t multisampled);
void d3dReleaseSrv(D3dSrv view);
void d3dReleaseRtv(D3dRtv view);
void d3dReleaseDsv(D3dDsv view);
void d3dResolveSubresource(D3dContext context, D3dTexture destination, D3dTexture source, int32_t format);
void d3dResolveViews(D3dContext context, D3dRtv destination, D3dRtv source, int32_t format);

D3dSampler d3dCreateSampler(D3dDevice device, int32_t filter, int32_t addressU, int32_t addressV, int32_t addressW);
void d3dReleaseSampler(D3dSampler sampler);

D3dBlob d3dCompile(const char *source, const char *entryPoint, const char *target);
const char *d3dCompileLog(void);
void d3dReleaseBlob(D3dBlob blob);
D3dVertexShader d3dCreateVertexShader(D3dDevice device, D3dBlob blob);
D3dPixelShader d3dCreatePixelShader(D3dDevice device, D3dBlob blob);
void d3dReleaseVertexShader(D3dVertexShader shader);
void d3dReleasePixelShader(D3dPixelShader shader);

void d3dInputElement(
	int32_t index,
	int32_t semanticIndex,
	int32_t format,
	int32_t slot,
	int32_t offset,
	int32_t perInstance);
D3dInputLayout d3dCreateInputLayout(D3dDevice device, int32_t count, D3dBlob vertexBlob);
void d3dReleaseInputLayout(D3dInputLayout layout);
D3dRasterizerState d3dCreateRasterizerState(D3dDevice device, int32_t cullMode, int32_t frontCounterClockwise, int32_t multisample);
void d3dReleaseRasterizerState(D3dRasterizerState state);
D3dDepthStencilState d3dCreateDepthStencilState(D3dDevice device, int32_t depthWrite, int32_t compare);
void d3dReleaseDepthStencilState(D3dDepthStencilState state);
void d3dBlendTarget(
	int32_t index,
	int32_t enabled,
	int32_t sourceColor,
	int32_t destinationColor,
	int32_t operationColor,
	int32_t sourceAlpha,
	int32_t destinationAlpha,
	int32_t operationAlpha,
	int32_t writeMask);
D3dBlendState d3dCreateBlendState(D3dDevice device);
void d3dReleaseBlendState(D3dBlendState state);

void d3dSetRenderTargets(D3dContext context, D3dRtv color0, D3dRtv color1, D3dRtv color2, D3dRtv color3, D3dDsv depth);
void d3dSetViewport(D3dContext context, int32_t width, int32_t height);
void d3dSetScissorRect(D3dContext context, int32_t left, int32_t top, int32_t right, int32_t bottom);
void d3dClearRtv(D3dContext context, D3dRtv view, double r, double g, double b, double a);
void d3dClearDsv(D3dContext context, D3dDsv view, int32_t flags, double depth, int32_t stencil);
void d3dClearState(D3dContext context);

void d3dRsSetState(D3dContext context, D3dRasterizerState state);
void d3dOmSetDepthStencilState(D3dContext context, D3dDepthStencilState state);
void d3dOmSetBlendState(D3dContext context, D3dBlendState state);
void d3dIaSetPrimitiveTopology(D3dContext context, int32_t topology);
void d3dIaSetInputLayout(D3dContext context, D3dInputLayout layout);
void d3dVsSetShader(D3dContext context, D3dVertexShader shader);
void d3dPsSetShader(D3dContext context, D3dPixelShader shader);
void d3dVsSetConstantBuffer(D3dContext context, int32_t slot, D3dBuffer buffer);
void d3dPsSetConstantBuffer(D3dContext context, int32_t slot, D3dBuffer buffer);
void d3dIaSetVertexBuffer(D3dContext context, int32_t slot, D3dBuffer buffer, int32_t stride, int32_t offset);
void d3dIaSetIndexBuffer(D3dContext context, D3dBuffer buffer, int32_t format, int32_t offset);
void d3dVsSetShaderResource(D3dContext context, int32_t slot, D3dSrv view);
void d3dPsSetShaderResource(D3dContext context, int32_t slot, D3dSrv view);
void d3dVsSetSampler(D3dContext context, int32_t slot, D3dSampler sampler);
void d3dPsSetSampler(D3dContext context, int32_t slot, D3dSampler sampler);

void d3dDraw(D3dContext context, int32_t vertexCount, int32_t firstVertex);
void d3dDrawInstanced(D3dContext context, int32_t vertexCount, int32_t instanceCount, int32_t firstVertex, int32_t firstInstance);
void d3dDrawIndexed(D3dContext context, int32_t indexCount, int32_t firstIndex, int32_t baseVertex);
void d3dDrawIndexedInstanced(
	D3dContext context,
	int32_t indexCount,
	int32_t instanceCount,
	int32_t firstIndex,
	int32_t baseVertex,
	int32_t firstInstance);
