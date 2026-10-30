import { doorSetup, doorSubmitFrame, doorFrameStat, doorReadTexture, DOOR_STAT_COUNT } from "../../src/gpu/doorGpu";
import { RenderTarget } from "../../src/gpu/target";
import { PixelFormat } from "../../src/gpu/door";
import { Scene2D, NodeRef } from "../../src/void2d/node";
import { isDirty } from "../../src/void2d/scene";
import {
	setup2d, begin2d, beginTarget, endTarget, drawRect, drawImage, frameEnd,
	drawCallCount, uploadCount, uploadBytes, vertexBufferBytes, droppedFrames, buffersAlive,
	atlasImagesAlive, glyphUploadCount, glyphUploadBytes, glyphPageCount, setTextGamma,
} from "../../src/void2d/draw";
import { currentContext } from "../../src/void2d/displayList";
import { rgba, targetTile, blurFilter, vec2 } from "../../src/void2d/types";
import { fillRect, fillGradientRect, fillCircle } from "../../src/void2d/graphics";
import { BoxStyle, uniformRadii, uniformBorders } from "../../src/void2d/boxStyle";
import { BlendMode } from "../../src/gpu/state";

when (voidDummy) {
} else when (windows) {
	import { warpDevice, warpContext } from "../../src/test/d3d11Warp.h";
	@passL("-ld3d11");
} else when (macos) {
	import { metalSystemDevice } from "../../src/test/metalDevice.h";
	@compile("../../src/test/metalDevice.m");
}

const RGBA8: int32 = 2;
const NO_DEPTH: int32 = 0;
const W: int32 = 128;
const H: int32 = 96;
const BIG_W: int32 = 1024;
const BIG_H: int32 = 768;
const BASIS: uint32 = 2166136261;

export struct PinRun {
	stats: uint32[];
	pixels: uint32[];
}

function mix(h: uint32, b: uint32): uint32 {
	return (((h ^ (b & 255)) as uint64 * 16777619) & 0xFFFFFFFF) as uint32;
}

function mixWord(h: uint32, w: uint32): uint32 {
	let r = mix(h, w);
	r = mix(r, w >> 8);
	r = mix(r, w >> 16);
	return mix(r, w >> 24);
}

function mixInt(h: uint32, v: int64): uint32 {
	return mixWord(mixWord(h, (v & 0xFFFFFFFF) as uint32), ((v >> 32) & 0xFFFFFFFF) as uint32);
}

function frameDigest(): uint32 {
	let h = BASIS;
	for (let i: int32 = 0; i < DOOR_STAT_COUNT; i++) { h = mixInt(h, doorFrameStat(i)); }
	h = mixInt(h, drawCallCount() as int64);
	h = mixInt(h, uploadCount() as int64);
	h = mixInt(h, uploadBytes() as int64);
	h = mixInt(h, vertexBufferBytes() as int64);
	h = mixInt(h, droppedFrames() as int64);
	h = mixInt(h, buffersAlive() as int64);
	h = mixInt(h, atlasImagesAlive() as int64);
	h = mixInt(h, glyphUploadCount() as int64);
	h = mixInt(h, glyphUploadBytes() as int64);
	h = mixInt(h, glyphPageCount() as int64);
	return h;
}

function pixelDigest(target: RenderTarget): uint32 {
	let out: Vec<uint8> = new Array(target.width * target.height * 4);
	if (doorReadTexture(target.image, 0, 0, target.width, target.height, out) != 1) { return 0; }
	let h = BASIS;
	for (let i: int32 = 0; i < (out.length as int32); i++) { h = mix(h, out[i] as uint32); }
	return h;
}

function setupDevice(): void {
	when (voidDummy) {
		doorSetup(null, null, RGBA8, PixelFormat.Depth as int32, 1);
	} else when (windows) {
		doorSetup(warpDevice(), warpContext(), RGBA8, NO_DEPTH, 1);
	} else when (macos) {
		doorSetup(metalSystemDevice(), null, RGBA8, NO_DEPTH, 1);
	}
}

function finishFrame(run: PinRun, target: RenderTarget, read: boolean): void {
	doorSubmitFrame();
	frameEnd();
	run.stats.push(frameDigest());
	run.pixels.push(read ? pixelDigest(target) : 0);
}

function sceneFrame(run: PinRun, s: Scene2D, target: RenderTarget, dpi: float32, read: boolean): void {
	s.prepare((target.width as float32) / dpi, (target.height as float32) / dpi, dpi);
	s.drawTarget(target);
	finishFrame(run, target, read);
}

function defaultFrame(run: PinRun, target: RenderTarget, source: RenderTarget, dpi: float32): void {
	begin2d((target.width as float32) / dpi, (target.height as float32) / dpi, dpi);
	drawRect(vec2(2.0, 2.0), vec2(30.0, 20.0), rgba(1.0, 0.0, 0.0, 1.0), BlendMode.Alpha);
	beginTarget(source, 8.0, 8.0, 1.0, 0.0, 0.0, rgba(0.0, 0.0, 0.0, 0.0));
	drawRect(vec2(0.0, 0.0), vec2(4.0, 4.0), rgba(0.0, 1.0, 0.0, 1.0), BlendMode.Alpha);
	endTarget();
	drawImage(targetTile(source, 8.0, 8.0).premultiplied(), vec2(40.0, 2.0), vec2(16.0, 16.0),
		rgba(1.0, 1.0, 1.0, 1.0), BlendMode.Alpha);
	const ctx = currentContext();
	ctx.prepare();
	ctx.drawTarget(target, rgba(0.0, 0.0, 0.0, 1.0));
	finishFrame(run, target, true);
}

