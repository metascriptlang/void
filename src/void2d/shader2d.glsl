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
    vec4 clipU;        // xy = edge axis; zw = accepted projection interval (disabled when w <= z)
    vec4 clipV;
};
in vec2 pos;
in vec2 uv0;
in vec4 color0;
out vec2 uv;
out vec4 color;
out float srcPremult;
out vec4 clipDistance;
void main() {
    vec2 world = vec2(model0.x * pos.x + model0.z * pos.y + model1.x,
                      model0.y * pos.x + model0.w * pos.y + model1.y);
    vec2 ndc = vec2(world.x / viewport.x * 2.0 - 1.0, 1.0 - world.y / viewport.y * 2.0);
    gl_Position = vec4(ndc, 0.0, 1.0);
    uv = (viewport.z > 0.5) ? vec2(uv0.x, 1.0 - uv0.y) : uv0;
    color = color0 * globalColor;
    srcPremult = viewport.w;
    if (clipU.w > clipU.z) {
        float cu = dot(world, clipU.xy);
        float cv = dot(world, clipV.xy);
        clipDistance = vec4(cu - clipU.z, clipU.w - cu, cv - clipV.z, clipV.w - cv);
    } else {
        clipDistance = vec4(1.0);
    }
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
    vec4 gradientMeta;
    vec4 gradientParams;
    vec4 gradientColor0;
    vec4 gradientColor1;
    vec4 gradientColor2;
};
in vec2 uv;
in vec4 color;
in float srcPremult;
in vec4 clipDistance;
out vec4 frag_color;
vec3 srgbToLinear(vec3 c) {
    vec3 lo = c / 12.92;
    vec3 hi = pow((c + vec3(0.055)) / 1.055, vec3(2.4));
    return mix(hi, lo, lessThanEqual(c, vec3(0.04045)));
}
vec3 linearToSrgb(vec3 c) {
    vec3 lo = c * 12.92;
    vec3 hi = vec3(1.055) * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - vec3(0.055);
    return mix(hi, lo, lessThanEqual(c, vec3(0.0031308)));
}
vec3 linearToOklab(vec3 c) {
    vec3 lms = vec3(
        0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b,
        0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b,
        0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b);
    lms = sign(lms) * pow(abs(lms), vec3(1.0 / 3.0));
    return vec3(
        0.2104542553 * lms.x + 0.7936177850 * lms.y - 0.0040720468 * lms.z,
        1.9779984951 * lms.x - 2.4285922050 * lms.y + 0.4505937099 * lms.z,
        0.0259040371 * lms.x + 0.7827717662 * lms.y - 0.8086757660 * lms.z);
}
vec3 oklabToLinear(vec3 c) {
    vec3 lms = vec3(
        c.x + 0.3963377774 * c.y + 0.2158037573 * c.z,
        c.x - 0.1055613458 * c.y - 0.0638541728 * c.z,
        c.x - 0.0894841775 * c.y - 1.2914855480 * c.z);
    lms = lms * lms * lms;
    return vec3(
         4.0767416621 * lms.x - 3.3077115913 * lms.y + 0.2309699292 * lms.z,
        -1.2684380046 * lms.x + 2.6097574011 * lms.y - 0.3413193965 * lms.z,
        -0.0041960863 * lms.x - 0.7034186147 * lms.y + 1.7076147010 * lms.z);
}
vec4 mixGradient(vec4 a, vec4 b, float t) {
    vec3 rgb;
    if (gradientMeta.y > 0.5) {
        vec3 la = linearToOklab(srgbToLinear(a.rgb));
        vec3 lb = linearToOklab(srgbToLinear(b.rgb));
        rgb = linearToSrgb(oklabToLinear(mix(la, lb, t)));
    } else {
        rgb = mix(a.rgb, b.rgb, t);
    }
    return vec4(rgb, mix(a.a, b.a, t));
}
vec4 gradientAt(float t) {
    float middle = gradientMeta.w;
    if (middle > 0.0 && middle < 1.0) {
        if (t < middle) { return mixGradient(gradientColor0, gradientColor1, t / middle); }
        return mixGradient(gradientColor1, gradientColor2, (t - middle) / (1.0 - middle));
    }
    return mixGradient(gradientColor0, gradientColor1, t);
}
float bayer4(vec2 pixel) {
    int x = int(mod(floor(pixel.x), 4.0));
    int y = int(mod(floor(pixel.y), 4.0));
    if (y == 0) {
        if (x == 0) return 0.0;
        if (x == 1) return 8.0;
        if (x == 2) return 2.0;
        return 10.0;
    }
    if (y == 1) {
        if (x == 0) return 12.0;
        if (x == 1) return 4.0;
        if (x == 2) return 14.0;
        return 6.0;
    }
    if (y == 2) {
        if (x == 0) return 3.0;
        if (x == 1) return 11.0;
        if (x == 2) return 1.0;
        return 9.0;
    }
    if (x == 0) return 15.0;
    if (x == 1) return 7.0;
    if (x == 2) return 13.0;
    return 5.0;
}
void main() {
    if (min(min(clipDistance.x, clipDistance.y), min(clipDistance.z, clipDistance.w)) < 0.0) { discard; }
    int gradientKind = int(gradientMeta.x + 0.5);
    vec4 texel;
    if (gradientKind == 1 || gradientKind == 2) {
        float t = gradientKind == 1 ? clamp(uv.x, 0.0, 1.0) : clamp(length(uv), 0.0, 1.0);
        texel = gradientAt(t);
        if (gradientMeta.z > 0.5) {
            float noise = (bayer4(gl_FragCoord.xy) - 7.5) * (2.0 / (7.5 * 255.0));
            texel.rgb = clamp(texel.rgb + vec3(noise), vec3(0.0), vec3(1.0));
        }
    } else if (gradientKind == 3) {
        float spacing = max(gradientParams.x, 1.0);
        float width = clamp(gradientParams.y, 0.0, spacing);
        texel = mod(uv.x + uv.y, spacing) < width ? gradientColor1 : gradientColor0;
    } else if (gradientKind == 4) {
        float cell = max(gradientParams.x, 1.0);
        float parity = mod(floor(uv.x / cell) + floor(uv.y / cell), 2.0);
        texel = parity < 1.0 ? gradientColor0 : gradientColor1;
    } else {
        texel = texture(sampler2D(tex, smp), uv);
    }
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
    vec4 clipU;
    vec4 clipV;
};
in vec2 corner;
in vec4 iAffine;      // a,b,c,d
in vec4 iOriginSize;  // tx,ty,w,h
in vec4 iUv;          // u0,v0,u1,v1
in vec4 iColor;
out vec2 uv;
out vec4 color;
out float srcPremult;
out vec4 clipDistance;
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
    if (clipU.w > clipU.z) {
        float cu = dot(world, clipU.xy);
        float cv = dot(world, clipV.xy);
        clipDistance = vec4(cu - clipU.z, clipU.w - cu, cv - clipV.z, clipV.w - cv);
    } else {
        clipDistance = vec4(1.0);
    }
}
@end

