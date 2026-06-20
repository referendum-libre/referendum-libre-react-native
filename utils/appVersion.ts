import * as Application from 'expo-application';

// App version, e.g. "1.0.0" — the native binary version, frozen at build time.
export function getAppVersion(): string {
  return Application.nativeApplicationVersion ?? '1.0';
}
