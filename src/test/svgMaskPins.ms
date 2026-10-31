// Digests of svgMask.c over the SVG corpus, recorded before that file was deleted: parse code,
// refusal reason, size and the alpha of five raster sizes per document, for the documents with
// no skew transform. "skew" was recorded from the port: libm tanf and the double tan the port
// rounds to float32 differ in the last bit, which moves 152 of 15.27M pixels by one or two levels.
// edges, gen1, gen2, gen5 and skew were re-recorded from the port, which refuses on purpose a CSS
// comment and geometry past the rasterizer's fixed-point reach at the largest mask (UB in nanosvg).
export const SVG_PINS: string[] = [
	"fixtures b9423f7f5568236f",
	"edges 5446f9ab66604e3f",
	"gen0 246ec2ccabef925f",
	"gen1 3cc48edbdf1137fc",
	"gen2 783061ebc62726c4",
	"gen3 ca64fcf491432ca9",
	"gen4 fd66b288210bbda5",
	"gen5 f1bc00ada6f08260",
	"skew 628aa53f8b8557bf",
];
