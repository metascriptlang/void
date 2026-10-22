#pragma once
#include <stdint.h>

int32_t oglLoad(void);
const char *oglLoadMissing(void);
void oglUnload(void);
int32_t oglGetInteger(int32_t name);
int32_t oglGetError(void);
void oglEnable(int32_t capability);
void oglDisable(int32_t capability);
void oglPixelStore(int32_t name, int32_t value);
void *oglTextureNative(uint32_t texture);
void oglCopyBytes(void *destination, int64_t destinationOffset, void *source, int64_t bytes);

uint32_t oglCreateVertexArray(void);
void oglBindVertexArray(uint32_t vertexArray);
void oglDeleteVertexArray(uint32_t vertexArray);

uint32_t oglCreateBuffer(void);
void oglBindBuffer(int32_t target, uint32_t buffer);
void oglBufferData(int32_t target, int64_t bytes, int32_t usage);
void oglBufferSubData(int32_t target, int64_t offset, void *data, int64_t bytes);
void oglDeleteBuffer(uint32_t buffer);
void oglCopyBufferData(uint32_t source, int64_t sourceOffset, uint32_t destination, int64_t destinationOffset, int64_t bytes);
int32_t oglGetBufferData(uint32_t buffer, int64_t offset, void *destination, int64_t bytes);

uint32_t oglCreateTexture(void);
void oglActiveTexture(int32_t unit);
void oglBindTexture(int32_t target, uint32_t texture);
void oglTexStorage(int32_t target, int32_t levels, int32_t internalFormat, int32_t width, int32_t height, int32_t depth);
void oglTexParameteri(int32_t target, int32_t name, int32_t value);
void oglTexStorage2DMultisample(int32_t target, int32_t samples, int32_t internalFormat, int32_t width, int32_t height);
uint32_t oglCreateRenderbuffer(int32_t samples, int32_t internalFormat, int32_t width, int32_t height);
void oglDeleteRenderbuffer(uint32_t renderbuffer);
void oglFramebufferRenderbuffer(int32_t attachment, uint32_t renderbuffer);
void oglTexSubImage(
	int32_t target,
	int32_t level,
	int32_t x,
	int32_t y,
	int32_t z,
	int32_t width,
	int32_t height,
	int32_t depth,
	int32_t format,
	int32_t type,
	void *data,
	int64_t offset,
	int32_t rowLength,
	int32_t imageHeight);
void oglTexSubImageFromBuffer(
	int32_t target,
	int32_t level,
	int32_t x,
	int32_t y,
	int32_t z,
	int32_t width,
	int32_t height,
	int32_t depth,
	int32_t format,
	int32_t type,
	uint32_t buffer,
	int64_t offset,
	int32_t rowLength,
	int32_t imageHeight);
int32_t oglReadTexelsToBuffer(
	uint32_t texture,
	int32_t target,
	int32_t level,
	int32_t layer,
	int32_t x,
	int32_t y,
	int32_t width,
	int32_t height,
	int32_t format,
	int32_t type,
	int32_t rowLength,
	uint32_t buffer,
	int64_t offset);
int32_t oglReadScreenRow(int32_t x, int32_t y, int32_t width, int32_t format, int32_t type, uint32_t buffer, int64_t offset);
int32_t oglCopyTexels(
	uint32_t source,
	int32_t sourceTarget,
	int32_t sourceLevel,
	int32_t sourceLayer,
	int32_t sourceX,
	int32_t sourceY,
	int32_t destinationTarget,
	int32_t destinationLevel,
	int32_t destinationX,
	int32_t destinationY,
	int32_t destinationLayer,
	int32_t width,
	int32_t height,
	int32_t count);
void oglDeleteTexture(uint32_t texture);

uint32_t oglCreateSampler(void);
void oglSamplerParameteri(uint32_t sampler, int32_t name, int32_t value);
void oglSamplerParameterf(uint32_t sampler, int32_t name, double value);
void oglSamplerBorderColor(uint32_t sampler, double r, double g, double b, double a);
void oglBindSampler(int32_t unit, uint32_t sampler);
void oglDeleteSampler(uint32_t sampler);

uint32_t oglCompileShader(int32_t stage, const char *source);
uint32_t oglLinkProgram(uint32_t vertexShader, uint32_t fragmentShader);
const char *oglLog(void);
void oglDeleteProgram(uint32_t program);
void oglUseProgram(uint32_t program);
int32_t oglUniformLocation(uint32_t program, const char *name);
int32_t oglAttribLocation(uint32_t program, const char *name);
void oglUniform1i(int32_t location, int32_t value);
void oglUniform4fv(int32_t location, int32_t count, void *data, int64_t offset);

