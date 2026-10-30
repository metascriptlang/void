export const COMMAND_FLOATS: int32 = 44;

// Field offsets inside one command record. Named, because `commands[base + 7]` in the
// emitter and `cmd[7]` in the replay is exactly how the two drift apart.
export const CMD_KIND: int32 = 0;
export const CMD_BREAK: int32 = 1;
export const CMD_VERTEX_OFFSET: int32 = 2;
export const CMD_VERTEX_COUNT: int32 = 3;
export const CMD_VIEW: int32 = 4;
export const CMD_BLEND: int32 = 5;
export const CMD_SAMPLER: int32 = 6;
export const SAMPLER_COUNT: int32 = 4;
export const SOURCE_PREMULTIPLIED: int32 = SAMPLER_COUNT;
export const CMD_EFFECT: int32 = 7;
export const CMD_CLIP_X: int32 = 8;
export const CMD_CLIP_Y: int32 = 9;
export const CMD_CLIP_W: int32 = 10;
export const CMD_CLIP_H: int32 = 11;
export const CMD_ARG0: int32 = 12;
export const CMD_ARG1: int32 = 13;
export const CMD_RT_MODE: int32 = 14;
// Zero for the swapchain; otherwise the render target's physical-pixels-per-logical-pixel
// scale. The replay uses nonzero to choose the offscreen pipeline and the value to scale
// logical scissors.
export const CMD_CLEAR_R: int32 = 15;
export const CMD_CLEAR_G: int32 = 16;
export const CMD_CLEAR_B: int32 = 17;
export const CMD_CLEAR_A: int32 = 18;
// Which of P2's two pipelines the run wants, and the instance range inside the stream that
// pipeline reads. A Draw carries either a vertex range or an instance range, never both;
// the field says which, so the replay branches on the record rather than on a guess about
// whether a count is zero.
export const CMD_PIPELINE: int32 = 19;
export const CMD_INSTANCE_OFFSET: int32 = 20;
export const CMD_INSTANCE_COUNT: int32 = 21;
export const CMD_CLIP_U_X: int32 = 22;
export const CMD_CLIP_U_Y: int32 = 23;
export const CMD_CLIP_U_MIN: int32 = 24;
export const CMD_CLIP_U_MAX: int32 = 25;
export const CMD_CLIP_V_X: int32 = 26;
export const CMD_CLIP_V_Y: int32 = 27;
export const CMD_CLIP_V_MIN: int32 = 28;
export const CMD_CLIP_V_MAX: int32 = 29;
export const CMD_VIEW_HIGH: int32 = 30;
export const CMD_SCOPE: int32 = 31;
export const CMD_CLIP_ROUND_U: int32 = 32;
export const CMD_CLIP_ROUND_V: int32 = 36;
export const CMD_CLIP_RADII: int32 = 40;
export const SCOPE_FLOATS: int32 = 8;
export const NO_SCOPE: int32 = -1;

export function commandViewOf(cmd: Readonly<Span<float32>>): uint32 {
	return (cmd[CMD_VIEW] as uint32) | ((cmd[CMD_VIEW_HIGH] as uint32) << 16);
}
