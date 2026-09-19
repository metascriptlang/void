// How the low-res image maps onto the framebuffer: the integer scale, the low-res target size
// and the offset the blit shader adds before dividing by the scale (shader3d.glsl blitFs:
// texel = floor((fragment + offset) / scale)). Pure arithmetic, so it is tested headless.
//
// The offset has two parts. Centering: the target covers the framebuffer rounded up to whole
// texels (plus the margin), and the overhang is split between both sides. Sub-pixel: the
// camera renders from a position snapped to the texel grid (M4), and the remainder of that
// snap moves the image by a fraction of a texel, which at 3x is whole framebuffer pixels.

export struct LowResView {
	// Low-res target size, margin included.
	width: int32;
	height: int32;
	// Framebuffer pixels per low-res texel.
	scale: int32;
	// Framebuffer pixels added to a fragment's position before dividing by the scale, in the
	// framebuffer's own row order (see withRemainder).
	offsetX: float32;
	offsetY: float32;
}

// A point in either of the two grids the blit maps between — framebuffer pixels and low-res
// texels — continuous, and in the framebuffer's row order.
export struct ViewPoint {
	x: float32;
	y: float32;
}

export enum ViewError {
	EmptyFramebuffer,
	BadShortSide,
	BadDivisor,
	BadMargin,
}

// `shortSide` texels across the framebuffer's short side at full fidelity (Hibernal: 360, so
// 1080x2400 is 360x800 at 3x); `divisor` shrinks it (the preview uses 2); `margin` texels are
// added on every side so a sub-pixel shift never samples past the edge.
export function lowResView(
	framebufferWidth: int32,
	framebufferHeight: int32,
	shortSide: int32,
	divisor: int32,
	margin: int32,
): Result<LowResView, ViewError> {
	if (framebufferWidth <= 0 || framebufferHeight <= 0) {
		return Result.err(ViewError.EmptyFramebuffer);
	}
	if (shortSide <= 0) { return Result.err(ViewError.BadShortSide); }
	if (divisor <= 0) { return Result.err(ViewError.BadDivisor); }
	if (margin < 0) { return Result.err(ViewError.BadMargin); }
	const framebufferShort: int32 = Math.min(framebufferWidth, framebufferHeight) as int32;
	const scale: int32 = (Math.max(1, framebufferShort / shortSide) as int32) * divisor;
	const coveredWidth: int32 = (framebufferWidth + scale - 1) / scale;
	const coveredHeight: int32 = (framebufferHeight + scale - 1) / scale;
	const overhangX: int32 = coveredWidth * scale - framebufferWidth;
	const overhangY: int32 = coveredHeight * scale - framebufferHeight;
	return Result.ok({
		width: coveredWidth + 2 * margin,
		height: coveredHeight + 2 * margin,
		scale: scale,
		offsetX: (overhangX / 2 + margin * scale) as float32,
		offsetY: (overhangY / 2 + margin * scale) as float32,
	});
}

// Applies the camera's snap remainder: the true camera position minus the snapped one, in
// low-res texels along the camera's right and up axes, each in [0, 1). The image then shows
// the scene as seen from the true position, so it moves opposite to the remainder: a fragment
// samples `remainder` texels further right and up. Up is -y in top-left framebuffers (D3D11,
// Metal) and +y in GL's bottom-left ones, so the caller says which (gpu3d originTopLeft).
export function withRemainder(
	this view: LowResView,
	remainderX: float32,
	remainderY: float32,
	originTopLeft: boolean,
): LowResView {
	const scale: float32 = view.scale as float32;
	const up: float32 = originTopLeft ? -remainderY * scale : remainderY * scale;
	return { ...view, offsetX: view.offsetX + remainderX * scale, offsetY: view.offsetY + up };
}

// The blit shader's own mapping, minus its floor: `texel = floor((fragment + offset) / scale)`
// without the floor is where inside the low-res image a framebuffer point reads from, and
// `framebufferAt` is that read the other way round. The camera goes through both — screen to
// world and back (camera.ms `rayFromScreen`, `project`) — so the formula is written once here
// and never restated against the shader.
export function texelAt(
	this view: LowResView,
	framebufferX: float32,
	framebufferY: float32,
): ViewPoint {
	const scale: float32 = view.scale as float32;
	const x: float32 = (framebufferX + view.offsetX) / scale;
	const y: float32 = (framebufferY + view.offsetY) / scale;
	return { x: x, y: y };
}

export function framebufferAt(this view: LowResView, texelX: float32, texelY: float32): ViewPoint {
	const scale: float32 = view.scale as float32;
	const x: float32 = texelX * scale - view.offsetX;
	const y: float32 = texelY * scale - view.offsetY;
	return { x: x, y: y };
}

// The blit shader's `pixel` uniform: scale twice, then the offset.
export function writeBlitParams(this view: LowResView, out: Span<float32>): void {
	out[0] = view.scale as float32;
	out[1] = view.scale as float32;
	out[2] = view.offsetX;
	out[3] = view.offsetY;
}

// Same target size and mapping: the frame needs no new targets and the same blit.
export function sameAs(this view: LowResView, other: LowResView): boolean {
	return view.width == other.width &&
		view.height == other.height &&
		view.scale == other.scale &&
		view.offsetX == other.offsetX &&
		view.offsetY == other.offsetY;
}
