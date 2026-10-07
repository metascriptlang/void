import { Scene2D } from "../../src/void2d/node";

function noVoid3d(name: string): Scene2D {
	console.log(`FAIL ${name} was built on a backend whose shader headers carry no void3d text`);
	unreachable;
}

export function mixedVoid3dTarget(): Scene2D { return noVoid3d("mixed/void3dTarget"); }
export function mixedVoid3dTranslucentTarget(): Scene2D {
	return noVoid3d("mixed/void3dTranslucentTarget");
}
