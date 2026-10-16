@vs vs
layout(binding=0) uniform void2d_params {
    vec4 viewport;
    vec4 model0;
    vec4 model1;
    vec4 globalColor;
    vec4 clipU;
    vec4 clipV;
    vec4 shift;
};
in vec2 pos;
in vec2 uv0;
in vec4 color0;
out vec2 uv;
out vec4 color;
out float srcPremult;
out float coverageTexture;
out vec4 clipDistance;
out vec2 pixel;
vec4 clipDistanceOf(vec2 world, vec4 clipU_1, vec4 clipV_1) {
    if (clipU_1.w > clipU_1.z) {
        float cu = dot(world, clipU_1.xy);
        float cv = dot(world, clipV_1.xy);
        return vec4((cu - clipU_1.z), (clipU_1.w - cu), (cv - clipV_1.z), (clipV_1.w - cv));
    }
    return vec4(1.0);
}
void main() {
    vec4 model0_1 = model0;
    vec4 model1_1 = model1;
    vec4 viewport_1 = viewport;
    vec2 world = vec2((((model0_1.x * pos.x) + (model0_1.z * pos.y)) + model1_1.x), (((model0_1.y * pos.x) + (model0_1.w * pos.y)) + model1_1.y));
    vec2 moved = world + shift.xy;
    vec2 ndc = vec2((((moved.x / viewport_1.x) * 2.0) - 1.0), (1.0 - ((moved.y / viewport_1.y) * 2.0)));
    uv = ((viewport_1.z > 0.5) ? vec2(uv0.x, (1.0 - uv0.y)) : uv0);
    color = (color0 * globalColor);
    srcPremult = viewport_1.w;
    coverageTexture = model1_1.z;
    clipDistance = clipDistanceOf(world, clipU, clipV);
    pixel = (moved * model1_1.w);
    gl_Position = vec4(ndc, 0.0, 1.0);
    return;
}
@end

