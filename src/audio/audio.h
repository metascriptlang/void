// Void audio — thin C "audio primitive" over sokol_audio (see audio.c). This layer is
// deliberately dumb: it owns the device, the shared Voice[]/Clip[] tables, and the
// per-sample mix kernel that runs on sokol's audio thread. It makes NO decisions.
//
// All policy — WAV decode, voice allocation, safe handles, fade math — lives in MetaScript
// (audioCore.ms). C is confined to what MetaScript cannot safely do: the audio-thread hot
// loop (the runtime's refcount/ORC GC is not safe on a foreign thread — see docs/AUDIO.md).
// This mirrors src/void2d/batcher.c ("logic in draw.ms, C only does the primitives").
#ifndef VOID_AUDIO_H
#define VOID_AUDIO_H

void voidAudioSetup(void);                                  // open the audio device (call once)
void voidAudioShutdown(void);                               // close the device

// Raw file I/O primitive — MetaScript (audioCore.ms) does the WAV parsing over these bytes.
int  voidAudioLoadFile(const char *path);                   // slurp file → byte length, or -1
const unsigned char *voidAudioFileBytes(void);              // pointer to the slurped bytes

// Copy decoded interleaved float PCM into a C-owned clip slot → clip id, or -1 if full/invalid.
// The caller's buffer is copied; it may be freed after this returns.
int  voidAudioRegisterClip(const float *pcm, int frames, int channels, int rate);
int  voidAudioClipFrames(int clip);                         // frame count of a loaded clip, or -1

// Decode a full OGG/Vorbis file (stb_vorbis, deps/stb) → clip id, or -1. 44100 Hz required.
// Unlike WAV (parsed in MetaScript), Vorbis is a heavy codec so C does it — the clip is still
// format-neutral PCM. Whole-file; long BGM streams instead (voidAudioStreamStart).
int  voidAudioLoadOgg(const char *path);

// Stream an OGG straight to voice `slot` (bg thread decodes into a ring buffer — never decoded
// whole into RAM). Returns 0, or -1 (missing / not 44100 / no free stream slot). 2 concurrent
// streams (BGM + crossfade). Windows: returns -1 (streaming is POSIX-thread based, a follow-up).
int  voidAudioStreamStart(int slot, const char *path, int loop, float vol, int group);

// Voice table primitives. `slot` is an index in [0, MAX_VOICES); the generation/handle
// bookkeeping that makes a slot reference safe lives in MetaScript, not here.
int  voidAudioSlotActive(int slot);                         // 1 if the slot is currently playing
void voidAudioVoiceStart(int slot, int clip, int loop, float vol, int group);  // (re)arm a slot on a bus, raise active
void voidAudioVoiceStop(int slot);                          // silence a slot immediately
void voidAudioVoiceQueue(int slot, int clip);               // enqueue a clip to play gaplessly after the current one
void voidAudioStopAll(void);                                // stop every voice
void voidAudioStopGroup(int group);                         // stop every voice on one bus
void voidAudioSuspend(int on);                              // 1 = pause all (silence + freeze), 0 = resume
void voidAudioVoicePause(int slot, int on);                 // pause/resume one voice (cursor held)
void voidAudioVoiceSeek(int slot, int frame);              // seek a clip voice to a frame (clip only)
int  voidAudioVoicePos(int slot);                           // current frame of a clip voice, or -1
void voidAudioVoicePitch(int slot, float pitch);            // playback speed / pitch (clip voices)
float voidAudioVoiceVol(int slot);                          // read live gain (fade start point)
void voidAudioVoiceSetVol(int slot, float vol);             // snap gain now (cancels any fade)
void voidAudioVoiceFade(int slot, float target, float step, int stopAtEnd);  // arm a per-sample fade
void voidAudioVoicePan(int slot, float panL, float panR);   // set the L/R pan gains (1,1 = center)
void voidAudioVoiceSpatial(int slot, float gain, float panL, float panR);  // positional attenuation + pan (updateSpatial)
void voidAudioVoiceLowPass(int slot, float coef);           // one-pole low-pass coef in (0,1]; >=1 bypass
void voidAudioGroupVol(int group, float vol);               // sub-mix bus gain (master → group → voice)
void voidAudioMasterVol(float vol);                         // global gain over all voices

#endif
