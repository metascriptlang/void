// Void 2D batcher shader (sokol-shdc dialect).
// vert pos → model (2D affine) → pixel → NDC; per-vertex color × globalColor.
// Dynamic batch passes model=identity, globalColor=white (verts already pixel-space) →
// no-op. Static buffers (local-space geometry) pass the object matrix + alpha here instead.
@vs vs
layout(binding=0) uniform void2d_params {
    vec4 viewport;     // x,y = framebuffer size in pixels; z = flipV (1 when sampling a GL render-target); w = srcAlreadyPremult (1 for RT textures)
    vec4 model0;       // 2D affine linear part (a,b,c,d): x'=a*x+c*y+tx, y'=b*x+d*y+ty
    vec4 model1;       // xy = translation (tx,ty), zw unused
    vec4 globalColor;  // multiplied into the per-vertex tint
};
in vec2 pos;
in vec2 uv0;
in vec4 color0;
out vec2 uv;
out vec4 color;
out float srcPremult;
void main() {
    vec2 world = vec2(model0.x * pos.x + model0.z * pos.y + model1.x,
                      model0.y * pos.x + model0.w * pos.y + model1.y);
    vec2 ndc = vec2(world.x / viewport.x * 2.0 - 1.0, 1.0 - world.y / viewport.y * 2.0);
    gl_Position = vec4(ndc, 0.0, 1.0);
    uv = (viewport.z > 0.5) ? vec2(uv0.x, 1.0 - uv0.y) : uv0;
    color = color0 * globalColor;
    srcPremult = viewport.w;
}
@end

@fs fs
layout(binding=0) uniform texture2D tex;
layout(binding=0) uniform sampler smp;
// h2d.Drawable color pipeline: multiply tint (per-vertex) → colorMatrix → colorAdd.
// Defaults (identity matrix, zero add) leave the pixel untouched, so no-effect nodes
// batch together unchanged.
layout(binding=1) uniform void2d_fx {
    mat4 colorMatrix;
    vec4 colorAdd;
    vec4 colorKey;
};
in vec2 uv;
in vec4 color;
in float srcPremult;
out vec4 frag_color;
void main() {
    vec4 texel = texture(sampler2D(tex, smp), uv);
    if (colorKey.a > 0.5) {
        vec3 d = abs(texel.rgb - colorKey.rgb);
        if (d.r + d.g + d.b < 0.08) { texel.a = 0.0; }
    }
    vec4 c = texel * color;
    // A premultiplied source - a render target, which the whole pass wrote through
    // premultiplied blending - already carries its coverage in rgb. A tint alpha therefore
    // has to scale rgb as well, or fading it changes only its coverage: measured on
    // filter/groupOpacity, a group at alpha 0.5 composited at full colour strength and the
    // only thing 0.5 did was let the background through at the edges.
    c.rgb = mix(c.rgb, c.rgb * color.a, srcPremult);
    c = colorMatrix * c;
    c = c + colorAdd;
    vec4 premult = vec4(c.rgb * c.a, c.a);
    frag_color = mix(premult, c, srcPremult);
}
@end

@program void2d vs fs

// The flat sprite pipeline (VOID2D.md "P2"). One instance per quad, 64 B, and no SDF maths
// anywhere in it — guardrail 8 is that a sprite-only scene must not pay for the UI pipeline,
// and the cheapest way to mean that is a program that cannot run the other one's code.
//
// `corner` is the per-vertex unit quad (0,0)..(1,1); everything else steps per instance. The
// affine is carried per instance rather than re-transformed on the CPU, which is what turns
// 192 B of re-written vertices into 64 B of unchanged bytes.
@vs spriteVs
layout(binding=0) uniform sprite_params {
    vec4 viewport;     // xy = framebuffer size in px; z = flipV; w = srcAlreadyPremult
};
in vec2 corner;
in vec4 iAffine;      // a,b,c,d
in vec4 iOriginSize;  // tx,ty,w,h
in vec4 iUv;          // u0,v0,u1,v1
in vec4 iColor;
out vec2 uv;
out vec4 color;
out float srcPremult;
void main() {
    vec2 local = corner * iOriginSize.zw;
    vec2 world = vec2(iAffine.x * local.x + iAffine.z * local.y + iOriginSize.x,
                      iAffine.y * local.x + iAffine.w * local.y + iOriginSize.y);
    vec2 ndc = vec2(world.x / viewport.x * 2.0 - 1.0, 1.0 - world.y / viewport.y * 2.0);
    gl_Position = vec4(ndc, 0.0, 1.0);
    vec2 t = mix(iUv.xy, iUv.zw, corner);
    uv = (viewport.z > 0.5) ? vec2(t.x, 1.0 - t.y) : t;
    color = iColor;
    srcPremult = viewport.w;
}
@end

