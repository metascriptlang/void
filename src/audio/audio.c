// Void audio kernel — sokol_audio (callback mode) + a fixed-size software mixer.
// Its own SOKOL_IMPL translation unit: sokol_audio's impl is independent of the sokol_gfx
// impl in sokolLinux.c/sokol.m/sokolWin.c, so there is no symbol clash. The backend is
// auto-selected by sokol per OS (Linux→ALSA, macOS→CoreAudio, Windows→WASAPI); the .ms
// layer links the matching lib.
//
// SCOPE: this file is the "audio primitive" tier only (see audio.h). It owns the device,
// the shared Voice[]/Clip[] tables, and the per-sample mix kernel. It makes no decisions —
// decode, voice allocation, safe handles and fade math are all in MetaScript (audioCore.ms).
// The kernel is C (not MetaScript) because it runs on sokol's audio thread, where the
// MetaScript runtime's non-atomic refcount + unlocked ORC collector are unsafe.
//
// THREADING: stream_cb runs on sokol's audio thread; every other function runs on the main
// thread. `active` is published with an atomic RELEASE store after the voice fields are
// written, and read with an atomic ACQUIRE load in the kernel — so the kernel never observes
// a half-initialised voice (plain `volatile` would NOT guarantee this on ARM/Apple Silicon).
// The fade fields (volCur/volTarget/volStep) race benignly with the kernel that advances
// volCur; a fade may start from a sample-stale gain, which is imperceptible.

#define SOKOL_IMPL
#include "sokol_audio.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifndef _WIN32
#include <pthread.h>    // streaming decode runs on a background POSIX thread (see below)
#include <unistd.h>     // usleep — the bg thread polls the ring buffers
#endif

// OGG/Vorbis decode — the one heavy codec void does not own (docs/AUDIO.md escape hatch).
// stb_vorbis is public-domain, vendored in deps/stb. Decoding Vorbis is a *codec*, not policy,
// so it lives in C like the mix kernel — but the clip it produces is the same format-neutral
// float PCM as the WAV path, so the decode-agnostic seam holds: voices never know it was OGG.
#include "stb_vorbis.c"

#define MAX_CLIPS   32
#define MAX_VOICES  16
#define MAX_GROUPS  4             // flat sub-mix buses (0=BGM 1=SFX 2=UI 3=VOICE); gain tree = voice × group × master
#define VOICE_Q     8             // gapless clip queue depth per voice (power of two — masked)
#define DEVICE_RATE 44100.0       // output rate; a clip at another rate is resampled by cursor step

typedef struct { float *pcm; int frames; int channels; int rate; } Clip;   // interleaved float PCM
typedef struct {
	int   clip;                   // clip id, OR -1 when this voice is streamed (source = s_streams[stream])
	int   stream;                 // stream slot index, OR -1 for a clip voice
	double cursor;                // fractional frame index into the clip — advances by `step` per
	                              // output frame (step = clipRate/deviceRate × pitch); linear-interp
	float pitch;                  // playback speed / pitch multiplier (1.0 = native)
	int   loop;
	int   group;                  // sub-mix bus index [0, MAX_GROUPS) — its gain multiplies this voice
	float volCur;                 // current gain — advanced on the audio thread during a fade
	float volTarget;              // fade destination
	float volStep;                // per-sample delta toward volTarget (0 = not fading)
	float panL;                   // per-out-channel pan gain (L / R); 1,1 = centered (no pan)
	float panR;
	float spatialGain;            // distance attenuation from updateSpatial (1 = none); multiplies the gain tree
	float spatialPanL;            // positional pan factors — separate from panL/panR so manual pan still composes
	float spatialPanR;
	float lpCoef;                 // one-pole low-pass coefficient in (0,1]; >= 1 = bypass (passthrough)
	float lpZ[2];                 // per-output-channel low-pass state (z^-1)
	int   fadeStop;               // when a fade reaches target, deactivate the voice
	int   paused;                 // atomic — freeze this one voice (silence, cursor held) vs global suspend
	int   seekTo;                 // pending seek target (frame); applied by the kernel then cleared
	int   seekPending;            // atomic — a seek is queued
	// gapless queue: SPSC ring of clip ids (main thread enqueues, audio thread dequeues at EOF).
	// qhead (audio) / qtail (main) are free-running; count = qtail - qhead.
	int      queue[VOICE_Q];
	unsigned qhead;               // atomic — audio thread
	unsigned qtail;               // atomic — main thread
	int   active;                 // published/observed via __atomic RELEASE/ACQUIRE
} Voice;

