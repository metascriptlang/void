// expect: void3d: closeUniformPool with ranges still reserved: 1
import { UniformBlock } from "../../src/void3d/material";
import {
	UniformPool,
	UniformError,
	reserveRange,
	closeUniformPool,
} from "../../src/void3d/uniformPool";

let pool: UniformPool = UniformPool.withCapacity(8);
const range: Result<UniformBlock, UniformError> = reserveRange(pool, 2, 4);
if (!range.ok) { unreachable; }
closeUniformPool(pool);
console.log("a pool closed with a range reserved returned");
