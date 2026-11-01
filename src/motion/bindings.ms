import { Color } from "../void2d/types";
import {
	NodeRef,
	Scene2D,
	local,
	paint,
	setAlpha,
	setColor,
	setPivot,
	setRotation,
	setScale,
	setScaleX,
	setScaleY,
	setX,
	setY,
} from "../void2d/node";
import { NodeId3D, Scene3D, Transform3D, liveRow, setLocal } from "../void3d/scene";
import { Quat, eulerQuat } from "../math/math3d";
import { MotionValue, ValueKind, colorValue, numberValue } from "pulse/src/document";
import { MotionBinding } from "pulse/src/player";
import { MotionTarget } from "pulse/src/target";

function fail(message: string): never {
	throw new Error("motion: " + message);
}

export enum NodeProperty {
	X,
	Y,
	Rotation,
	Scale,
	ScaleX,
	ScaleY,
	PivotX,
	PivotY,
	Alpha,
	Color,
}

export enum ObjectProperty {
	X,
	Y,
	Z,
	RotationX,
	RotationY,
	RotationZ,
	Scale,
	ScaleX,
	ScaleY,
	ScaleZ,
}

function nodeProperty(slot: string, name: string): NodeProperty {
	switch (name) {
		case "x": return NodeProperty.X;
		case "y": return NodeProperty.Y;
		case "rotation": return NodeProperty.Rotation;
		case "scale": return NodeProperty.Scale;
		case "scaleX": return NodeProperty.ScaleX;
		case "scaleY": return NodeProperty.ScaleY;
		case "pivotX": return NodeProperty.PivotX;
		case "pivotY": return NodeProperty.PivotY;
		case "alpha": return NodeProperty.Alpha;
		case "color": return NodeProperty.Color;
		default: fail(slot + "." + name + " is not a Void 2D node property");
	}
}

function objectProperty(slot: string, name: string): ObjectProperty {
	switch (name) {
		case "x": return ObjectProperty.X;
		case "y": return ObjectProperty.Y;
		case "z": return ObjectProperty.Z;
		case "rotationX": return ObjectProperty.RotationX;
		case "rotationY": return ObjectProperty.RotationY;
		case "rotationZ": return ObjectProperty.RotationZ;
		case "scale": return ObjectProperty.Scale;
		case "scaleX": return ObjectProperty.ScaleX;
		case "scaleY": return ObjectProperty.ScaleY;
		case "scaleZ": return ObjectProperty.ScaleZ;
		default: fail(slot + "." + name + " is not a Void 3D object property");
	}
}

function uniformScale(slot: string, axes: float32[]): float64 {
	for (const axis of axes) {
		if (axis !== axes[0]) {
			fail(slot + ".scale reads a non-uniform scale; bind its axes instead");
		}
	}
	return axes[0];
}

function refuseScaleOverlap(slot: string, properties: string[]): void {
	if (!properties.includes("scale")) { return; }
	for (const property of properties) {
		if (property !== "scale" && property.startsWith("scale")) {
			fail(slot + ".scale and " + slot + "." + property + " both write one scale");
		}
	}
}

function numberOf(slot: string, name: string, value: MotionValue): float32 {
	if (value.kind !== ValueKind.Number) { fail(slot + "." + name + " is bound as a number"); }
	return value.number as float32;
}

export struct NodeBinding {
	slot: string;
	name: string;
	node: NodeRef;
	property: NodeProperty;
}

