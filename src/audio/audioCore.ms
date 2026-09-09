// Void audio — LOGIC in MetaScript. This is the whole audio engine above the device: WAV
// decode, voice allocation, safe handles and fade math all live here. C (audio.c) is only
// the "audio primitive" tier — the device + the per-sample mix kernel that must run on
// sokol's audio thread (where the MetaScript runtime is not safe). Mirrors the void2d split:
// draw.ms owns the batcher logic, batcher.c only does the sokol/fontstash primitives.
//
// OS-agnostic: the per-OS link flags live in the thin audio.{ms,linux,windows}.ms shims that
// re-export this module (same shape as sokol/gpu.*.ms wrapping one renderer).
//
// `import from "./audio.h"` parses the C header and auto-compiles audio.c; @passC lets that
// unit find sokol_audio.h. voidAudioRegisterClip is hand-declared (not auto-imported) so its
// `const float *pcm` maps to Borrow<float32> — same pattern as draw.ms's void2dUploadDraw.
// -Ideps/sokol: sokol_audio.h. -Ideps/stb: stb_vorbis.c (OGG decoder). -lm: stb_vorbis uses libm.
@passC("-Ideps/sokol");
@passC("-Ideps/stb");
@passL("-lm");

import {
	voidAudioSetup, voidAudioShutdown, voidAudioLoadFile, voidAudioLoadOgg, voidAudioClipFrames,
	voidAudioSlotActive, voidAudioVoiceStart, voidAudioStreamStart, voidAudioVoiceStop,
	voidAudioVoiceQueue, voidAudioStopAll, voidAudioStopGroup, voidAudioSuspend,
	voidAudioVoicePause, voidAudioVoiceSeek, voidAudioVoicePos, voidAudioVoicePitch,
	voidAudioVoiceVol, voidAudioVoiceSetVol, voidAudioVoiceFade, voidAudioVoicePan,
	voidAudioVoiceSpatial, voidAudioVoiceLowPass,
	voidAudioGroupVol, voidAudioMasterVol
} from "./audio.h";

// Hand-declared (not auto-imported) so the C pointer types map to Borrow/Ptr — same pattern as
// draw.ms's void2dUploadDraw. registerClip takes the decoded PCM buffer head; fileBytes returns
// the slurped WAV bytes we index during decode.
extern function voidAudioRegisterClip(pcm: Borrow<float32>, frames: int32, channels: int32, rate: int32): int32;
extern function voidAudioFileBytes(): Ptr<uint8>;

const MAX_VOICES: int32 = 16;
const DEVICE_RATE: float32 = 44100.0;
const MAX_GAIN: float32 = 4.0;

// Flat sub-mix buses — the "gain tree" middle tier (master → group → voice), the one hxd.snd
// abstraction void takes wholesale. These four mirror a card game's mix exactly (underrealm's
// audio_manager.gd: BGM / SFX / UI / VOICE). NOT a routing graph — one gain per bus. Kept
// internal (named play*/…Volume wrappers below expose them) so callers never juggle raw indices.
const GROUP_BGM: int32 = 0;
const GROUP_SFX: int32 = 1;
const GROUP_UI: int32 = 2;
const GROUP_VOICE: int32 = 3;

// Generation per voice slot — the other half of the safe handle. Lives in MetaScript
// (main-thread only; the audio thread never reads it). A public handle is (gen << 16 | slot);
// bumping gen on every (re)use makes a stale handle to a recycled slot resolve to -1, so
// stop/setVol/fade on it no-op instead of hitting whatever sound now owns the slot.
const gen: Vec<int32> = new Array(MAX_VOICES);

