import React from 'react';
import { View, Text, ScrollView, LayoutChangeEvent, Platform, Image } from 'react-native';
import { createModalStyles, createStepSpecificStyles } from './styles';
import { useColors } from '@/constants/theme';
import { useTranslation } from 'react-i18next';
import { CAP_SMALL } from '@/utils/font-scale-cap';

interface Step2Props {
  containerWidth: number;
  slideAreaHeight?: number;
  onLayout?: (event: LayoutChangeEvent) => void;
  isPassportFlow?: boolean;
}

const Step2: React.FC<Step2Props> = ({
  containerWidth,
  slideAreaHeight,
  onLayout,
  isPassportFlow = false,
}) => {
  const { t } = useTranslation();
  const docSfx = isPassportFlow ? 'passport' : 'idCard';
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
            source={require('@/assets/webp/step2-phone.webp')}
            style={stepSpecificStyles.phoneImage}
            resizeMode="contain"
          />
        </View>
        <View style={modalStyles.contentSection}>
          <View style={modalStyles.stepContent}>
            <View style={modalStyles.stepHeader}>
              <View style={modalStyles.numberCircle}>
                <Text style={modalStyles.numberText} maxFontSizeMultiplier={CAP_SMALL}>
                  2
                </Text>
              </View>
              <Text style={modalStyles.stepTitle} maxFontSizeMultiplier={CAP_SMALL}>
                {t('voting.step2Title')}
              </Text>
            </View>
            <Text style={modalStyles.stepDescription} maxFontSizeMultiplier={CAP_SMALL}>
              {t(`voting.step2Description_${docSfx}`)}
            </Text>
          </View>
        </View>
      </ScrollView>
    </View>
  );
};

export default Step2;
