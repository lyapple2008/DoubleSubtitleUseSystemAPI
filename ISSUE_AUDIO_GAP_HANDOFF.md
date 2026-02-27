# Audio Gap Handoff

## Current status
- `debug_recognition_audio.wav` waveform is generally valid.
- Audio still contains periodic silent gaps.
- Current reproducible input format from extension logs:
  - `sampleRate=44100`
  - `channels=2`
  - `bitsPerChannel=16`
  - `isNonInterleaved=false` (interleaved stereo)

## Observed conversion stats
- Typical chunk:
  - input: `1024` frames @ `44100`
  - output: `371` or `372` frames @ `16000`
- This ratio is expected numerically, so frame count loss is not the primary issue.

## Code baseline to continue from
- `AudioCaptureExtension` currently:
  - always converts extension input to `16k/mono/int16`
  - uses cached `AVAudioConverter` (`getOrCreateConverter`)
  - uses block-based convert with drain loop (`status == .haveData` continues)
  - reads source bytes using `CMBlockBufferGetDataPointer`
- `AudioCaptureManager` currently:
  - treats extension output as fixed `16k/mono/int16`
  - carries odd trailing byte across reads to avoid `Int16` frame split

## Main unresolved issue
- Periodic silence remains after conversion, even when output frame counts are stable.

## Next debugging directions
1. Verify source-buffer fill path for interleaved input:
   - `createSourceFormat(asbd:)`
   - `createSourcePCMBuffer(...)`
2. Compare direct interleaved-buffer copy vs manual deinterleave path for `Int16` stereo input.
3. Add short-run diagnostics:
   - per-chunk RMS before conversion and after conversion
   - check if silent chunks already exist before converter input.
