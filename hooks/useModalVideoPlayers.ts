import { useCallback } from 'react';
import { useVideoPlayer } from 'expo-video';

// ---------------------------------------------------------------------------
// One player, one codec.
//
// The voting flow used to run six VideoPlayers — one per illustrated step —
// which meant up to four concurrent ExoPlayer/MediaCodec instances on Android
// through the ±1 sliding window. That many hardware decoders in flight is a
// documented stressor for the vendor-codec use-after-free that crashes media3
// in SampleDataQueue.readData -> DirectByteBuffer.put -> memcpy, and the
// workaround at the time (static PNG posters on Android) cost the animation
// entirely on those steps.
//
// Those step clips were all short silent loops of a flat-shaded illustration,
// so they now ship as animated WebP (assets/webp) rendered through
// react-native's Image. No ExoPlayer, no MediaCodec: Fresco decodes them on
// Android — via the animated-webp module that plugins/withAnimatedWebp.js
// enables — and iOS decodes them natively. That restores motion on Android
// *and* removes the codecs.
//
// The Step 4 intro is the one genuine video: full-bleed, six seconds, with a
// skip affordance. It keeps a real player — and it is now the only one, so the
// concurrent-codec pressure that caused the crash is gone by construction.
// ---------------------------------------------------------------------------

export function useModalVideoPlayers() {
  // Intro video — full-bleed clip that plays *above* the Step 4 content as a
  // teaching screen. Android uses a re-muxed .mp4 (H.264 Baseline, faststart)
  // so Media3 takes the standard MP4 extractor path and hardware-decodes via
  // MediaCodec on every device.
  // Placeholder — the original Step 4 intro clip was removed (copyright).
  // TODO: replace assets/videos/intro-placeholder.mp4 with a licensed intro.
  const playerIntro = useVideoPlayer(
    require('@/assets/videos/intro-placeholder.mp4'),
    player => {
      player.loop = true;
      player.muted = true;
      player.audioMixingMode = 'mixWithOthers';
      // Preload but don't play; handleStepChange starts it when Step 4 arrives.
      player.pause();
    }
  );

  const safePause = (player: any) => {
    try {
      if (player && typeof player.pause === 'function') {
        player.pause();
      }
    } catch (e) { /* Ignore errors from released players */ }
  };

  const handleStepChange = useCallback((nextStep: number) => {
    // Step 4 shows the intro clip ahead of the existing card content; every
    // other step's motion is a GIF and needs no playback control.
    if (nextStep === 4) {
      // Small delay on Android to let the player initialize before playing.
      setTimeout(() => {
        try {
          if (playerIntro && typeof playerIntro.play === 'function') {
            playerIntro.play();
          }
        } catch (e) { /* Ignore errors from released players */ }
      }, 100);
    } else if (nextStep === 5) {
      safePause(playerIntro);
    }
  }, [playerIntro]);

  const pauseAll = useCallback(() => {
    safePause(playerIntro);
  }, [playerIntro]);

  return {
    players: { playerIntro },
    handleStepChange,
    pauseAll,
  };
}
