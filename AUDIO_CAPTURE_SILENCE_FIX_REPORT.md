# Audio Capture Silence Fix Report

## Background
- Symptom: `debug_recognition_audio.wav` had valid waveform shape, but periodic silent gaps (about `11ms`) appeared.
- Capture path: `Broadcast Upload Extension` captures system audio, converts to `16k/mono/16bit`, writes to App Group file, main app reads and forwards to speech recognition.

## Reproduction Signal
- Extension logs showed stable input/output frame ratio:
  - input: `1024` frames @ `44.1k`
  - output: `371/372` frames @ `16k`
- This indicates sample-rate conversion ratio itself was numerically correct.
- Therefore, issue focus moved from "frame count loss" to "sample content/layout interpretation".

## Root Cause
Primary root cause was in extension source-buffer packing for interleaved input:

1. Input format from ReplayKit was interleaved stereo (`isNonInterleaved=false`).
2. Source `AVAudioFormat` remained interleaved.
3. But source `AVAudioPCMBuffer` filling logic used a per-channel `channelData` style copy path (planar style assumptions).
4. This mismatch can corrupt/degrade effective sample continuity and produced periodic silent gaps in converted output.

Additionally, a robustness risk existed:
- `CMBlockBufferGetDataPointer` may expose only a contiguous segment while total buffer can be non-contiguous.
- Using total length against a segment pointer is unsafe.
- In this run, logs did not show non-contiguous fallback triggered, but code now handles this safely.

## Code Fix Summary
File: `AudioCaptureExtension/AudioCaptureExtension.swift`

### 1) Safe CMBlockBuffer read path
- Read both:
  - `lengthAtOffsetOut`
  - `totalLengthOut`
- If contiguous (`lengthAtOffset == totalLength`): use direct pointer.
- If non-contiguous: fallback to `CMBlockBufferCopyDataBytes` into contiguous `Data`.

### 2) Correct interleaved source buffer fill
- For interleaved input:
  - write bytes directly into `buffer.mutableAudioBufferList.pointee.mBuffers.mData`.
  - avoid channelData-based per-frame copy path.
- For planar input:
  - keep per-channel copy into `floatChannelData` / `int16ChannelData`.

### 3) Keep existing converter behavior
- Keep converter caching (`getOrCreateConverter`).
- Keep block-based drain loop (`status == .haveData` continues).
- Keep output target fixed at `16k/mono/int16`.

## Validation Result
- Latest verification: saved debug wav no longer has periodic silent gaps.
- Result quality: audio signal is continuous and normal for downstream recognition.

## Why the Gap Looked Like ~11ms
- Observed chunk size was often `1024` frames at `44.1k` (~`23.22ms` per chunk).
- Wrong interleaved/planar handling can produce chunk-local pattern artifacts that present as roughly half-chunk interruptions (~`11.6ms`), matching the symptom.

## Practical Notes for Extension Audio Conversion

### Format and memory layout
- Never mix interleaved format with planar copy assumptions.
- For interleaved PCM:
  - prefer direct `AudioBufferList` copy.
- For planar PCM:
  - use channel arrays (`channelData`) per channel.

### CMSampleBuffer / CMBlockBuffer safety
- Do not assume block buffer is fully contiguous.
- Always compare `lengthAtOffsetOut` vs `totalLengthOut`.
- Use `CMBlockBufferCopyDataBytes` fallback when needed.

### Converter usage
- Use block-based `AVAudioConverter.convert(to:error:withInputFrom:)`.
- Drain output in loop while `status == .haveData`.
- Reuse converter per source format to avoid unnecessary churn.

### Diagnostics to keep
- Log ASBD once per session.
- Log first few conversion stats (`inFrames/outFrames`).
- Keep non-contiguous fallback log capped to avoid flooding.

## Follow-up Recommendation
- Keep a short integration test checklist for audio path changes:
  1. ASBD log sanity.
  2. Output wav continuity in DAW.
  3. Recognition stability check with same source clip.
