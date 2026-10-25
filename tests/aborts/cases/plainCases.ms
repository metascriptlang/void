// expect addChildCycle: addChild would put node 1 under node 2, which is inside it
// expect animDelaysMismatch: setFrameDelays got 2 delays for an Anim of 3 frames
// expect animDelayZero: setFrameDelays frame 1 has a delay of 0 ms
// expect animSetFrameOutOfRange: setFrame(3) on an Anim of 3 frames
// expect animSetSpeedNegative: a speed is 0 or more
// expect animTickNegative: time only moves forward
// expect blurOutsideTarget: void2d: blurPass outside beginTarget; the blur draws only into a target
// expect boxFillCellZero: got a checker BoxFill with cell 0; it must be > 0
// expect breakOutsideText: shaping break 5 falls outside the text's 4 UTF-16 units
// expect breakSplitsSurrogate: shaping break 2 falls inside the surrogate pair at 1
// expect clearOnRect: clear asked of a Rect node; only a Graphics or a TileGroup can be cleared
// expect endTargetWithoutBegin: void2d: endTarget with no target open; every endTarget closes one beginTarget
// expect glyphKeyOverflow: void2d glyph atlas: a key of size 1100 px and outline lane 0 does not fit the packed key
// expect layerSlotInLanes: layer slot on node 3 inside a noOverlap subtree
// expect metricsOnRect: textWidth asked of a Rect node
// expect outlineOff: void2d text outline: setOutline needs the outline module; build with -d:voidTextOutline
// expect overlapPromise: node 1 promised setNoOverlap, but its children 2 and 3 overlap
// expect paintMovesColorMatrix: void2d: setPaint cannot move a node's color matrix row
// expect profilerNegativeDuration: commit at 3000000 ns is before drawBegin at 9000000 ns
// expect profilerPresentBeforeDraw: present at 5000000 ns before the frame was drawn and committed
// expect runSplitsSurrogate: text run 1 starts inside the surrogate pair at 1
// expect runsShort: text runs cover 2 UTF-16 units of a text of 3
// expect screenLayoutWithoutDevice: gpu door: a screen layout was resolved before gfxSetup made the device
// expect selectionOnRect: setSelectionRange asked of a Rect node
// expect shaderSqrtNegative: sqrt: the GPU result is undefined below 0
// expect staleNode: setX on stale node 1: the handle has generation 1, the row 2
// expect svgMaskOff: void2d svg: svgMaskParse needs the SVG module; build with -d:voidSvg
// expect targetNotRgba8: void2d: beginTarget needs an allocated Rgba8 target and a positive scale, got Depth 16x16 view 2 at scale 1
// expect targetOtherContext2d: gpu door: beginTarget on a render target of GPU context 7; the context is now 1
// expect targetWithoutScale: void2d: beginTarget needs an allocated Rgba8 target and a positive scale, got Rgba8 16x16 view 2 at scale 0
// expect textShapingOff: void2d: text shaping was asked for without -d:voidShaper
// expect tileOutOfRange: setTile(3) on tile group 1, which holds 3 tiles
// expect tileRangeNegative: setRange(-1, 4) on tile group 1: a range starts at tile 0 or later
// expect unregisteredProgram: gpu door: program id 2000000000 was never registered
// expect writeBufferRewriteUniform: rewrites bytes this frame already wrote, up to 16
// expect shaperOff: void2d shaper: shaperBegin needs the shaper module; build with -d:voidShaper
import { argv } from "std/process";
import "../../../src/sokol/gpu";
import { fakeTexture } from "../../../src/test/helpers";
import { Scene2D, TileCell } from "../../../src/void2d/node";
import "../../../src/void2d/scene";
import { paint } from "../../../src/void2d/scene";
import { sync } from "../../../src/void2d/render";
import { rgba, whiteTile, identity2d, tile } from "../../../src/void2d/types";
import { begin2d, blurPass, endTarget, beginTarget } from "../../../src/void2d/draw";
import { BoxFillKind, BoxStyle, solidFill, uniformBorders, uniformRadii } from "../../../src/void2d/boxStyle";
import { GlyphKey, PageKind } from "../../../src/void2d/glyphAtlas";
import { colorMatrixGrayscale } from "../../../src/void2d/effect";
import { frameProfiler, drawBegin, commit, present } from "../../../src/void2d/profiler";
import { DEFAULT_FONT } from "../../../src/void2d/font";
import { TextRun, setTextShaping } from "../../../src/void2d/textLayout";
import { SWAPCHAIN_LAYOUT, TargetLayout, RenderTarget } from "../../../src/gpu/target";
import { PixelFormat, contextGeneration } from "../../../src/gpu/door";
import { PipelineCache, pipelineFor } from "../../../src/gpu/pipeline";
import { RenderState } from "../../../src/gpu/state";
import { sqrt } from "../../../src/shader/std";
import { svgMaskParse } from "../../../src/void2d/svgMask";
import { shaperBegin, ShapeDirection } from "../../../src/void2d/shaper";
import { GPUBufferUsage } from "../../../src/webgpu/types.ms";
import "../../../src/webgpu/device.ms";
import { openTestDevice } from "../../../src/test/testDevice";