// ---- positional-audio state (coordinate-based; the logic lives in the tier-E section at the end).
// Listener + per-slot source position, parallel to the C voice slots. Declared next to `gen` (the
// other per-slot main-thread table) so reserveSlot can clear `spat` when a slot is reused.
let listenerX: float32 = 0.0;
let listenerY: float32 = 0.0;
let listenerZ: float32 = 0.0;
let defRef: float32 = 1.0;          // default reference distance for playSoundAt (full volume within)
let defMax: float32 = 1000.0;       // default max distance (gain / muffle floor past it)
let panStrength: float32 = 1.0;     // 0 = centred … 1 = full directional pan
let muffleAmt: float32 = 0.0;       // 0 = no distance low-pass; > 0 enables the Godot-style muffle
const LP_OPEN_HZ: float32 = 20000.0;   // cutoff at/above this = filter open (Godot's "disable" convention)
const LP_MIN_HZ: float32 = 500.0;      // cutoff floor at max distance when muffle = 1
const srcX: Vec<float32> = new Array(MAX_VOICES);
const srcY: Vec<float32> = new Array(MAX_VOICES);
const srcZ: Vec<float32> = new Array(MAX_VOICES);
const srcRef: Vec<float32> = new Array(MAX_VOICES);
const srcMax: Vec<float32> = new Array(MAX_VOICES);
const spat: Vec<int32> = new Array(MAX_VOICES);     // 1 = this slot is spatialized

function clampGain(x: float32): float32 {
	return x < 0.0 ? 0.0 : (x > MAX_GAIN ? MAX_GAIN : x);
}

// Shared small math — single source of truth so manual setPan and the positional path can't drift.
function clampUnit(x: float32): float32 { return x < -1.0 ? -1.0 : (x > 1.0 ? 1.0 : x); }   // → [-1, 1]
function panGainL(pan: float32): float32 { return pan <= 0.0 ? 1.0 : 1.0 - pan; }           // balance law, L
function panGainR(pan: float32): float32 { return pan >= 0.0 ? 1.0 : 1.0 + pan; }           // balance law, R
function safeRef(r: float32): float32 { return r > 0.001 ? r : 0.001; }                     // positive reference dist
function safeMax(m: float32, ref: float32): float32 { return m > ref ? m : ref + 0.001; }   // maxDist strictly > ref

// Tiny LCG (stdlib has no random) for per-shot pitch/volume jitter — same generator as magicCat.
const RAND_DIV: float32 = 32768.0;   // float32 divisor so the result stays float32 (not float64)
let rngSeed: uint32 = 2463534242;
function randUnit(): float32 {   // [0, 1)
	rngSeed = rngSeed * 1103515245 + 12345;
	return ((((rngSeed >> 16) & 0x7fff) as int32) as float32) / RAND_DIV;
}

// ---- little-endian scalar reads over the WAV byte buffer (Ptr<uint8> from the C slurp) ----
function u16(b: Ptr<uint8>, o: int32): int32 {
	return (b[o] as int32) | ((b[o + 1] as int32) << 8);
}
function u32(b: Ptr<uint8>, o: int32): int32 {
	return (b[o] as int32) | ((b[o + 1] as int32) << 8)
	     | ((b[o + 2] as int32) << 16) | ((b[o + 3] as int32) << 24);
}
// four-byte chunk tag compare (ASCII codes)
function tag(b: Ptr<uint8>, o: int32, c0: int32, c1: int32, c2: int32, c3: int32): boolean {
	return (b[o] as int32) == c0 && (b[o + 1] as int32) == c1
	    && (b[o + 2] as int32) == c2 && (b[o + 3] as int32) == c3;
}

// ---- lifecycle ----
export function audioSetup(): void { voidAudioSetup(); }
export function audioShutdown(): void { voidAudioShutdown(); }

// Frame count of a loaded clip (duration = frames / 44100), or -1 if the clip id is invalid.
export function clipFrames(clip: int32): int32 { return voidAudioClipFrames(clip); }