@fs fs
layout(binding=0) uniform texture2D tex;
layout(binding=0) uniform sampler smp;
layout(binding=1) uniform void2d_fx {
    mat4 colorMatrix;
    vec4 colorAdd;
    vec4 colorKey;
    vec4 gradientMeta;
    vec4 gradientParams;
    vec4 gradientColor0;
    vec4 gradientColor1;
    vec4 gradientColor2;
    vec4 gammaRatios;
    vec4 textParams;
    vec4 sourceParams;
};
in vec2 uv;
in vec4 color;
in float srcPremult;
in float coverageTexture;
in vec4 clipDistance;
in vec2 pixel;
layout(location=0) out vec4 fragColor;
vec3 linearToOklab(vec3 c) {
    vec3 lms = vec3((((0.4122214708 * c.x) + (0.5363325363 * c.y)) + (0.0514459929 * c.z)), (((0.2119034982 * c.x) + (0.6806995451 * c.y)) + (0.1073969566 * c.z)), (((0.0883024619 * c.x) + (0.2817188376 * c.y)) + (0.6299787005 * c.z)));
    lms = sign(lms) * pow(abs(lms), vec3(0.3333333333333333));
    return vec3((((0.2104542553 * lms.x) + (0.793617785 * lms.y)) - (0.0040720468 * lms.z)), (((1.9779984951 * lms.x) - (2.428592205 * lms.y)) + (0.4505937099 * lms.z)), (((0.0259040371 * lms.x) + (0.7827717662 * lms.y)) - (0.808675766 * lms.z)));
}
vec3 srgbToLinear(vec3 c) {
    vec3 lo = c / 12.92;
    vec3 hi = pow(((c + vec3(0.055)) / 1.055), vec3(2.4));
    return vec3(((c.x <= 0.04045) ? lo.x : hi.x), ((c.y <= 0.04045) ? lo.y : hi.y), ((c.z <= 0.04045) ? lo.z : hi.z));
}
vec3 linearToSrgb(vec3 c) {
    vec3 lo = c * 12.92;
    vec3 hi = (vec3(1.055) * pow(max(c, vec3(0.0)), vec3(0.4166666666666667))) - vec3(0.055);
    return vec3(((c.x <= 0.0031308) ? lo.x : hi.x), ((c.y <= 0.0031308) ? lo.y : hi.y), ((c.z <= 0.0031308) ? lo.z : hi.z));
}
vec3 oklabToLinear(vec3 c) {
    vec3 lms = vec3(((c.x + (0.3963377774 * c.y)) + (0.2158037573 * c.z)), ((c.x - (0.1055613458 * c.y)) - (0.0638541728 * c.z)), ((c.x - (0.0894841775 * c.y)) - (1.291485548 * c.z)));
    lms = (lms * lms) * lms;
    return vec3((((4.0767416621 * lms.x) - (3.3077115913 * lms.y)) + (0.2309699292 * lms.z)), (((-1.2684380046 * lms.x) + (2.6097574011 * lms.y)) - (0.3413193965 * lms.z)), (((-0.0041960863 * lms.x) - (0.7034186147 * lms.y)) + (1.707614701 * lms.z)));
}
vec4 mixColorSpace(vec4 a, vec4 b, float t, bool oklab) {
    vec3 rgb = vec3(0.0);
    if (oklab) {
        vec3 la = linearToOklab(srgbToLinear(a.xyz));
        vec3 lb = linearToOklab(srgbToLinear(b.xyz));
        rgb = linearToSrgb(oklabToLinear(mix(la, lb, t)));
    } else {
        rgb = mix(a.xyz, b.xyz, t);
    }
    return vec4(rgb, mix(a.w, b.w, t));
}
vec4 mixGradient(vec4 x, vec4 y, float t) {
    return mixColorSpace(x, y, t, (gradientMeta.y > 0.5));
}
vec4 gradientAt(float t) {
    float middle = gradientMeta.w;
    vec4 c0 = gradientColor0;
    vec4 c1 = gradientColor1;
    if ((middle > 0.0) && (middle < 1.0)) {
        if (t < middle) {
            return mixGradient(c0, c1, (t / middle));
        }
        return mixGradient(c1, gradientColor2, ((t - middle) / (1.0 - middle)));
    }
    return mixGradient(c0, c1, t);
}
float floorMod(float x, float y) {
    return x - (y * floor((x / y)));
}
float bayer4(vec2 pixel_1) {
    int x = int(floorMod(floor(pixel_1.x), 4.0));
    int y = int(floorMod(floor(pixel_1.y), 4.0));
    if (y == 0) {
        if (x == 0) {
            return 0.0;
        }
        if (x == 1) {
            return 8.0;
        }
        if (x == 2) {
            return 2.0;
        }
        return 10.0;
    }
    if (y == 1) {
        if (x == 0) {
            return 12.0;
        }
        if (x == 1) {
            return 4.0;
        }
        if (x == 2) {
            return 14.0;
        }
        return 6.0;
    }
    if (y == 2) {
        if (x == 0) {
            return 3.0;
        }
        if (x == 1) {
            return 11.0;
        }
        if (x == 2) {
            return 1.0;
        }
        return 9.0;
    }
    if (x == 0) {
        return 15.0;
    }
    if (x == 1) {
        return 7.0;
    }
    if (x == 2) {
        return 13.0;
    }
    return 5.0;
}
vec3 ditherRgb(vec3 rgb, vec2 pixel_1) {
    float noise = (bayer4(pixel_1) - 7.5) * 0.0010457516339869282;
    return clamp((rgb + vec3(noise)), vec3(0.0), vec3(1.0));
}
const float PATTERN_TIE_BIAS = 0.015625;
const float SDF_EDGE = 0.7490196078431373;
const float SDF_RADIUS = 8.0;
float sdfCoverage(float sampled, float texelsPerPixel) {
    float texels = (sampled - SDF_EDGE) * SDF_RADIUS;
    return clamp(((texels / texelsPerPixel) + 0.5), 0.0, 1.0);
}
float sdfTexelsPerPixel(vec2 uvDx, vec2 uvDy, vec2 pageSize) {
    return max((0.5 * (length((uvDx * pageSize)) + length((uvDy * pageSize)))), 0.0001);
}
float applyContrastAndGamma(float coverage, vec3 color_1, float contrastFactor, vec4 ratios) {
    float brightness = dot(color_1, vec3(0.3, 0.59, 0.11));
    float k = contrastFactor * clamp((4.0 * (0.75 - brightness)), 0.0, 1.0);
    float a = (coverage * (k + 1.0)) / ((coverage * k) + 1.0);
    float correction = (((ratios.x * brightness) + ratios.y) * a) + ((ratios.z * brightness) + ratios.w);
    return a + ((a * (1.0 - a)) * correction);
}
void main() {
    vec2 uvDx = dFdx(uv);
    vec2 uvDy = dFdy(uv);
    vec4 d = clipDistance;
    if (min(min(d.x, d.y), min(d.z, d.w)) < 0.0) {
        discard;
    }
    vec4 meta = gradientMeta;
    vec4 params = gradientParams;
    int gradientKind = int(meta.x + 0.5);
    vec4 texel = vec4(0.0);
    if ((gradientKind == 1) || (gradientKind == 2)) {
        float t = (gradientKind == 1) ? clamp(uv.x, 0.0, 1.0) : clamp(length(uv), 0.0, 1.0);
        texel = gradientAt(t);
        if (meta.z > 0.5) {
            texel = vec4(ditherRgb(texel.xyz, pixel), texel.w);
        }
    } else if (gradientKind == 3) {
        float spacing = max(params.x, 1.0);
        float width = clamp(params.y, 0.0, spacing);
        float diagonal = uv.x + uv.y;
        diagonal += fwidth(diagonal) * PATTERN_TIE_BIAS;
        texel = (floorMod(diagonal, spacing) < width) ? gradientColor1 : gradientColor0;
    } else if (gradientKind == 4) {
        float cell = max(params.x, 1.0);
        vec2 at = uv + (fwidth(uv) * PATTERN_TIE_BIAS);
        float parity = floorMod((floor((at.x / cell)) + floor((at.y / cell))), 2.0);
        texel = (parity < 1.0) ? gradientColor0 : gradientColor1;
    } else {
        texel = texture(sampler2D(tex, smp), uv);
        if (sourceParams.x > 0.5) {
            texel = vec4(((texel.w > 0.0) ? (texel.xyz / texel.w) : vec3(0.0)), texel.w);
        }
        if (coverageTexture > 0.5) {
            float coverage = texel.x;
            if (coverageTexture > 1.5) {
                vec2 pageSize = vec2(textureSize(sampler2D(tex, smp), 0));
                coverage = sdfCoverage(coverage, sdfTexelsPerPixel(uvDx, uvDy, pageSize));
            }
            float gamma = applyContrastAndGamma(coverage, color.xyz, textParams.x, gammaRatios);
            texel = vec4(1.0, 1.0, 1.0, gamma);
        }
    }
    vec4 key = colorKey;
    if (key.w > 0.5) {
        vec3 kd = abs((texel.xyz - key.xyz));
        if (((kd.x + kd.y) + kd.z) < 0.08) {
            texel.w = 0.0;
        }
    }
    vec4 c = texel * color;
    c = vec4(mix(c.xyz, (c.xyz * color.w), srcPremult), c.w);
    c = colorMatrix * c;
    c = c + colorAdd;
    vec4 premult = vec4((c.xyz * c.w), c.w);
    fragColor = mix(premult, c, srcPremult);
    return;
}
@end

