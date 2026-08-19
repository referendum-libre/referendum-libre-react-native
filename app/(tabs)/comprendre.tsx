import React from 'react';
import { StyleSheet, ScrollView, View, Text, Image, useWindowDimensions } from 'react-native';
import Accordion from '@/components/Accordion';
import { useColors, Typography, Spacing } from '@/constants/theme';
import { useTranslation } from 'react-i18next';
import SettingsButton from '@/components/SettingsButton';
import { CAP_BIG } from '@/utils/font-scale-cap';

export default function ComprendreScreen() {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = createStyles(colors);
  // Scale the character animation in step with the welcome text so they grow
  // together — never below the design size, never past CAP_BIG.
  const { fontScale } = useWindowDimensions();
  const welcomeMediaScale = Math.min(Math.max(fontScale, 1), CAP_BIG);
  const sectionsRaw = t('comprendre.sections', { returnObjects: true });
  const sections = Array.isArray(sectionsRaw)
    ? (sectionsRaw as {
        title: string;
        intro?: string;
        accordions: { title: string; content: string }[];
      }[])
    : [];

  return (
    <View style={styles.screenContainer}>
      <ScrollView style={styles.scrollView} contentContainerStyle={styles.contentContainer} bounces={false}>
        {/* Header Section */}
        <View style={styles.headerSection}>
          <View style={styles.headerRow}>
            <Text style={styles.headerTitle}>{t('comprendre.welcome.title')}</Text>
            <SettingsButton />
          </View>
          <View style={styles.welcomeContainer}>
            <Image
              style={[
                styles.characterVideo,
                {
                  width: Spacing.video.characterWidth * welcomeMediaScale,
                  height: Spacing.video.characterHeight * welcomeMediaScale,
                },
              ]}
              source={require('@/assets/webp/comprendre-welcome.webp')}
              resizeMode="cover"
            />
            <View style={styles.welcomeTextContainer}>
              <Text style={styles.welcomeText} maxFontSizeMultiplier={CAP_BIG}>
                {t('comprendre.welcome.text')}
              </Text>
            </View>
          </View>
        </View>

        {/* Sections — each with a pillar header, optional intro paragraph, and a list of Q/A accordions */}
        {sections.map((section, sIdx) => (
          <View key={sIdx} style={styles.section}>
            <Text style={styles.sectionTitle}>{section.title}</Text>
            {section.intro ? (
              <Text style={styles.sectionIntro}>{section.intro}</Text>
            ) : null}
            {section.accordions.map((accordion, aIdx) => (
              <Accordion
                key={aIdx}
                title={accordion.title}
                content={accordion.content}
                showBorder={true}
              />
            ))}
          </View>
        ))}

        {/* Empty spacer for tab bar */}
        <View style={styles.tabBarSpacer} />
      </ScrollView>
    </View>
  );
}

const createStyles = (colors: ReturnType<typeof useColors>) => StyleSheet.create({
  screenContainer: {
    flex: 1,
    backgroundColor: colors.background,
  },
  scrollView: {
    flex: 1,
  },
  contentContainer: {
    paddingBottom: Spacing.tabBar.containerHeight,
  },
  headerSection: {
    backgroundColor: colors.cardBackground,
    paddingTop: Spacing.screen.top,
    paddingHorizontal: Spacing.screen.horizontal,
    paddingBottom: Spacing.screen.bottom,
    gap: Spacing.screen.gap,
  },
  headerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  headerTitle: {
    fontFamily: Typography.fontFamily.bold,
    fontSize: Typography.fontSize.h1,
    lineHeight: Typography.lineHeight.h1,
    letterSpacing: Typography.letterSpacing.h1,
    color: colors.text,
  },
  welcomeContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.screen.gap,
    backgroundColor: colors.cardBackground,
  },
  characterVideo: {
    width: Spacing.video.characterWidth,
    height: Spacing.video.characterHeight,
    borderRadius: Spacing.video.borderRadius,
    margin: 12,
  },
  welcomeTextContainer: {
    flex: 1,
    justifyContent: 'center',
    backgroundColor: colors.cardBackground,
  },
  welcomeText: {
    fontFamily: Typography.fontFamily.medium,
    fontWeight: Typography.fontWeight.medium,
    fontSize: Typography.fontSize.small,
    lineHeight: Typography.lineHeight.small,
    letterSpacing: Typography.letterSpacing.small,
    color: colors.text,
  },
  section: {
    backgroundColor: colors.cardBackground,
    paddingTop: Spacing.accordion.padding,
  },
  sectionTitle: {
    paddingHorizontal: Spacing.accordion.padding,
    paddingBottom: Spacing.accordion.gap,
    fontFamily: Typography.fontFamily.bold,
    fontSize: Typography.fontSize.h1,
    lineHeight: Typography.lineHeight.h1,
    letterSpacing: Typography.letterSpacing.h1,
    color: colors.text,
  },
  sectionIntro: {
    paddingHorizontal: Spacing.accordion.padding,
    paddingBottom: Spacing.accordion.gap,
    fontFamily: Typography.fontFamily.medium,
    fontWeight: Typography.fontWeight.medium,
    fontSize: Typography.fontSize.body,
    lineHeight: Typography.lineHeight.body,
    letterSpacing: Typography.letterSpacing.body,
    color: colors.text,
  },
  tabBarSpacer: {
    height: Spacing.tabBar.containerHeight,
    backgroundColor: 'transparent',
  },
});
