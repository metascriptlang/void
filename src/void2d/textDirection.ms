export enum TextDirection {
	Auto,
	Ltr,
	Rtl,
}

export function possiblyRtl(codepoint: int32): boolean {
	if (codepoint < 0x0590) { return false; }
	if (codepoint <= 0x08FF) { return true; }
	if (codepoint < 0x200F) { return false; }
	if (codepoint == 0x200F || codepoint == 0x202B || codepoint == 0x202E) { return true; }
	if (codepoint == 0x2067 || codepoint == 0x2068) { return true; }
	if (codepoint < 0xFB1D) { return false; }
	if (codepoint <= 0xFDFF) { return true; }
	if (codepoint >= 0xFE70 && codepoint <= 0xFEFF) { return true; }
	if (codepoint >= 0x10800 && codepoint <= 0x10FFF) { return true; }
	return codepoint >= 0x1E800 && codepoint <= 0x1EFFF;
}