void oglDepthFunc(int32_t compare);
void oglDepthMask(int32_t write);
void oglStencilMask(int32_t mask);
void oglStencilFunc(int32_t compare, int32_t reference, int32_t mask);
void oglStencilOp(int32_t fail, int32_t depthFail, int32_t pass);
void oglStencilFuncSeparate(int32_t face, int32_t compare, int32_t reference, int32_t mask);
void oglStencilOpSeparate(int32_t face, int32_t fail, int32_t depthFail, int32_t pass);
void oglDepthRange(double nearDepth, double farDepth);
void oglBlendFuncSeparate(int32_t sourceColor, int32_t destinationColor, int32_t sourceAlpha, int32_t destinationAlpha);
void oglBlendEquationSeparate(int32_t color, int32_t alpha);
void oglEnablei(int32_t capability, int32_t index);
void oglDisablei(int32_t capability, int32_t index);
void oglBlendFuncSeparatei(int32_t index, int32_t sourceColor, int32_t destinationColor, int32_t sourceAlpha, int32_t destinationAlpha);
void oglBlendEquationSeparatei(int32_t index, int32_t color, int32_t alpha);
void oglBlendColor(double r, double g, double b, double a);
void oglColorMask(int32_t mask);
void oglColorMaski(int32_t index, int32_t mask);
void oglPolygonOffset(double factor, double units);
void oglCullFace(int32_t face);
void oglFrontFace(int32_t winding);
void oglViewport(int32_t x, int32_t y, int32_t width, int32_t height);
void oglScissor(int32_t x, int32_t y, int32_t width, int32_t height);

uint32_t oglCreateFramebuffer(void);
void oglBindFramebuffer(int32_t target, uint32_t framebuffer);
void oglDeleteFramebuffer(uint32_t framebuffer);
void oglFramebufferTexture2D(int32_t attachment, int32_t textureTarget, uint32_t texture, int32_t level);
void oglFramebufferTextureLayer(int32_t attachment, uint32_t texture, int32_t level, int32_t layer);
void oglFramebufferDetach(int32_t attachment);
int32_t oglCheckFramebufferStatus(void);
void oglDrawBuffers(int32_t count, int32_t colorMask);
void oglReadBuffer(int32_t attachment);
void oglBlitColor(int32_t width, int32_t height);
void oglClearColor(int32_t attachment, double r, double g, double b, double a);
void oglClearDepth(double depth);
void oglClearDepthStencil(double depth, int32_t stencil);

void oglVertexAttribPointer(int32_t index, int32_t size, int32_t type, int32_t normalized, int32_t stride, int64_t offset);
void oglVertexAttribIPointer(int32_t index, int32_t size, int32_t type, int32_t stride, int64_t offset);
void oglVertexAttribDivisor(int32_t index, int32_t divisor);
void oglEnableVertexAttribArray(int32_t index);
void oglDisableVertexAttribArray(int32_t index);

void oglDrawArrays(int32_t mode, int32_t first, int32_t count);
void oglDrawArraysInstanced(int32_t mode, int32_t first, int32_t count, int32_t instances);
void oglDrawArraysInstancedBaseInstance(int32_t mode, int32_t first, int32_t count, int32_t instances, int32_t baseInstance);
void oglDrawElements(int32_t mode, int32_t count, int32_t type, int64_t offset);
void oglDrawElementsBaseVertex(int32_t mode, int32_t count, int32_t type, int64_t offset, int32_t baseVertex);
void oglDrawElementsInstanced(int32_t mode, int32_t count, int32_t type, int64_t offset, int32_t instances);
void oglDrawElementsInstancedBaseVertex(int32_t mode, int32_t count, int32_t type, int64_t offset, int32_t instances, int32_t baseVertex);
void oglDrawElementsInstancedBaseVertexBaseInstance(
	int32_t mode,
	int32_t count,
	int32_t type,
	int64_t offset,
	int32_t instances,
	int32_t baseVertex,
	int32_t baseInstance);

int32_t oglCapabilities(void);
int64_t oglGetInteger64(int32_t name);
int32_t oglHasExtension(const char *name);
int32_t oglGetIntegeri(int32_t name, int32_t index);
uint32_t oglLinkComputeProgram(uint32_t computeShader);
void oglDispatchCompute(int32_t x, int32_t y, int32_t z);
void oglDispatchComputeIndirect(uint32_t buffer, int64_t offset);
void oglMemoryBarrier(int32_t barriers);
void oglBindBufferRange(int32_t target, uint32_t index, uint32_t buffer, int64_t offset, int64_t bytes);
void oglBindImageTexture(int32_t unit, uint32_t texture, int32_t level, int32_t layered, int32_t layer, int32_t access, int32_t format);

uint32_t oglCreateQuery(void);
void oglDeleteQuery(uint32_t query);
void oglBeginQuery(int32_t target, uint32_t query);
void oglEndQuery(int32_t target);
int32_t oglQueryAvailable(uint32_t query);
uint64_t oglQueryResult(uint32_t query);
void oglQueryCounter(uint32_t query);
int32_t oglQueryCounterBits(void);

void oglPushDebugGroup(const char *label);
void oglPopDebugGroup(void);
void oglDebugMarker(const char *label);
void oglObjectLabel(int32_t identifier, uint32_t name, const char *label);