@fs spriteFs
layout(binding=0) uniform texture2D spriteTex;
layout(binding=0) uniform sampler spriteSmp;
in vec2 uv;
in vec4 color;
in float srcPremult;
in vec4 clipDistance;
out vec4 frag_color;
void main() {
    if (min(min(clipDistance.x, clipDistance.y), min(clipDistance.z, clipDistance.w)) < 0.0) { discard; }
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
    vec4 clipU;
    vec4 clipV;
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
out vec4 clipDistance;
void main() {
    // One device pixel across an edge, in the node's local units — the geometric mean of the
    // two axis lengths, so a non-uniform scale gets one width rather than a direction-
    // dependent one. Mirrors aaWidthForAffine in sdf.ms. Glyph mode is the exception: the
    // atlas texel already carries the antialiasing fontstash rasterized, so aa stays zero —
    // the quad un-inflated at the glyph's exact bitmap rect, coverage a hard step at that
    // rect, which is the quad the mesh path always drew.
    float sx = length(iAffine.xy);
    float sy = length(iAffine.zw);
    float s = sqrt(sx * sy);
    float aa = iParams0.x == 2.0 ? 0.0 : (s > 0.0 ? 1.0 / s : 0.0);

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
    if (clipU.w > clipU.z) {
        float cu = dot(world, clipU.xy);
        float cv = dot(world, clipV.xy);
        clipDistance = vec4(cu - clipU.z, clipU.w - cu, cv - clipV.z, clipV.w - cv);
    } else {
        clipDistance = vec4(1.0);
    }
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
in vec4 clipDistance;
out vec4 frag_color;

// Negative inside. `r` is clamped to the largest radius the box can hold, because a radius
// past that is not a rounded rect at all and silently produces a lens shape.
float roundedRectDistance(vec2 p, vec2 half_, float r) {
    float rr = clamp(r, 0.0, min(half_.x, half_.y));
    vec2 q = abs(p) - (half_ - rr);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rr;
}

float cornerRadius(vec2 p, vec4 radii) {
    return p.x < 0.0 ? (p.y < 0.0 ? radii.x : radii.w)
                     : (p.y < 0.0 ? radii.y : radii.z);
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

// GPUI's error function (`shaders.wgsl:325`), rational form. Its polynomial error is orders
// below one 8-bit level, so it is never the term a bound has to worry about. Mirrored in
// sdf.ms as erfApprox, where the coverage oracle judges the integral built on it.
float erfApprox(float x) {
    float s = sign(x);
    float a = abs(x);
    float r1 = 1.0 + (0.278393 + (0.230389 + (0.000972 + 0.078108 * a) * a) * a) * a;
    float r2 = r1 * r1;
    return s - s / (r2 * r2);
}

// The Gaussian pdf, GPUI's `gaussian`.
float gaussianPdf(float x, float sigma) {
    return exp(-(x * x) / (2.0 * sigma * sigma)) / (sqrt(6.283185307179586) * sigma);
}

// One side's half-extent at |y|: the core width plus the chord the corner circle still covers
// at that height. GPUI's `curved`, computed per side - per-corner radii get their own chords,
// where GPUI symmetrises to the evaluation point's quadrant.
float scanlineHalf(float hx, float hy, float ay, float r) {
    float dy = ay - (hy - r);
    float under = r * r - dy * dy;
    float chord = (dy > 0.0 && under > 0.0) ? sqrt(under) : r;
    return hx - r + chord;
}

// The Gaussian-blurred rounded rect: closed-form CDF difference along x (erfApprox), four
// midpoint samples along y over the kernel's +-3-sigma window clamped to the box's extent -
// GPUI's `fs_shadow` integral. The blur is applied by evaluating at (p - offset), which is
// GPUI's CPU-side bounds offset stated as one subtraction. sigma <= 0 is the hard shadow.
// Judged against the kernel-integral oracle within 0.02 (worst measured 0.0078).
float shadowCoverage(vec2 p, vec2 half_, vec4 radii, vec2 offset, float sigma, float aa) {
    vec4 rr = clamp(radii, vec4(0.0), vec4(min(half_.x, half_.y)));
    vec2 c = p - offset;
    if (sigma <= 0.0) {
        return coverageFromDistance(roundedRectDistance(c, half_, cornerRadius(c, rr)), aa);
    }
    float low = c.y - half_.y;
    float high = c.y + half_.y;
    float start = clamp(-3.0 * sigma, low, high);
    float end = clamp(3.0 * sigma, low, high);
    float stepY = (end - start) / 4.0;
    float k = sqrt(0.5) / sigma;
    float acc = 0.0;
    float y = start + stepY * 0.5;
    for (int i = 0; i < 4; i++) {
        float scanY = c.y - y;
        float ay = abs(scanY);
        float wL = scanlineHalf(half_.x, half_.y, ay, scanY < 0.0 ? rr.x : rr.w);
        float wR = scanlineHalf(half_.x, half_.y, ay, scanY < 0.0 ? rr.y : rr.z);
        float hi = 0.5 + 0.5 * erfApprox((c.x + wL) * k);
        float lo = 0.5 + 0.5 * erfApprox((c.x - wR) * k);
        acc += (hi - lo) * gaussianPdf(y, sigma) * stepY;
        y += stepY;
    }
    return acc;
}

void main() {
    if (min(min(clipDistance.x, clipDistance.y), min(clipDistance.z, clipDistance.w)) < 0.0) { discard; }
    vec2 p = vLocalHalf.xy;
    vec2 half_ = vLocalHalf.zw;
    float aa = vUvAa.z;
    int mode = int(vUvAa.w + 0.5);

    if (mode == 1) {                       // Shadow: standalone drop or inset
        // The box's own half extents and blur ride in the borders lane; the quad is inflated
        // by the emitter (3-sigma + offset for a drop, nothing for an inset - it cannot
        // escape the element), so `half_` here is the QUAD's half, not the box's.
        vec2 halfBox = vBorders.xy;
        float sigma = vBorders.z;
        float alpha;
        if (vBorders.w > 0.5) {
            // Inset: the complement of the blurred hole, clipped to the element itself.
            float blur = shadowCoverage(p, halfBox, vRadii, vec2(0.0), sigma, aa);
            alpha = (1.0 - blur) * coverageFromDistance(
                roundedRectDistance(p, halfBox, cornerRadius(p, vRadii)), aa);
        } else {
            alpha = shadowCoverage(p, halfBox, vRadii, vParams1.xy, sigma, aa);
        }
        frag_color = vec4(vExtra.rgb * (vExtra.a * alpha), vExtra.a * alpha);
        return;
    }

    // A shadowed box is ONE instance (cardOneInstance): the quad carries the shadow's
    // extent, so `half_` is the QUAD's half and the box's own half is derived back from the
    // emitter's margin formula - 3 sigma plus the offset's displacement per axis, nothing
    // for an inset, which cannot escape the element. params1 = (offsetX, offsetY, sigma,
    // inset) while vExtra.a > 0, and vExtra is the shadow colour: a zero-alpha extra is no
    // shadow, the same convention the style itself uses. The margin formula is one contract
    // with render.ms, mirrored the way aaWidthForAffine is.
    vec2 halfBox = half_;
    bool shadowed = vExtra.a > 0.0;
    if (shadowed && vParams1.w <= 0.5) {
        halfBox = half_ - (vec2(3.0 * vParams1.z) + abs(vParams1.xy));
    }

    float r = cornerRadius(p, vRadii);
    float dOuter = roundedRectDistance(p, halfBox, r);

    // The border's inner edge is the outer rect inset per side, which moves its centre when
    // the two opposite widths differ. Each corner radius shrinks with the thicker of the two
    // sides touching that corner.
    vec4 borders = max(vBorders, vec4(0.0));
    vec2 inset = vec2(borders.x + borders.z, borders.y + borders.w) * 0.5;
    vec2 shift = vec2(borders.x - borders.z, borders.y - borders.w) * 0.5;
    vec4 innerRadii = max(vRadii - vec4(
        max(borders.x, borders.y),
        max(borders.y, borders.z),
        max(borders.z, borders.w),
        max(borders.w, borders.x)
    ), vec4(0.0));
    vec2 innerPoint = p - shift;
    float dInner = roundedRectDistance(
        innerPoint,
        max(halfBox - inset, vec2(0.0)),
        cornerRadius(innerPoint, innerRadii)
    );

    // Area fractions, not a blend factor between two colours. The fill covers the inner
    // rect and the border covers the RING between the two, so a zero-width border has zero
    // area and contributes nothing — where `mix` on the inner distance would paint half a
    // border colour along every edge of a box that has no border at all. That is what
    // `snap/zeroBorder` means by "zero stays zero", stated as arithmetic instead of a rule.
    float outer = coverageFromDistance(dOuter, aa);
    float inner = coverageFromDistance(dInner, aa);
    float ring = max(outer - inner, 0.0);

    vec4 fill = vFill;
    if (mode == 3) {                       // Image
        fill = fill * texture(sampler2D(uiTex, uiSmp), vUvAa.xy);
    } else if (mode == 2) {                // Glyph: the atlas is white in rgb, coverage in alpha
        fill.a = fill.a * texture(sampler2D(uiTex, uiSmp), vUvAa.xy).a;
    }
    float alpha = fill.a * inner + vBorder.a * ring;
    vec3 rgb = fill.rgb * (fill.a * inner) + vBorder.rgb * (vBorder.a * ring);
    if (shadowed) {
        float sAlpha;
        if (vParams1.w > 0.5) {
            // Inset: the complement of the blurred hole, clipped to the element, OVER the
            // fill - the same `over` the two-instance form drew by blending order.
            float blurCov = shadowCoverage(p, halfBox, vRadii, vec2(0.0), vParams1.z, aa);
            sAlpha = (1.0 - blurCov) * outer;
        } else {
            sAlpha = shadowCoverage(p, halfBox, vRadii, vParams1.xy, vParams1.z, aa);
        }
        sAlpha *= vExtra.a;
        if (vParams1.w > 0.5) {
            rgb = vExtra.rgb * sAlpha + rgb * (1.0 - sAlpha);
            alpha = sAlpha + alpha * (1.0 - sAlpha);
        } else {
            rgb = rgb + vExtra.rgb * sAlpha * (1.0 - alpha);
            alpha = alpha + sAlpha * (1.0 - alpha);
        }
    }
    frag_color = vec4(rgb, alpha);
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
