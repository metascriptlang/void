#import "VoidView.h"
#import "VoidEmbed.h"
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>

@interface VoidView ()
@property(nonatomic, strong) CADisplayLink *link;
@property(nonatomic, assign) BOOL started;
@end

@implementation VoidView

+ (Class)layerClass { return [CAMetalLayer class]; }

- (CAMetalLayer *)metalLayer { return (CAMetalLayer *)self.layer; }

// MsMain runs the whole MetaScript module-init graph; do it exactly once per
// process no matter how many VoidViews mount.
static void ensureMsMain(void) {
	static dispatch_once_t once;
	dispatch_once(&once, ^{ MsMain(); });
}

- (CGSize)drawablePx {
	CGFloat scale = self.contentScaleFactor > 0.0 ? self.contentScaleFactor : [UIScreen mainScreen].scale;
	int w = (int)(self.bounds.size.width * scale);
	int h = (int)(self.bounds.size.height * scale);
	return CGSizeMake(w < 1 ? 1 : w, h < 1 ? 1 : h);
}

- (void)didMoveToWindow {
	[super didMoveToWindow];
	if (self.window && !self.started) { [self startVoid]; }
}

- (void)startVoid {
	self.started = YES;
	ensureMsMain();

	CGSize px = [self drawablePx];
	CAMetalLayer *layer = [self metalLayer];
	layer.device = MTLCreateSystemDefaultDevice();
	layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
	layer.framebufferOnly = NO;
	layer.contentsScale = self.contentScaleFactor > 0.0 ? self.contentScaleFactor : [UIScreen mainScreen].scale;
	layer.drawableSize = px;

	voidEmbedInit((__bridge const void *)layer, (int)px.width, (int)px.height);

	self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
	[self.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)layoutSubviews {
	[super layoutSubviews];
	if (!self.started) return;
	CGSize px = [self drawablePx];
	[self metalLayer].drawableSize = px;
	voidEmbedResize((int)px.width, (int)px.height);
}

- (void)tick { voidEmbedFrame(); }

- (void)dealloc { [self.link invalidate]; }

@end