function run(name: string): void {
	if (name == "addChildCycle") {
		const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
		const other = s.group();
		const b = other.addChild(s.rect(10.0, 10.0, rgba(1.0, 1.0, 1.0, 1.0)));
		b.addChild(other);
		console.log("a node went under its own child");
	} else if (name == "animDelaysMismatch") {
		const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
		const frames = [whiteTile(8.0, 8.0), whiteTile(8.0, 8.0), whiteTile(8.0, 8.0)];
		s.anim(frames, 10.0).setFrameDelays([100, 200]);
		console.log("two delays were taken for three frames");
	} else if (name == "animDelayZero") {
		const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
		const frames = [whiteTile(8.0, 8.0), whiteTile(8.0, 8.0), whiteTile(8.0, 8.0)];
		s.anim(frames, 10.0).setFrameDelays([100, 0, 50]);
		console.log("a zero delay was taken");
	} else if (name == "animSetFrameOutOfRange") {
		const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
		const frames = [whiteTile(8.0, 8.0), whiteTile(8.0, 8.0), whiteTile(8.0, 8.0)];
		s.anim(frames, 10.0).setFrame(3);
		console.log("a frame past the end was shown");
	} else if (name == "animSetSpeedNegative") {
		const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
		const frames = [whiteTile(8.0, 8.0), whiteTile(8.0, 8.0), whiteTile(8.0, 8.0)];
		s.anim(frames, 10.0).setSpeed(-1.0);
		console.log("a negative speed was taken");
	} else if (name == "animTickNegative") {
		const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
		const frames = [whiteTile(8.0, 8.0), whiteTile(8.0, 8.0), whiteTile(8.0, 8.0)];
		s.add(s.anim(frames, 10.0));
		s.tick(-0.5);
		console.log("time ran backwards");
	} else if (name == "blurOutsideTarget") {
		begin2d(16.0, 16.0, 1.0);
		blurPass(1, 1.0 / 16.0, 0.0);
		console.log("a blur was recorded into the screen list");
	} else if (name == "boxFillCellZero") {
		const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
		const style = BoxStyle.create(uniformRadii(2.0), uniformBorders(0.0), rgba(0.0, 0.0, 0.0, 0.0));
		const box = s.add(s.rect(10.0, 10.0, rgba(1.0, 1.0, 1.0, 1.0)));
		box.setBoxStyle({ ...style, fill: { ...solidFill(), kind: BoxFillKind.Checker, cell: 0.0 } });
		console.log("a checker fill of no cell size was taken");
	} else if (name == "breakOutsideText") {
		const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
		const breaks: int32[] = [5];
		const n = s.label("a😀b", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
		n.setShapingBreaks(breaks);
		n.sync(identity2d(), false);
		console.log(`a label with a shaping break outside its text measured ${n.textWidth()}`);
	} else if (name == "breakSplitsSurrogate") {
		const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
		const breaks: int32[] = [2];
		const n = s.label("a😀b", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
		n.setShapingBreaks(breaks);
		n.sync(identity2d(), false);
		console.log(`a label with a shaping break inside a surrogate pair measured ${n.textWidth()}`);
	} else if (name == "clearOnRect") {
		const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
		const box = s.add(s.rect(10.0, 10.0, rgba(1.0, 1.0, 1.0, 1.0)));
		box.clear();
		console.log("a Rect was cleared");
	} else if (name == "endTargetWithoutBegin") {
		begin2d(16.0, 16.0, 1.0);
		endTarget();
		console.log("an endTarget with no target open returned");
	} else if (name == "glyphKeyOverflow") {
		const key: GlyphKey = {
			kind: PageKind.Coverage, face: 0, glyph: 36, sizePx: 1100.0, variant: 0, outline: 0,
		};
		console.log(`the key packed to ${key.packed()}`);
	} else if (name == "layerSlotInLanes") {
		const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
		const list = s.add(s.group());
		list.addChild(s.rect(40.0, 20.0, rgba(1.0, 0.0, 0.0, 1.0)));
		list.addChild(s.rect(40.0, 20.0, rgba(0.0, 1.0, 0.0, 1.0)).at(0.0, 30.0).setLayerSlot(true));
		list.setNoOverlap(true);
		s.paint(200.0, 100.0, 1.0);
		console.log("a layer slot was drawn inside lanes");
	} else if (name == "metricsOnRect") {
		const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
		const box = s.rect(10.0, 10.0, rgba(1.0, 1.0, 1.0, 1.0));
		box.sync(identity2d(), false);
		console.log(`textWidth of a Rect returned ${box.textWidth()}`);
	} else if (name == "outlineOff") {
		const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
		const n = s.label("outlined", 16.0, rgba(1.0, 1.0, 1.0, 1.0));
		n.setOutline(2.0, rgba(0.0, 0.0, 0.0, 1.0));
		console.log("a label took an outline with the module off");
	} else if (name == "overlapPromise") {
		const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
		const list = s.add(s.group());
		list.addChild(s.rect(40.0, 20.0, rgba(1.0, 0.0, 0.0, 1.0)));
		list.addChild(s.rect(40.0, 20.0, rgba(0.0, 1.0, 0.0, 1.0)).at(0.0, 10.0));
		list.setNoOverlap(true);
		s.paint(200.0, 100.0, 1.0);
		console.log("two overlapping children were drawn in lanes");
	} else if (name == "paintMovesColorMatrix") {
		const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
		const white = rgba(1.0, 1.0, 1.0, 1.0);
		const grey = s.rect(4.0, 4.0, white).setColorMatrix(colorMatrixGrayscale(1.0));
		const plain = s.rect(4.0, 4.0, white);
		plain.setPaint(grey.paint());
		console.log("a paint carried another node's color matrix row across");
	} else if (name == "profilerNegativeDuration") {
		const p = frameProfiler();
		p.drawBegin(9000000);
		p.commit(3000000);
		console.log("a frame ended before it began");
	} else if (name == "profilerPresentBeforeDraw") {
		const p = frameProfiler();
		p.present(5000000, 6000000);
		console.log("a present was recorded with no frame");
	} else if (name == "runSplitsSurrogate") {
		const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
		const clear = rgba(0.0, 0.0, 0.0, 0.0);
		const white = rgba(1.0, 1.0, 1.0, 1.0);
		const runs: TextRun[] = [
			{
				len: 2, font: DEFAULT_FONT, color: white, background: clear, underline: clear,
				wavy: false, strikethrough: clear,
			},
			{
				len: 2, font: DEFAULT_FONT, color: white, background: clear, underline: clear,
				wavy: false, strikethrough: clear,
			},
		];
		const n = s.label("a😀b", 13.0, white);
		n.setTextRuns(runs);
		n.sync(identity2d(), false);
		console.log(`a label whose second run starts inside a surrogate pair measured ${n.textWidth()}`);
	} else if (name == "runsShort") {
		const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
		const clear = rgba(0.0, 0.0, 0.0, 0.0);
		const runs: TextRun[] = [{
			len: 2, font: DEFAULT_FONT, color: rgba(1.0, 1.0, 1.0, 1.0), background: clear,
			underline: clear, wavy: false, strikethrough: clear,
		}];
		const n = s.label("abc", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
		n.setTextRuns(runs);
		n.sync(identity2d(), false);
		console.log(`a label whose runs miss a unit measured ${n.textWidth()}`);
	} else if (name == "screenLayoutWithoutDevice") {
		const resolved: TargetLayout = SWAPCHAIN_LAYOUT.resolved();
		console.log(`the screen layout resolved without a device: ${resolved.toString()}`);
	} else if (name == "selectionOnRect") {
		const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
		const n = s.rect(40.0, 20.0, rgba(1.0, 1.0, 1.0, 1.0));
		n.setSelectionRange({ start: 0, length: 1 }, rgba(0.3, 0.5, 0.9, 0.5));
		console.log("a Rect took a selection range");
	} else if (name == "shaderSqrtNegative") {
		const below: float32 = -1.0;
		console.log(`sqrt of a negative was ${sqrt(below)}`);
	} else if (name == "staleNode") {
		const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
		const b = s.add(s.rect(10.0, 10.0, rgba(1.0, 1.0, 1.0, 1.0)));
		b.dispose();
		b.setX(1.0);
		console.log("a disposed node took a write");
	} else if (name == "svgMaskOff") {
		svgMaskParse("<svg/>");
		console.log("an SVG was parsed with the module off");
	} else if (name == "targetNotRgba8") {
		const depth: RenderTarget = {
			width: 16,
			height: 16,
			format: PixelFormat.Depth,
			sampled: false,
			image: 1,
			attachment: 2,
			texture: 0,
			generation: contextGeneration(),
			closed: false,
		};
		begin2d(16.0, 16.0, 1.0);
		beginTarget(depth, 16.0, 16.0, 1.0, 0.0, 0.0, rgba(0.0, 0.0, 0.0, 0.0));
		console.log("a depth target opened a void2d target list");
	} else if (name == "targetOtherContext2d") {
		const stale: RenderTarget = {
			width: 16,
			height: 16,
			format: PixelFormat.Rgba8,
			sampled: true,
			image: 1,
			attachment: 2,
			texture: 3,
			generation: 7,
			closed: false,
		};
		begin2d(16.0, 16.0, 1.0);
		beginTarget(stale, 16.0, 16.0, 1.0, 0.0, 0.0, rgba(0.0, 0.0, 0.0, 0.0));
		console.log("a target of another GPU context opened a void2d target list");
	} else if (name == "targetWithoutScale") {
		const color: RenderTarget = {
			width: 16,
			height: 16,
			format: PixelFormat.Rgba8,
			sampled: true,
			image: 1,
			attachment: 2,
			texture: 3,
			generation: contextGeneration(),
			closed: false,
		};
		begin2d(16.0, 16.0, 1.0);
		beginTarget(color, 16.0, 16.0, 0.0, 0.0, 0.0, rgba(0.0, 0.0, 0.0, 0.0));
		console.log("a target with no scale opened a void2d target list");
	} else if (name == "textShapingOff") {
		setTextShaping(true);
		console.log("text shaping was turned on with the module off");
	} else if (name == "tileOutOfRange") {
		const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
		const map = s.add(s.tileGroup());
		const one: TileCell = {
			x: 0.0, y: 0.0, tile: tile(fakeTexture(11), 8.0, 8.0), color: rgba(1.0, 1.0, 1.0, 1.0),
			scaleX: 1.0,
			scaleY: 1.0, rotation: 0.0, skew: 0.0,
		};
		const three: TileCell[] = [one, one, one];
		map.setTiles(three);
		map.setTile(3, one);
		console.log("a tile past the end of its group was written");
	} else if (name == "tileRangeNegative") {
		const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
		const map = s.add(s.tileGroup());
		map.setRange(-1, 4);
		console.log("a range starting before tile 0 was taken");
	} else if (name == "unregisteredProgram") {
		let cache: PipelineCache = PipelineCache.empty();
		const pipeline: uint32 = pipelineFor(
			cache, 2000000000, 0, false, RenderState.defaults(), SWAPCHAIN_LAYOUT,
		);
		console.log(`an unregistered program made pipeline ${pipeline}`);
	} else if (name == "writeBufferRewriteUniform") {
		const device = openTestDevice();
		const buffer = device.createBuffer({ label: "rewritten", size: 512, usage: (GPUBufferUsage.UNIFORM as int32) | (GPUBufferUsage.COPY_DST as int32) });
		const first: Vec<float32> = [1.0, 0.0, 0.0, 1.0];
		const second: Vec<float32> = [0.0, 1.0];
		device.queue.writeBuffer(buffer, 0, first);
		device.queue.writeBuffer(buffer, 8, second);
		console.log("a second write over bytes the frame already wrote returned");
	} else if (name == "shaperOff") {
		shaperBegin(0, ShapeDirection.Ltr);
		console.log("the shaper began with the module off");
	} else {
		console.log(`no case named '${name}'`);
		process.exit(2);
	}
	console.log(`${name} returned`);
}

run((argv.length as int32) > 1 ? argv[1] : "");
