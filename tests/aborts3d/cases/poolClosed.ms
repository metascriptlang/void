// expect reserveRange: void3d: reserveRange on a uniform pool that was closed
// expect ownRange: void3d: ownRange on a uniform pool that was closed
// expect disownRange: void3d: disownRange on a uniform pool that was closed
// expect releaseRange: void3d: releaseRange on a uniform pool that was closed
// expect writeRange: void3d: writeRange on a uniform pool that was closed
// expect reserveBlock: void3d: reserveBlock on a uniform pool that was closed
// expect writeBlock: void3d: writeBlock on a uniform pool that was closed
// expect closeUniformPool: void3d: closeUniformPool on a uniform pool that was closed
import { argv } from "std/process";
import { NO_UNIFORMS, TypedBlock, UniformBlock } from "../../../src/void3d/material";
import { OutlineWidthParams } from "../../../src/void3d/post3d";
import { DrawContext, closeContext } from "../../../src/void3d/draw";
import {
	UniformPool,
	UniformError,
	reserveRange,
	ownRange,
	disownRange,
	releaseRange,
	writeRange,
	reserveBlock,
	writeBlock,
	closeUniformPool,
} from "../../../src/void3d/uniformPool";

function closedPool(): UniformPool {
	let context: DrawContext = DrawContext.withUniformCapacity(8);
	let pool: UniformPool = context.uniforms;
	closeContext(context);
	return pool;
}

function run(name: string): void {
	let pool: UniformPool = closedPool();
	let values: Vec<float32> = [0.0, 0.0, 0.0, 0.0];
	if (name == "reserveRange") {
		const _r: Result<UniformBlock, UniformError> = reserveRange(pool, 2, 4);
	} else if (name == "ownRange") {
		const _r: Result<int32, UniformError> = ownRange(pool, NO_UNIFORMS);
	} else if (name == "disownRange") {
		const _r: Result<int32, UniformError> = disownRange(pool, NO_UNIFORMS);
	} else if (name == "releaseRange") {
		const _r: Result<int32, UniformError> = releaseRange(pool, NO_UNIFORMS);
	} else if (name == "writeRange") {
		const _r: Result<int32, UniformError> = writeRange(pool, NO_UNIFORMS, values);
	} else if (name == "reserveBlock") {
		const _r: Result<TypedBlock<OutlineWidthParams>, UniformError> =
			reserveBlock<OutlineWidthParams>(pool, 2);
	} else if (name == "writeBlock") {
		const _r: Result<int32, UniformError> = writeBlock<OutlineWidthParams>(
			pool,
			{ block: NO_UNIFORMS },
			{ outlineWidth: { x: 0.0, y: 0.0, z: 0.0, w: 0.0 } },
		);
	} else if (name == "closeUniformPool") {
		closeUniformPool(pool);
	} else {
		console.log(`no case named '${name}'`);
		return;
	}
	console.log(`${name} returned on a closed pool`);
}

run((argv.length as int32) > 1 ? argv[1] : "");