static Clip  s_clips[MAX_CLIPS];
static int   s_num_clips = 0;
static Voice s_voices[MAX_VOICES];
static float s_master = 1.0f;     // master gain, multiplied into every voice
static int   s_suspended = 0;     // atomic — when set, the kernel outputs silence AND freezes every
                                  // voice (true pause: cursors don't advance), for app focus loss
// per-group gain — the "gain tree" middle tier (master → group → voice), the one hxd.snd
// abstraction void takes wholesale. Flat (one scalar per bus), NOT a routing graph. Must have
// MAX_GROUPS initialisers.
static float s_group[MAX_GROUPS] = { 1.0f, 1.0f, 1.0f, 1.0f };

// ============================ streaming (tier C) ============================================
// Long BGM is NOT decoded whole (a 3-min stereo track = ~63 MB of float PCM). Instead each
// Stream keeps the OGG open and a background thread decodes it incrementally into a lock-free
// SPSC ring buffer; the audio thread only ever READS pre-decoded PCM from the ring — never file
// I/O, never a Vorbis decode (both can block and would starve the device). This is the same
// producer/consumer split Heaps' Manager and Godot use. POSIX-thread based; Windows streaming is
// a follow-up (playStream returns -1 there), so the whole subsystem is #ifdef'd out on _WIN32.
#ifndef _WIN32
#define MAX_STREAMS        2      // concurrent streamed voices — BGM + one for crossfade (adaptive music)
#define STREAM_RING_FRAMES 44100  // ~1 s of lookahead per stream — 5 ms poll can never underrun this

typedef struct {
	stb_vorbis  *vf;              // open decoder — touched only by the bg thread once inUse
	float       *ring;            // interleaved float PCM; allocated once per slot and REUSED (never
	                              //   freed mid-session, so the audio thread can't read freed memory)
	int          ringChannels;    // channels the ring was sized for
	int          channels;        // current stream channels
	int          loop;
	// SPSC cursors in FRAMES, free-running (wrap via unsigned arithmetic). Producer=bg writes wpos,
	// consumer=audio reads rpos. available = (unsigned)(wpos - rpos).
	unsigned     wpos;            // atomic — released by bg after writing samples
	unsigned     rpos;            // atomic — released by audio after consuming
	int          eof;             // atomic — bg hit end and won't loop (ring will drain, then voice ends)
	int          wantClose;       // atomic — request bg to stb_vorbis_close and free the slot
	int          inUse;           // atomic — slot occupied (bg fills it only while set)
} Stream;

static Stream    s_streams[MAX_STREAMS];
static pthread_t s_bg;
static int       s_bg_run = 0;   // atomic — bg thread loops while set

// bg thread: top up one stream's ring buffer (or service a close request). Only the bg thread
// calls stb_vorbis on a stream, so no decoder is shared across threads.
static void stream_fill_one(Stream *s) {
	if (__atomic_load_n(&s->wantClose, __ATOMIC_ACQUIRE)) {
		if (s->vf) { stb_vorbis_close(s->vf); s->vf = NULL; }   // close off the audio thread
		__atomic_store_n(&s->wantClose, 0, __ATOMIC_RELEASE);
		__atomic_store_n(&s->inUse, 0, __ATOMIC_RELEASE);       // slot free; ring kept for reuse
		return;
	}
	if (__atomic_load_n(&s->eof, __ATOMIC_ACQUIRE)) return;      // fully produced; wait for drain/close
	unsigned w = s->wpos;
	unsigned r = __atomic_load_n(&s->rpos, __ATOMIC_ACQUIRE);
	while ((unsigned)(w - r) < (unsigned)STREAM_RING_FRAMES) {
		unsigned idx   = w % (unsigned)STREAM_RING_FRAMES;
		unsigned space = (unsigned)STREAM_RING_FRAMES - (unsigned)(w - r);
		unsigned chunk = space;
		if (idx + chunk > (unsigned)STREAM_RING_FRAMES) chunk = (unsigned)STREAM_RING_FRAMES - idx;  // stop at wrap
		int got = stb_vorbis_get_samples_float_interleaved(
			s->vf, s->channels, s->ring + (size_t)idx * s->channels, (int)chunk * s->channels);
		if (got <= 0) {                                         // end of file
			if (s->loop) { stb_vorbis_seek_start(s->vf); continue; }
			__atomic_store_n(&s->eof, 1, __ATOMIC_RELEASE);
			break;
		}
		w += (unsigned)got;
		__atomic_store_n(&s->wpos, w, __ATOMIC_RELEASE);        // publish after the samples are written
		r = __atomic_load_n(&s->rpos, __ATOMIC_ACQUIRE);
	}
}

