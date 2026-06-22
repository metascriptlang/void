// Void 2D batcher shader (sokol-shdc dialect).
// Pixel-space verts (pos in framebuffer pixels) → NDC; per-vertex color tint.
@vs vs
layout(binding=0) uniform void2d_params {
    vec4 viewport;   // xy = framebuffer size in pixels (zw unused, pads to 16)
};
in vec2 pos;
in vec2 uv0;
in vec4 color0;
out vec2 uv;
out vec4 color;
void main() {
    vec2 ndc = vec2(pos.x / viewport.x * 2.0 - 1.0, 1.0 - pos.y / viewport.y * 2.0);
    gl_Position = vec4(ndc, 0.0, 1.0);
    uv = uv0;
    color = color0;
}
@end

@fs fs
layout(binding=0) uniform texture2D tex;
layout(binding=0) uniform sampler smp;
in vec2 uv;
in vec4 color;
out vec4 frag_color;
void main() {
    frag_color = texture(sampler2D(tex, smp), uv) * color;
}
@end

@program void2d vs fs