// Decode a 16-bit PCM WAV → clip id, or -1 (missing / unsupported). Any sample rate is accepted —
// the clip keeps its native rate and the mixer resamples to the device rate (tier B). Parsing is
// pure MetaScript over the file bytes.
export function loadSound(path: string): int32 {
	const n: int32 = voidAudioLoadFile(path);
	if (n < 44) { return -1; }                           // missing, empty, or too small for a header
	const bytes: Ptr<uint8> = voidAudioFileBytes();
	if (!tag(bytes, 0, 82, 73, 70, 70)) { return -1; }   // "RIFF"
	if (!tag(bytes, 8, 87, 65, 86, 69)) { return -1; }   // "WAVE"

	let fmt: int32 = 0;
	let channels: int32 = 0;
	let rate: int32 = 0;
	let bits: int32 = 0;
	let haveFmt: boolean = false;
	let pos: int32 = 12;
	while (pos + 8 <= n) {
		const csz: int32 = u32(bytes, pos + 4);
		const body: int32 = pos + 8;
		if (tag(bytes, pos, 102, 109, 116, 32)) {           // "fmt "
			fmt      = u16(bytes, body);
			channels = u16(bytes, body + 2);
			rate     = u32(bytes, body + 4);
			bits     = u16(bytes, body + 14);
			haveFmt  = true;
		} else if (tag(bytes, pos, 100, 97, 116, 97)) {     // "data"
			if (!haveFmt || fmt != 1 || bits != 16 || channels < 1 || rate < 1) { return -1; }
			// any rate ok — the clip keeps its native rate and the mixer resamples (tier B)
			let dataEnd: int32 = body + csz;
			if (dataEnd > n) { dataEnd = n; }               // tolerate a truncated/rounded size
			const nsamp: int32 = (dataEnd - body) / 2;      // total int16 samples (all channels)
			if (nsamp < channels) { return -1; }
			const pcm: Vec<float32> = new Array(nsamp);
			let i: int32 = 0;
			let p: int32 = body;
			while (i < nsamp) {
				let s: int32 = (bytes[p] as int32) | ((bytes[p + 1] as int32) << 8);
				if (s >= 32768) { s = s - 65536; }          // sign-extend int16
				pcm[i] = (s as float32) / 32768.0;
				i = i + 1;
				p = p + 2;
			}
			return voidAudioRegisterClip(pcm[0], nsamp / channels, channels, rate);
		}
		pos = body + csz + (csz & 1);                       // chunks are word-aligned
	}
	return -1;
}

// Decode a full OGG/Vorbis file → clip id, or -1 (missing / corrupt / not 44100 Hz). Vorbis is a
// heavy codec, so unlike WAV (parsed here in MetaScript) the decode is done in C by stb_vorbis
// (docs/AUDIO.md escape hatch). The clip it returns is the same format-neutral PCM, so the voice
// model is unchanged — plug-in, not rewrite. Whole-file; long BGM will stream (tier C).
export function loadOgg(path: string): int32 { return voidAudioLoadOgg(path); }

// ---- voice model + safe handle (all MetaScript; C just executes the slot ops) ----
// Claim the first free voice slot, bumping its generation, → slot index (or -1 if all busy).
// The generation bump is what makes an old handle to this recycled slot resolve to -1.
function reserveSlot(): int32 {
	let slot: int32 = 0;
	while (slot < MAX_VOICES) {
		if (voidAudioSlotActive(slot) == 0) {
			gen[slot] = (gen[slot] + 1) & 0xFFFF;
			spat[slot] = 0;                                     // a reused slot starts non-spatial
			return slot;
		}
		slot = slot + 1;
	}
	return -1;                                              // all voices busy
}

// Form the public handle for a reserved slot — the inverse of resolve().
function handleOf(slot: int32): int32 { return (gen[slot] << 16) | slot; }

function play(clip: int32, group: int32, loop: int32, vol: float32): int32 {
	if (clip < 0) { return -1; }
	const slot: int32 = reserveSlot();
	if (slot < 0) { return -1; }
	voidAudioVoiceStart(slot, clip, loop, clampGain(vol), group);
	return handleOf(slot);
}

// Resolve a public handle → live slot, or -1 if the slot was recycled (generation mismatch).
function resolve(handle: int32): int32 {
	if (handle < 0) { return -1; }
	const slot: int32 = handle & 0xFFFF;
	const g: int32 = (handle >> 16) & 0xFFFF;
	if (slot < 0 || slot >= MAX_VOICES) { return -1; }
	if (gen[slot] != g) { return -1; }
	return slot;
}

// One entry per bus — the loop flag and group are implied by intent, so callers never pass raw
// indices. SFX/UI/VOICE are one-shots; music loops. All return a voice handle (-1 if none free).
export function playSound(clip: int32, vol: float32): int32 { return play(clip, GROUP_SFX, 0, vol); }
export function playMusic(clip: int32, vol: float32): int32 { return play(clip, GROUP_BGM, 1, vol); }
export function playUI(clip: int32, vol: float32): int32 { return play(clip, GROUP_UI, 0, vol); }
export function playVoice(clip: int32, vol: float32): int32 { return play(clip, GROUP_VOICE, 0, vol); }