static void *stream_thread(void *arg) {
	(void)arg;
	while (__atomic_load_n(&s_bg_run, __ATOMIC_ACQUIRE)) {
		for (int i = 0; i < MAX_STREAMS; i++)
			if (__atomic_load_n(&s_streams[i].inUse, __ATOMIC_ACQUIRE)) stream_fill_one(&s_streams[i]);
		usleep(5000);   // 5 ms; the ~1 s ring makes this comfortably underrun-proof
	}
	return NULL;
}
#endif // !_WIN32

// Advance this voice's per-sample fade and return its gain (voice × group × master). Sets *stop
// if a fade-to-stop just reached its target. Shared by the clip and stream mixers so the gain
// tree behaves identically whichever the sample source is.
static inline float voice_step_gain(Voice *vo, float master, int *stop) {
	if (vo->volStep != 0.0f) {
		vo->volCur += vo->volStep;
		if ((vo->volStep > 0.0f && vo->volCur >= vo->volTarget) ||
		    (vo->volStep < 0.0f && vo->volCur <= vo->volTarget)) {
			vo->volCur  = vo->volTarget;
			vo->volStep = 0.0f;
			if (vo->fadeStop) *stop = 1;
		}
	}
	return vo->volCur * vo->spatialGain * s_group[vo->group] * master;   // gain tree: voice × spatial × group × master
}

// Per-voice, per-output-channel low-pass — the single DSP insertion point (the "keystone"): both
// mixers route each voice sample through here before summing. One-pole IIR (y += coef·(x−y)); a
// coef >= 1 is a true bypass, so a voice with no filter is byte-identical to before. State is
// per-voice, touched only on the audio thread. Future per-voice DSP extends this, not the mixers.
static inline float voice_lp(Voice *vo, int ch, float smp) {
	if (vo->lpCoef < 1.0f && ch < 2) {
		vo->lpZ[ch] += vo->lpCoef * (smp - vo->lpZ[ch]);
		return vo->lpZ[ch];
	}
	return smp;
}

// Write one source frame into the output at frame f, applying low-pass + gain + pan. mono src →
// duplicated; multi-channel → wrapped; pan attenuates out channels 0/1 only.
static inline void mix_frame(float *buf, int f, int nc, const float *src, int srcCh, float g, float pL, float pR, Voice *vo) {
	for (int ch = 0; ch < nc; ch++) {
		int cc = (srcCh == 1) ? 0 : (ch % srcCh);
		float pg = (ch == 0) ? pL : (ch == 1 ? pR : 1.0f);
		buf[f * nc + ch] += voice_lp(vo, ch, src[cc]) * g * pg;
	}
}

// Pop the next queued clip into this voice (SPSC dequeue, audio thread). Returns 1 and swaps
// vo->clip if one was queued, else 0. Used for gapless sequences (queue B after A → no gap).
static int voice_next_queued(Voice *vo) {
	unsigned h = vo->qhead;
	if (h == __atomic_load_n(&vo->qtail, __ATOMIC_ACQUIRE)) return 0;   // queue empty
	int clip = vo->queue[h & (VOICE_Q - 1)];
	__atomic_store_n(&vo->qhead, h + 1, __ATOMIC_RELEASE);
	if (clip < 0 || clip >= s_num_clips) return 0;
	vo->clip = clip;
	vo->cursor = 0;
	return 1;
}