@vs spriteVs
layout(binding=0) uniform sprite_params {
    vec4 viewport;
    vec4 clipU;
    vec4 clipV;
    vec4 shift;
};
in vec2 corner;
in vec4 iAffine;
in vec4 iOriginSize;
in vec4 iUv;
in vec4 iColor;
out vec2 uv;
out vec4 color;
out float srcPremult;
out vec4 clipDistance;
vec4 clipDistanceOf(vec2 world, vec4 clipU_1, vec4 clipV_1) {
    if (clipU_1.w > clipU_1.z) {
        float cu = dot(world, clipU_1.xy);
        float cv = dot(world, clipV_1.xy);
        return vec4((cu - clipU_1.z), (clipU_1.w - cu), (cv - clipV_1.z), (clipV_1.w - cv));
    }
    return vec4(1.0);
}
void main() {
    vec2 local = corner * iOriginSize.zw;
    vec2 world = vec2((((iAffine.x * local.x) + (iAffine.z * local.y)) + iOriginSize.x), (((iAffine.y * local.x) + (iAffine.w * local.y)) + iOriginSize.y));
    vec4 viewport_1 = viewport;
    vec2 moved = world + shift.xy;
    vec2 ndc = vec2((((moved.x / viewport_1.x) * 2.0) - 1.0), (1.0 - ((moved.y / viewport_1.y) * 2.0)));
    vec2 t = mix(iUv.xy, iUv.zw, corner);
    uv = ((viewport_1.z > 0.5) ? vec2(t.x, (1.0 - t.y)) : t);
    color = iColor;
    srcPremult = viewport_1.w;
    clipDistance = clipDistanceOf(world, clipU, clipV);
    gl_Position = vec4(ndc, 0.0, 1.0);
    return;
}
@end

@fs spriteFs
layout(binding=0) uniform texture2D spriteTex;
layout(binding=0) uniform sampler spriteSmp;
in vec2 uv;
in vec4 color;
in float srcPremult;
in vec4 clipDistance;
layout(location=0) out vec4 fragColor;
void main() {
    vec4 d = clipDistance;
    if (min(min(d.x, d.y), min(d.z, d.w)) < 0.0) {
        discard;
    }
    vec4 c = texture(sampler2D(spriteTex, spriteSmp), uv) * color;
    vec4 straight = vec4(mix(c.xyz, (c.xyz * color.w), srcPremult), c.w);
    vec4 premult = vec4((straight.xyz * straight.w), straight.w);
    fragColor = mix(premult, straight, srcPremult);
    return;
}
@end

@vs uiVs
layout(binding=0) uniform ui_params {
    vec4 viewport;
    vec4 clipU;
    vec4 clipV;
    vec4 shift;
};
in vec2 corner;
in vec4 iAffine;
in vec4 iOriginSize;
in vec4 iUvRadii;
in vec4 iBorders;
in vec4 iParams0;
in vec4 iParams1;
in vec4 iColorFill;
in vec4 iColorBorder;
in vec4 iColorExtra;
out vec4 vLocalHalf;
out vec4 vUvAa;
out vec4 vRadii;
out vec4 vBorders;
out vec3 vParams0;
out vec4 vParams1;
out vec4 vFill;
out vec4 vBorder;
out vec4 vExtra;
out vec4 clipDistance;
out vec2 vPixel;
float floorMod(float x, float y) {
    return x - (y * floor((x / y)));
}
float dilateStroke(float width, float pixelsPerLocal) {
    if ((width <= 0.0) || (pixelsPerLocal <= 0.0)) {
        return 0.0;
    }
    return max(width, (1.0 / pixelsPerLocal));
}
vec3 linearToOklab(vec3 c) {
    vec3 lms = vec3((((0.4122214708 * c.x) + (0.5363325363 * c.y)) + (0.0514459929 * c.z)), (((0.2119034982 * c.x) + (0.6806995451 * c.y)) + (0.1073969566 * c.z)), (((0.0883024619 * c.x) + (0.2817188376 * c.y)) + (0.6299787005 * c.z)));
    lms = sign(lms) * pow(abs(lms), vec3(0.3333333333333333));
    return vec3((((0.2104542553 * lms.x) + (0.793617785 * lms.y)) - (0.0040720468 * lms.z)), (((1.9779984951 * lms.x) - (2.428592205 * lms.y)) + (0.4505937099 * lms.z)), (((0.0259040371 * lms.x) + (0.7827717662 * lms.y)) - (0.808675766 * lms.z)));
}
vec3 srgbToLinear(vec3 c) {
    vec3 lo = c / 12.92;
    vec3 hi = pow(((c + vec3(0.055)) / 1.055), vec3(2.4));
    return vec3(((c.x <= 0.04045) ? lo.x : hi.x), ((c.y <= 0.04045) ? lo.y : hi.y), ((c.z <= 0.04045) ? lo.z : hi.z));
}
vec4 clipDistanceOf(vec2 world, vec4 clipU_1, vec4 clipV_1) {
    if (clipU_1.w > clipU_1.z) {
        float cu = dot(world, clipU_1.xy);
        float cv = dot(world, clipV_1.xy);
        return vec4((cu - clipU_1.z), (clipU_1.w - cu), (cv - clipV_1.z), (clipV_1.w - cv));
    }
    return vec4(1.0);
}
void main() {
    vec4 viewport_1 = viewport;
    float mode = iParams0.x;
    float sx = length(iAffine.xy) * viewport_1.w;
    float sy = length(iAffine.zw) * viewport_1.w;
    float s = sqrt((sx * sy));
    float aa = (mode == 2.0) ? 0.0 : ((s > 0.0) ? (1.0 / s) : 0.0);
    vec2 size = iOriginSize.zw;
    vec2 inflate = (mode == 5.0) ? vec2(aa, 0.0) : vec2(aa);
    vec2 local = (corner * (size + (2.0 * inflate))) - inflate;
    vec2 world = vec2((((iAffine.x * local.x) + (iAffine.z * local.y)) + iOriginSize.x), (((iAffine.y * local.x) + (iAffine.w * local.y)) + iOriginSize.y));
    vec2 moved = world + shift.xy;
    vec2 ndc = vec2((((moved.x / viewport_1.x) * 2.0) - 1.0), (1.0 - ((moved.y / viewport_1.y) * 2.0)));
    vec4 clip = vec4(ndc, 0.0, 1.0);
    vec2 t = mix(iUvRadii.xy, iUvRadii.zw, (((size.x > 0.0) && (size.y > 0.0)) ? (local / size) : vec2(0.0)));
    vec4 borders = iBorders;
    bool oklabFill = (((mode == 0.0) && (iParams0.z > 0.5)) && (iParams0.z < 1.5)) && (floorMod(iParams0.w, 2.0) > 0.5);
    vec4 fill = iColorFill;
    vec4 extra = iColorExtra;
    vLocalHalf = vec4((local - (size * 0.5)), (size * 0.5));
    vUvAa = vec4(((viewport_1.z > 0.5) ? vec2(t.x, (1.0 - t.y)) : t), aa, mode);
    vRadii = ((mode == 2.0) ? vec4(0.0) : iUvRadii);
    vBorders = ((mode == 0.0) ? vec4(dilateStroke(borders.x, sx), dilateStroke(borders.y, sy), dilateStroke(borders.z, sx), dilateStroke(borders.w, sy)) : borders);
    vParams0 = iParams0.yzw;
    vParams1 = iParams1;
    vFill = (oklabFill ? vec4(linearToOklab(srgbToLinear(fill.xyz)), fill.w) : fill);
    vBorder = iColorBorder;
    vExtra = (oklabFill ? vec4(linearToOklab(srgbToLinear(extra.xyz)), extra.w) : extra);
    clipDistance = clipDistanceOf(world, clipU, clipV);
    vPixel = (moved * viewport_1.w);
    gl_Position = clip;
    return;
}
@end