// Play a SFX with per-shot pitch + slight volume jitter so repeats don't sound identical (Godot's
// AudioStreamRandomizer — the cheap game-feel win). `jitter` in [0,1]: pitch = 1 ± jitter, volume
// dips up to 30%·jitter. Returns the voice handle. (Pick a random clip from a pool game-side.)
export function playVaried(clip: int32, vol: float32, jitter: float32): int32 {
	const p: float32 = 1.0 + (randUnit() * 2.0 - 1.0) * jitter;   // 1 ± jitter
	const v: float32 = vol * (1.0 - randUnit() * jitter * 0.3);
	const h: int32 = playSound(clip, v);
	if (h >= 0) { setPitch(h, p); }
	return h;
}

// Stream a long BGM straight from disk on the BGM bus — decoded incrementally by a background
// thread into a ring buffer, so a multi-minute track never sits fully decoded in RAM (the tier-C
// win for mobile). Loops by default; returns a voice handle usable with fadeTo/fadeOut/setVolume/
// setPan (so crossfade + ducking compose on top), or -1 (missing / not 44100 Hz / no free voice /
// no free stream slot / Windows-not-yet). Same safe-handle model as play().
export function playStream(path: string, vol: float32): int32 {
	const slot: int32 = reserveSlot();
	if (slot < 0) { return -1; }                           // all voices busy
	// open failed (missing / wrong rate / no stream slot / Windows) — slot stays inactive, so free again
	if (voidAudioStreamStart(slot, path, 1, clampGain(vol), GROUP_BGM) != 0) { return -1; }
	return handleOf(slot);
}

export function stopSound(handle: int32): void {
	const slot: int32 = resolve(handle);
	if (slot >= 0) { voidAudioVoiceStop(slot); }
}

// True while the handle's voice is still sounding; false once it finished (drained/stopped) or the
// slot was recycled. The thread-safe alternative to an onEnd callback (which can't fire from the
// audio thread): a game polls this each frame to sequence "when this ends, do X".
export function isPlaying(handle: int32): boolean {
	const slot: int32 = resolve(handle);
	return slot >= 0 && voidAudioSlotActive(slot) == 1;
}

// Queue a clip to play GAPLESSLY after `handle`'s current clip ends (e.g. intro → loop, or a
// stitched playlist). Clip voices only; no-op on a stale handle or a stream. Queue up to 8 deep.
export function queueSound(handle: int32, clip: int32): void {
	const slot: int32 = resolve(handle);
	if (slot >= 0) { voidAudioVoiceQueue(slot, clip); }
}

// Bulk stop: everything, or one bus. Groups: 0=BGM 1=SFX 2=UI 3=VOICE (GROUP_* below). Handy on
// scene changes ("stop all SFX") without tracking every handle.
export function stopAll(): void { voidAudioStopAll(); }
export function stopGroup(group: int32): void { voidAudioStopGroup(group); }

// Global pause/resume — silence + freeze every voice (cursors don't advance), for app focus loss.
// Resume continues exactly where it stopped.
export function suspendAudio(): void { voidAudioSuspend(1); }
export function resumeAudio(): void { voidAudioSuspend(0); }

// Pause/resume ONE voice (menu pause of the BGM, etc.) — position is held; resume continues.
export function pauseSound(handle: int32): void {
	const slot: int32 = resolve(handle);
	if (slot >= 0) { voidAudioVoicePause(slot, 1); }
}
export function resumeSound(handle: int32): void {
	const slot: int32 = resolve(handle);
	if (slot >= 0) { voidAudioVoicePause(slot, 0); }
}

// Seek a clip voice to `sec` seconds (clip voices only — stream seek is a follow-up). Stale → no-op.
export function seekSound(handle: int32, sec: float32): void {
	const slot: int32 = resolve(handle);
	if (slot >= 0) { voidAudioVoiceSeek(slot, (sec * DEVICE_RATE) as int32); }
}

