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
    c = colorMatrix * c;
    c = c + colorAdd;
    vec4 premult = vec4(c.rgb * c.a, c.a);
    frag_color = mix(premult, c, srcPremult);
}
@end

@program void2d vs fs

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
