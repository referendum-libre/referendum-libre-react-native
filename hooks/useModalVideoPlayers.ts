import { useCallback } from 'react';
import { Platform } from 'react-native';
import { useVideoPlayer } from 'expo-video';

// ---------------------------------------------------------------------------
// Player hygiene: minimise concurrent media3 (ExoPlayer) codec instances.
//
// The voting flow mounts VideoViews through a ±1 sliding window (see
// app/voting-flow.tsx). Each mounted VideoView binds to one VideoPlayer, and
// binding two *simultaneously-mounted* VideoViews to the SAME player instance
// is unsupported on Android and itself a crash source (expo/expo#30271). So
// every player that can be on-screen at the same time as another must be a
// distinct instance.
//
// On Android all five non-intro steps show the *same* clip (the others never
// shipped an Android-encoded variant), so historically we created five
// identical players + intro = 6 concurrent ExoPlayer/MediaCodec instances. On
// low/mid devices that many hardware decoders in flight is a documented
// stressor for the vendor-codec use-after-free that crashes media3 in
// SampleDataQueue.readData -> DirectByteBuffer.put -> memcpy.
//
// Steps that render a VideoView and the player they bind (idx = step-1):
//   Step1(p1) Step2(p2) Step3(p3) Step4(intro+p1) Step6(p4) Step7(p5) Step10(p3)
// With the ±1 window the on-screen sets are always three consecutive indices,
// so the players that can be co-mounted are:
//   {p1,p2,p3}, {p1,p2,p3,intro}, {intro,p1,p4}, {p4,p5}
// A conflict-graph colouring of the five shared-clip players (intro is a
// different file, always its own instance) needs only THREE instances:
//   A = player1 & player5   B = player2 & player4   C = player3
// No two members of a co-mounted set share a colour, so no VideoView collision.
//
// Result on Android: 3 shared-clip players + 1 intro = 4 concurrent codecs
// (down from 6). iOS is unchanged — every step has a distinct source there and
// no crash is reported, so all six carry their own clip.
//
// Hook-count stays a constant 6 (rules-of-hooks). The two slots that Android
// doesn't need (iOS Step6/Step7 clips) are created with a `null` source on
// Android, which constructs no native media / no codec.
// ---------------------------------------------------------------------------

export function useModalVideoPlayers() {
  const isAndroid = Platform.OS === 'android';

  // The single Android-encoded clip shared by all non-intro steps.
  const androidClip = require('@/assets/videos/kling_20250904_Image_to_Video_A_playful__4900_0_android.mp4');

  const setup = (player: any) => {
    player.loop = true;
    player.muted = true;
    player.audioMixingMode = 'mixWithOthers';
    // Preload but don't play; handleStepChange starts the visible step's player.
    player.pause();
  };

  // Role A — player1 (Step1/Step4) and player5 (Step7). Never co-mounted.
  const playerA = useVideoPlayer(
    Platform.select({
      ios: require('@/assets/videos/kling_20250904_Image_to_Video_A_playful__4846_0.mp4'),
      android: androidClip,
    })!,
    setup
  );

  // Role B — player2 (Step2) and player4 (Step6). Never co-mounted.
  const playerB = useVideoPlayer(
    Platform.select({
      ios: require('@/assets/videos/kling_20250904_Image_to_Video_A_playful__4900_0.mp4'),
      android: androidClip,
    })!,
    setup
  );

  // Role C — player3 (Step3/Step10).
  const playerC = useVideoPlayer(
    Platform.select({
      ios: require('@/assets/videos/kling_20250904_Image_to_Video_A_playful__5078_0.mp4'),
      android: androidClip,
    })!,
    setup
  );

  // iOS-only Step6 clip (phoneOverCard). On Android, Step6 uses Role B, so this
  // slot carries no media there (null source → no codec).
  const playerIosStep6 = useVideoPlayer(
    isAndroid ? null : require('@/assets/videos/phoneOverCard.mp4'),
    setup
  );

  // iOS-only Step7 clip. On Android, Step7 uses Role A, so this slot is idle.
  const playerIosStep7 = useVideoPlayer(
    isAndroid ? null : require('@/assets/videos/kling_20250904_Image_to_Video_A_playful__5198_0.mp4'),
    setup
  );

  // Intro video — full-bleed clip that plays *above* the Step 4 content as a
  // teaching screen. Same source on both platforms; Android uses a re-muxed
  // .mp4 (H.264 Baseline, faststart) so Media3 takes the standard MP4 extractor
  // path and hardware-decodes via MediaCodec on every device.
  // Placeholder — the original Step 4 intro clip was removed (copyright).
  // TODO: replace assets/videos/intro-placeholder.mp4 with a licensed intro.
  const playerIntro = useVideoPlayer(
    require('@/assets/videos/intro-placeholder.mp4'),
    setup
  );

  // Map the six public keys onto the deduplicated instances. iOS keeps a
  // distinct player per step; Android aliases per the A/B/C colouring above.
  const player1 = playerA;
  const player2 = playerB;
  const player3 = playerC;
  const player4 = isAndroid ? playerB : playerIosStep6;
  const player5 = isAndroid ? playerA : playerIosStep7;

  const handleStepChange = useCallback((nextStep: number) => {
    // On Android, add small delay to let player initialize before playing
    const playDelay = isAndroid ? 100 : 0;

    const safePlay = (player: any) => {
      setTimeout(() => {
        try {
          if (player && typeof player.play === 'function') {
            player.play();
          }
        } catch (e) { /* Ignore errors from released players */ }
      }, playDelay);
    };

    const safePause = (player: any) => {
      try {
        if (player && typeof player.pause === 'function') {
          player.pause();
        }
      } catch (e) { /* Ignore errors from released players */ }
    };

    // Handle video playback for each step
    switch (nextStep) {
      case 1:
        safePlay(player1);
        break;
      case 2:
        safePause(player1);
        safePlay(player2);
        break;
      case 3:
        safePause(player2);
        safePlay(player3);
        break;
      case 4:
        safePause(player3);
        safePlay(player1);
        // Step 4 has an iOS-only intro phase that plays the intro video
        // ahead of the existing card content. Kick it off in parallel so
        // the user sees motion the instant the slide arrives.
        safePlay(playerIntro);
        break;
      case 5:
        safePause(player1);
        safePause(playerIntro);
        break;
      case 6:
        safePlay(player4);
        break;
      case 7:
        safePause(player4);
        safePlay(player5);
        break;
      case 9:
        safePlay(player3);
        break;
      case 10:
        safePause(player3);
        break;
    }
  }, [player1, player2, player3, player4, player5, playerIntro, isAndroid]);

  const pauseAll = useCallback(() => {
    // player4/player5 alias player2/player1 on Android, so this covers all
    // live instances (and the null-source iOS slots on Android are no-ops).
    [player1, player2, player3, player4, player5, playerIntro].forEach((player) => {
      try {
        if (player && typeof player.pause === 'function') {
          player.pause();
        }
      } catch (e) { /* Ignore errors from released players */ }
    });
  }, [player1, player2, player3, player4, player5, playerIntro]);

  const pauseVerificationVideo = useCallback(() => {
    try {
      if (player5 && typeof player5.pause === 'function') {
        player5.pause();
      }
    } catch (e) { /* Ignore errors from released players */ }
  }, [player5]);

  return {
    players: { player1, player2, player3, player4, player5, playerIntro },
    handleStepChange,
    pauseAll,
    pauseVerificationVideo,
  };
}
