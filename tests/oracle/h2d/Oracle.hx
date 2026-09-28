typedef Spec = {
	var kind : String;
	@:optional var x : Float;
	@:optional var y : Float;
	@:optional var scaleX : Float;
	@:optional var scaleY : Float;
	@:optional var rotation : Float;
	@:optional var w : Float;
	@:optional var h : Float;
	@:optional var dx : Float;
	@:optional var dy : Float;
	@:optional var scrollX : Float;
	@:optional var scrollY : Float;
	@:optional var scrollBounds : Array<Float>;
	@:optional var visible : Bool;
	@:optional var children : Array<Spec>;
}

class Oracle {
	static function num(v : Null<Float>, fallback : Float) : Float {
		return v == null ? fallback : v;
	}

	static function build(spec : Spec, parent : h2d.Object, nodes : Array<h2d.Object>) : Void {
		var o : h2d.Object = switch( spec.kind ) {
			case "bitmap":
				var t = @:privateAccess new h2d.Tile(null, 0, 0, spec.w, spec.h, num(spec.dx, 0), num(spec.dy, 0));
				new h2d.Bitmap(t, parent);
			case "mask":
				new h2d.Mask(Std.int(spec.w), Std.int(spec.h), parent);
			default:
				new h2d.Object(parent);
		}
		o.x = num(spec.x, 0);
		o.y = num(spec.y, 0);
		o.scaleX = num(spec.scaleX, 1);
		o.scaleY = num(spec.scaleY, 1);
		o.rotation = num(spec.rotation, 0);
		if( spec.visible != null ) o.visible = spec.visible;
		nodes.push(o);
		if( spec.kind == "mask" ) {
			var m : h2d.Mask = cast o;
			if( spec.scrollBounds != null ) {
				var b = spec.scrollBounds;
				m.scrollBounds = h2d.col.Bounds.fromValues(b[0], b[1], b[2] - b[0], b[3] - b[1]);
			}
			m.scrollTo(num(spec.scrollX, 0), num(spec.scrollY, 0));
		}
		if( spec.children != null )
			for( c in spec.children ) build(c, o, nodes);
	}

	static function point(p : h2d.col.Point) : Array<Float> {
		return [p.x, p.y];
	}

	static function bitmap(w : Float, h : Float, ?at : Array<Float>) : Spec {
		return { kind: "bitmap", w: w, h: h, x: at == null ? 0 : at[0], y: at == null ? 0 : at[1] };
	}

	static function cases() : Array<{ name : String, tree : Spec }> {
		return [
			{ name: "bitmap", tree: bitmap(40, 20, [10, 5]) },
			{ name: "tileOffset", tree: { kind: "bitmap", w: 40, h: 20, dx: -20, dy: -10, x: 50, y: 50 } },
			{ name: "scaled", tree: { kind: "bitmap", w: 30, h: 10, x: 5, y: 7, scaleX: 2, scaleY: 0.5 } },
			{ name: "rotated", tree: { kind: "bitmap", w: 40, h: 20, x: 60, y: 40, rotation: 0.5 } },
			{ name: "mirrored", tree: { kind: "bitmap", w: 20, h: 10, x: 40, y: 10, scaleX: -1 } },
			{ name: "nested", tree: { kind: "object", x: 10, y: 10, rotation: 0.3, scaleX: 1.5, scaleY: 1.5, children: [
				{ kind: "object", x: 20, y: 0, scaleX: 0.5, scaleY: 0.5, children: [
					{ kind: "bitmap", w: 16, h: 16, x: 4, y: 4, rotation: -0.2 },
				] },
			] } },
			{ name: "emptyObject", tree: { kind: "object", x: 12, y: 34 } },
			{ name: "union", tree: { kind: "object", x: 3, y: 2, children: [
				bitmap(10, 10), bitmap(5, 5, [30, 40]),
			] } },
			{ name: "hiddenChild", tree: { kind: "object", children: [
				bitmap(10, 10), { kind: "bitmap", w: 50, h: 50, x: 100, y: 100, visible: false },
			] } },
			{ name: "mask", tree: { kind: "mask", w: 50, h: 30, x: 10, y: 10, children: [
				bitmap(100, 100, [-20, -20]),
			] } },
			{ name: "maskScrolled", tree: { kind: "mask", w: 50, h: 30, x: 10, y: 10, scrollX: 5, scrollY: 12, children: [
				bitmap(40, 10, [0, 0]), bitmap(40, 10, [0, 20]), bitmap(40, 10, [0, 40]),
			] } },
			{ name: "maskNested", tree: { kind: "mask", w: 60, h: 60, children: [
				{ kind: "mask", w: 40, h: 40, x: 30, y: 30, children: [ bitmap(100, 100, [-50, -50]) ] },
			] } },
			{ name: "maskRotated", tree: { kind: "mask", w: 50, h: 30, x: 40, y: 20, rotation: 0.4, children: [
				bitmap(80, 80, [-10, -10]),
			] } },
			{ name: "maskScrollBounds", tree: { kind: "mask", w: 40, h: 40, scrollBounds: [0, 0, 40, 200], scrollY: 500, children: [
				bitmap(40, 200),
			] } },
			{ name: "maskInsideContent", tree: { kind: "mask", w: 80, h: 80, children: [
				bitmap(20, 20, [10, 10]),
			] } },
		];
	}