// Shared voice setup for clip + stream voices — every field except the source (clip/stream).
// Does NOT publish `active`: the caller sets clip/stream, then does the release-store of active
// LAST, so the kernel never observes a half-initialised voice (see the THREADING note above).
static void voice_init_common(Voice *vo, int loop, float vol, int group) {
	vo->cursor = 0.0;
	vo->pitch = 1.0f;                                     // native speed until setPitch
	vo->loop = loop;
	vo->group = (group < 0 || group >= MAX_GROUPS) ? 0 : group;   // clamp to a valid bus
	vo->volCur = vo->volTarget = vol;
	vo->volStep = 0.0f;
	vo->panL = vo->panR = 1.0f;                           // centered until setPan
	vo->spatialGain = 1.0f;                               // no distance attenuation until updateSpatial
	vo->spatialPanL = vo->spatialPanR = 1.0f;
	vo->lpCoef = 1.0f;                                    // low-pass bypassed → byte-identical to no filter
	vo->lpZ[0] = vo->lpZ[1] = 0.0f;
	vo->fadeStop = 0;
	vo->paused = 0;
	vo->seekPending = 0;
	vo->qhead = vo->qtail = 0;                            // empty gapless queue
}

// Bounds-checked voice fetch — the single source of truth for the slot range. NULL if `slot` is
// out of [0, MAX_VOICES); the primitives below map that NULL to their own sentinel. Also folds in
// the `&s_voices[slot]` most of them needed anyway, so the check costs no extra line.
static Voice *voice_at(int slot) {
	if (slot < 0 || slot >= MAX_VOICES) return NULL;
	return &s_voices[slot];
}

// Resampling clip mixer: the cursor is fractional and advances by `step = clipRate/deviceRate ×
// pitch` per output frame, so a clip at any rate (or any pitch) plays correct-speed via linear
// interpolation between adjacent frames. step == 1.0 (44100 clip, pitch 1) degenerates to a plain
// copy (frac 0). One mechanism covers both resample and pitch (Godot's PlaybackResampled insight).
static void mix_clip_voice(Voice *vo, float *buf, int nf, int nc, float master) {
	Clip *c = &s_clips[vo->clip];
	if (__atomic_load_n(&vo->seekPending, __ATOMIC_ACQUIRE)) {   // apply a queued seek, then clear
		int fr = vo->seekTo;
		vo->cursor = fr < 0 ? 0.0 : (fr > c->frames ? (double)c->frames : (double)fr);
		__atomic_store_n(&vo->seekPending, 0, __ATOMIC_RELEASE);
	}
	double step = ((double)c->rate / DEVICE_RATE) * (double)vo->pitch;
	for (int f = 0; f < nf; f++) {
		if (vo->cursor >= (double)c->frames) {
			if (vo->loop) { vo->cursor -= (double)c->frames; }       // wrap, keep the fraction
			else if (voice_next_queued(vo)) {                        // gapless: continue with the next clip
				c = &s_clips[vo->clip];
				step = ((double)c->rate / DEVICE_RATE) * (double)vo->pitch;
			} else { __atomic_store_n(&vo->active, 0, __ATOMIC_RELEASE); return; }
			if (vo->cursor >= (double)c->frames) vo->cursor = 0.0;   // guard: overshoot past a tiny clip
		}
		int stop = 0;
		float g = voice_step_gain(vo, master, &stop);
		int   i    = (int)vo->cursor;
		float frac = (float)(vo->cursor - (double)i);
		int   i1   = i + 1;
		int   wrap = (i1 >= c->frames);                              // past the last frame → wrap or hold
		for (int ch = 0; ch < nc; ch++) {
			int cc = (c->channels == 1) ? 0 : (ch % c->channels);
			float pg = (ch == 0) ? vo->panL * vo->spatialPanL : (ch == 1 ? vo->panR * vo->spatialPanR : 1.0f);
			float s0 = c->pcm[(size_t)i * c->channels + cc];
			float s1 = wrap ? (vo->loop ? c->pcm[cc] : s0) : c->pcm[(size_t)i1 * c->channels + cc];
			float smp = voice_lp(vo, ch, s0 + frac * (s1 - s0));    // low-pass (bypassed when open) after interp
			buf[f * nc + ch] += smp * g * pg;
		}
		vo->cursor += step;
		if (stop) { __atomic_store_n(&vo->active, 0, __ATOMIC_RELEASE); return; }
	}
}

