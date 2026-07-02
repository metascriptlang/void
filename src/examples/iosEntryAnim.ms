// Void — iOS embed entry (animated demo). Registers renderer2d's init2d/frame2d, and wires
// the message system (message.ms self-registers the pump on import). Game message handlers
// register with voidOnMessage — empty here since this is a render demo, not a game.

import { init2d, frame2d } from "./renderer2d";
import { voidOnMessage } from "../void2d/message";

@include("bridge.h");
extern function voidEmbedRegister(init: () => void, frame: () => void): void;

// Host (React-Native) messages arrive here, in MetaScript — the Void equivalent of Godot's
// GDScript message_received. Game logic goes here; no-op in this demo.
function onMsg(m: string): void {}

function main(): int32 {
	voidEmbedRegister(init2d, frame2d);
	voidOnMessage(onMsg);
	return 0;
}
