import {
	AtlasError,
	GlyphAtlas,
	GlyphKey,
	GlyphTile,
	NO_GLYPH_PAGE_HANDLE,
	PageKind,
	maskKey,
} from "../void2d/glyphAtlas";
import {
	IconId,
	ICON_SUPERSAMPLE,
	acquireIconMask,
	iconRasterizations,
	iconHeight,
	iconWidth,
	maskSide,
	registerIcon,
} from "../void2d/icon";
import { SvgMaskError } from "../void2d/svgMask";
import { void2dGlyphPageTexel } from "../void2d/glyph.h";

const SQUARE: string = `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" ` +
	`viewBox="0 0 24 24"><rect x="0" y="0" width="24" height="24" fill="#000"/></svg>`;
const DOT: string = `<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" ` +
	`viewBox="0 0 12 12"><circle cx="6" cy="6" r="4" fill="#000"/></svg>`;

function registered(svg: string): IconId {
	const r = registerIcon(svg);
	if (!r.ok) {
		console.log(`test icon refused: ${r.error.what}`);
		unreachable;
	}
	return r.value;
}

function texelAt(atlas: GlyphAtlas, t: GlyphTile, dx: int32, dy: int32): int32 {
	return void2dGlyphPageTexel(atlas.pageHandle(t.page) as int32, t.x + dx, t.y + dy);
}

test "registering an icon answers its natural size and each registration is its own id" {
	const a: IconId = registered(SQUARE);
	const b: IconId = registered(DOT);
	assert a != b;
	assert iconWidth(a) == 24.0 && iconHeight(a) == 24.0;
	assert iconWidth(b) == 12.0 && iconHeight(b) == 12.0;
}

test "an unparsable icon and one using an element the module refuses are named, not drawn" {
	const bad = registerIcon("not an svg");
	assert !bad.ok;
	if (!bad.ok) { assert bad.error.error == SvgMaskError.Unparsable; }
	const used = registerIcon(
		`<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8" viewBox="0 0 8 8">` +
		`<defs><rect id="r" width="4" height="4"/></defs><use href="#r"/></svg>`,
	);
	assert !used.ok;
	if (!used.ok) {
		assert used.error.error == SvgMaskError.Unsupported;
	}
}

test "the mask side is twice the device pixels rounded up and nothing for no size" {
	assert ICON_SUPERSAMPLE == 2;
	assert maskSide(24.0) == 48;
	assert maskSide(16.0 * 1.5) == 48;
	assert maskSide(24.2) == 50;
	assert maskSide(24.0005) == 48;
	assert maskSide(24.002) == 50;
	assert maskSide(0.5) == 2;
	assert maskSide(0.0) == 0;
	assert maskSide(-3.0) == 0;
}

test "the same icon at the same mask size is one tile and the second costs no rasterization" {
	const atlas = GlyphAtlas.create(128, 4);
	const id: IconId = registered(SQUARE);
	const first = acquireIconMask(atlas, id, 48, 48);
	assert first.ok;
	assert atlas.rasterizations == 1;
	const second = acquireIconMask(atlas, id, 48, 48);
	assert second.ok;
	assert atlas.rasterizations == 1;
	if (first.ok && second.ok) {
		assert first.value == second.value;
		assert atlas.tile(first.value).refs == 2;
		assert atlas.tile(first.value).page != (-1);
	}
}

test "two sizes of one icon and two icons at one size are separate tiles" {
	const atlas = GlyphAtlas.create(128, 4);
	const square: IconId = registered(SQUARE);
	const dot: IconId = registered(DOT);
	const small = acquireIconMask(atlas, square, 32, 32);
	const large = acquireIconMask(atlas, square, 48, 48);
	const other = acquireIconMask(atlas, dot, 32, 32);
	assert small.ok && large.ok && other.ok;
	if (small.ok && large.ok && other.ok) {
		assert small.value != large.value;
		assert small.value != other.value;
		assert atlas.tile(large.value).width == 48;
	}
	assert atlas.rasterizations == 3;
}

