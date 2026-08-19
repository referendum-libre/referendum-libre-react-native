/**
 * Expo config plugin: enable Fresco's animated-WebP decoder on Android.
 *
 * Why this is required (not optional):
 *   The illustrated steps in the voting flow (Step1/2/3/4/6/7/10, Step9Vote and
 *   the Comprendre hero) render short looping animations through React Native's
 *   <Image>. On Android that goes through Fresco, and Fresco ships *no* animated
 *   image decoders by default — the bare template gates each one behind a gradle
 *   property:
 *
 *     def isWebpEnabled        = (findProperty('expo.webp.enabled')  ?: "") == "true"
 *     def isWebpAnimatedEnabled= (findProperty('expo.webp.animated') ?: "") == "true"
 *     if (isWebpEnabled) {
 *       implementation("com.facebook.fresco:webpsupport:...")
 *       if (isWebpAnimatedEnabled) {
 *         implementation("com.facebook.fresco:animated-webp:...")
 *       }
 *     }
 *
 *   Note animated-webp is nested inside the webpsupport branch, so BOTH
 *   properties are required — setting `expo.webp.animated` alone silently does
 *   nothing. Without them the .webp assets decode as a still first frame (or
 *   fail outright), which is exactly the "no motion on Android" regression the
 *   move away from ExoPlayer was meant to fix.
 *
 *   iOS needs no equivalent: animated WebP is decoded natively there.
 *
 * A direct edit to android/app/gradle.properties works for the current dev APK
 * but is wiped on the next `expo prebuild --clean` (the android/ folder is
 * gitignored and regenerated). This plugin makes the properties survive every
 * prebuild.
 */

const { withGradleProperties } = require('@expo/config-plugins');

const PROPERTIES = [
  // Pulls in com.facebook.fresco:webpsupport (static WebP + the gate for the
  // animated decoder below).
  'expo.webp.enabled',
  // Pulls in com.facebook.fresco:animated-webp.
  'expo.webp.animated',
];

module.exports = function withAnimatedWebp(config) {
  return withGradleProperties(config, (cfg) => {
    for (const key of PROPERTIES) {
      // Replace any existing entry so a stale `false` from a previous prebuild
      // (or a template default) can't win over ours.
      cfg.modResults = cfg.modResults.filter(
        (item) => !(item.type === 'property' && item.key === key)
      );
      cfg.modResults.push({ type: 'property', key, value: 'true' });
    }
    return cfg;
  });
};
