import React from 'react';
import { View, Text, ScrollView, LayoutChangeEvent, Platform, Image } from 'react-native';
import { createModalStyles, createStepSpecificStyles } from './styles';
import { useColors } from '@/constants/theme';
import { useTranslation } from 'react-i18next';
import { CAP_SMALL } from '@/utils/font-scale-cap';

interface Step1Props {
  containerWidth: number;
  /** Available slide-area height; caps the iOS ScrollView so content scrolls
   * only when it overflows. */
  slideAreaHeight?: number;
  onLayout?: (event: LayoutChangeEvent) => void;
}

const Step1: React.FC<Step1Props> = ({
  containerWidth,
  slideAreaHeight,
  onLayout,
}) => {
  const { t } = useTranslation();
  const colors = useColors();
  const modalStyles = createModalStyles(colors);
  const stepSpecificStyles = createStepSpecificStyles(colors);

  return (
    <View style={[modalStyles.stepSlide, { width: containerWidth }]} onLayout={onLayout}>
      <ScrollView
        style={[
          { width: '100%' },
          Platform.OS === 'ios' ? { maxHeight: slideAreaHeight } : { flex: 1 },
        ]}
        showsVerticalScrollIndicator={false}
        bounces={false}
      >
        <View style={modalStyles.mediaContainer}>
          <Image
            source={require('@/assets/webp/step1-card.webp')}
            style={stepSpecificStyles.cardVideo}
            resizeMode="cover"
          />
        </View>
        <View style={modalStyles.contentSection}>
          <View style={modalStyles.stepContent}>
            <View style={modalStyles.stepHeader}>
              <View style={modalStyles.numberCircle}>
                <Text style={modalStyles.numberText} maxFontSizeMultiplier={CAP_SMALL}>
                  1
                </Text>
              </View>
              <Text style={modalStyles.stepTitle} maxFontSizeMultiplier={CAP_SMALL}>
                {t('voting.step1Title')}
              </Text>
            </View>
            <Text style={modalStyles.stepDescription} maxFontSizeMultiplier={CAP_SMALL}>
              {t('voting.step1Description')}
            </Text>
            <Text
              style={[
                modalStyles.stepDescription,
                { fontWeight: 'bold', color: colors.errorText, marginTop: 8 },
              ]}
              maxFontSizeMultiplier={CAP_SMALL}
            >
              {t('voting.step1Privacy')}
            </Text>
          </View>
        </View>
      </ScrollView>
    </View>
  );
};

export default Step1;