#ifndef _WIN32
// Consume from the ring the bg thread fills. Empty ring: if the stream is at EOF the voice has
// drained → end it and ask the bg thread to close the decoder; otherwise it's a transient
// underrun → emit silence for this frame and keep going.
static void mix_stream_voice(Voice *vo, float *buf, int nf, int nc, float master) {
	Stream *s = &s_streams[vo->stream];
	int sc = s->channels;
	unsigned r = __atomic_load_n(&s->rpos, __ATOMIC_RELAXED);
	for (int f = 0; f < nf; f++) {
		unsigned w = __atomic_load_n(&s->wpos, __ATOMIC_ACQUIRE);
		if (w == r) {   // ring empty
			if (__atomic_load_n(&s->eof, __ATOMIC_ACQUIRE)) {
				__atomic_store_n(&s->rpos, r, __ATOMIC_RELEASE);
				__atomic_store_n(&vo->active, 0, __ATOMIC_RELEASE);
				__atomic_store_n(&s->wantClose, 1, __ATOMIC_RELEASE);
				return;
			}
			continue;   // underrun: silence, keep the voice alive
		}
		int stop = 0;
		float g = voice_step_gain(vo, master, &stop);
		mix_frame(buf, f, nc, &s->ring[(size_t)(r % (unsigned)STREAM_RING_FRAMES) * sc], sc, g, vo->panL * vo->spatialPanL, vo->panR * vo->spatialPanR, vo);
		r++;
		if (stop) {   // fadeOut finished → end voice + close stream
			__atomic_store_n(&s->rpos, r, __ATOMIC_RELEASE);
			__atomic_store_n(&vo->active, 0, __ATOMIC_RELEASE);
			__atomic_store_n(&s->wantClose, 1, __ATOMIC_RELEASE);
			return;
		}
	}
	__atomic_store_n(&s->rpos, r, __ATOMIC_RELEASE);
}
#endif

// --- audio thread: mix every active voice into the output buffer, then clamp ------------
static void stream_cb(float *buf, int num_frames, int num_channels) {
	memset(buf, 0, sizeof(float) * (size_t)num_frames * (size_t)num_channels);
	if (__atomic_load_n(&s_suspended, __ATOMIC_ACQUIRE)) return;   // paused: silence, freeze all cursors
	float master = s_master;
	for (int v = 0; v < MAX_VOICES; v++) {
		Voice *vo = &s_voices[v];
		if (!__atomic_load_n(&vo->active, __ATOMIC_ACQUIRE)) continue;   // acquire: see full voice
		if (__atomic_load_n(&vo->paused, __ATOMIC_ACQUIRE)) continue;    // per-voice pause: frozen, silent
#ifndef _WIN32
		if (vo->stream >= 0) { mix_stream_voice(vo, buf, num_frames, num_channels, master); continue; }
#endif
		mix_clip_voice(vo, buf, num_frames, num_channels, master);
	}
	// hard-limit the summed mix so N loud voices can't exceed the device range and wrap/clip.
	int total = num_frames * num_channels;
	for (int i = 0; i < total; i++) {
		float s = buf[i];
		buf[i] = s > 1.0f ? 1.0f : (s < -1.0f ? -1.0f : s);
	}
}

void voidAudioSetup(void) {
	saudio_desc d;
	memset(&d, 0, sizeof(d));
	d.sample_rate  = 44100;
	d.num_channels = 2;
	d.stream_cb    = stream_cb;
	saudio_setup(&d);
#ifndef _WIN32
	__atomic_store_n(&s_bg_run, 1, __ATOMIC_RELEASE);   // start the streaming decode thread
	pthread_create(&s_bg, NULL, stream_thread, NULL);
#endif
}

void voidAudioShutdown(void) {
	saudio_shutdown();   // stops the audio-thread callback first
#ifndef _WIN32
	if (__atomic_load_n(&s_bg_run, __ATOMIC_ACQUIRE)) {
		__atomic_store_n(&s_bg_run, 0, __ATOMIC_RELEASE);
		pthread_join(s_bg, NULL);
		for (int i = 0; i < MAX_STREAMS; i++)
			if (s_streams[i].vf) { stb_vorbis_close(s_streams[i].vf); s_streams[i].vf = NULL; }
	}
#endif
}