@fs spriteFs
layout(binding=0) uniform texture2D spriteTex;
layout(binding=0) uniform sampler spriteSmp;
in vec2 uv;
in vec4 color;
in float srcPremult;
out vec4 frag_color;
void main() {
    vec4 c = texture(sampler2D(spriteTex, spriteSmp), uv) * color;
    c.rgb = mix(c.rgb, c.rgb * color.a, srcPremult);
    vec4 premult = vec4(c.rgb * c.a, c.a);
    frag_color = mix(premult, c, srcPremult);
}
@end

@program sprite spriteVs spriteFs

// The unified UI pipeline (VOID2D.md "P2"). One program, one 108-byte stride, a per-instance
// `mode` — so a card, its label and its image batch together instead of costing a draw each.
//
// The SDF is evaluated in LOCAL space (GPUI.md:35-39): the fragment stage gets the point in
// the node's own rectangle and the antialiasing width expressed in local units, so a rotated
// or scaled card keeps its corner radius and its edge softness instead of having them baked
// in at record time. `src/void2d/sdf.ms` holds the same arithmetic in MetaScript, where
// `tests/oracle/coverage.ms` supersamples the geometry independently and says whether the
// coverage is actually right — which is the only tier that can, because a golden reports
// that the AA has not changed, never that it is correct.
//
// The quad is inflated by one device pixel on every side before the affine is applied, or
// the coverage ramp would be clipped by the geometry it is meant to soften.
@vs uiVs
layout(binding=0) uniform ui_params {
    vec4 viewport;     // xy = framebuffer size in px; z = flipV; w unused
};
in vec2 corner;
in vec4 iAffine;      // a,b,c,d
in vec4 iOriginSize;  // tx,ty,w,h
in vec4 iUvRadii;     // image u0,v0,u1,v1 | box four corner radii, TL TR BR BL
in vec4 iBorders;     // per-side widths, L T R B
in vec4 iParams0;     // x = mode, then per-mode params
in vec4 iParams1;     // gradient stops | shadow offset + spread
in vec4 iColorFill;
in vec4 iColorBorder;
in vec4 iColorExtra;
out vec4 vLocalHalf;  // xy = point relative to the rect centre; zw = half extents
out vec4 vUvAa;       // xy = uv; z = one device pixel in local units; w = mode
out vec4 vRadii;
out vec4 vBorders;
out vec4 vParams1;
out vec4 vFill;
out vec4 vBorder;
out vec4 vExtra;
void main() {
    // One device pixel across an edge, in the node's local units — the geometric mean of the
    // two axis lengths, so a non-uniform scale gets one width rather than a direction-
    // dependent one. Mirrors aaWidthForAffine in sdf.ms.
    float sx = length(iAffine.xy);
    float sy = length(iAffine.zw);
    float s = sqrt(sx * sy);
    float aa = s > 0.0 ? 1.0 / s : 0.0;

    vec2 size = iOriginSize.zw;
    vec2 local = corner * (size + 2.0 * aa) - aa;
    vec2 world = vec2(iAffine.x * local.x + iAffine.z * local.y + iOriginSize.x,
                      iAffine.y * local.x + iAffine.w * local.y + iOriginSize.y);
    gl_Position = vec4(world.x / viewport.x * 2.0 - 1.0, 1.0 - world.y / viewport.y * 2.0, 0.0, 1.0);

    vec2 t = mix(iUvRadii.xy, iUvRadii.zw, size.x > 0.0 && size.y > 0.0 ? local / size : vec2(0.0));
    vLocalHalf = vec4(local - size * 0.5, size * 0.5);
    vUvAa = vec4((viewport.z > 0.5) ? vec2(t.x, 1.0 - t.y) : t, aa, iParams0.x);
    vRadii = iUvRadii;
    vBorders = iBorders;
    vParams1 = iParams1;
    vFill = iColorFill;
    vBorder = iColorBorder;
    vExtra = iColorExtra;
}
@end

