// expect: gpu door: shaderFor on a pipeline cache that was closed
import { PipelineCache, closePipelines, shaderFor } from "../../src/gpu/pipeline";

const cache: PipelineCache = PipelineCache.empty();
closePipelines(cache);
console.log(`a closed pipeline cache made shader ${shaderFor(cache, 0)}`);
