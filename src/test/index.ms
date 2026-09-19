import "../sokol/gpu";
import "./transformCheck";
import "./tileCheck";
import "./graphicsCheck";
import "./nodeCheck";
import "./sceneCheck";
import "./effectCheck";
import "./textCheck";
import "./math3dCheck";
import "./pipelineCheck";
import "./rendererCheck";
import "./cameraCheck";
// The harness's own parsers. The gate is a claim about the renderer, so the code that reads
// the gate's own tables has to be tested like anything else (docs/TESTING.md, "Distrust the
// harness before the engine").
import "../../tests/harness/parse";
