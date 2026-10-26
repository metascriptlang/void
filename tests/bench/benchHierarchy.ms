// Void's counterpart of Bevy's transform_hierarchy stress test (docs/VOID3D.md "Bevy comparison
// bench"): the same nine configurations, trees of group nodes whose active nodes move every frame,
// and the world matrices synced as Bevy's PostUpdate propagates transforms. Windowless, as Bevy
// runs it, printing the frame_time lines scripts/frameTime.sh reads. BENCH_HIERARCHY names the
// configuration; BENCH_HIERARCHY_SECONDS how many lines to print before exiting.

import { env, exit } from "std/process";
import { vec3 } from "../../src/math/math3d";
import { DrawContext } from "../../src/void3d/draw";
import {
	Scene3D, NodeId3D, Transform3D, addGroup, rootId, setLocal, syncWorld,
} from "../../src/void3d/scene";
import {
	FrameTimeLog, lastFrameSeconds, positiveEnv, startFrameTimeLog, tick,
} from "./frameTimeLog";

enum TestCase {
	Tree,
	NonUniformTree,
	Humanoids,
}

// transform_hierarchy.rs Cfg: the test case with its two sizes, and the update filter.
struct Config {
	testCase: TestCase;
	depth: int32;
	width: int32;
	active: int32;
	inactive: int32;
	probability: float32;
	minDepth: int32;
	maxDepth: int32;
}

const ANY_DEPTH: int32 = 2147483647;

// The parent of each node of a mixamo rig after its root (transform_hierarchy.rs HUMANOID_RIG).
const HUMANOID_RIG: Vec<int32> = [
	0, 1, 2, 3, 4, 5, 6, 6, 6, 4, 10, 11, 12, 13, 14, 15, 16, 13, 18, 19, 20, 13, 22, 23, 24, 13,
	26, 27, 28, 13, 30, 31, 32, 4, 34, 35, 36, 37, 38, 39, 40, 37, 42, 43, 44, 37, 46, 47, 48, 37,
	50, 51, 52, 37, 54, 55, 56, 1, 58, 59, 60, 61, 1, 63, 64, 65, 66,
];

let scene: Scene3D = Scene3D.create(DrawContext.withUniformCapacity(0));
let moving: Vec<NodeId3D> = [];
let angles: Vec<float32> = [];
let maximumDepth: int32 = 0;
let inserted: int32 = 0;

function configOf(name: string): Config {
	const tree: Config = {
		testCase: TestCase.Tree, depth: 0, width: 0, active: 0, inactive: 0,
		probability: 0.5, minDepth: 0, maxDepth: ANY_DEPTH,
	};
	if (name == "large_tree") {
		return { ...tree, testCase: TestCase.NonUniformTree, depth: 18, width: 8 };
	}
	if (name == "wide_tree") { return { ...tree, depth: 3, width: 500 }; }
	if (name == "deep_tree") {
		return { ...tree, testCase: TestCase.NonUniformTree, depth: 25, width: 2 };
	}
	if (name == "chain") { return { ...tree, depth: 2500, width: 1 }; }
	if (name == "update_leaves") { return { ...tree, depth: 18, width: 2, minDepth: 17 }; }
	if (name == "update_shallow") { return { ...tree, depth: 18, width: 2, maxDepth: 8 }; }
	const rigs: Config = { ...tree, testCase: TestCase.Humanoids, probability: 1.0 };
	if (name == "humanoids_active") { return { ...rigs, active: 4000 }; }
	if (name == "humanoids_inactive") { return { ...rigs, active: 10, inactive: 3990 }; }
	if (name == "humanoids_mixed") { return { ...rigs, active: 2000, inactive: 2000 }; }
	console.log(`BENCH_HIERARCHY must name a transform_hierarchy configuration, got "${name}"`);
	unreachable;
}

// gen_tree: `depth` levels where each node has `width` children, as a parent map.
function uniformTree(depth: int32, width: int32): Vec<int32> {
	let parents: int32 = 0;
	let level: int32 = 1;
	for (let i = 0; i < depth - 1; i++) {
		parents = parents + level;
		level = level * width;
	}
	let tree: Vec<int32> = [];
	for (let parent = 0; parent < parents; parent++) {
		for (let k = 0; k < width; k++) { tree.push(parent); }
	}
	return tree;
}