export function writeNode(b: NodeBinding, value: MotionValue): void {
	const node = b.node;
	if (!node.isLive()) { return; }
	if (b.property === NodeProperty.Color) {
		if (value.kind !== ValueKind.Color) { fail(b.slot + "." + b.name + " is bound as a colour"); }
		const c = value.color;
		const color: Color = { r: c.r as float32, g: c.g as float32, b: c.b as float32, a: c.a as float32 };
		node.setColor(color);
		return;
	}
	const v = numberOf(b.slot, b.name, value);
	switch (b.property) {
		case NodeProperty.X: node.setX(v); break;
		case NodeProperty.Y: node.setY(v); break;
		case NodeProperty.Rotation: node.setRotation(v); break;
		case NodeProperty.Scale: node.setScale(v); break;
		case NodeProperty.ScaleX: node.setScaleX(v); break;
		case NodeProperty.ScaleY: node.setScaleY(v); break;
		case NodeProperty.PivotX: node.setPivot(v, node.local().pivotY); break;
		case NodeProperty.PivotY: node.setPivot(node.local().pivotX, v); break;
		case NodeProperty.Alpha: node.setAlpha(v); break;
		default: fail(b.slot + "." + b.name + " has no Void 2D write");
	}
}

export function readNode(b: NodeBinding): MotionValue {
	const node = b.node;
	switch (b.property) {
		case NodeProperty.X: return numberValue(node.local().x);
		case NodeProperty.Y: return numberValue(node.local().y);
		case NodeProperty.Rotation: return numberValue(node.local().rotation);
		case NodeProperty.Scale: return numberValue(uniformScale(b.slot, [node.local().scaleX, node.local().scaleY]));
		case NodeProperty.ScaleX: return numberValue(node.local().scaleX);
		case NodeProperty.ScaleY: return numberValue(node.local().scaleY);
		case NodeProperty.PivotX: return numberValue(node.local().pivotX);
		case NodeProperty.PivotY: return numberValue(node.local().pivotY);
		case NodeProperty.Alpha: return numberValue(node.paint().alpha);
		case NodeProperty.Color: {
			const c = node.paint().color;
			return colorValue(c.r, c.g, c.b, c.a);
		}
	}
}

struct Euler {
	x: float32;
	y: float32;
	z: float32;
}

function eulerOf(q: Quat): Euler {
	const sinY = Math.min(1, Math.max(-1, 2 * (q.w * q.y - q.z * q.x)));
	return {
		x: Math.atan2(2 * (q.w * q.x + q.y * q.z), 1 - 2 * (q.x * q.x + q.y * q.y)) as float32,
		y: Math.asin(sinY) as float32,
		z: Math.atan2(2 * (q.w * q.z + q.x * q.y), 1 - 2 * (q.y * q.y + q.z * q.z)) as float32,
	};
}

function sameQuat(a: Quat, b: Quat): boolean {
	return a.x === b.x && a.y === b.y && a.z === b.z && a.w === b.w;
}

// The angles an object's rotation bindings animate, shared by its three axes. A write composes
// the quaternion from these angles; they are decomposed from the object only when its rotation
// is no longer the one last written here, because a decomposition picks one of two equivalent
// triples and switching between them mid-animation flips the other axes.
export class ObjectRotation {
	scene: Scene3D;
	id: NodeId3D;
	angles: Euler = { x: 0.0, y: 0.0, z: 0.0 };
	written: Quat = { x: 0.0, y: 0.0, z: 0.0, w: 0.0 };
	source: Quat = { x: 0.0, y: 0.0, z: 0.0, w: 0.0 };
	sourceAngles: Euler = { x: 0.0, y: 0.0, z: 0.0 };

	constructor(scene: Scene3D, id: NodeId3D) {
		this.scene = scene;
		this.id = id;
	}

	held(rotation: Quat): Euler {
		if (!sameQuat(rotation, this.written)) {
			this.angles = eulerOf(rotation);
			this.written = rotation;
			this.source = rotation;
			this.sourceAngles = this.angles;
		}
		return this.angles;
	}
}

export struct ObjectBinding {
	slot: string;
	name: string;
	scene: Scene3D;
	id: NodeId3D;
	property: ObjectProperty;
	rotation: ObjectRotation;
}

function current(b: ObjectBinding): Transform3D {
	if (b.scene.isLive(b.id)) { return b.scene.nodes[b.id.index].local; }
	return b.scene.nodes[b.scene.liveRow(b.id, "motion " + b.slot + "." + b.name)].local;
}

