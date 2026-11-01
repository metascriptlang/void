import { Color } from "../void2d/types";
import {
	NodeRef,
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

	constructor(scene: Scene3D, id: NodeId3D) {
		this.scene = scene;
		this.id = id;
	}

	held(rotation: Quat): Euler {
		if (!sameQuat(rotation, this.written)) {
			this.angles = eulerOf(rotation);
			this.written = rotation;
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
	return b.scene.nodes[b.scene.liveRow(b.id, "motion " + b.slot + "." + b.name)].local;
}

function rotate(b: ObjectBinding, t: Transform3D, angles: Euler): void {
	b.rotation.angles = angles;
	b.rotation.written = eulerQuat(angles.x, angles.y, angles.z);
	setLocal(b.scene, b.id, { ...t, rotation: b.rotation.written });
}

export function writeObject(b: ObjectBinding, value: MotionValue): void {
	const v = numberOf(b.slot, b.name, value);
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
	property: NodeProperty;
	target: MotionTarget;
}

struct ObjectTarget {
	scene: Scene3D;
	id: NodeId3D;
	property: ObjectProperty;
	target: MotionTarget;
}

let nodeTargets: NodeTarget[] = [];
let objectTargets: ObjectTarget[] = [];
let rotations: ObjectRotation[] = [];

function sameNode(a: NodeRef, b: NodeRef): boolean {
	return a.scene === b.scene && a.id.index === b.id.index && a.id.generation === b.id.generation;
}

function sameObject(scene: Scene3D, id: NodeId3D, otherScene: Scene3D, other: NodeId3D): boolean {
	return scene === otherScene && id.index === other.index && id.generation === other.generation;
}

function nodeTarget(b: NodeBinding): MotionTarget {
	nodeTargets = nodeTargets.filter((entry: NodeTarget): boolean => entry.node.isLive());
	for (const entry of nodeTargets) {
		if (entry.property === b.property && sameNode(entry.node, b.node)) { return entry.target; }
	}
	const target = new MotionTarget((): MotionValue => readNode(b), (value: MotionValue): void => { writeNode(b, value); });
	nodeTargets.push({ node: b.node, property: b.property, target });
	return target;
}

function objectTarget(b: ObjectBinding): MotionTarget {
	objectTargets = objectTargets.filter((entry: ObjectTarget): boolean => entry.scene.isLive(entry.id));
	for (const entry of objectTargets) {
		if (entry.property === b.property && sameObject(entry.scene, entry.id, b.scene, b.id)) { return entry.target; }
	}
	const target = new MotionTarget((): MotionValue => readObject(b), (value: MotionValue): void => { writeObject(b, value); });
	objectTargets.push({ scene: b.scene, id: b.id, property: b.property, target });
	return target;
}

function objectRotation(scene: Scene3D, id: NodeId3D): ObjectRotation {
	rotations = rotations.filter((entry: ObjectRotation): boolean => entry.scene.isLive(entry.id));
	for (const entry of rotations) {
		if (sameObject(entry.scene, entry.id, scene, id)) { return entry; }
	}
	const rotation = new ObjectRotation(scene, id);
	rotations.push(rotation);
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
