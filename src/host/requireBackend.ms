import { Node, NodeKind } from "std/meta";

export macro requireBrowserBackend(): Node {
	const none: Node = { kind: NodeKind.NullLiteral, line: 0, column: 0 };
	error("void on --target=js names its browser API: pass -d:webgpu or -d:webgl2 to msc", none);
	return none;
}