// Current playback position in seconds of a clip voice, or -1 (stream / stale / finished).
export function playbackSeconds(handle: int32): float32 {
	const slot: int32 = resolve(handle);
	if (slot < 0) { return -1.0; }
	const fr: int32 = voidAudioVoicePos(slot);
	return fr < 0 ? -1.0 : (fr as float32) / DEVICE_RATE;
}

// Snap a voice's gain immediately (cancels any in-flight fade). Stale handle → ignored.
export function setVolume(handle: int32, vol: float32): void {
	const slot: int32 = resolve(handle);
	if (slot >= 0) { voidAudioVoiceSetVol(slot, clampGain(vol)); }
}

// Fade math (MetaScript): convert (target, seconds) → per-sample step from the live gain,
// then hand the armed fade to the kernel. stopAtEnd=1 deactivates the voice on arrival.
function fade(handle: int32, target: float32, sec: float32, stopAtEnd: int32): void {
	const slot: int32 = resolve(handle);
	if (slot < 0) { return; }
	const t: float32 = clampGain(target);
	const cur: float32 = voidAudioVoiceVol(slot);
	if (sec <= 0.0 || cur == t) {                           // instantaneous
		voidAudioVoiceSetVol(slot, t);
		if (stopAtEnd == 1 && t == 0.0) { voidAudioVoiceStop(slot); }
		return;
	}
	const step: float32 = (t - cur) / (sec * DEVICE_RATE);
	voidAudioVoiceFade(slot, t, step, stopAtEnd);
}

export function fadeTo(handle: int32, target: float32, sec: float32): void { fade(handle, target, sec, 0); }
export function fadeOut(handle: int32, sec: float32): void { fade(handle, 0.0, sec, 1); }

// Stereo pan: p in [-1, +1] (−1 = full left, 0 = center, +1 = full right). Balance law — center
// keeps both channels at full (no volume dip), panning fades the opposite channel toward 0. Stale
// handle → ignored.
export function setPan(handle: int32, p: float32): void {
	const slot: int32 = resolve(handle);
	if (slot < 0) { return; }
	const pan: float32 = clampUnit(p);
	voidAudioVoicePan(slot, panGainL(pan), panGainR(pan));
}

// Playback speed / pitch (1.0 = native; 2.0 = octave up + double speed). Independent of, and on
// top of, the automatic rate-resample. Clip voices only; stale handle ignored.
export function setPitch(handle: int32, pitch: float32): void {
	const slot: int32 = resolve(handle);
	if (slot >= 0) { voidAudioVoicePitch(slot, pitch); }
}

export function masterVolume(vol: float32): void { voidAudioMasterVol(clampGain(vol)); }

// ---- adaptive music: crossfade + ducking (the "exceed" layer) --------------------------------
// Pure composition over fadeTo + the BGM bus + the 2 stream slots — no new C. A tiny director
// tracks the "current BGM" handle so a game can crossfade tracks (smooth, vs underrealm's hard
// cut) and duck it under a voice line. Source-agnostic: the tracked handle can be a stream
// (playStream) or a clip loop (playMusic) — fadeTo doesn't care.
let curBgm: int32 = -1;      // handle of the BGM the director currently owns, or -1
let curBgmVol: float32 = 1.0; // its un-ducked target volume (so duck/unduck know where to return)

// Make an already-started (at vol 0) handle the current BGM, crossfading from the previous one:
// the old BGM fades out (and frees itself), the new fades in — both over `sec`.
export function crossfadeTo(handle: int32, vol: float32, sec: float32): void {
	if (handle < 0) { return; }
	const v: float32 = clampGain(vol);
	if (curBgm >= 0) { fadeOut(curBgm, sec); }   // old fades to 0 then stops (releases its stream slot)
	fadeTo(handle, v, sec);
	curBgm = handle;
	curBgmVol = v;
}

// Crossfade to a streamed BGM file in one call (the common case). Returns the new handle, or -1.
export function crossfadeStream(path: string, vol: float32, sec: float32): int32 {
	const h: int32 = playStream(path, 0.0);      // start silent, then fade in
	crossfadeTo(h, vol, sec);
	return h;
}

