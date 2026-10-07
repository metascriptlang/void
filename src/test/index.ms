import "../sokol/gpu";
import "./transformCheck";
import "./tileCheck";
import "./graphicsCheck";
import "./nodeCheck";
import "./tileGroupCheck";
import "./sceneCheck";
import "./effectCheck";
import "./faceCheck";
import "./glyphAtlasCheck";
import "./textLayoutCheck";
import "./labelTextCheck";
import "./textMetricsCheck";
import "./textGammaCheck";
import "./fontCheck";
import "./syntheticFaceCheck";
import "./fontOracleCheck";
import "./ucdOracleCheck";
import "./h2dOracleCheck";
import "./math3dCheck";
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
import "./dirShadowCheck";
import "./cameraCheck";
import "./frustumCheck";
import "./boundsCheck";
import "./meshDataCheck";
import "./drawCheck";
import "./gltfCheck";
import "./gltfMaterialCheck";
import "./slotsCheck";
import "./uniformPoolCheck";
import "./lifetimeCheck";
import "./storeCheck";
import "./closeCheck";
import "./textureCheck";
import "./imageDecodeCheck";
import "./scene3dCheck";
import "./animationCheck";
import "./pickCheck";
import "./particlesCheck";
import "./layoutCheck";
import "./billboardCheck";
when (voidProfiler) {
	import "./profilerCheck";
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
