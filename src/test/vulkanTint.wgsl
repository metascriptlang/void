struct Tint {
	color: vec4<u32>,
	offset: vec2<i32>,
}

@group(0) @binding(0) var<uniform> tint: Tint;

@vertex
fn vs(@location(0) position: vec2<i32>) -> @builtin(position) vec4<f32> {
	return vec4<f32>(vec2<f32>(position + tint.offset), 0.0, 1.0);
}

@fragment
fn fs() -> @location(0) vec4<f32> {
	return vec4<f32>(tint.color) / 255.0;
}