// Duck the current BGM to `level` (0..1 of its normal volume) over `sec` — e.g. under a voice
// line — then unduckMusic() to restore. No-op if no BGM is playing.
export function duckMusic(level: float32, sec: float32): void {
	if (curBgm < 0) { return; }
	const l: float32 = level < 0.0 ? 0.0 : (level > 1.0 ? 1.0 : level);
	fadeTo(curBgm, curBgmVol * l, sec);
}
export function unduckMusic(sec: float32): void {
	if (curBgm >= 0) { fadeTo(curBgm, curBgmVol, sec); }
}

// Fade the current BGM out and forget it (so duck/crossfade no longer touch it).
export function fadeOutMusic(sec: float32): void {
	if (curBgm >= 0) { fadeOut(curBgm, sec); curBgm = -1; }
}

// Per-bus gain (master → group → voice). One setter per bus so callers never pass a raw index —
// mirrors underrealm's set_volume(AudioType.BGM/SFX/UI/VOICE, v). Snap (no fade); smooth ducking
// composes fadeTo per-voice, which already exists. Applies to voices currently on the bus and
// every future one — the gain is read live in the kernel each sample.
export function musicVolume(vol: float32): void { voidAudioGroupVol(GROUP_BGM, clampGain(vol)); }
export function sfxVolume(vol: float32): void { voidAudioGroupVol(GROUP_SFX, clampGain(vol)); }
export function uiVolume(vol: float32): void { voidAudioGroupVol(GROUP_UI, clampGain(vol)); }
export function voiceVolume(vol: float32): void { voidAudioGroupVol(GROUP_VOICE, clampGain(vol)); }

// ---- positional audio: coordinate-based, render-agnostic (tier E) ----------------------------
// Spatialization is pure coordinate math over the existing gain/pan/low-pass cascade — no void2d/
// void3d dependency. The game supplies a listener + per-source (x,y,z); updateSpatial() (once a
// frame) turns distance → gain (inverse-clamped, the OpenAL/Heaps model) + direction → pan, and —
// when setMuffle is on — distance → low-pass (Godot's attenuation filter). 2D games pass z = 0.
// Pan here is the direction cosine (dx/dist): full L/R when horizontal, 0 straight ahead — the
// orientation-free reduction of Heaps/OpenAL panning. Listener orientation is an additive follow-up.

// sqrt — MetaScript has no Math. Newton from above the root: g decreases monotonically toward the
// root, so `ng >= g` means float rounding stalled it (converged). The 40-cap backstops huge inputs.
function sqrtApprox(x: float32): float32 {
	if (x <= 0.0) { return 0.0; }
	let g: float32 = x > 1.0 ? x : 1.0;
	let i: int32 = 0;
	while (i < 40) {
		const ng: float32 = 0.5 * (g + x / g);
		if (ng >= g) { return ng; }
		g = ng;
		i = i + 1;
	}
	return g;
}

function clamp01(x: float32): float32 { return x < 0.0 ? 0.0 : (x > 1.0 ? 1.0 : x); }

// Cutoff Hz → one-pole low-pass coefficient (RC form — arithmetic only, no exp). fc at/above ~nyquist
// returns 1.0, which the kernel treats as bypass (Godot's "set cutoff to 20500 to disable").
function lpCoefFromHz(fc: float32): float32 {
	if (fc >= LP_OPEN_HZ) { return 1.0; }
	if (fc <= 0.0) { return 0.02; }
	const w: float32 = 6.2831853 * fc / DEVICE_RATE;   // 2π·fc/fs
	const coef: float32 = w / (1.0 + w);
	return coef > 1.0 ? 1.0 : (coef < 0.02 ? 0.02 : coef);
}

