import React from 'react';
import { View, Text, ScrollView, LayoutChangeEvent, Platform, Image } from 'react-native';
import { createModalStyles, createStepSpecificStyles } from './styles';
import { useColors } from '@/constants/theme';
import { useTranslation } from 'react-i18next';
import { CAP_SMALL } from '@/utils/font-scale-cap';

interface Step3Props {
  containerWidth: number;
  slideAreaHeight?: number;
  onLayout?: (event: LayoutChangeEvent) => void;
}

const Step3: React.FC<Step3Props> = ({ containerWidth, slideAreaHeight, onLayout }) => {
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
            source={require('@/assets/webp/step3-ballot.webp')}
            style={stepSpecificStyles.ballotImage}
            resizeMode="contain"
          />
        </View>
        <View style={modalStyles.contentSection}>
          <View style={modalStyles.stepContent}>
            <View style={modalStyles.stepHeader}>
              <View style={modalStyles.numberCircle}>
                <Text style={modalStyles.numberText} maxFontSizeMultiplier={CAP_SMALL}>
                  3
                </Text>
              </View>
              <Text style={modalStyles.stepTitle} maxFontSizeMultiplier={CAP_SMALL}>
                {t('voting.step3Title')}
              </Text>
            </View>
            <Text style={modalStyles.stepDescription} maxFontSizeMultiplier={CAP_SMALL}>
              {t('voting.step3Description')}
            </Text>
          </View>
        </View>
      </ScrollView>
    </View>
  );
};

export default Step3;
