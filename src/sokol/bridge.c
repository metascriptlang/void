// Void sokol bridge — thin C wrappers over sokol_gfx, shared by every driver. The driver
// (bridgeWin.c, bridgeIos.m, bridgeAndroid.c) owns the sokol implementation unit, the
// device and the swapchain.

#include "bridge.h"
#include "views.h"

#include <stdio.h>
#include <stdlib.h>

// --- Resource creation (sokol handle .id ↔ uint32) ---

uint32_t voidMakeImage(const void *rgba, int w, int h) {
	static const uint8_t white[4] = {255, 255, 255, 255};
	if (rgba == NULL || w <= 0 || h <= 0) { rgba = white; w = 1; h = 1; }
	sg_image_desc d = {0};
	d.width = w;
	d.height = h;
	d.pixel_format = SG_PIXELFORMAT_RGBA8;
	d.data.mip_levels[0].ptr = rgba;
	d.data.mip_levels[0].size = (size_t)(w * h * 4);
	return sg_make_image(&d).id;
}

uint32_t voidMakeView(uint32_t image) {
	sg_view_desc d = {0};
	d.texture.image = (sg_image){.id = image};
	return sg_make_view(&d).id;
}

// --- Frame sequence ---

static void stopOnSwapchainOutsideEnvironment(const sg_swapchain *swapchain) {
	const sg_environment_defaults environment = sg_query_desc().environment.defaults;
	const sg_pixel_format color = swapchain->color_format != _SG_PIXELFORMAT_DEFAULT
		? swapchain->color_format : environment.color_format;
	const sg_pixel_format depth = swapchain->depth_format != _SG_PIXELFORMAT_DEFAULT
		? swapchain->depth_format : environment.depth_format;
	const int samples = swapchain->sample_count != 0
		? swapchain->sample_count : environment.sample_count;
	if (color == environment.color_format && depth == environment.depth_format
		&& samples == environment.sample_count) {
		return;
	}
	fprintf(stderr, "void: the swapchain is color format %d, depth format %d, %d samples, but "
		"screen pipelines are made for the environment's color format %d, depth format %d, "
		"%d samples (sokol pixel formats)\n", (int)color, (int)depth, samples,
		(int)environment.color_format, (int)environment.depth_format, environment.sample_count);
	abort();
}

void voidBeginPass(float r, float g, float b, float a) {
	sg_pass pass = {0};
	pass.action.colors[0].load_action = SG_LOADACTION_CLEAR;
	pass.action.colors[0].clear_value = (sg_color){r, g, b, a};
	pass.action.depth.load_action = SG_LOADACTION_CLEAR;
	pass.action.depth.clear_value = 1.0f;
	pass.swapchain = voidDriverSwapchain();
	stopOnSwapchainOutsideEnvironment(&pass.swapchain);
	sg_begin_pass(&pass);
}

void voidEndPass(void) { sg_end_pass(); }
static void (*s_commitHook)(void);
void voidSetCommitHook(void (*fn)(void)) { s_commitHook = fn; }
void voidCommit(void) {
	sg_commit();
	if (s_commitHook) { s_commitHook(); }
	voidDriverPresent();
}
