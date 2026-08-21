import React, { useState, useEffect } from 'react';
import { View, Text, TextInput, TouchableOpacity, LayoutChangeEvent, Image, ScrollView, Keyboard, Platform } from 'react-native';
import { createStepSpecificStyles } from './styles';
import { useColors } from '@/constants/theme';
import { useTranslation } from 'react-i18next';
import { CAP_SMALL } from '@/utils/font-scale-cap';

/** The CAN printed on French CNIe / recent passports is always 6 digits. */
const CAN_LENGTH = 6;

interface Step5CanProps {
  containerWidth: number;
  /** Available slide-area height; caps the iOS ScrollView so content scrolls
   * only when it overflows. */
  slideAreaHeight?: number;
  isActive?: boolean;
  /** Emits the 6-digit CAN once the user confirms. Step 6 forwards it to
   * scanDocument() as the PACE key. */
  onCanEntered?: (data: { can: string }) => void;
  /** Switches Step 5 over to the camera MRZ scanner (BAC) — the fallback for
   * documents with no printed CAN. */
  onUseMrzInstead?: () => void;
  onLayout?: (event: LayoutChangeEvent) => void;
  /** Only selects the doc-type-specific copy ("carte" vs "passeport") —
   * the CAN itself is entered the same way for both. Driven by the
   * selected proposal's voting contract upstream in voting-flow.tsx. */
  isPassportFlow?: boolean;
}

const Step5Can: React.FC<Step5CanProps> = ({ containerWidth, slideAreaHeight, isActive, onCanEntered, onUseMrzInstead, onLayout, isPassportFlow = false }) => {
  const { t } = useTranslation();
  const colors = useColors();
  const stepSpecificStyles = createStepSpecificStyles(colors);
  const docSfx = isPassportFlow ? 'passport' : 'idCard';
  const [can, setCan] = useState('');

  // Clear the field whenever the step becomes active again (e.g. Step 6's
  // "wrong document" path routes back here) so the user isn't confirming a
  // stale CAN from a previous attempt.
  useEffect(() => {
    if (isActive) setCan('');
  }, [isActive]);

  const isCanValid = can.length === CAN_LENGTH;

  const submit = () => {
    if (!isCanValid) return;
    // Drop the number pad before the slide animation runs, otherwise it stays
    // up over Step 6's NFC screen.
    Keyboard.dismiss();
    onCanEntered?.({ can });
  };

  return (
    <View style={[{ width: containerWidth }]} onLayout={onLayout}>
      {/* The number pad covers roughly the lower half of the screen, and this
          step sits inside the flow's fixed-height slide area — without a
          scroll container the Continue button ends up behind the keyboard and
          untappable. */}
      <ScrollView
        style={[
          { width: '100%' },
          Platform.OS === 'ios' ? { maxHeight: slideAreaHeight } : { flex: 1 },
        ]}
        // Without this a tap on Continue is swallowed by the gesture that
        // dismisses the number pad, so the first press does nothing.
        keyboardShouldPersistTaps="handled"
        showsVerticalScrollIndicator={false}
        contentContainerStyle={stepSpecificStyles.step5Container}
      >
        <Text style={stepSpecificStyles.step5Title} maxFontSizeMultiplier={CAP_SMALL}>
          {t(`voting.step5CanTitle_${docSfx}`)}
        </Text>

        <Image
          source={require('@/assets/webp/step6-nfc.webp')}
          style={{ width: '70%', height: 120 }}
          resizeMode="contain"
        />

        <Text
          maxFontSizeMultiplier={CAP_SMALL}
          style={{
            marginHorizontal: 24,
            textAlign: 'center',
            fontSize: 14,
            lineHeight: 20,
            color: colors.textSecondary,
          }}
        >
          {t(`voting.step5CanHint_${docSfx}`)}
        </Text>

        <TextInput
          style={{
            width: '70%',
            borderWidth: isCanValid ? 2 : 1,
            borderColor: isCanValid ? colors.scanReticleSuccess : colors.border,
            borderRadius: 8,
            paddingVertical: 14,
            fontSize: 26,
            textAlign: 'center',
            letterSpacing: 8,
            color: colors.text,
          }}
          value={can}
          // Strip anything non-numeric as the user types (some keyboards
          // still surface separators on the numeric pad) and hard-cap the
          // length so the confirm button can't be enabled by a paste.
          onChangeText={(text) => setCan(text.replace(/[^0-9]/g, '').slice(0, CAN_LENGTH))}
          keyboardType="number-pad"
          maxLength={CAN_LENGTH}
          placeholder="123456"
          placeholderTextColor={colors.textSecondary}
          autoFocus={isActive}
          returnKeyType="done"
          onSubmitEditing={submit}
        />

        <TouchableOpacity
          style={[
            stepSpecificStyles.step5Button,
            // step5Button's background matches the card, so on its own the
            // button reads as flat text. Give it the primary fill and dim it
            // when fewer than 6 digits are in, so enabled/disabled is obvious.
            { backgroundColor: colors.primary, opacity: isCanValid ? 1 : 0.4 },
          ]}
          activeOpacity={0.8}
          disabled={!isCanValid}
          onPress={submit}
        >
          <Text style={[stepSpecificStyles.step5ButtonText, { color: colors.buttonText }]}>
            {t('common.continue')}
          </Text>
        </TouchableOpacity>

        {onUseMrzInstead && (
          <TouchableOpacity onPress={onUseMrzInstead} activeOpacity={0.7}>
            <Text
              maxFontSizeMultiplier={CAP_SMALL}
              style={{ fontSize: 14, color: colors.primary, textDecorationLine: 'underline' }}
            >
              {t('voting.step5CanUseMrz')}
            </Text>
          </TouchableOpacity>
        )}
      </ScrollView>
    </View>
  );
};

export default Step5Can;
