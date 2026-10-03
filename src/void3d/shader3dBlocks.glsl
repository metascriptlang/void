@block vertexUniforms
layout(binding=0) uniform vertexParams {
    mat4 viewProj;
    vec4 cameraRight;
    vec4 cameraUp;
};
@end

@block modelUniforms
layout(binding=4) uniform modelParams {
    mat4 model;
    mat4 normalModel;
};
@end

@block quadCorner
// h3d.parts.Particles' quad, ±0.5 around the instance, two triangles, read by the vertex index
// with no buffer behind it; Bevy's sprite.wgsl makes its four corners from the index's bits.
const vec2 QUAD_CORNERS[6] = vec2[6](
    vec2(-0.5, -0.5), vec2(0.5, -0.5), vec2(0.5, 0.5),
    vec2(-0.5, -0.5), vec2(0.5, 0.5), vec2(-0.5, 0.5));
@end

@block billboardPoint
vec3 billboardPoint(vec3 position, vec2 size, vec2 anchor, vec2 corner) {
    vec2 offset = corner - anchor;
    return position + cameraRight.xyz * (offset.x * size.x) + cameraUp.xyz * (offset.y * size.y);
}
@end

@block billboardUniforms
layout(binding=2) uniform billboardParams {
    vec4 billboardColor;
    vec4 billboard;
};
@end

@block materialUniforms
layout(binding=3) uniform materialParams {
    vec4 material;
};
@end

@block saturation
// h3d.Matrix.colorSaturate in scalar form; campfireGreyCpuCapture holds it to colorSaturated.
vec3 saturated(vec3 rgb, float amount) {
    if (amount == 0.0) {
        return rgb;
    }
    float luma = dot(rgb, vec3(0.212671, 0.71516, 0.072169));
    float keep = amount + 1.0;
    return rgb * keep + vec3(luma * (1.0 - keep));
}
@end

@block colorSpace
// h3d.shader.ColorSpaces' exact pair (ColorSpaces.hx:56-76); bevy_color's gamma_function
// carries the same constants. Colour inputs and stored targets stay gamma-encoded. The pow
// operands clamp at 0 only to keep fxc's X3571 out of consumer stdout: output-neutral, the
// selects route every input a matrix can make negative to the linear branch.
vec3 srgbToLinear(vec3 srgb) {
    vec3 low = srgb * 0.0773993808;
    vec3 high = pow(max(srgb * 0.9478672986 + vec3(0.0521327014), vec3(0.0)), vec3(2.4));
    return vec3(
        srgb.x <= 0.04045 ? low.x : high.x,
        srgb.y <= 0.04045 ? low.y : high.y,
        srgb.z <= 0.04045 ? low.z : high.z);
}

vec3 linearToSrgb(vec3 rgb) {
    vec3 low = rgb * 12.92;
    vec3 high = vec3(1.055) * pow(max(rgb, vec3(0.0)), vec3(0.41666)) - vec3(0.055);
    return vec3(
        rgb.x <= 0.0031308 ? low.x : high.x,
        rgb.y <= 0.0031308 ? low.y : high.y,
        rgb.z <= 0.0031308 ? low.z : high.z);
}
@end

@block facingNormal
// h3d.shader.FlipBackFaceNormal, on when the material says so (glTF doubleSided).
vec3 facingNormal(vec3 normal, float doubleSided) {
    return (doubleSided > 0.5 && !gl_FrontFacing) ? -normal : normal;
}
@end

@block lightUniforms
layout(binding=1) uniform lightParams {
    vec4 ambient;
    vec4 dirLight;
    vec4 dirColor;
    vec4 pointLight[4];
    vec4 pointColor[4];
};

@end
