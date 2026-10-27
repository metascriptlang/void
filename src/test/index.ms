import "../sokol/gpu";
import "../sokol/window";
import "./transformCheck";
import "./tileCheck";
import "./graphicsCheck";
import "./sceneExclusionCheck";
import "./nodeCheck";
import "./tileGroupCheck";
import "./sceneCheck";
import "./effectCheck";
import "./filterPlanCheck";
import "./faceCheck";
import "./glyphAtlasCheck";
import "./glyphPageReleaseCheck";
import "./glyphPortCheck";
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
import "./sfntPortCheck";
import "./trueTypePortCheck";
import "./pngPortCheck";
import "./colourFacePortCheck";
import "./svgMaskPortCheck";
import "./kbUnicodePortCheck";
import "./kbBreakPortCheck";
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
import "./pipelineLookupCheck";
import "./instanceLayoutCheck";
import "./instanceAttributeCheck";
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
import "./doorResidentCheck";
import "./gpuTimerRingCheck";
import "./bloomKernelCheck";
import "./dirShadowCheck";
import "./cameraCheck";
import "./frustumCheck";
import "./planeProjectionCheck";
import "./rayPlaneCheck";
import "./boundsCheck";
import "./orientedBoundsCheck";
import "./frustumOrientedBoundsCheck";
import "./segmentCheck";
import "./capsuleCheck";
import "./cylinderCheck";
import "./polygonColliderCheck";
import "./heightMapCheck";
import "./transformColliderCheck";
import "./objectColliderCheck";
import "./optimizedColliderCheck";
import "./boundsSphereBuildCheck";
import "./sphereQueryCheck";
import "./spherePointCheck";
import "./sphereRayCheck";
import "./meshDataCheck";
import "./meshTranslationCheck";
import "./meshUvScaleCheck";
import "./meshScaleCheck";
import "./meshNormalsCheck";
import "./sphereTangentsCheck";
import "./meshLodCheck";
import "./meshLodDrawCheck";
import "./drawCheck";
import "./gltfCheck";
import "./gltfIndexCheck";
import "./gltfDiagnosticCheck";
import "./gltfSkinCheck";
import "./gltfMaterialCheck";
import "./gltfEmbeddedImageCheck";
import "./gltfCurveCheck";
import "./gltfPoseCheck";
import "./unicodeTablesPortCheck";
import "./floatBitsPortCheck";
import "./mat4PortCheck";
import "./mikkTangentsPortCheck";
import "./viewsPortCheck";
import "./appEventPortCheck";
import "./appWindowPortCheck";
import "./gltfComposeSceneCheck";
import "./gltfAccessorCheck";
import "./gltfColourCheck";
import "./gltfColourImportCheck";
import "./slotsCheck";
import "./poolCheck";
import "./vulkanMemoryCheck";
import "./vulkanResourcesCheck";
import "./vulkanPassCheck";
import "./featureBitCheck";
import "./webgpuValidateCheck";
import "./uniformPoolCheck";
import "./uniformPoolGrowCheck";
import "./lifetimeCheck";
import "./storeCheck";
import "./closeCheck";
import "./textureCheck";
import "./textureMipCheck";
import "./textureMipUploadCheck";
import "./pbrResponseCheck";
import "./pbrLitCheck";
import "./pbrMapsCheck";
import "./pbrEnvironmentCheck";
import "./environmentShaderCheck";
import "./gltfPbrMaterialCheck";
import "./gltfPbrSceneCheck";
import "./lightShapeShaderCheck";
import "./lightShapeSceneCheck";
import "./spotShadowCheck";
import "./morphSkinSceneCheck";
import "./lightShapeCheck";
import "./morphGeometryCheck";
import "./morphSceneCheck";
import "./gltfMorphImportCheck";
import "./colorMatrixPassCheck";
import "./imageDecodeCheck";
import "./animationSheetCheck";
import "./scene3dCheck";
import "./lightColorCheck";
import "./sceneMeshesCheck";
import "./sceneMaterialsCheck";
import "./sceneContainsCheck";
import "./animationCheck";
import "./animationComposeCheck";
import "./animationTransitionCheck";
import "./animationSmoothTargetCheck";
import "./animationBlendSpaceCheck";
import "./pickCheck";
import "./layersCheck";
import "./renderOrderCheck";
import "./passListSortCheck";
import "./particleFadeCheck";
import "./trailCheck";
import "./graphics3dCheck";
import "./worldGraphicsMiterCheck";
import "./particleShaderCheck";
import "./particleCurveCheck";
import "./particleSystemCheck";
import "./particleEffectCheck";
import "./particles2dCheck";
import "./particleWriterCheck";
import "./particleTrailCheck";
import "./particleUnityCheck";
import "./particleModeCheck";
import "./particleMeshCheck";
import "./particleFromHeapsCheck";
import "./particleUnityPrefabCheck";
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
import "./shaderModuleCheck";
import "./void3dModuleCheck";
import "./shaderComputeCheck";
import "./shaderComputeOpsCheck";
import "./shaderSampleCheck";
import "./shaderDepthCheck";
import "./shaderFragDepthCheck";
import "./shaderTexelCheck";
import "./shaderBitsCheck";
import "./shaderInterpolateCheck";
import "./shaderIrCheck";
import "./shaderPrintCheck";
import "./shaderSpecializeCheck";
import "./shaderLayoutCheck";
import "./shaderReflectCheck";
import "./shaderHlslCheck";
import "./shaderWgslCheck";
import "./shaderIrProgramCheck";
import "./shaderGlslCheck";
import "./shaderMslCheck";
import "./shaderSpirvCheck";
import "./shadyExamplesCheck";
import "./shadyTestsCheck";
import "./shadyPortsCheck";
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
import "./frameTimingCheck";
import "./deviceLossCheck";