function rotate(b: ObjectBinding, t: Transform3D, angles: Euler): void {
	const r = b.rotation;
	const back = angles.x === r.sourceAngles.x && angles.y === r.sourceAngles.y && angles.z === r.sourceAngles.z;
	r.angles = angles;
	r.written = back ? r.source : eulerQuat(angles.x, angles.y, angles.z);
	setLocal(b.scene, b.id, { ...t, rotation: b.rotation.written });
}

export function writeObject(b: ObjectBinding, value: MotionValue): void {
	const v = numberOf(b.slot, b.name, value);
	if (!b.scene.isLive(b.id)) { return; }
	const t = current(b);
	switch (b.property) {
		case ObjectProperty.X: setLocal(b.scene, b.id, { ...t, position: { ...t.position, x: v } }); break;
		case ObjectProperty.Y: setLocal(b.scene, b.id, { ...t, position: { ...t.position, y: v } }); break;
		case ObjectProperty.Z: setLocal(b.scene, b.id, { ...t, position: { ...t.position, z: v } }); break;
		case ObjectProperty.RotationX: rotate(b, t, { ...b.rotation.held(t.rotation), x: v }); break;
		case ObjectProperty.RotationY: rotate(b, t, { ...b.rotation.held(t.rotation), y: v }); break;
		case ObjectProperty.RotationZ: rotate(b, t, { ...b.rotation.held(t.rotation), z: v }); break;
		case ObjectProperty.Scale: setLocal(b.scene, b.id, { ...t, scale: { x: v, y: v, z: v } }); break;
		case ObjectProperty.ScaleX: setLocal(b.scene, b.id, { ...t, scale: { ...t.scale, x: v } }); break;
		case ObjectProperty.ScaleY: setLocal(b.scene, b.id, { ...t, scale: { ...t.scale, y: v } }); break;
		case ObjectProperty.ScaleZ: setLocal(b.scene, b.id, { ...t, scale: { ...t.scale, z: v } }); break;
	}
}

export function readObject(b: ObjectBinding): MotionValue {
	const t = current(b);
	switch (b.property) {
		case ObjectProperty.X: return numberValue(t.position.x);
		case ObjectProperty.Y: return numberValue(t.position.y);
		case ObjectProperty.Z: return numberValue(t.position.z);
		case ObjectProperty.RotationX: return numberValue(b.rotation.held(t.rotation).x);
		case ObjectProperty.RotationY: return numberValue(b.rotation.held(t.rotation).y);
		case ObjectProperty.RotationZ: return numberValue(b.rotation.held(t.rotation).z);
		case ObjectProperty.Scale: return numberValue(uniformScale(b.slot, [t.scale.x, t.scale.y, t.scale.z]));
		case ObjectProperty.ScaleX: return numberValue(t.scale.x);
		case ObjectProperty.ScaleY: return numberValue(t.scale.y);
		case ObjectProperty.ScaleZ: return numberValue(t.scale.z);
	}
}

struct NodeTarget {
	node: NodeRef;
	target: MotionTarget;
}

struct ObjectTarget {
	id: NodeId3D;
	target: MotionTarget;
}

const FIRST_PRUNE: int32 = 64;

class NodeRegistry {
	scene: Scene2D;
	targets: Map<string, NodeTarget> = new Map<string, NodeTarget>();
	pruneAt: int32 = FIRST_PRUNE;

	constructor(scene: Scene2D) {
		this.scene = scene;
	}
}

class ObjectRegistry {
	scene: Scene3D;
	targets: Map<string, ObjectTarget> = new Map<string, ObjectTarget>();
	rotations: Map<string, ObjectRotation> = new Map<string, ObjectRotation>();
	pruneAt: int32 = FIRST_PRUNE;

	constructor(scene: Scene3D) {
		this.scene = scene;
	}
}

let nodeRegistries: NodeRegistry[] = [];
let objectRegistries: ObjectRegistry[] = [];

function slotKey(index: int32, generation: int32): string {
	return index.toString() + ":" + generation.toString();
}

