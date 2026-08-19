import React, { useEffect } from 'react';
import { View, Text, TouchableOpacity, LayoutChangeEvent, Image } from 'react-native';
import { createModalStyles, createStepSpecificStyles } from './styles';
import { useColors } from '@/constants/theme';
import type { ProposalInfo } from '@rarimo/rarime-rn-sdk';
import { useTranslation } from 'react-i18next';

interface Step10Props {
  containerWidth: number;
  onCancel?: () => void;
  onConfirm?: () => void;
  onLayout?: (event: LayoutChangeEvent) => void;
  selectedVote?: number;
  proposalInfo?: ProposalInfo;
}

const Step10: React.FC<Step10Props> = ({ containerWidth, onCancel, onConfirm, onLayout, selectedVote = 0, proposalInfo }) => {
  const { t } = useTranslation();
  const colors = useColors();
  const modalStyles = createModalStyles(colors);
  const stepSpecificStyles = createStepSpecificStyles(colors);

  const variants = proposalInfo?.questions[0]?.variants ?? ['OUI', 'BLANC', 'NON'];
  const variantName = variants[selectedVote] ?? '';

  useEffect(() => {
    if (proposalInfo) {
      // No variant / index — anonymous voting (see Step9Vote comment).
      console.log(`[Step10] Confirming vote for proposal #${proposalInfo.id}`);
    }
  }, [selectedVote, proposalInfo]);

  const getVoteText = () => variantName.toUpperCase();
  const getButtonText = () => t('voting.step10VoteAction', { vote: variantName });

  return (
    <View style={[{ width: containerWidth }]} onLayout={onLayout}>
      <View style={stepSpecificStyles.step10Container}>
        <View style={stepSpecificStyles.step10Content}>
          <Text style={stepSpecificStyles.step10Title}>
            {t('voting.step10Confirm', { vote: getVoteText() })}
          </Text>

          <Image
            source={require('@/assets/webp/step3-ballot.webp')}
            style={stepSpecificStyles.step10BallotVideo}
            resizeMode="cover"
          />
        </View>

        <View style={stepSpecificStyles.step10ButtonContainer}>
          <TouchableOpacity
            style={stepSpecificStyles.step10CancelButton}
            activeOpacity={0.8}
            onPress={onCancel || (() => console.log('Cancel'))}
          >
            <Text style={stepSpecificStyles.step10CancelButtonText}>{t('common.cancel')}</Text>
          </TouchableOpacity>

          <TouchableOpacity
            style={stepSpecificStyles.step10ConfirmButton}
            activeOpacity={0.8}
            onPress={onConfirm || (() => console.log('Confirm vote'))}
          >
            <Text style={stepSpecificStyles.step10ConfirmButtonText}>{getButtonText()}</Text>
          </TouchableOpacity>
        </View>
      </View>
    </View>
  );
};

export default Step10;