// --- raw file slurp: I/O primitive so MetaScript can parse the WAV bytes itself ------------
// (a narrow-waist I/O primitive, like void2d/batcher.c's readFile; the WAV *parsing* is all in
// audioCore.ms). One reusable buffer, valid until the next voidAudioLoadFile — the main thread
// decodes each clip fully before loading the next, so no aliasing.
static unsigned char *s_file = NULL;
static int            s_file_len = 0;

int voidAudioLoadFile(const char *path) {
	if (s_file) { free(s_file); s_file = NULL; s_file_len = 0; }
	FILE *f = fopen(path, "rb");
	if (!f) return -1;
	fseek(f, 0, SEEK_END);
	long sz = ftell(f);
	fseek(f, 0, SEEK_SET);
	if (sz <= 0) { fclose(f); return -1; }
	unsigned char *buf = (unsigned char *)malloc((size_t)sz);
	if (!buf) { fclose(f); return -1; }
	size_t rd = fread(buf, 1, (size_t)sz, f);
	fclose(f);
	if (rd != (size_t)sz) { free(buf); return -1; }
	s_file = buf;
	s_file_len = (int)sz;
	return s_file_len;
}

const unsigned char *voidAudioFileBytes(void) { return s_file; }

// --- clip table: MetaScript decodes, we take an owned copy the audio thread can read ------
int voidAudioRegisterClip(const float *pcm, int frames, int channels, int rate) {
	if (s_num_clips >= MAX_CLIPS || frames <= 0 || channels < 1 || rate <= 0) return -1;
	size_t n = (size_t)frames * (size_t)channels;
	float *buf = (float *)malloc(n * sizeof(float));
	if (!buf) return -1;
	memcpy(buf, pcm, n * sizeof(float));
	int id = s_num_clips++;
	s_clips[id].pcm = buf;
	s_clips[id].frames = frames;
	s_clips[id].channels = channels;
	s_clips[id].rate = rate;      // native rate — the mixer resamples to the device rate on the fly
	return id;
}

int voidAudioClipFrames(int clip) {
	if (clip < 0 || clip >= s_num_clips) return -1;
	return s_clips[clip].frames;
}

// Decode a whole OGG/Vorbis file → clip id, or -1 (missing / corrupt). Any sample rate is accepted
// now — the clip keeps its native rate and the mixer resamples to the device rate on the fly
// (tier B). stb_vorbis returns interleaved int16; we normalise to float and hand it to the shared
// clip table. Whole-file decode (not streamed): fine for SFX; long BGM uses the streaming path.
int voidAudioLoadOgg(const char *path) {
	int channels = 0, rate = 0;
	short *pcm16 = NULL;
	int frames = stb_vorbis_decode_filename(path, &channels, &rate, &pcm16);   // frames = per-channel
	if (frames <= 0 || !pcm16) { if (pcm16) free(pcm16); return -1; }
	if (rate <= 0 || channels < 1) { free(pcm16); return -1; }   // any rate ok now — mixer resamples
	size_t n = (size_t)frames * (size_t)channels;
	float *pcm = (float *)malloc(n * sizeof(float));
	if (!pcm) { free(pcm16); return -1; }
	for (size_t i = 0; i < n; i++) pcm[i] = (float)pcm16[i] / 32768.0f;
	free(pcm16);
	int id = voidAudioRegisterClip(pcm, frames, channels, rate);
	free(pcm);
	return id;
}

