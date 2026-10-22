import "../sokol/gpu";
import "./transformCheck";
import "./tileCheck";
import "./graphicsCheck";
import "./sceneExclusionCheck";
import "./nodeCheck";
import "./tileGroupCheck";
import "./sceneCheck";
import "./effectCheck";
import "./faceCheck";
import "./glyphAtlasCheck";
import "./glyphPageReleaseCheck";
import "./outlineKeyCheck";
import "./textLayoutCheck";
import "./labelTextCheck";
import "./glyphRetryCheck";
import "./textMetricsCheck";
import "./textGammaCheck";
import "./fontCheck";
when (macos) {
	import "./platformFaceCheck";
}
import "./syntheticFaceCheck";
when (voidSprites) {
	import "./spriteOracleCheck";
} else {
	import "./spriteOffCheck";
}
import "./fontOracleCheck";
import "./sfntBoundsCheck";
import "./sfntCmapCheck";
import "./ucdOracleCheck";
import "./h2dOracleCheck";
import "./math3dCheck";
import "./skinPaletteCheck";
import "./skinPoseCheck";
import "./skinMeshCheck";
import "./skinTangentCheck";
import "./skinGeometryCheck";
import "./skinSceneCheck";
import "./skinRangeCheck";
import "./skinPartitionCheck";
import "./gltfAnimationCheck";
import "./skinInfluencesCheck";
import "./pipelineCheck";
import "./instanceLayoutCheck";
import "./instanceStreamCheck";
import "./coverageOracleCheck";
import "./gradientCheck";
import "./imageStyleCheck";
import "./uiPipelineCheck";
import "./snapCheck";
import "./rendererCheck";
import "./programKeyCheck";
import "./drawSurfaceCheck";
import "./bloomCheck";
import "./bloomKernelCheck";
import "./dirShadowCheck";
import "./cameraCheck";
import "./frustumCheck";
import "./boundsCheck";
import "./meshDataCheck";
import "./meshLodCheck";
import "./meshLodDrawCheck";
import "./drawCheck";
import "./gltfCheck";
import "./gltfIndexCheck";
import "./gltfDiagnosticCheck";
import "./gltfSkinCheck";
import "./gltfMaterialCheck";
import "./gltfCurveCheck";
import "./gltfPoseCheck";
import "./gltfComposeSceneCheck";
import "./gltfAccessorCheck";
import "./gltfColourCheck";
import "./gltfColourImportCheck";
import "./slotsCheck";
import "./uniformPoolCheck";
import "./lifetimeCheck";
import "./storeCheck";
import "./closeCheck";
import "./textureCheck";
import "./imageDecodeCheck";
import "./animationSheetCheck";
import "./scene3dCheck";
import "./animationCheck";
import "./animationComposeCheck";
import "./pickCheck";
import "./layersCheck";
import "./renderOrderCheck";
import "./particlesCheck";
import "./particleFadeCheck";
import "./particleVisualCheck";
import "./particleShaderCheck";
import "./layoutCheck";
import "./billboardCheck";
import "./shaderCheck";
import "./shaderInterfaceCheck";
import "./shaderEmitCheck";
import "./shaderStdCheck";
import "./shader2dCheck";
import "./shaderCalleeCheck";
import "./shaderStatementCheck";
import "./shaderProgramCheck";
import "./shaderComputeCheck";
import "./shadyExamplesCheck";
import "./shadyTestsCheck";
import "./litShaderCheck";
import "./pixelArtShaderCheck";
import "./post3dCheck";
when (voidShaper) {
	import "./shaperBridgeCheck";
	import "./shapeOracleCheck";
	import "./shapedLayoutCheck";
}
when (voidBidi) {
	import "./bidiTableCheck";
	import "./bidiOracleCheck";
	import "./bidiLayoutCheck";
	import "./bidiCaretCheck";
	import "./bidiSelectionCheck";
	when (voidShaper) {
		import "./bidiShapedCheck";
	}
} else {
	import "./bidiOffCheck";
}
when (voidSvg) {
	import "./svgMaskCheck";
	import "./svgOracleCheck";
	import "./iconCheck";
} else {
	import "./iconOffCheck";
}
when (voidProfiler) {
	import "./profilerCheck";
	import "./frameMarksCheck";
	import "./profilerOverlayCheck";
}

import "./worldLabelCheck";
import "./forwardOutlineCheck";


when (voidColourEmoji) {
	import "./glyphColourAtlasCheck";
	import "./colourFaceCheck";
	import "./labelTextColourCheck";
	when (testBuild) {
		import "../../tests/integration/colourSampler";
	}
} else {
	import "./glyphColourOffCheck";
}
when (voidTextOutline) {
	import "./glyphOutlineCheck";
	import "./outlineOracleCheck";
	import "./labelOutlineCheck";
	import "./outlineEmitCheck";
}
when (voidSdfText) {
	import "./textSdfCheck";
	import "./glyphSdfCheck";
	import "./glyphSdfAtlasCheck";
	import "./sdfOracleCheck";
	import "./labelTextSdfCheck";
	import "./sdfEmitCheck";
	when (voidTextOutline) {
		import "./sdfOutlineOracleCheck";
	}
}
// The harness's own parsers. The gate is a claim about the renderer, so the code that reads
// the gate's own tables has to be tested like anything else (docs/TESTING.md, "Distrust the
// harness before the engine").
import "../../tests/harness/parse";
import "../../tests/harness/benchRows";
import "../../tests/harness/record";
// T1 - the display list, asserted as data with no GPU (docs/TESTING.md "T1").
import "../../tests/displayList/snapshot";
import "../../tests/displayList/retain";
import "../../tests/displayList/rangeCompare";
import "../../tests/isolated/displayListLink";
when (testBuild && voidSdfText && voidShaper) {
	import "../../tests/integration/fontPanel";
}
