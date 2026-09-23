#import "VoidView.h"
#import "VoidEmbed.h"
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>

@interface VoidView ()
@property(nonatomic, strong) CADisplayLink *link;
@property(nonatomic, assign) BOOL started;
@property(nonatomic, assign) VoidViewId viewId;
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

- (CGFloat)pixelScale {
	return self.contentScaleFactor > 0.0 ? self.contentScaleFactor : [UIScreen mainScreen].scale;
}

- (CGSize)drawablePx {
	CGFloat scale = [self pixelScale];
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
	layer.framebufferOnly = NO;
	layer.contentsScale = [self pixelScale];

	self.viewId = voidViewCreate((long long)(intptr_t)(__bridge void *)layer, (int)px.width, (int)px.height, (float)[self pixelScale]);

	self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
	[self.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)layoutSubviews {
	[super layoutSubviews];
	if (!self.started) return;
	CGSize px = [self drawablePx];
	voidViewResize(self.viewId, (int)px.width, (int)px.height, (float)[self pixelScale]);
}

- (void)tick { voidViewFrame(self.viewId); }

- (void)dealloc {
	[self.link invalidate];
	if (self.viewId != 0) voidViewDestroy(self.viewId);
}

@end
