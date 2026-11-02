@block fxaaFilter
// Heaps pass/FXAA.hx filters raw RGB and keeps center alpha. Do not infer premultiplied
// target correctness; caller supplies same-origin UV, positive reciprocal size and sampling.
vec4 fxaaFilterRaw(texture2D colorTexture, sampler colorSampler, vec2 uv, vec2 delta) {
	vec3 nw = texture(sampler2D(colorTexture, colorSampler), uv + vec2(-1.0, -1.0) * delta).rgb;
	vec3 ne = texture(sampler2D(colorTexture, colorSampler), uv + vec2(1.0, -1.0) * delta).rgb;
	vec3 sw = texture(sampler2D(colorTexture, colorSampler), uv + vec2(-1.0, 1.0) * delta).rgb;
	vec3 se = texture(sampler2D(colorTexture, colorSampler), uv + vec2(1.0, 1.0) * delta).rgb;
	vec4 origin = texture(sampler2D(colorTexture, colorSampler), uv);
	vec3 luma = vec3(0.299, 0.587, 0.114);
	float lumNW = dot(nw, luma);
	float lumNE = dot(ne, luma);
	float lumSW = dot(sw, luma);
	float lumSE = dot(se, luma);
	float lumMid = dot(origin.rgb, luma);
	float lumMin = min(lumMid, min(min(lumNW, lumNE), min(lumSW, lumSE)));
	float lumMax = max(lumMid, max(max(lumNW, lumNE), max(lumSW, lumSE)));
	vec2 dir = vec2(-((lumNW + lumNE) - (lumSW + lumSE)),
		(lumNW + lumSW) - (lumNE + lumSE));
	float dirReduce = max((lumNW + lumNE + lumSW + lumSE) * (0.25 / 128.0), 1.0 / 8.0);
	float rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
	dir = min(vec2(8.0), max(vec2(-8.0), dir * rcpDirMin)) * delta;
	vec3 rgbA = 0.5 * (
		texture(sampler2D(colorTexture, colorSampler), uv + dir * (1.0 / 3.0 - 0.5)).rgb +
		texture(sampler2D(colorTexture, colorSampler), uv + dir * (2.0 / 3.0 - 0.5)).rgb);
	vec3 rgbB = rgbA * 0.5 + 0.25 * (
		texture(sampler2D(colorTexture, colorSampler), uv + dir * -0.5).rgb +
		texture(sampler2D(colorTexture, colorSampler), uv + dir * 0.5).rgb);
	float lumB = dot(rgbB, luma);
	float weight = (lumB > lumMin && lumB < lumMax) ? 1.0 : 0.0;
	return vec4(mix(rgbA, rgbB, weight), origin.a);
}
@end