// Open an OGG as a STREAM bound to voice `slot`: the bg thread keeps its ring fed while the audio
// thread plays it, so a multi-minute BGM never sits decoded in RAM. Returns 0 on success, or -1
// (missing / not 44100 Hz / no free stream slot / OOM) with the voice left inactive. 44100-only,
// same rule as the whole-file decoders.
#ifndef _WIN32
int voidAudioStreamStart(int slot, const char *path, int loop, float vol, int group) {
	Voice *vo = voice_at(slot);
	if (!vo) return -1;
	int si = -1;
	for (int i = 0; i < MAX_STREAMS; i++)
		if (!__atomic_load_n(&s_streams[i].inUse, __ATOMIC_ACQUIRE)) { si = i; break; }
	if (si < 0) return -1;                                   // all streams busy
	int err = 0;
	stb_vorbis *vf = stb_vorbis_open_filename(path, &err, NULL);
	if (!vf) return -1;
	stb_vorbis_info info = stb_vorbis_get_info(vf);
	if (info.sample_rate != 44100 || info.channels < 1) { stb_vorbis_close(vf); return -1; }
	Stream *s = &s_streams[si];
	if (!s->ring || s->ringChannels != info.channels) {     // (re)size the reusable ring on first use / channel change
		free(s->ring);
		s->ring = (float *)malloc((size_t)STREAM_RING_FRAMES * info.channels * sizeof(float));
		if (!s->ring) { s->ringChannels = 0; stb_vorbis_close(vf); return -1; }
		s->ringChannels = info.channels;
	}
	s->vf = vf;
	s->channels = info.channels;
	s->loop = loop;
	s->wpos = s->rpos = 0;
	s->eof = 0;
	s->wantClose = 0;
	stream_fill_one(s);                                     // prime before it goes live (bg ignores it while inUse==0)
	__atomic_store_n(&s->inUse, 1, __ATOMIC_RELEASE);       // now hand it to the bg thread

	voice_init_common(vo, loop, vol, group);               // (queue fields kept clean too — streams don't queue)
	vo->clip = -1;
	vo->stream = si;                                       // stream-sourced voice
	__atomic_store_n(&vo->active, 1, __ATOMIC_RELEASE);     // publish last
	return 0;
}
#else
int voidAudioStreamStart(int slot, const char *path, int loop, float vol, int group) {
	(void)slot; (void)path; (void)loop; (void)vol; (void)group;
	return -1;   // streaming not yet implemented on Windows (POSIX-thread based)
}
#endif

// --- voice table primitives: dumb setters; MetaScript owns the allocation policy ----------
int voidAudioSlotActive(int slot) {
	Voice *vo = voice_at(slot);
	if (!vo) return 0;
	return __atomic_load_n(&vo->active, __ATOMIC_ACQUIRE) ? 1 : 0;
}

void voidAudioVoiceStart(int slot, int clip, int loop, float vol, int group) {
	Voice *vo = voice_at(slot);
	if (!vo) return;
	if (clip < 0 || clip >= s_num_clips) return;
	voice_init_common(vo, loop, vol, group);
	vo->clip = clip;
	vo->stream = -1;                                      // clip-sourced voice
	__atomic_store_n(&vo->active, 1, __ATOMIC_RELEASE);   // publish last: kernel then sees it all
}

void voidAudioVoiceStop(int slot) {
	Voice *vo = voice_at(slot);
	if (!vo) return;
#ifndef _WIN32
	int st = vo->stream;   // a streamed voice must also tear down its decoder (on the bg thread)
	if (st >= 0 && st < MAX_STREAMS) __atomic_store_n(&s_streams[st].wantClose, 1, __ATOMIC_RELEASE);
#endif
	__atomic_store_n(&vo->active, 0, __ATOMIC_RELEASE);
}

// Enqueue a clip to play gaplessly after this voice's current clip finishes (main-thread SPSC
// producer). Clip voices only; ignored for streams / a full queue / an invalid clip.
void voidAudioVoiceQueue(int slot, int clip) {
	Voice *vo = voice_at(slot);
	if (!vo) return;
	if (clip < 0 || clip >= s_num_clips) return;
	if (vo->stream >= 0) return;
	unsigned t = vo->qtail;
	if (t - __atomic_load_n(&vo->qhead, __ATOMIC_ACQUIRE) >= (unsigned)VOICE_Q) return;   // queue full
	vo->queue[t & (VOICE_Q - 1)] = clip;
	__atomic_store_n(&vo->qtail, t + 1, __ATOMIC_RELEASE);   // publish after the slot is written
}

// Bulk control. stopAll silences every voice; stopGroup silences one bus (e.g. all SFX on a scene
// change). Both reuse voidAudioVoiceStop, so streamed voices are torn down correctly.
void voidAudioStopAll(void) {
	for (int i = 0; i < MAX_VOICES; i++) voidAudioVoiceStop(i);
}
void voidAudioStopGroup(int group) {
	for (int i = 0; i < MAX_VOICES; i++)
		if (__atomic_load_n(&s_voices[i].active, __ATOMIC_ACQUIRE) && s_voices[i].group == group)
			voidAudioVoiceStop(i);
}

