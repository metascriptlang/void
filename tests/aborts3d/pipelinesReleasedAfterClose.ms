// expect: gpu door: releasePipelines on a pipeline cache that was closed
import { PipelineCache, closePipelines, releasePipelines } from "../../src/gpu/pipeline";

const cache: PipelineCache = PipelineCache.empty();
closePipelines(cache);
releasePipelines(cache);
console.log("a closed pipeline cache was released again");
