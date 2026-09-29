@vs gpuCopyVs
in vec2 position;
void main() {
    gl_Position = vec4(position, 0.5, 1.0);
}
@end

@fs gpuCopyFs
layout(binding=0) uniform texture2D sourceTexture;
layout(binding=0) uniform sampler pointSampler;
out vec4 fragColor;
void main() {
    ivec2 size = textureSize(sampler2D(sourceTexture, pointSampler), 0);
    ivec2 pixel = clamp(ivec2(gl_FragCoord.xy), ivec2(0), size - ivec2(1));
    fragColor = vec4(texelFetch(sampler2D(sourceTexture, pointSampler), pixel, 0).rgb, 1.0);
}
@end

@program gpuCopy gpuCopyVs gpuCopyFs