// Global pause: the kernel outputs silence and freezes every cursor (streams included — their bg
// ring simply fills and waits), so resume continues exactly where it stopped. For app focus loss.
void voidAudioSuspend(int on) { __atomic_store_n(&s_suspended, on ? 1 : 0, __ATOMIC_RELEASE); }

// Pause/resume ONE voice (vs global suspend): the kernel skips it and its cursor is held. Works
// for clip and stream voices (a paused stream just stops draining its ring).
void voidAudioVoicePause(int slot, int on) {
	Voice *vo = voice_at(slot);
	if (!vo) return;
	__atomic_store_n(&vo->paused, on ? 1 : 0, __ATOMIC_RELEASE);
}

// Seek a clip voice to `frame` (the kernel applies it next callback). Clip voices only — stream
// seek needs bg-thread decoder coordination (a follow-up); ignored for streams / stale slots.
void voidAudioVoiceSeek(int slot, int frame) {
	Voice *vo = voice_at(slot);
	if (!vo) return;
	if (vo->stream >= 0) return;
	vo->seekTo = frame;
	__atomic_store_n(&vo->seekPending, 1, __ATOMIC_RELEASE);
}

// Current playback position (frame) of an active clip voice, or -1 (stream / inactive). Benign
// racy read — a sample-stale value at worst, like voidAudioVoiceVol.
int voidAudioVoicePos(int slot) {
	Voice *vo = voice_at(slot);
	if (!vo) return -1;
	if (vo->stream >= 0 || !__atomic_load_n(&vo->active, __ATOMIC_ACQUIRE)) return -1;
	return (int)vo->cursor;
}

// Set a clip voice's pitch / playback speed (1.0 = native; 2.0 = octave up + double speed). Clamped
// to a sane range so the cursor step stays positive and finite. Clip voices only (streams ignore).
void voidAudioVoicePitch(int slot, float pitch) {
	Voice *vo = voice_at(slot);
	if (!vo) return;
	vo->pitch = pitch < 0.03125f ? 0.03125f : (pitch > 32.0f ? 32.0f : pitch);
}

float voidAudioVoiceVol(int slot) {
	Voice *vo = voice_at(slot);
	if (!vo) return 0.0f;
	return vo->volCur;   // benign racy read: only a fade's start point
}

void voidAudioVoiceSetVol(int slot, float vol) {
	Voice *vo = voice_at(slot);
	if (!vo) return;
	vo->volStep   = 0.0f;
	vo->volTarget = vol;
	vo->volCur    = vol;
}

void voidAudioVoiceFade(int slot, float target, float step, int stopAtEnd) {
	Voice *vo = voice_at(slot);
	if (!vo) return;
	vo->volTarget = target;
	vo->volStep   = step;
	vo->fadeStop  = stopAtEnd;
}

void voidAudioVoicePan(int slot, float panL, float panR) {
	Voice *vo = voice_at(slot);
	if (!vo) return;
	vo->panL = panL;
	vo->panR = panR;
}

void voidAudioMasterVol(float vol) { s_master = vol; }

// Set a sub-mix bus gain (master → group → voice). Out-of-range group ignored. Clamping is the
// caller's job (audioCore.ms), same as voidAudioMasterVol.
void voidAudioGroupVol(int group, float vol) {
	if (group < 0 || group >= MAX_GROUPS) return;
	s_group[group] = vol;
}

// Positional attenuation + pan for one voice — computed each frame by audioCore.ms's updateSpatial
// (distance → gain, direction → pan). Separate from setVol/setPan so a fade or manual pan still
// composes on top. Benign racy plain writes, like voidAudioVoicePan.
void voidAudioVoiceSpatial(int slot, float gain, float panL, float panR) {
	Voice *vo = voice_at(slot);
	if (!vo) return;
	vo->spatialGain = gain;
	vo->spatialPanL = panL;
	vo->spatialPanR = panR;
}

// One voice's low-pass coefficient (one-pole, in (0,1]; >= 1 bypasses). audioCore.ms maps a cutoff
// in Hz → coef, for both the manual setLowPass and the distance-driven muffle. Benign racy write.
void voidAudioVoiceLowPass(int slot, float coef) {
	Voice *vo = voice_at(slot);
	if (!vo) return;
	vo->lpCoef = coef;
}
