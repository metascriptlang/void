// Stage-1 POC: sokol_gfx renders into a host-provided CAMetalLayer with NO sokol_app.
// This is the make-or-break premise for embedding Void as a <VoidView> inside
// React Native (kiểu B). We provide the Metal device + per-frame drawable ourselves;
// sokol_gfx draws into them and presents on sg_commit. If a window shows the
// animated clear color + triangle, the embedding path is proven.

#import <Cocoa/Cocoa.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#include <math.h>

#define SOKOL_IMPL
#define SOKOL_METAL
#include "sokol_gfx.h"
#include "sokol_log.h"

static id<MTLDevice> g_device;
static CAMetalLayer*  g_layer;
static int   g_w = 640, g_h = 480;
static int   g_frames = 0;
static float g_t = 0.0f;
static sg_pipeline g_pip;
static sg_buffer   g_vbuf;

static const char* k_vs =
    "#include <metal_stdlib>\n"
    "using namespace metal;\n"
    "struct vs_in  { float2 pos [[attribute(0)]]; float4 color [[attribute(1)]]; };\n"
    "struct vs_out { float4 pos [[position]]; float4 color; };\n"
    "vertex vs_out vs_main(vs_in in [[stage_in]]) {\n"
    "  vs_out o;\n"
    "  o.pos = float4(in.pos, 0.0, 1.0);\n"
    "  o.color = in.color;\n"
    "  return o;\n"
    "}\n";

static const char* k_fs =
    "#include <metal_stdlib>\n"
    "using namespace metal;\n"
    "struct vs_out { float4 pos [[position]]; float4 color; };\n"
    "fragment float4 fs_main(vs_out in [[stage_in]]) { return in.color; }\n";

static void setup(void) {
    sg_desc d = {0};
    d.environment.metal.device = (__bridge const void*)g_device;
    d.logger.func = slog_func;
    sg_setup(&d);

    float verts[] = {
        // x, y,    r, g, b, a
         0.0f,  0.6f,  1.0f, 0.2f, 0.2f, 1.0f,
        -0.6f, -0.6f,  0.2f, 1.0f, 0.2f, 1.0f,
         0.6f, -0.6f,  0.2f, 0.2f, 1.0f, 1.0f,
    };
    sg_buffer_desc bd = {0};
    bd.usage.vertex_buffer = true;
    bd.data.ptr = verts;
    bd.data.size = sizeof(verts);
    g_vbuf = sg_make_buffer(&bd);

    sg_shader_desc sd = {0};
    sd.vertex_func.source   = k_vs;
    sd.vertex_func.entry    = "vs_main";
    sd.fragment_func.source = k_fs;
    sd.fragment_func.entry  = "fs_main";
    sg_shader shd = sg_make_shader(&sd);

    sg_pipeline_desc pd = {0};
    pd.shader = shd;
    pd.primitive_type = SG_PRIMITIVETYPE_TRIANGLES;
    pd.depth.pixel_format = SG_PIXELFORMAT_NONE;
    pd.layout.attrs[0].format = SG_VERTEXFORMAT_FLOAT2;
    pd.layout.attrs[1].format = SG_VERTEXFORMAT_FLOAT4;
    g_pip = sg_make_pipeline(&pd);
}

// Read the just-rendered drawable back to CPU and dump a PPM — deterministic
// proof the swapchain path produced pixels, independent of window stacking.
static void capture(id<CAMetalDrawable> drawable) {
    id<MTLTexture> tex = drawable.texture;
    NSUInteger w = tex.width, h = tex.height;
    MTLTextureDescriptor* desc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
        width:w height:h mipmapped:NO];
    desc.storageMode = MTLStorageModeManaged;
    desc.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> staging = [g_device newTextureWithDescriptor:desc];

    id<MTLCommandQueue> q = [g_device newCommandQueue];
    id<MTLCommandBuffer> cb = [q commandBuffer];
    id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
    [blit copyFromTexture:tex sourceSlice:0 sourceLevel:0
        sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(w,h,1)
        toTexture:staging destinationSlice:0 destinationLevel:0
        destinationOrigin:MTLOriginMake(0,0,0)];
    [blit synchronizeResource:staging];
    [blit endEncoding];
    [cb commit];
    [cb waitUntilCompleted];

    NSUInteger rowBytes = w * 4;
    uint8_t* buf = (uint8_t*)malloc(rowBytes * h);
    [staging getBytes:buf bytesPerRow:rowBytes
        fromRegion:MTLRegionMake2D(0,0,w,h) mipmapLevel:0];

    FILE* f = fopen("/tmp/embedProbe.ppm", "wb");
    fprintf(f, "P6\n%lu %lu\n255\n", (unsigned long)w, (unsigned long)h);
    for (NSUInteger i = 0; i < w*h; i++) {
        uint8_t b = buf[i*4+0], g = buf[i*4+1], r = buf[i*4+2];
        fputc(r, f); fputc(g, f); fputc(b, f);
    }
    fclose(f);
    free(buf);
    NSLog(@"capture: wrote /tmp/embedProbe.ppm %lux%lu", (unsigned long)w, (unsigned long)h);
}

static void frame(void) {
    id<CAMetalDrawable> drawable = [g_layer nextDrawable];
    if (!drawable) return;

    g_t += 1.0f / 60.0f;
    float r = 0.10f + 0.10f * sinf(g_t * 2.0f);

    sg_pass pass = {0};
    pass.action.colors[0].load_action = SG_LOADACTION_CLEAR;
    pass.action.colors[0].clear_value = (sg_color){ r, 0.12f, 0.18f, 1.0f };
    pass.swapchain.width = g_w;
    pass.swapchain.height = g_h;
    pass.swapchain.sample_count = 1;
    pass.swapchain.color_format = SG_PIXELFORMAT_BGRA8;
    pass.swapchain.depth_format = SG_PIXELFORMAT_NONE;
    pass.swapchain.metal.current_drawable = (__bridge const void*)drawable;

    sg_begin_pass(&pass);
    sg_apply_pipeline(g_pip);
    sg_bindings b = {0};
    b.vertex_buffers[0] = g_vbuf;
    sg_apply_bindings(&b);
    sg_draw(0, 3, 1);
    sg_end_pass();
    sg_commit();

    g_frames++;
    if (g_frames == 5) { capture(drawable); [NSApp terminate:nil]; }
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

        NSRect rect = NSMakeRect(0, 0, g_w, g_h);
        NSWindow* win = [[NSWindow alloc] initWithContentRect:rect
            styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
            backing:NSBackingStoreBuffered defer:NO];
        [win setTitle:@"Void embed probe — sokol_gfx, NO sokol_app"];

        NSView* view = [win contentView];
        view.wantsLayer = YES;

        g_device = MTLCreateSystemDefaultDevice();
        g_layer = [CAMetalLayer layer];
        g_layer.device = g_device;
        g_layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        g_layer.framebufferOnly = NO;
        g_layer.frame = view.bounds;
        g_layer.drawableSize = CGSizeMake(g_w, g_h);
        [view setLayer:g_layer];

        [win center];
        [win makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];

        setup();

        [NSTimer scheduledTimerWithTimeInterval:1.0/60.0
            repeats:YES
            block:^(NSTimer* t){ (void)t; frame(); }];

        [NSApp run];
    }
    return 0;
}
