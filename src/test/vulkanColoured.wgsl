struct Out {
	@builtin(position) position: vec4<f32>,
	@location(0) colour: vec4<f32>,
};

@vertex
fn vs(@location(0) position: vec2<f32>, @location(1) colour: vec4<f32>) -> Out {
	return Out(vec4<f32>(position, 0.0, 1.0), colour);
}

@fragment
fn fs(@location(0) colour: vec4<f32>) -> @location(0) vec4<f32> {
	return colour;
}
