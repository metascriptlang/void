import "../sokol/gpu";
import "./transformCheck";
import "./tileCheck";
import "./graphicsCheck";
import "./nodeCheck";
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
import "./cameraCheck";
import "./boundsCheck";
import "./meshDataCheck";
import "./drawCheck";
import "./gltfCheck";
import "./scene3dCheck";
import "./animationCheck";
import "./pickCheck";
import "./particlesCheck";
// The harness's own parsers. The gate is a claim about the renderer, so the code that reads
// the gate's own tables has to be tested like anything else (docs/TESTING.md, "Distrust the
// harness before the engine").
import "../../tests/harness/parse";
import "../../tests/harness/benchRows";
// T1 - the display list, asserted as data with no GPU (docs/TESTING.md "T1").
import "../../tests/displayList/snapshot";
