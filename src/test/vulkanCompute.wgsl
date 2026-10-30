@group(1) @binding(0) var<storage, read> source: array<u32>;
@group(1) @binding(1) var<storage, read_write> result: array<u32>;

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
	result[id.x] = source[id.x] * 3u + 1u;
}
