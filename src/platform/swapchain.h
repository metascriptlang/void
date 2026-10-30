#ifndef VOID_PLATFORM_SWAPCHAIN_H
#define VOID_PLATFORM_SWAPCHAIN_H

#include <stdint.h>

// The frame's screen target as the window owns it, read by the GPU door at beginScreenPass.
// The views are the backend's native objects (ID3D11RenderTargetView / DepthStencilView on
// D3D11); a missing one is NULL.
int32_t voidSwapchainWidth(void);
int32_t voidSwapchainHeight(void);
int32_t voidSwapchainSampleCount(void);
void *voidSwapchainRenderView(void);
void *voidSwapchainResolveView(void);
void *voidSwapchainDepthStencilView(void);

#endif