@fs uiFs
layout(binding=0) uniform texture2D uiTex;
layout(binding=0) uniform sampler uiSmp;
in vec4 vLocalHalf;
in vec4 vUvAa;
in vec4 vRadii;
in vec4 vBorders;
in vec4 vParams1;
in vec4 vFill;
in vec4 vBorder;
in vec4 vExtra;
out vec4 frag_color;

// Negative inside. `r` is clamped to the largest radius the box can hold, because a radius
// past that is not a rounded rect at all and silently produces a lens shape.
float roundedRectDistance(vec2 p, vec2 half_, float r) {
    float rr = clamp(r, 0.0, min(half_.x, half_.y));
    vec2 q = abs(p) - (half_ - rr);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rr;
}

// LINEAR, and this is the one line in this file that was measured rather than inherited.
// The true area of a pixel cut by a straight edge is linear in the edge's distance from the
// pixel centre; smoothstep is an S-curve through the same endpoints and overshoots by up to
// 0.094 — 24 levels of 255 on every antialiased edge. tests/oracle/coverage.ms convicted it
// before a pixel was ever drawn, and keeps the curve as a case that must fail.
float coverageFromDistance(float d, float aa) {
    if (aa <= 0.0) { return d <= 0.0 ? 1.0 : 0.0; }
    return clamp(0.5 - d / aa, 0.0, 1.0);
}

void main() {
    vec2 p = vLocalHalf.xy;
    vec2 half_ = vLocalHalf.zw;
    float aa = vUvAa.z;
    int mode = int(vUvAa.w + 0.5);

    float r = p.x < 0.0 ? (p.y < 0.0 ? vRadii.x : vRadii.w)
                        : (p.y < 0.0 ? vRadii.y : vRadii.z);
    float dOuter = roundedRectDistance(p, half_, r);

    // The border's inner edge is the outer rect inset per side, which moves its centre when
    // the two opposite widths differ. Its radius shrinks with the thickest side it touches,
    // so a 1-px border on a 6-px radius leaves a 5-px inner radius rather than a flat corner.
    vec2 inset = vec2(vBorders.x + vBorders.z, vBorders.y + vBorders.w) * 0.5;
    vec2 shift = vec2(vBorders.x - vBorders.z, vBorders.y - vBorders.w) * 0.5;
    float maxBorder = max(max(vBorders.x, vBorders.y), max(vBorders.z, vBorders.w));
    float dInner = roundedRectDistance(p - shift, max(half_ - inset, vec2(0.0)), max(r - maxBorder, 0.0));

    vec4 c = mix(vFill, vBorder, coverageFromDistance(-dInner, aa));
    if (mode == 3) {                       // Image
        c = c * texture(sampler2D(uiTex, uiSmp), vUvAa.xy);
    } else if (mode == 2) {                // Glyph: the atlas carries coverage, not colour
        c.a = c.a * texture(sampler2D(uiTex, uiSmp), vUvAa.xy).r;
    }
    c.a = c.a * coverageFromDistance(dOuter, aa);
    frag_color = vec4(c.rgb * c.a, c.a);
}
@end

@program ui uiVs uiFs


// Separable Gaussian blur (h2d.filter.Blur). Fullscreen quad; `dir` is the per-tap UV step
// (radius/texW,0) for the horizontal pass, (0,radius/texH) for the vertical. Two passes = 2D blur.
@vs blurVs
in vec2 pos;
in vec2 uv0;
out vec2 uv;
void main() {
    gl_Position = vec4(pos, 0.0, 1.0);
    uv = uv0;
}
@end

@fs blurFs
layout(binding=0) uniform texture2D srcTex;
layout(binding=0) uniform sampler srcSmp;
layout(binding=0) uniform blur_params {
    vec4 dir;   // xy = per-tap UV step; zw unused
};
in vec2 uv;
out vec4 frag_color;
void main() {
    vec2 o1 = dir.xy * 1.384615;
    vec2 o2 = dir.xy * 3.230769;
    vec4 sum = texture(sampler2D(srcTex, srcSmp), uv) * 0.227027;
    sum += texture(sampler2D(srcTex, srcSmp), uv + o1) * 0.316216;
    sum += texture(sampler2D(srcTex, srcSmp), uv - o1) * 0.316216;
    sum += texture(sampler2D(srcTex, srcSmp), uv + o2) * 0.070270;
    sum += texture(sampler2D(srcTex, srcSmp), uv - o2) * 0.070270;
    frag_color = sum;
}
@end

@program blur blurVs blurFs
