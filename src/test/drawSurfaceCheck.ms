import {
	BINDING_VERTEX_BUFFER,
	BINDING_INDEX_BUFFER,
	BINDING_VIEW,
	BINDING_SAMPLER,
	BINDING_LENGTH,
	makeVertexBuffer,
	makeIndexBuffer,
	makeIndexBuffer32,
	makeStreamBuffer,
	updateBuffer,
} from "../gpu/draw";

test "the draw surface binds two vertex buffers, the index buffer, six views and three samplers" {
	assert BINDING_VERTEX_BUFFER == 0;
	assert BINDING_INDEX_BUFFER == 2;
	assert BINDING_VIEW == 3;
	assert BINDING_SAMPLER == BINDING_VIEW + 6;
	assert BINDING_LENGTH == BINDING_SAMPLER + 3;
}

test "an empty buffer or update is refused before it reaches sokol" {
	const floats: Vec<float32> = [];
	const shorts: Vec<uint16> = [];
	const words: Vec<uint32> = [];
	assert makeVertexBuffer(floats) == 0;
	assert makeIndexBuffer(shorts) == 0;
	assert makeIndexBuffer32(words) == 0;
	assert makeStreamBuffer(0) == 0;
	assert !updateBuffer(0, floats);
}
