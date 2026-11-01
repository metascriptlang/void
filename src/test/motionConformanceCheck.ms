import { NodeRef, Scene2D, group, local, setX } from "../void2d/node";
import { close, create } from "../void2d/scene";
import { rgba } from "../void2d/types";
import { Clock } from "pulse/src/clock";
import { flatten } from "pulse/src/compose";
import {
	ConformanceAdapter,
	ConformanceCase,
	ConformancePlayer,
	ConformanceProperty,
	ConformanceResult,
	ConformanceSupport,
	ConformanceTiming,
	ConformanceValue,
	runConformance,
} from "pulse/src/conformance";
import { conformanceCases } from "pulse/src/conformanceCases";
import { CONFORMANCE_GOLDEN } from "pulse/src/conformanceGolden";
import { CONFORMANCE_FRAME_MS } from "pulse/src/headless";
import { MotionDocument } from "pulse/src/document";
import { MotionBinding, MotionPlayer, motionOptions } from "pulse/src/player";
import { MotionPolicy } from "pulse/src/policy";
import { Composition, MotionTarget } from "pulse/src/target";
import { AnimatedValue, AnimationSpec } from "pulse/src/value";
import { VoidBindings } from "../motion/bindings";
import { VoidClock } from "../motion/clock";

// Each conformance property is the x of its own void2d node, so every write and read crosses
// Void's bindings and every frame is a VoidClock tick in seconds, as Void's loop drives it.
class Stage {
	scene: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	clock: VoidClock = new VoidClock();
	policy: MotionPolicy;
	names: string[] = [];
	nodes: NodeRef[] = [];

	constructor(properties: ConformanceProperty[], policy: MotionPolicy) {
		this.policy = policy;
		for (const property of properties) {
			this.names.push(property.name);
			this.nodes.push(this.scene.group().setX(property.initial as float32));
		}
	}

	node(property: string): NodeRef {
		const index = this.names.indexOf(property) as int32;
		if (index < 0) { throw new Error("motion: void: unknown property " + property); }
		return this.nodes[index];
	}

	binding(slot: string, property: string): MotionBinding {
		const bindings = new VoidBindings();
		bindings.node(slot, this.node(slot + "." + property), ["x"]);
		return { ...bindings.bindings[0], property };
	}

	target(property: string): MotionTarget {
		const bindings = new VoidBindings();
		bindings.node(property, this.node(property), ["x"]);
		return bindings.bindings[0].target as MotionTarget;
	}

	player(document: MotionDocument, timing: ConformanceTiming, emit: (event: string) => void): ConformancePlayer {
		const keys: string[] = [];
		const bindings: MotionBinding[] = [];
		for (const writer of flatten(document)) {
			const key = writer.slot + "." + writer.track.property;
			if (keys.includes(key)) { continue; }
			keys.push(key);
			bindings.push(this.binding(writer.slot, writer.track.property));
		}
		const player = new MotionPlayer(document, bindings, {
			...motionOptions(this.clock.clock),
			delay: timing.delay,
			repeat: timing.repeat,
			repeatDelay: timing.repeatDelay,
			yoyo: timing.yoyo,
			timeScale: timing.timeScale,
			paused: timing.paused,
			composition: timing.composition,
		});
		player.onStart = (): void => { emit("start"); };
		player.onRepeat = (): void => { emit("repeat"); };
		player.onComplete = (): void => { emit("complete"); };
		player.onReverseComplete = (): void => { emit("reverseComplete"); };
		return {
			play: (): void => { player.play(); },
			pause: (): void => { player.pause(); },
			seek: (position: float64, suppressEvents: boolean): void => { player.seek(position, suppressEvents); },
			reverse: (): void => { player.reverse(); },
			setTimeScale: (rate: float64): void => { player.setTimeScale(rate); },
			cancel: (): void => { player.cancel(); },
			finish: (): void => { player.finish(); },
			revert: (): void => { player.revert(); },
			dispose: (): void => { player.dispose(); },
		};
	}

	value(property: string, composition: Composition): ConformanceValue {
		const node = this.node(property);
		const value = new AnimatedValue(node.local().x, this.clock.clock, this.policy, this.target(property), composition);
		value.subscribe((next: float64): void => { node.setX(next as float32); });
		return {
			get: (): float64 => value.get(),
			set: (next: float64): void => { value.set(next); },
			animate: (spec: AnimationSpec, onEnd: ((finished: boolean) => void) | null): void => {
				value.animate(spec, onEnd);
			},
			cancel: (): void => { value.cancel(); },
			dispose: (): void => { value.dispose(); },
			subscribe: (callback: (next: float64) => void): (() => void) => value.subscribe(callback),
		};
	}

	advanceTo(time: float64): void {
		while (this.clock.clock.now() < time) {
			const ms = Math.max(Math.min(CONFORMANCE_FRAME_MS, time - this.clock.clock.now()), 0.001);
			this.clock.tick(ms / 1000);
		}
	}
}

class VoidConformance {
	stage: Stage = new Stage([], new MotionPolicy());
	adapter: ConformanceAdapter;

	constructor() {
		this.adapter = {
			name: "void",
			support: (testCase: ConformanceCase): ConformanceSupport => ConformanceSupport.Evaluator,
			begin: (properties: ConformanceProperty[], policy: MotionPolicy): void => {
				this.stage = new Stage(properties, policy);
			},
			player: (document: MotionDocument, timing: ConformanceTiming, emit: (event: string) => void): ConformancePlayer =>
				this.stage.player(document, timing, emit),
			value: (property: string, composition: Composition): ConformanceValue => this.stage.value(property, composition),
			clock: (): Clock => this.stage.clock.clock,
			advanceTo: (time: float64): void => { this.stage.advanceTo(time); },
			read: (property: string): float64 => this.stage.node(property).local().x,
			end: (): void => { this.stage.scene.close(); },
		};
	}
}

test "the Void adapter passes Pulse's conformance suite" {
	const results: ConformanceResult[] = runConformance(new VoidConformance().adapter, conformanceCases(), CONFORMANCE_GOLDEN);
	const failures: string[] = [];
	for (const result of results) {
		for (const failure of result.failures) { failures.push(failure); }
	}
	assert results.length > 0;
	assert failures.length === 0, failures.join("\n");
}
