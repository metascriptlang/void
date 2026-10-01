// expect: gpu door: closePipelines on a pipeline cache that was closed
import { PipelineCache, closePipelines } from "../../src/gpu/pipeline";

const cache: PipelineCache = PipelineCache.empty();
closePipelines(cache);
closePipelines(cache);
console.log("a pipeline cache closed twice returned");
