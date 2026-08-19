import React from 'react';
import { render, fireEvent, screen } from '@testing-library/react-native';

jest.mock('@react-native-async-storage/async-storage', () =>
  require('@react-native-async-storage/async-storage/jest/async-storage-mock'),
);
jest.mock('lottie-react-native', () => {
  const { View } = require('react-native');
  return { __esModule: true, default: View };
});

import '@/locales';
import Step8 from './Step8';
import { ThemeProvider } from '@/contexts/ThemeContext';

// The "Vote now" button must only advance the flow when Step 7 actually
// verified the registration. Three production reports (2026-06-11/12, all
// iOS, proposal #54) show users reaching the vote screens with NO NFC scan
// and NO registration — Step 11 then dead-ends on "Unknown vote error".
// Whatever the (still unidentified) jump path is, this guard makes it
// harmless: an unverified user cannot advance past Step 8.
describe('Step8 vote-now guard', () => {
  // ThemeProvider loads the persisted theme from AsyncStorage and renders
  // nothing until that promise settles, so wait for the button to appear
  // before pressing it.
  const press = async (ui: React.ReactElement) => {
    const r = render(<ThemeProvider>{ui}</ThemeProvider>);
    // i18n fr: "Votez maintenant"; fall back to the raw key if i18n isn't
    // initialised in the jest environment.
    fireEvent.press(await screen.findByText(/Votez maintenant|step8VoteNow/));
    return r;
  };

  it('fires onVoteSuccess when verification succeeded', async () => {
    const onVoteSuccess = jest.fn();
    await press(<Step8 containerWidth={300} verificationResult="success" onVoteSuccess={onVoteSuccess} />);
    expect(onVoteSuccess).toHaveBeenCalledTimes(1);
  });

  it.each([null, undefined, 'error'] as const)(
    'does NOT fire onVoteSuccess when verificationResult is %s',
    async (vr) => {
      const onVoteSuccess = jest.fn();
      await press(
        <Step8
          containerWidth={300}
          verificationResult={vr as any}
          onVoteSuccess={onVoteSuccess}
        />,
      );
      expect(onVoteSuccess).not.toHaveBeenCalled();
    },
  );
});
