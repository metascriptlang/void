// JS ↔ Void messaging for MetaScript game code. The Void equivalent of Godot's GDScript
// `message_received` signal: register voidOnMessage(handler) to receive host (React-Native)
// messages, and call voidEmit(json) to send messages back to JS. Messages are JSON strings.

@include("bridge.h");
@compile("../sokol/voidRelay.c");
@compile("../sokol/voidMessage.c");
import { voidRelayEmit, voidRelayNext } from "../sokol/voidMessage.h";

extern function voidEmbedSetMessagePump(pump: () => void): void;

type MessageHandler = (msg: string) => void;

// Default no-op (avoids a nullable-closure union); replaced by voidOnMessage.
let handler: MessageHandler = (msg: string) => {};

export function voidOnMessage(h: MessageHandler): void {
	handler = h;
}

export function voidEmit(msg: string): void {
	voidRelayEmit(msg);
}

// Called once per frame by the bridge: drain every pending host→void message into the handler.
function pump(): void {
	let m: string = voidRelayNext();
	while (m.length > 0) {
		handler(m);
		m = voidRelayNext();
	}
}

voidEmbedSetMessagePump(pump);