// Recompute one spatialized slot's gain / pan / (muffle) from the listener + source positions.
function applySpatial(slot: int32): void {
	const dx: float32 = srcX[slot] - listenerX;
	const dy: float32 = srcY[slot] - listenerY;
	const dz: float32 = srcZ[slot] - listenerZ;
	const dist: float32 = sqrtApprox(dx * dx + dy * dy + dz * dz);
	const ref: float32 = srcRef[slot];
	const mx: float32 = srcMax[slot];
	const d: float32 = dist < ref ? ref : (dist > mx ? mx : dist);   // clamp distance to [ref, max]
	const gain: float32 = ref / d;                                   // inverse-clamped (rolloff = 1)
	const pan: float32 = clampUnit(dist > 0.0001 ? (dx / dist) * panStrength : 0.0);   // direction cosine
	voidAudioVoiceSpatial(slot, gain, panGainL(pan), panGainR(pan));
	if (muffleAmt > 0.0) {
		const span: float32 = mx - ref;
		const t: float32 = span > 0.0 ? (d - ref) / span : 0.0;                    // 0 near → 1 far
		const farHz: float32 = LP_OPEN_HZ - muffleAmt * (LP_OPEN_HZ - LP_MIN_HZ);   // cutoff at max distance
		const cutoff: float32 = LP_OPEN_HZ - t * (LP_OPEN_HZ - farHz);              // open near, farHz far
		voidAudioVoiceLowPass(slot, lpCoefFromHz(cutoff));
	}
}

// Set the listener ("ears") position — usually the camera centre, opt-in the player. z = 0 for 2D.
export function setListener(x: float32, y: float32, z: float32): void {
	listenerX = x; listenerY = y; listenerZ = z;
}

// Default attenuation range for future playSoundAt — set once to your world scale (pixels:
// spatialRange(80, 900)). refDist = full volume within it; maxDist = where gain/muffle bottom out.
export function spatialRange(refDist: float32, maxDist: float32): void {
	defRef = safeRef(refDist);
	defMax = safeMax(maxDist, defRef);
}

// Pan intensity (0 = centred … 1 = full directional). Distance muffle amount (0 = off … 1 = fully
// dull at max distance) — the Godot-style auto low-pass layered on the positional update.
export function setPanStrength(s: float32): void { panStrength = clamp01(s); }
export function setMuffle(amount: float32): void { muffleAmt = clamp01(amount); }

// Manual low-pass on ANY voice by cutoff Hz (the Heaps-style primitive — drive it from occlusion,
// "underwater", etc.). cutoff >= 20000 opens it. On a spatialized voice with setMuffle on, the
// per-frame auto-muffle overrides this. Stale handle → no-op.
export function setLowPass(handle: int32, cutoffHz: float32): void {
	const slot: int32 = resolve(handle);
	if (slot >= 0) { voidAudioVoiceLowPass(slot, lpCoefFromHz(cutoffHz)); }
}

// Play a clip positioned at (x,y,z) on the SFX bus (one-shot) → voice handle, or -1. Attenuation +
// pan apply immediately; call updateSpatial() each frame to keep them fresh as things move.
export function playSoundAt(clip: int32, x: float32, y: float32, z: float32, vol: float32): int32 {
	const h: int32 = play(clip, GROUP_SFX, 0, vol);
	if (h < 0) { return -1; }
	const slot: int32 = resolve(h);
	srcX[slot] = x; srcY[slot] = y; srcZ[slot] = z;
	srcRef[slot] = defRef; srcMax[slot] = defMax;
	spat[slot] = 1;
	applySpatial(slot);
	return h;
}

// Move a positioned voice (a moving enemy, say) — updates immediately too. Stale handle → no-op.
export function setSourcePos(handle: int32, x: float32, y: float32, z: float32): void {
	const slot: int32 = resolve(handle);
	if (slot < 0) { return; }
	srcX[slot] = x; srcY[slot] = y; srcZ[slot] = z;
	if (spat[slot] == 1) { applySpatial(slot); }
}

// Override one voice's attenuation range (per-source falloff). Stale handle → no-op.
export function setSourceRange(handle: int32, refDist: float32, maxDist: float32): void {
	const slot: int32 = resolve(handle);
	if (slot < 0) { return; }
	const r: float32 = safeRef(refDist);
	srcRef[slot] = r;
	srcMax[slot] = safeMax(maxDist, r);
	if (spat[slot] == 1) { applySpatial(slot); }
}

// Recompute every positioned voice — call once per frame after moving the listener / sources. Drops
// tracking for voices that have ended, so a recycled slot starts non-spatial.
export function updateSpatial(): void {
	let slot: int32 = 0;
	while (slot < MAX_VOICES) {
		if (spat[slot] == 1) {
			if (voidAudioSlotActive(slot) == 1) { applySpatial(slot); }
			else { spat[slot] = 0; }
		}
		slot = slot + 1;
	}
}
