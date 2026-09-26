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

@block lightUniforms
layout(binding=1) uniform lightParams {
    vec4 ambient;
    vec4 dirLight;
    vec4 dirColor;
    vec4 pointLight[4];
    vec4 pointColor[4];
};

@end