function nodeRegistry(scene: Scene2D): NodeRegistry {
	nodeRegistries = nodeRegistries.filter((r: NodeRegistry): boolean => !r.scene.closed);
	for (const r of nodeRegistries) {
		if (r.scene === scene) { return r; }
	}
	const r = new NodeRegistry(scene);
	nodeRegistries.push(r);
	return r;
}

function objectRegistry(scene: Scene3D): ObjectRegistry {
	objectRegistries = objectRegistries.filter((r: ObjectRegistry): boolean => !r.scene.closed);
	for (const r of objectRegistries) {
		if (r.scene === scene) { return r; }
	}
	const r = new ObjectRegistry(scene);
	objectRegistries.push(r);
	return r;
}

function pruneNodes(r: NodeRegistry): void {
	if (r.targets.size < r.pruneAt) { return; }
	const live = new Map<string, NodeTarget>();
	for (const [key, entry] of r.targets) {
		if (entry.node.isLive()) { live.set(key, entry); }
	}
	r.targets = live;
	r.pruneAt = Math.max(FIRST_PRUNE, 2 * live.size) as int32;
}

function pruneObjects(r: ObjectRegistry): void {
	if (r.targets.size + r.rotations.size < r.pruneAt) { return; }
	const live = new Map<string, ObjectTarget>();
	for (const [key, entry] of r.targets) {
		if (r.scene.isLive(entry.id)) { live.set(key, entry); }
	}
	const turning = new Map<string, ObjectRotation>();
	for (const [key, rotation] of r.rotations) {
		if (r.scene.isLive(rotation.id)) { turning.set(key, rotation); }
	}
	r.targets = live;
	r.rotations = turning;
	r.pruneAt = Math.max(FIRST_PRUNE, 2 * (live.size + turning.size)) as int32;
}

function nodeTarget(b: NodeBinding): MotionTarget {
	const r = nodeRegistry(b.node.scene);
	pruneNodes(r);
	const key = slotKey(b.node.id.index, b.node.id.generation) + ":" + (b.property as int32).toString();
	const found = r.targets.get(key);
	if (found !== null) { return found.target; }
	const target = new MotionTarget((): MotionValue => readNode(b), (value: MotionValue): void => { writeNode(b, value); });
	r.targets.set(key, { node: b.node, target });
	return target;
}

function objectTarget(b: ObjectBinding): MotionTarget {
	const r = objectRegistry(b.scene);
	pruneObjects(r);
	const key = slotKey(b.id.index, b.id.generation) + ":" + (b.property as int32).toString();
	const found = r.targets.get(key);
	if (found !== null) { return found.target; }
	const target = new MotionTarget((): MotionValue => readObject(b), (value: MotionValue): void => { writeObject(b, value); });
	r.targets.set(key, { id: b.id, target });
	return target;
}

function objectRotation(scene: Scene3D, id: NodeId3D): ObjectRotation {
	const r = objectRegistry(scene);
	const key = slotKey(id.index, id.generation);
	const found = r.rotations.get(key);
	if (found !== null) { return found; }
	const rotation = new ObjectRotation(scene, id);
	r.rotations.set(key, rotation);
	return rotation;
}

export class VoidBindings {
	bindings: MotionBinding[] = [];

	node(slot: string, node: NodeRef, properties: string[]): void {
		refuseScaleOverlap(slot, properties);
		for (const name of properties) {
			const b: NodeBinding = { slot, name, node, property: nodeProperty(slot, name) };
			this.bindings.push({
				slot,
				property: name,
				write: (value: MotionValue): void => { writeNode(b, value); },
				read: (): MotionValue => readNode(b),
				target: nodeTarget(b),
			});
		}
	}

	object(slot: string, scene: Scene3D, id: NodeId3D, properties: string[]): void {
		refuseScaleOverlap(slot, properties);
		const rotation = objectRotation(scene, id);
		for (const name of properties) {
			const b: ObjectBinding = { slot, name, scene, id, property: objectProperty(slot, name), rotation };
			this.bindings.push({
				slot,
				property: name,
				write: (value: MotionValue): void => { writeObject(b, value); },
				read: (): MotionValue => readObject(b),
				target: objectTarget(b),
			});
		}
	}
}