test "a mask tile holds the rasterized alpha and its gutter stays zero" {
	const atlas = GlyphAtlas.create(128, 4);
	const id: IconId = registered(SQUARE);
	const r = acquireIconMask(atlas, id, 40, 40);
	assert r.ok;
	if (!r.ok) { return; }
	const t = atlas.tile(r.value);
	assert t.width == 40 && t.height == 40 && t.left == 0 && t.top == 0;
	assert atlas.pageKind(t.page) == PageKind.Mask;
	assert texelAt(atlas, t, 0, 0) == 255;
	assert texelAt(atlas, t, 39, 39) == 255;
	assert texelAt(atlas, t, 20, 20) == 255;
	assert texelAt(atlas, t, 40, 0) == 0;
	assert texelAt(atlas, t, 0, 40) == 0;
	assert texelAt(atlas, t, 40, 40) == 0;
}

test "a mask page is R8 and never shares a page with coverage" {
	const atlas = GlyphAtlas.create(64, 4);
	const id: IconId = registered(SQUARE);
	assert acquireIconMask(atlas, id, 32, 32).ok;
	assert atlas.pageCount() == 1;
	assert atlas.residentBytes() == 64 * 64;
	assert atlas.ensurePage() != NO_GLYPH_PAGE_HANDLE;
	assert atlas.pageCount() == 2;
	assert atlas.residentBytes() == 64 * 64 * 2;
}

test "released masks are reclaimed whole when the page is full and nothing holds them" {
	const atlas = GlyphAtlas.create(64, 1);
	const square: IconId = registered(SQUARE);
	const dot: IconId = registered(DOT);
	const first = acquireIconMask(atlas, square, 48, 48);
	assert first.ok;
	const drawnBefore: int32 = iconRasterizations();
	const blocked = acquireIconMask(atlas, dot, 40, 40);
	assert !blocked.ok;
	assert iconRasterizations() == drawnBefore;
	assert atlas.reclaims == 0;
	assert atlas.rasterizations == 1;
	if (first.ok) { atlas.release(first.value); }
	const after = acquireIconMask(atlas, dot, 40, 40);
	assert after.ok;
	assert atlas.reclaims == 1;
	assert !atlas.cached(maskKey(square as int32, 48, 48));
}

test "a mask larger than a page is refused by name before it is rasterized" {
	const atlas = GlyphAtlas.create(64, 4);
	const id: IconId = registered(SQUARE);
	const r = acquireIconMask(atlas, id, 64, 32);
	assert !r.ok;
	if (!r.ok) { assert r.error == "TooLarge: a 64x32 mask does not fit a 64 page"; }
	assert atlas.rasterizations == 0;
	assert atlas.pageCount() == 0;
}

test "mask keys differ by icon, width and height and never collide with another kind" {
	const a = maskKey(3, 48, 48);
	assert a.packed() != maskKey(4, 48, 48).packed();
	assert a.packed() != maskKey(3, 50, 48).packed();
	assert a.packed() != maskKey(3, 48, 50).packed();
	const coverage: GlyphKey = { ...a, kind: PageKind.Coverage };
	assert a.packed() != coverage.packed();
	assert maskKey(65534, 8192, 8192).packed() != maskKey(65534, 8192, 8191).packed();
}

test "the atlas refuses a mask of the wrong key kind, shape or variant by name" {
	const atlas = GlyphAtlas.create(64, 4);
	const alpha: Vec<uint8> = [255, 255, 255, 255];
	const coverage: GlyphKey = { ...maskKey(1, 2, 2), kind: PageKind.Coverage };
	const wrongKind = atlas.acquireMask(coverage, 2, 2, alpha);
	assert !wrongKind.ok;
	if (!wrongKind.ok) { assert wrongKind.error == AtlasError.KindNotBuilt; }
	const short = atlas.acquireMask(maskKey(1, 3, 2), 3, 2, alpha);
	assert !short.ok;
	if (!short.ok) { assert short.error == AtlasError.MaskBadShape; }
	const shifted: GlyphKey = { ...maskKey(1, 2, 2), variant: 1 };
	const variant = atlas.acquireMask(shifted, 2, 2, alpha);
	assert !variant.ok;
	if (!variant.ok) { assert variant.error == AtlasError.VariantOutOfRange; }
	assert atlas.pageCount() == 0;
}
