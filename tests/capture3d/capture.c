// Scratch readback: copies the resolved D3D11 swapchain buffer to a PPM before Present.
#define COBJMACROS
#include <d3d11.h>
#include <dxgi.h>
#include <stdio.h>
#include <stdlib.h>
#include "capture.h"

const void *sg_d3d11_device(void);
const void *sg_d3d11_device_context(void);
const void *sapp_d3d11_get_swap_chain(void);

static const GUID TEXTURE2D_IID = {0x6f15aaf2, 0xd208, 0x4e89, {0x9a, 0xb4, 0x48, 0x95, 0x35, 0xd3, 0x4f, 0x9c}};

void captureSwapchain(int32_t frame) {
	IDXGISwapChain *swapChain = (IDXGISwapChain *)sapp_d3d11_get_swap_chain();
	ID3D11Device *device = (ID3D11Device *)sg_d3d11_device();
	ID3D11DeviceContext *context = (ID3D11DeviceContext *)sg_d3d11_device_context();
	ID3D11Texture2D *back = NULL;
	if (FAILED(IDXGISwapChain_GetBuffer(swapChain, 0, &TEXTURE2D_IID, (void **)&back))) { fprintf(stderr, "GetBuffer failed\n"); return; }
	D3D11_TEXTURE2D_DESC desc;
	ID3D11Texture2D_GetDesc(back, &desc);
	desc.Usage = D3D11_USAGE_STAGING;
	desc.BindFlags = 0;
	desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
	desc.MiscFlags = 0;
	ID3D11Texture2D *staging = NULL;
	ID3D11Device_CreateTexture2D(device, &desc, NULL, &staging);
	ID3D11DeviceContext_CopyResource(context, (ID3D11Resource *)staging, (ID3D11Resource *)back);
	D3D11_MAPPED_SUBRESOURCE mapped;
	ID3D11DeviceContext_Map(context, (ID3D11Resource *)staging, 0, D3D11_MAP_READ, 0, &mapped);
	const char *prefix = getenv("CAPTURE_PREFIX");
	char path[512];
	snprintf(path, sizeof(path), "%s_%d.ppm", prefix ? prefix : "out/tmp/capture/frame", frame);
	FILE *file = fopen(path, "wb");
	fprintf(file, "P6\n%u %u\n255\n", desc.Width, desc.Height);
	for (UINT y = 0; y < desc.Height; y++) {
		const uint8_t *row = (const uint8_t *)mapped.pData + y * mapped.RowPitch;
		for (UINT x = 0; x < desc.Width; x++) {
			uint8_t rgb[3] = {row[x * 4 + 2], row[x * 4 + 1], row[x * 4 + 0]};
			fwrite(rgb, 1, 3, file);
		}
	}
	fclose(file);
	ID3D11DeviceContext_Unmap(context, (ID3D11Resource *)staging, 0);
	ID3D11Texture2D_Release(staging);
	ID3D11Texture2D_Release(back);
	fprintf(stderr, "captured %s (%ux%u, format %d)\n", path, desc.Width, desc.Height, (int)desc.Format);
}

void captureQuit(void) { exit(0); }