@fs uiFs
layout(binding=0) uniform texture2D uiTex;
layout(binding=0) uniform sampler uiSmp;
layout(binding=1) uniform ui_fx {
    vec4 gammaRatios;
    vec4 textParams;
    mat4 colorMatrix;
    vec4 colorAdd;
    vec4 colorKey;
    vec4 effectParams;
};
in vec4 vLocalHalf;
in vec4 vUvAa;
in vec4 vRadii;
in vec4 vBorders;
in vec3 vParams0;
in vec4 vParams1;
in vec4 vFill;
in vec4 vBorder;
in vec4 vExtra;
in vec4 clipDistance;
in vec2 vPixel;
layout(location=0) out vec4 fragColor;
float coverageFromDistance(float d, float aa) {
    if (aa <= 0.0) {
        return (d <= 0.0) ? 1.0 : 0.0;
    }
    return clamp((0.5 - (d / aa)), 0.0, 1.0);
}
float roundedRectDistance(vec2 p, vec2 half_1, float r) {
    float rr = clamp(r, 0.0, min(half_1.x, half_1.y));
    vec2 q = abs(p) - (half_1 - rr);
    return (length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0)) - rr;
}
float cornerRadius(vec2 p, vec4 radii) {
    return (p.x < 0.0) ? ((p.y < 0.0) ? radii.x : radii.w) : ((p.y < 0.0) ? radii.y : radii.z);
}
vec4 withEffect(vec4 p, vec3 keyTexel) {
    if ((effectParams.x < 0.5) || (p.w <= 0.0)) {
        return p;
    }
    vec4 s = vec4((p.xyz / p.w), p.w);
    vec4 key = colorKey;
    if (key.w > 0.5) {
        vec3 d = abs((keyTexel - key.xyz));
        if (((d.x + d.y) + d.z) < 0.08) {
            s.w = 0.0;
        }
    }
    s = (colorMatrix * s) + colorAdd;
    return vec4((s.xyz * s.w), s.w);
}
float underlineDistance(vec2 p, vec2 half_1, vec4 shape) {
    float thickness = shape.x;
    if (shape.y > 0.5) {
        float height = half_1.y * 2.0;
        float frequency = (6.283185307179586 * thickness) / height;
        float amplitude = (thickness * 0.8) / height;
        float phase = ((p.x + half_1.x) / height) * frequency;
        float slope = (cos(phase) * amplitude) * frequency;
        float distance_1 = (((p.y / height) - (sin(phase) * amplitude)) * height) / sqrt((1.0 + (slope * slope)));
        return abs(distance_1) - (thickness * 0.5);
    }
    return roundedRectDistance(p, half_1, 0.0);
}
float smoothUnionDistance(float a, float b, float k) {
    if (k <= 0.0) {
        return min(a, b);
    }
    float h = clamp((0.5 + ((0.5 * (a - b)) / k)), 0.0, 1.0);
    return mix(a, b, h) - ((k * h) * (1.0 - h));
}
float scanlineHalf(float hx, float hy, float ay, float r) {
    float dy = ay - (hy - r);
    float under = (r * r) - (dy * dy);
    float chord = ((dy > 0.0) && (under > 0.0)) ? sqrt(under) : r;
    return (hx - r) + chord;
}
float erfApprox(float x) {
    float s = sign(x);
    float a = abs(x);
    float r1 = 1.0 + ((0.278393 + ((0.230389 + ((0.000972 + (0.078108 * a)) * a)) * a)) * a);
    float r2 = r1 * r1;
    return s - (s / (r2 * r2));
}
float gaussianPdf(float x, float sigma) {
    return exp(((-(x * x)) / ((2.0 * sigma) * sigma))) / (sqrt(6.283185307179586) * sigma);
}
float blurredCoverage(vec2 c, vec2 half_1, vec4 rr, float sigma) {
    float low = c.y - half_1.y;
    float high = c.y + half_1.y;
    float start = clamp((float(-3.0) * sigma), low, high);
    float end = clamp((3.0 * sigma), low, high);
    float stepY = (end - start) / 4.0;
    float k = sqrt(0.5) / sigma;
    float acc = 0.0;
    float y = start + (stepY * 0.5);
    for (int i = 0; i < 4; i++) {
        float scanY = c.y - y;
        float ay = abs(scanY);
        float wL = scanlineHalf(half_1.x, half_1.y, ay, ((scanY < 0.0) ? rr.x : rr.w));
        float wR = scanlineHalf(half_1.x, half_1.y, ay, ((scanY < 0.0) ? rr.y : rr.z));
        float hi = 0.5 + (0.5 * erfApprox(((c.x + wL) * k)));
        float lo = 0.5 + (0.5 * erfApprox(((c.x - wR) * k)));
        acc += ((hi - lo) * gaussianPdf(y, sigma)) * stepY;
        y += stepY;
    }
    return acc;
}
float shadowCoverage(vec2 p, vec2 half_1, vec4 radii, vec2 offset, float sigma, float aa) {
    vec4 rr = clamp(radii, vec4(0.0), vec4(min(half_1.x, half_1.y)));
    vec2 c = p - offset;
    float coverage = 0.0;
    if (sigma <= 0.0) {
        coverage = coverageFromDistance(roundedRectDistance(c, half_1, cornerRadius(c, rr)), aa);
    } else {
        coverage = blurredCoverage(c, half_1, rr, sigma);
    }
    return coverage;
}
float cornerDashVelocity(float first, float second) {
    if (first == 0.0) {
        return second;
    }
    if (second == 0.0) {
        return first;
    }
    return min(first, second);
}
float floorMod(float x, float y) {
    return x - (y * floor((x / y)));
}
float dashAlpha(float t, float period, float dashLength, float velocity, float aa) {
    if (velocity <= 0.0) {
        return 0.0;
    }
    float halfPeriod = period * 0.5;
    float halfLength = dashLength * 0.5;
    float centered = floorMod(((t + halfPeriod) - halfLength), period) - halfPeriod;
    return coverageFromDistance(((abs(centered) - halfLength) / velocity), aa);
}
float dashedBorderAlpha(vec2 p, vec2 half_1, vec4 rawRadii, vec4 borders, float aa) {
    vec4 radii = clamp(rawRadii, vec4(0.0), vec4(min(half_1.x, half_1.y)));
    vec2 size = half_1 * 2.0;
    vec2 point = p + half_1;
    float radius = cornerRadius(p, radii);
    vec2 cornerDelta = abs(p) - (half_1 - vec2(radius));
    bool unrounded = (((radii.x == 0.0) && (radii.y == 0.0)) && (radii.z == 0.0)) && (radii.w == 0.0);
    bool horizontal = cornerDelta.x < cornerDelta.y;
    float dashLength = 0.6666666666666666;
    float velocity = 0.0;
    float t = 0.0;
    float maxT = 0.0;
    bool noBorder = false;
    if (unrounded) {
        float width = horizontal ? max(borders.y, borders.w) : max(borders.x, borders.z);
        noBorder = width <= 0.0;
        if (!noBorder) {
            velocity = 1.0 / (3.0 * width);
            t = (horizontal ? point.x : point.y) * velocity;
            maxT = ((horizontal ? size.x : size.y) * velocity) - dashLength;
        }
    } else {
        float dvT = (borders.y > 0.0) ? (1.0 / (3.0 * borders.y)) : 0.0;
        float dvR = (borders.z > 0.0) ? (1.0 / (3.0 * borders.z)) : 0.0;
        float dvB = (borders.w > 0.0) ? (1.0 / (3.0 * borders.w)) : 0.0;
        float dvL = (borders.x > 0.0) ? (1.0 / (3.0 * borders.x)) : 0.0;
        float sT = ((size.x - radii.x) - radii.y) * dvT;
        float sR = ((size.y - radii.y) - radii.z) * dvR;
        float sB = ((size.x - radii.z) - radii.w) * dvB;
        float sL = ((size.y - radii.w) - radii.x) * dvL;
        float cvTR = cornerDashVelocity(dvT, dvR);
        float cvBR = cornerDashVelocity(dvB, dvR);
        float cvBL = cornerDashVelocity(dvB, dvL);
        float cvTL = cornerDashVelocity(dvT, dvL);
        float quarterPi = 1.5707963267948966;
        float cTR = (radii.y * quarterPi) * cvTR;
        float cBR = (radii.z * quarterPi) * cvBR;
        float cBL = (radii.w * quarterPi) * cvBL;
        float cTL = (radii.x * quarterPi) * cvTL;
        float uptoTR = sT;
        float uptoR = uptoTR + cTR;
        float uptoBR = uptoR + sR;
        float uptoB = uptoBR + cBR;
        float uptoBL = uptoB + sB;
        float uptoL = uptoBL + cBL;
        float uptoTL = uptoL + sL;
        maxT = uptoTL + cTL;
        if ((cornerDelta.x > 0.0) && (cornerDelta.y > 0.0)) {
            float angle = atan(cornerDelta.y, cornerDelta.x);
            if (p.x >= 0.0) {
                if (p.y < 0.0) {
                    velocity = cvTR;
                    t = uptoR - ((angle * radii.y) * velocity);
                } else {
                    velocity = cvBR;
                    t = uptoBR + ((angle * radii.z) * velocity);
                }
            } else {
                if (p.y >= 0.0) {
                    velocity = cvBL;
                    t = uptoL - ((angle * radii.w) * velocity);
                } else {
                    velocity = cvTL;
                    t = uptoTL + ((angle * radii.x) * velocity);
                }
            }
        } else if (horizontal) {
            if (p.y < 0.0) {
                velocity = dvT;
                t = (point.x - radii.x) * velocity;
            } else {
                velocity = dvB;
                t = uptoBL - ((point.x - radii.w) * velocity);
            }
        } else {
            if (p.x < 0.0) {
                velocity = dvL;
                t = uptoTL - ((point.y - radii.x) * velocity);
            } else {
                velocity = dvR;
                t = uptoR + ((point.y - radii.y) * velocity);
            }
        }
    }
    float alpha = 1.0;
    if (noBorder) {
        alpha = 0.0;
    } else if (maxT >= 1.0) {
        alpha = dashAlpha(t, (maxT / floor(maxT)), dashLength, velocity, aa);
    } else if (unrounded && ((maxT - dashLength) > 0.0)) {
        alpha = dashAlpha(t, maxT, dashLength, velocity, aa);
    }
    return alpha;
}
vec3 linearToSrgb(vec3 c) {
    vec3 lo = c * 12.92;
    vec3 hi = (vec3(1.055) * pow(max(c, vec3(0.0)), vec3(0.4166666666666667))) - vec3(0.055);
    return vec3(((c.x <= 0.0031308) ? lo.x : hi.x), ((c.y <= 0.0031308) ? lo.y : hi.y), ((c.z <= 0.0031308) ? lo.z : hi.z));
}
vec3 oklabToLinear(vec3 c) {
    vec3 lms = vec3(((c.x + (0.3963377774 * c.y)) + (0.2158037573 * c.z)), ((c.x - (0.1055613458 * c.y)) - (0.0638541728 * c.z)), ((c.x - (0.0894841775 * c.y)) - (1.291485548 * c.z)));
    lms = (lms * lms) * lms;
    return vec3((((4.0767416621 * lms.x) - (3.3077115913 * lms.y)) + (0.2309699292 * lms.z)), (((-1.2684380046 * lms.x) + (2.6097574011 * lms.y)) - (0.3413193965 * lms.z)), (((-0.0041960863 * lms.x) - (0.7034186147 * lms.y)) + (1.707614701 * lms.z)));
}
float bayer4(vec2 pixel) {
    int x = int(floorMod(floor(pixel.x), 4.0));
    int y = int(floorMod(floor(pixel.y), 4.0));
    if (y == 0) {
        if (x == 0) {
            return 0.0;
        }
        if (x == 1) {
            return 8.0;
        }
        if (x == 2) {
            return 2.0;
        }
        return 10.0;
    }
    if (y == 1) {
        if (x == 0) {
            return 12.0;
        }
        if (x == 1) {
            return 4.0;
        }
        if (x == 2) {
            return 14.0;
        }
        return 6.0;
    }
    if (y == 2) {
        if (x == 0) {
            return 3.0;
        }
        if (x == 1) {
            return 11.0;
        }
        if (x == 2) {
            return 1.0;
        }
        return 9.0;
    }
    if (x == 0) {
        return 15.0;
    }
    if (x == 1) {
        return 7.0;
    }
    if (x == 2) {
        return 13.0;
    }
    return 5.0;
}
vec3 ditherRgb(vec3 rgb, vec2 pixel) {
    float noise = (bayer4(pixel) - 7.5) * 0.0010457516339869282;
    return clamp((rgb + vec3(noise)), vec3(0.0), vec3(1.0));
}
vec4 overCoverage(vec4 a, vec4 b, float coverage) {
    float alpha = (a.w * coverage) + (b.w * (1.0 - coverage));
    vec3 rgb = (a.xyz * (a.w * coverage)) + (b.xyz * (b.w * (1.0 - coverage)));
    return vec4(((alpha > 0.0) ? (rgb / alpha) : vec3(0.0)), alpha);
}
const float PATTERN_TIE_BIAS = 0.015625;
vec4 boxFillAt(vec2 p, vec2 half_1, float aa) {
    int kind = int(vParams0.y + 0.5);
    vec4 params = vParams1;
    vec2 corner = p + half_1;
    if (kind == 1) {
        float angle = (floorMod(params.x, 360.0) - 90.0) * 0.017453292519943295;
        vec2 direction = vec2(cos(angle), sin(angle));
        vec2 size = max((half_1 * 2.0), vec2(0.000001));
        if (size.x > size.y) {
            direction.y *= size.y / size.x;
        } else {
            direction.x *= size.x / size.y;
        }
        float t = dot(p, direction) / length(direction);
        t = (abs(direction.x) > abs(direction.y)) ? ((t + half_1.x) / size.x) : ((t + half_1.y) / size.y);
        float span = params.z - params.y;
        t = (span > 0.0) ? clamp(((t - params.y) / span), 0.0, 1.0) : step(params.y, t);
        vec4 c = mix(vFill, vExtra, t);
        if (floorMod(vParams0.z, 2.0) > 0.5) {
            c = vec4(linearToSrgb(oklabToLinear(c.xyz)), c.w);
        }
        if (vParams0.z > 1.5) {
            c = vec4(ditherRgb(c.xyz, vPixel), c.w);
        }
        return c;
    }
    if (kind == 2) {
        float height = params.x + params.y;
        float period = height * 0.7071067811865476;
        float pattern = floorMod(((corner.x + corner.y) * 0.7071067811865476), period);
        float distance_1 = min(pattern, (period - pattern)) - ((period * (params.x / height)) * 0.5);
        return overCoverage(vFill, vExtra, coverageFromDistance(distance_1, aa));
    }
    vec2 cell = floor(((corner + vec2((aa * PATTERN_TIE_BIAS))) / params.x));
    return (floorMod((cell.x + cell.y), 2.0) > 0.5) ? vFill : vExtra;
}
const float SDF_EDGE = 0.7490196078431373;
const float SDF_RADIUS = 8.0;
float sdfCoverage(float sampled, float texelsPerPixel) {
    float texels = (sampled - SDF_EDGE) * SDF_RADIUS;
    return clamp(((texels / texelsPerPixel) + 0.5), 0.0, 1.0);
}
float sdfTexelsPerPixel(vec2 uvDx, vec2 uvDy, vec2 pageSize) {
    return max((0.5 * (length((uvDx * pageSize)) + length((uvDy * pageSize)))), 0.0001);
}
float applyContrastAndGamma(float coverage, vec3 color, float contrastFactor, vec4 ratios) {
    float brightness = dot(color, vec3(0.3, 0.59, 0.11));
    float k = contrastFactor * clamp((4.0 * (0.75 - brightness)), 0.0, 1.0);
    float a = (coverage * (k + 1.0)) / ((coverage * k) + 1.0);
    float correction = (((ratios.x * brightness) + ratios.y) * a) + ((ratios.z * brightness) + ratios.w);
    return a + ((a * (1.0 - a)) * correction);
}
void main() {
    vec2 uvDx = dFdx(vUvAa.xy);
    vec2 uvDy = dFdy(vUvAa.xy);
    vec4 d = clipDistance;
    if (min(min(d.x, d.y), min(d.z, d.w)) < 0.0) {
        discard;
    }
    vec2 p = vLocalHalf.xy;
    vec2 half_1 = vLocalHalf.zw;
    float aa = vUvAa.z;
    int mode = int(vUvAa.w + 0.5);
    if (mode == 3) {
        vec4 radii = clamp(vBorders, vec4(0.0), vec4(min(half_1.x, half_1.y)));
        float coverage = coverageFromDistance(roundedRectDistance(p, half_1, cornerRadius(p, radii)), aa);
        vec4 texel = texture(sampler2D(uiTex, uiSmp), vUvAa.xy);
        vec3 keyTexel = ((vParams1.y > 0.5) && (texel.w > 0.0)) ? (texel.xyz / texel.w) : texel.xyz;
        if (vParams1.x > 0.5) {
            float gray = dot(texel.xyz, vec3(0.2126, 0.7152, 0.0722));
            texel = vec4(vec3(gray), texel.w);
        }
        vec4 fill = texel * vFill;
        float alpha = fill.w * coverage;
        vec3 rgb = (vParams1.y > 0.5) ? (fill.xyz * (vFill.w * coverage)) : (fill.xyz * alpha);
        fragColor = withEffect(vec4(rgb, alpha), keyTexel);
        return;
    }
    if (mode == 4) {
        float coverage_1 = coverageFromDistance(underlineDistance(p, half_1, vBorders), aa);
        float alpha_1 = vFill.w * coverage_1;
        fragColor = withEffect(vec4((vFill.xyz * alpha_1), alpha_1), vec3(1.0));
        return;
    }
    if (mode == 5) {
        vec2 boxHalf = vBorders.xy;
        float radius = vBorders.z;
        float gloopiness = vBorders.w;
        vec4 params = vParams1;
        float distance_1 = roundedRectDistance(p, boxHalf, radius);
        if (params.y > 0.0) {
            vec2 prevCenter = vec2(((params.x + (params.y * 0.5)) - boxHalf.x), ((-boxHalf.y) * 2.0));
            float prev = roundedRectDistance((p - prevCenter), vec2((params.y * 0.5), boxHalf.y), radius);
            distance_1 = smoothUnionDistance(distance_1, prev, gloopiness);
        }
        if (params.w > 0.0) {
            vec2 nextCenter = vec2(((params.z + (params.w * 0.5)) - boxHalf.x), (boxHalf.y * 2.0));
            float next = roundedRectDistance((p - nextCenter), vec2((params.w * 0.5), boxHalf.y), radius);
            distance_1 = smoothUnionDistance(distance_1, next, gloopiness);
        }
        float coverage_2 = coverageFromDistance(distance_1, aa);
        float alpha_2 = vFill.w * coverage_2;
        fragColor = withEffect(vec4((vFill.xyz * alpha_2), alpha_2), vec3(1.0));
        return;
    }
    vec4 extra = vExtra;
    vec4 radiiIn = vRadii;
    if (mode == 1) {
        vec2 halfBox = vBorders.xy;
        float sigma = vBorders.z;
        float spread = vParams1.z;
        float alpha_3 = 0.0;
        if (vBorders.w > 0.5) {
            float blur = shadowCoverage(p, max((halfBox - vec2(spread)), vec2(0.0)), max((radiiIn - vec4(spread)), vec4(0.0)), vParams1.xy, sigma, aa);
            alpha_3 = (1.0 - blur) * coverageFromDistance(roundedRectDistance(p, halfBox, cornerRadius(p, radiiIn)), aa);
        } else {
            vec2 offset = vParams1.xy;
            alpha_3 = shadowCoverage(p, (halfBox + vec2(spread)), radiiIn, offset, sigma, aa);
        }
        fragColor = withEffect(vec4((extra.xyz * (extra.w * alpha_3)), (extra.w * alpha_3)), vec3(1.0));
        return;
    }
    vec2 halfBox_1 = half_1;
    bool filled = (mode == 0) && (vParams0.y > 0.5);
    bool shadowed = (!filled) && (extra.w > 0.0);
    if (shadowed && (vParams1.w <= 0.5)) {
        halfBox_1 = half_1 - (vec2((3.0 * vParams1.z)) + abs(vParams1.xy));
    }
    float r = cornerRadius(p, radiiIn);
    float dOuter = roundedRectDistance(p, halfBox_1, r);
    vec4 borders = max(vBorders, vec4(0.0));
    vec2 inset = vec2((borders.x + borders.z), (borders.y + borders.w)) * 0.5;
    vec2 shift = vec2((borders.x - borders.z), (borders.y - borders.w)) * 0.5;
    vec4 innerRadii = max((radiiIn - vec4(max(borders.x, borders.y), max(borders.y, borders.z), max(borders.z, borders.w), max(borders.w, borders.x))), vec4(0.0));
    vec2 innerPoint = p - shift;
    float dInner = roundedRectDistance(innerPoint, max((halfBox_1 - inset), vec2(0.0)), cornerRadius(innerPoint, innerRadii));
    float outer = coverageFromDistance(dOuter, aa);
    float inner = coverageFromDistance(dInner, aa);
    float ring = max((outer - inner), 0.0);
    if ((mode != 2) && (vParams0.x > 0.5)) {
        ring *= dashedBorderAlpha(p, halfBox_1, radiiIn, borders, aa);
    }
    vec4 fill_1 = filled ? boxFillAt(p, halfBox_1, aa) : vFill;
    if (mode == 2) {
        float coverage_3 = texture(sampler2D(uiTex, uiSmp), vUvAa.xy).x;
        if (vParams0.x > 0.5) {
            vec2 pageSize = vec2(textureSize(sampler2D(uiTex, uiSmp), 0));
            coverage_3 = sdfCoverage(coverage_3, sdfTexelsPerPixel(uvDx, uvDy, pageSize));
        }
        fill_1.w = fill_1.w * applyContrastAndGamma(coverage_3, fill_1.xyz, textParams.x, gammaRatios);
    }
    vec4 border = vBorder;
    vec2 offset_1 = vParams1.xy;
    float alpha_4 = (fill_1.w * inner) + (border.w * ring);
    vec3 rgb_1 = (fill_1.xyz * (fill_1.w * inner)) + (border.xyz * (border.w * ring));
    if (shadowed && (vParams1.w > 0.5)) {
        float blurCov = shadowCoverage(p, halfBox_1, radiiIn, offset_1, vParams1.z, aa);
        float sAlpha = ((1.0 - blurCov) * outer) * extra.w;
        float fillAlpha = fill_1.w * inner;
        vec3 under = (extra.xyz * sAlpha) + ((fill_1.xyz * fillAlpha) * (1.0 - sAlpha));
        float underAlpha = sAlpha + (fillAlpha * (1.0 - sAlpha));
        float ringAlpha = border.w * ring;
        rgb_1 = (border.xyz * ringAlpha) + (under * (1.0 - ringAlpha));
        alpha_4 = ringAlpha + (underAlpha * (1.0 - ringAlpha));
    } else if (shadowed) {
        float sAlpha_1 = shadowCoverage(p, halfBox_1, radiiIn, offset_1, vParams1.z, aa) * extra.w;
        rgb_1 = rgb_1 + ((extra.xyz * sAlpha_1) * (1.0 - alpha_4));
        alpha_4 = alpha_4 + (sAlpha_1 * (1.0 - alpha_4));
    }
    fragColor = withEffect(vec4(rgb_1, alpha_4), vec3(1.0));
    return;
}
@end

@vs blurVs
in vec2 pos;
in vec2 uv0;
out vec2 uv;
void main() {
    uv = uv0;
    gl_Position = vec4(pos, 0.0, 1.0);
    return;
}
@end

@fs blurFs
layout(binding=0) uniform texture2D srcTex;
layout(binding=0) uniform sampler srcSmp;
layout(binding=0) uniform blur_params {
    vec4 dir;
};
in vec2 uv;
layout(location=0) out vec4 fragColor;
void main() {
    vec2 step_1 = dir.xy;
    vec2 o1 = step_1 * 1.384615;
    vec2 o2 = step_1 * 3.230769;
    vec4 sum = texture(sampler2D(srcTex, srcSmp), uv) * 0.227027;
    sum += texture(sampler2D(srcTex, srcSmp), (uv + o1)) * 0.316216;
    sum += texture(sampler2D(srcTex, srcSmp), (uv - o1)) * 0.316216;
    sum += texture(sampler2D(srcTex, srcSmp), (uv + o2)) * 0.07027;
    sum += texture(sampler2D(srcTex, srcSmp), (uv - o2)) * 0.07027;
    fragColor = sum;
    return;
}
@end

