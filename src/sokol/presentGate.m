#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>

#include <stdatomic.h>

#include "presentGate.h"

static const NSUInteger VOID_DRAWABLE_COUNT = 3;

@interface VoidPresentGate : NSObject {
@public
	atomic_int pending;
	int cap;
}
@end

@implementation VoidPresentGate
@end

void *voidPresentGateCreate(void *metalLayer) {
	CAMetalLayer *layer = (__bridge CAMetalLayer *)metalLayer;
	// A composited window keeps about three frames between acquire and display at 120 Hz:
	// two drawables or an admission cap of two dropped to 40-80 fps (M1, 2026-10-22).
	layer.maximumDrawableCount = VOID_DRAWABLE_COUNT;
	VoidPresentGate *gate = [VoidPresentGate new];
	atomic_init(&gate->pending, 0);
	gate->cap = (int)layer.maximumDrawableCount;
	return (void *)CFBridgingRetain(gate);
}

void voidPresentGateRelease(void *gate) {
	if (gate) CFRelease(gate);
}

int voidPresentGateAdmits(void *gate) {
	VoidPresentGate *g = (__bridge VoidPresentGate *)gate;
	return atomic_load(&g->pending) < g->cap;
}

void voidPresentGateTrack(void *gate, void *drawable) {
	VoidPresentGate *g = (__bridge VoidPresentGate *)gate;
	atomic_fetch_add(&g->pending, 1);
	[(__bridge id<MTLDrawable>)drawable addPresentedHandler:^(id<MTLDrawable> shown) {
		(void)shown;
		atomic_fetch_sub(&g->pending, 1);
	}];
}
