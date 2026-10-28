import {
	glyphFaceBytes,
	void2dGlyphPageBytes,
	void2dGlyphPageCount,
	void2dGlyphPageGeneration,
	void2dGlyphPageKind,
	void2dGlyphPageSize,
	void2dGlyphPageTakeUpload,
	void2dGlyphPagesFrameBegin,
	void2dGlyphPagesMarkDirty,
	state,
	validPage,
} from "./glyph";

when (c) {
	@exportName("void2dGlyphPageBytes")
	export function exportPageBytes(page: int32): int32 {
		return void2dGlyphPageBytes(page);
	}

	@exportName("void2dGlyphPageCount")
	export function exportPageCount(): int32 {
		return void2dGlyphPageCount();
	}

	@exportName("void2dGlyphPageGeneration")
	export function exportPageGeneration(page: int32): uint32 {
		return void2dGlyphPageGeneration(page);
	}

	@exportName("void2dGlyphPageKind")
	export function exportPageKind(page: int32): int32 {
		return void2dGlyphPageKind(page);
	}

	@exportName("void2dGlyphPageSize")
	export function exportPageSize(page: int32): int32 {
		return void2dGlyphPageSize(page);
	}

	@exportName("void2dGlyphPageTakeUpload")
	export function exportPageTakeUpload(page: int32): int32 {
		return void2dGlyphPageTakeUpload(page);
	}

	@exportName("void2dGlyphPagesFrameBegin")
	export function exportPagesFrameBegin(): void {
		void2dGlyphPagesFrameBegin();
	}

	@exportName("void2dGlyphPagesMarkDirty")
	export function exportPagesMarkDirty(): void {
		void2dGlyphPagesMarkDirty();
	}

	@exportName("void2dGlyphPageData")
	export function exportPageData(page: int32): Ptr<uint8> | null {
		if (!validPage(page)) { return null; }
		return (state.pages[page].texels as Span<uint8>) as Ptr<uint8>;
	}

	@exportName("void2dGlyphPageUploadBox")
	export function exportPageUploadBox(page: int32): Ptr<int32> | null {
		if (page < 0 || page >= (state.pages.length as int32)) { return null; }
		return (state.pages[page].takenBox as Span<int32>) as Ptr<int32>;
	}

	@exportName("void2dGlyphFaceData")
	export function exportFaceData(face: int32, length: Ptr<int32>): Ptr<uint8> | null {
		const holder = glyphFaceBytes(face);
		if (holder == null) { return null; }
		length[0] = holder.data.length as int32;
		return (holder.data as Span<uint8>) as Ptr<uint8>;
	}
}
