struct Varyings {
	@builtin(position) position: vec4<f32>,
	@location(0) uv: vec2<f32>,
}

@group(1) @binding(0) var tex: texture_2d<f32>;
@group(1) @binding(1) var smp: sampler;

@vertex
fn vs(@location(0) position: vec2<f32>) -> Varyings {
	var out: Varyings;
	out.position = vec4<f32>(position, 0.0, 1.0);
	out.uv = position * 0.5 + 0.5;
	return out;
}

@fragment
fn fs(input: Varyings) -> @location(0) vec4<f32> {
	return textureSample(tex, smp, input.uv);
}
