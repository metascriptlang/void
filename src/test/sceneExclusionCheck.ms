import { sceneRows, sceneExclusion, backendDirectory } from "../../tests/golden/table";

function excludedCount(directory: string): int32 {
	let count: int32 = 0;
	for (const row of sceneRows()) {
		if (sceneExclusion(directory, row.name).length > 0) { count = count + 1; }
	}
	return count;
}

test "the GL core 4.3 backend leaves out the two scenes that draw with void3d, by name" {
	assert sceneExclusion("gl430", "mixed/void3dTarget").length > 0;
	assert sceneExclusion("gl430", "mixed/void3dTranslucentTarget").length > 0;
	assert excludedCount("gl430") == 2;
}

test "no other backend leaves a scene out" {
	assert excludedCount("d3d11") == 0;
	assert excludedCount("gles3") == 0;
	assert excludedCount("webgl2") == 0;
}

test "the GL core 4.3 capture has a directory of its own, apart from the GLES3 ones" {
	assert backendDirectory(4).equals("gl430");
	assert !backendDirectory(4).equals(backendDirectory(2));
	assert !backendDirectory(4).equals(backendDirectory(3));
}
