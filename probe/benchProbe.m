// Stage-1 perf probe: measure the embed render-path cost (nextDrawable + encode +
// commit) with a heavy batched draw, through the SAME no-sokol_app swapchain path.
// Answers "what does kiểu-B cost per frame on the CPU side?"

#import <Cocoa/Cocoa.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#include <stdlib.h>

#define SOKOL_IMPL
#define SOKOL_METAL
#include "sokol_gfx.h"
#include "sokol_log.h"

#define QUADS 10000

static id<MTLDevice> g_device;
static CAMetalLayer*  g_layer;
static int   g_w = 640, g_h = 480;
static int   g_frames = 0;
static sg_pipeline g_pip;
static sg_buffer   g_vbuf;
static int   g_verts;
static double g_acc = 0.0, g_min = 1e9, g_max = 0.0;

static const char* k_vs =
    "#include <metal_stdlib>\n"
    "using namespace metal;\n"
    "struct vs_in  { float2 pos [[attribute(0)]]; float4 color [[attribute(1)]]; };\n"
    "struct vs_out { float4 pos [[position]]; float4 color; };\n"
    "vertex vs_out vs_main(vs_in in [[stage_in]]) {\n"
    "  vs_out o; o.pos = float4(in.pos, 0.0, 1.0); o.color = in.color; return o; }\n";
static const char* k_fs =
    "#include <metal_stdlib>\n"
    "using namespace metal;\n"
    "struct vs_out { float4 pos [[position]]; float4 color; };\n"
    "fragment float4 fs_main(vs_out in [[stage_in]]) { return in.color; }\n";

static float frnd(void) { return (float)rand() / (float)RAND_MAX; }

static void setup(void) {
    sg_desc d = {0};
    d.environment.metal.device = (__bridge const void*)g_device;
    d.logger.func = slog_func;
    sg_setup(&d);

    g_verts = QUADS * 6;
    float* v = (float*)malloc((size_t)g_verts * 6 * sizeof(float));
    int k = 0;
    for (int i = 0; i < QUADS; i++) {
        float cx = frnd() * 2.0f - 1.0f, cy = frnd() * 2.0f - 1.0f;
        float s = 0.02f;
        float r = frnd(), g = frnd(), b = frnd();
        float xs[6] = { cx-s, cx+s, cx+s, cx-s, cx+s, cx-s };
        float ys[6] = { cy-s, cy-s, cy+s, cy-s, cy+s, cy+s };
        for (int j = 0; j < 6; j++) {
            v[k++]=xs[j]; v[k++]=ys[j]; v[k++]=r; v[k++]=g; v[k++]=b; v[k++]=0.5f;
        }
    }
    sg_buffer_desc bd = {0};
    bd.usage.vertex_buffer = true;
    bd.data.ptr = v;
    bd.data.size = (size_t)g_verts * 6 * sizeof(float);
    g_vbuf = sg_make_buffer(&bd);
    free(v);

    sg_shader_desc sd = {0};
    sd.vertex_func.source = k_vs; sd.vertex_func.entry = "vs_main";
    sd.fragment_func.source = k_fs; sd.fragment_func.entry = "fs_main";
    sg_shader shd = sg_make_shader(&sd);

    sg_pipeline_desc pd = {0};
    pd.shader = shd;
    pd.primitive_type = SG_PRIMITIVETYPE_TRIANGLES;
    pd.depth.pixel_format = SG_PIXELFORMAT_NONE;
    pd.colors[0].blend.enabled = true;
    pd.colors[0].blend.src_factor_rgb = SG_BLENDFACTOR_SRC_ALPHA;
    pd.colors[0].blend.dst_factor_rgb = SG_BLENDFACTOR_ONE_MINUS_SRC_ALPHA;
    pd.layout.attrs[0].format = SG_VERTEXFORMAT_FLOAT2;
    pd.layout.attrs[1].format = SG_VERTEXFORMAT_FLOAT4;
    g_pip = sg_make_pipeline(&pd);
}

static void frame(void) {
    id<CAMetalDrawable> drawable = [g_layer nextDrawable];
    if (!drawable) return;

    double t0 = CACurrentMediaTime();

    sg_pass pass = {0};
    pass.action.colors[0].load_action = SG_LOADACTION_CLEAR;
    pass.action.colors[0].clear_value = (sg_color){ 0.08f, 0.09f, 0.12f, 1.0f };
    pass.swapchain.width = g_w; pass.swapchain.height = g_h;
    pass.swapchain.sample_count = 1;
    pass.swapchain.color_format = SG_PIXELFORMAT_BGRA8;
    pass.swapchain.depth_format = SG_PIXELFORMAT_NONE;
    pass.swapchain.metal.current_drawable = (__bridge const void*)drawable;

    sg_begin_pass(&pass);
    sg_apply_pipeline(g_pip);
    sg_bindings b = {0}; b.vertex_buffers[0] = g_vbuf;
    sg_apply_bindings(&b);
    sg_draw(0, g_verts, 1);
    sg_end_pass();
    sg_commit();

    double ms = (CACurrentMediaTime() - t0) * 1000.0;
    g_frames++;
    if (g_frames > 20) {  // warm-up
        g_acc += ms;
        if (ms < g_min) g_min = ms;
        if (ms > g_max) g_max = ms;
    }
    if (g_frames == 320) {
        int n = g_frames - 20;
        printf("BENCH quads=%d verts=%d  CPU-encode/frame: avg=%.3fms min=%.3fms max=%.3fms\n",
               QUADS, g_verts, g_acc / n, g_min, g_max);
        [NSApp terminate:nil];
    }
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        NSRect rect = NSMakeRect(0, 0, g_w, g_h);
        NSWindow* win = [[NSWindow alloc] initWithContentRect:rect
            styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        NSView* view = [win contentView];
        view.wantsLayer = YES;
        g_device = MTLCreateSystemDefaultDevice();
        g_layer = [CAMetalLayer layer];
        g_layer.device = g_device;
        g_layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        g_layer.framebufferOnly = YES;
        g_layer.frame = view.bounds;
        g_layer.drawableSize = CGSizeMake(g_w, g_h);
        [view setLayer:g_layer];
        [win makeKeyAndOrderFront:nil];
        setup();
        [NSTimer scheduledTimerWithTimeInterval:0.0 repeats:YES
            block:^(NSTimer* t){ (void)t; frame(); }];
        [NSApp run];
    }
    return 0;
}