// add_children_non_uniform: each child takes one level off the depth its later siblings have.
function addNonUniform(ref tree: Vec<int32>, parent: int32, depth: int32, width: int32): void {
	let left: int32 = depth;
	for (let k = 0; k < width; k++) {
		tree.push(parent);
		left = left - 1;
		if (left == 0) { return; }
		addNonUniform(tree, tree.length as int32, left, width);
	}
}

function nonUniformTree(depth: int32, width: int32): Vec<int32> {
	let tree: Vec<int32> = [];
	addNonUniform(tree, 0, depth, width);
	return tree;
}

// set_translation: the point at angle `a` on a circle of radius 32 in the XY plane.
function onCircle(a: float32): Transform3D {
	return {
		...Transform3D.identity(),
		position: vec3((Math.cos(a) * 32.0) as float32, (Math.sin(a) * 32.0) as float32, 0.0),
	};
}

// spawn_tree: a root at `rootLocal`, then each node under its parent at the angle of its place
// among its siblings, moving when the filter picks it.
function spawnTree(
	parents: Readonly<Span<int32>>, config: Config, probability: float32, rootLocal: Transform3D,
): void {
	const count: int32 = (parents.length as int32) + 1;
	let childCount: Vec<int32> = new Array(count);
	let childIndex: Vec<int32> = new Array(count);
	let depths: Vec<int32> = new Array(count);
	for (let i = 0; i < count; i++) {
		childCount[i] = 0;
		childIndex[i] = 0;
		depths[i] = 0;
	}
	for (let i = 0; i < count - 1; i++) { childCount[parents[i]] = childCount[parents[i]] + 1; }
	let ids: Vec<NodeId3D> = [addGroup(scene, scene.rootId(), rootLocal)];
	for (let i = 0; i < count - 1; i++) {
		const parent: int32 = parents[i];
		const sep: float32 = (childIndex[parent] as float32) / (childCount[parent] as float32);
		childIndex[parent] = childIndex[parent] + 1;
		const depth: int32 = depths[parent] + 1;
		depths[i + 1] = depth;
		maximumDepth = Math.max(maximumDepth, depth);
		const id: NodeId3D = addGroup(scene, ids[parent], onCircle(sep));
		if ((Math.random() as float32) <= probability && depth >= config.minDepth &&
			depth <= config.maxDepth) {
			moving.push(id);
			angles.push(sep);
		}
		ids.push(id);
	}
	inserted = inserted + count;
}

function randomRoot(): Transform3D {
	return {
		...Transform3D.identity(),
		position: vec3(
			(Math.random() * 500.0 - 250.0) as float32, (Math.random() * 500.0 - 250.0) as float32,
			0.0,
		),
	};
}

function setup(config: Config): void {
	match (config.testCase) {
		TestCase.Tree => spawnTree(
			uniformTree(config.depth, config.width), config, config.probability,
			Transform3D.identity(),
		),
		TestCase.NonUniformTree => spawnTree(
			nonUniformTree(config.depth, config.width), config, config.probability,
			Transform3D.identity(),
		),
		TestCase.Humanoids => {
			for (let i = 0; i < config.active; i++) {
				spawnTree(HUMANOID_RIG, config, config.probability, randomRoot());
			}
			for (let i = 0; i < config.inactive; i++) {
				spawnTree(HUMANOID_RIG, config, -1.0, randomRoot());
			}
		},
	};
	console.log(`hierarchy.nodes ${inserted}`);
	console.log(`hierarchy.active ${moving.length}`);
	console.log(`hierarchy.depth ${maximumDepth}`);
}

function main(): void {
	setup(configOf(env.get("BENCH_HIERARCHY")));
	const _synced: int32 = syncWorld(scene);
	let log: FrameTimeLog = startFrameTimeLog(positiveEnv("BENCH_HIERARCHY_SECONDS", 30));
	while (!tick(log, performance.now())) {
		// update: each active node turns by a tenth of the frame's seconds.
		const step: float32 = (lastFrameSeconds(log) * 0.1) as float32;
		for (let i = 0; i < (moving.length as int32); i++) {
			angles[i] = angles[i] + step;
			setLocal(scene, moving[i], onCircle(angles[i]));
		}
		const _moved: int32 = syncWorld(scene);
	}
	console.log(`hierarchy.frames ${log.frames}`);
	exit(0);
}
main();