	static function viewport(mode : h2d.Scene.ScaleMode, width : Int, height : Int) : Dynamic {
		var engine = Type.createEmptyInstance(h3d.Engine);
		@:privateAccess engine.width = width;
		@:privateAccess engine.height = height;
		@:privateAccess h3d.Engine.CURRENT = engine;
		var scene = Type.createEmptyInstance(h2d.Scene);
		scene.scaleMode = mode;
		var a : Float = @:privateAccess scene.viewportA;
		var d : Float = @:privateAccess scene.viewportD;
		var x : Float = @:privateAccess scene.viewportX;
		var y : Float = @:privateAccess scene.viewportY;
		return {
			window: [width, height],
			scale: [a * width / 2, d * height / 2],
			offset: [(x + 1) * width / 2, (y + 1) * height / 2],
		};
	}

	static function scaleModes() : Array<Dynamic> {
		var out : Array<Dynamic> = [];
		var windows = [[800, 600], [1000, 600], [801, 599], [640, 900]];
		for( w in windows ) {
			var rows : Array<{ name : String, design : Array<Int>, mode : h2d.Scene.ScaleMode }> = [
				{ name: "Resize", design: [0, 0], mode: Resize },
				{ name: "Stretch", design: [400, 300], mode: Stretch(400, 300) },
				{ name: "LetterBox", design: [400, 300], mode: LetterBox(400, 300) },
				{ name: "Fixed", design: [400, 300], mode: Fixed(400, 300, 1) },
			];
			for( r in rows ) {
				var v = viewport(r.mode, w[0], w[1]);
				v.name = r.name;
				v.design = r.design;
				out.push(v);
			}
		}
		return out;
	}

	static function main() {
		var path : String = js.Syntax.code("process.argv[2]");
		var out = [];
		for( c in cases() ) {
			var root = new h2d.Object();
			var nodes : Array<h2d.Object> = [];
			build(c.tree, root, nodes);
			var results = [];
			for( n in nodes ) {
				var b = n.getBounds();
				results.push({
					bounds: [b.xMin, b.yMin, b.xMax, b.yMax],
					origin: point(n.localToGlobal(new h2d.col.Point(0, 0))),
					corner: point(n.localToGlobal(new h2d.col.Point(3, 7))),
					local: point(n.globalToLocal(new h2d.col.Point(20, 30))),
				});
			}
			out.push({ name: c.name, tree: c.tree, results: results });
		}
		var heaps : String = js.Syntax.code("process.argv[3]");
		var text = haxe.Json.stringify({ heaps: heaps, cases: out, scaleModes: scaleModes() }, null, "\t");
		js.Syntax.code("require('fs').writeFileSync({0}, {1} + '\\n')", path, text);
		js.Syntax.code("process.exit(0)");
	}
}