function richScene(source: RenderTarget): Scene2D {
	const s = Scene2D.create(rgba(0.1, 0.2, 0.3, 1.0));
	s.add(s.rect(16.0, 12.0, rgba(1.0, 0.0, 0.0, 0.5)).at(4.0, 4.0));
	const rounded = s.rect(16.0, 16.0, rgba(0.0, 1.0, 0.0, 0.5)).at(24.0, 4.0);
	rounded.setBoxStyle(BoxStyle.create(uniformRadii(4.0), uniformBorders(1.0), rgba(1.0, 1.0, 1.0, 1.0)));
	s.add(rounded);
	const g = s.graphics().at(4.0, 26.0);
	fillRect(g, 0.0, 0.0, 12.0, 8.0, rgba(0.0, 0.0, 1.0, 0.5));
	fillCircle(g, 20.0, 4.0, 4.0, rgba(1.0, 1.0, 0.0, 1.0));
	fillGradientRect(g, 28.0, 0.0, 10.0, 8.0, rgba(1.0, 0.0, 0.0, 1.0), rgba(0.0, 0.0, 1.0, 1.0), 0.5);
	s.add(g);
	s.add(s.sprite(targetTile(source, 8.0, 8.0).premultiplied()).at(4.0, 40.0));
	s.add(s.sprite(targetTile(source, 8.0, 8.0).premultiplied()).at(14.0, 40.0).setTileWrap(true));
	const filtered = s.rect(10.0, 8.0, rgba(1.0, 0.0, 1.0, 0.5)).at(50.0, 26.0);
	filtered.setFilter(blurFilter(1.0));
	s.add(filtered);
	const clipped = s.mask(8.0, 12.0).at(46.0, 4.0);
	clipped.addChild(s.rect(16.0, 12.0, rgba(0.0, 1.0, 1.0, 1.0)));
	s.add(clipped);
	const round = s.mask(12.0, 12.0).at(60.0, 4.0);
	round.setMaskRadii(uniformRadii(4.0));
	round.addChild(s.rect(24.0, 24.0, rgba(1.0, 0.5, 0.0, 1.0)));
	s.add(round);
	const tinted = s.rect(10.0, 8.0, rgba(0.5, 0.5, 0.5, 1.0)).at(70.0, 26.0);
	tinted.setColorAdd(rgba(0.2, 0.0, 0.0, 0.0));
	s.add(tinted);
	for (let b: int32 = 0; b < 12; b++) {
		s.add(s.rect(6.0, 6.0, rgba(0.9, 0.4, 0.2, 0.6)).at((4 + b * 8) as float32, 60.0)
			.setBlend(b as BlendMode));
	}
	return s;
}

function growth(run: PinRun, target: RenderTarget, source: RenderTarget): void {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const rects: NodeRef[] = [];
	const counts: int32[3] = [5000, 12000, 3000];
	for (let step: int32 = 0; step < 3; step++) {
		while ((rects.length as int32) < counts[step]) {
			const n: int32 = rects.length as int32;
			const r = s.rect(6.0, 6.0, rgba(0.2, 0.7, 0.4, 1.0)).at(((n % 128) * 8) as float32, ((n / 128) * 8) as float32);
			s.add(r);
			rects.push(r);
		}
		for (let i: int32 = 0; i < (rects.length as int32); i++) { rects[i].setVisible(i < counts[step]); }
		sceneFrame(run, s, target, 1.0, false);
		sceneFrame(run, s, target, 1.0, false);
	}
	const sprites: NodeRef[] = [];
	for (let i: int32 = 0; i < 20000; i++) {
		const n = s.sprite(targetTile(source, 4.0, 4.0).premultiplied())
			.at(((i % 256) * 4) as float32, (400 + (i / 256) * 4) as float32);
		s.add(n);
		sprites.push(n);
	}
	sceneFrame(run, s, target, 1.0, false);
	const g = s.graphics();
	s.add(g);
	for (let i: int32 = 0; i < 8000; i++) {
		fillRect(g, ((i % 100) * 10) as float32, (300 + (i / 100) * 5) as float32, 8.0, 3.0,
			rgba(0.3, 0.3, 0.9, 1.0));
	}
	sceneFrame(run, s, target, 1.0, false);
	for (let i: int32 = 0; i < 20000; i++) { sprites[i].setVisible(false); }
	sceneFrame(run, s, target, 1.0, false);
	s.close();
	sceneFrame(run, Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)), target, 1.0, false);
}

export function runPin(): PinRun {
	const run: PinRun = { stats: [], pixels: [] };
	setupDevice();
	setup2d();
	const target = RenderTarget.allocate(W, H, PixelFormat.Rgba8, true);
	const source = RenderTarget.allocate(8, 8, PixelFormat.Rgba8, true);
	const s = richScene(source);
	sceneFrame(run, s, target, 1.0, true);
	sceneFrame(run, s, target, 1.0, true);
	s.add(s.rect(6.0, 6.0, rgba(0.1, 0.9, 0.9, 1.0)).at(100.0, 80.0));
	sceneFrame(run, s, target, 1.0, true);
	setTextGamma(1.4, 0.3);
	sceneFrame(run, s, target, 1.5, true);
	setTextGamma(1.0, 0.0);
	sceneFrame(run, s, target, 2.0, true);
	sceneFrame(run, s, target, 1.0, true);
	defaultFrame(run, target, source, 1.0);
	defaultFrame(run, target, source, 2.0);

	const bigTarget = RenderTarget.allocate(BIG_W, BIG_H, PixelFormat.Rgba8, true);
	growth(run, bigTarget, source);

	setupDevice();
	target.resize(W, H);
	source.resize(8, 8);
	sceneFrame(run, s, target, 1.0, true);
	sceneFrame(run, s, target, 1.0, true);
	defaultFrame(run, target, source, 1.0);
	return run;
}
