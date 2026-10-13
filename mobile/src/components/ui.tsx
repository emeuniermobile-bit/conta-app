import { Pressable, StyleSheet, Text, View, type StyleProp, type TextStyle, type ViewStyle } from 'react-native';
import type { ReactNode } from 'react';

import { corruptText, noise, withAlpha } from '@/lib/theme';
import { useTheme } from '@/state/theme-context';
import { useTick } from './use-tick';

/** Texte qui tremble pendant l'incubation et se déforme chez les zombies. */
export function GlitchText({
  children,
  size = 16,
  weight = '400',
  style,
}: {
  children: string;
  size?: number;
  weight?: TextStyle['fontWeight'];
  style?: StyleProp<TextStyle>;
}) {
  const theme = useTheme();
  const glitching = theme.corruption > 0;
  const tick = useTick(theme.isZombie ? 120 : 200, glitching);
  const base: TextStyle = { fontFamily: theme.mono, fontSize: size, fontWeight: weight, color: theme.text };

  if (!glitching) return <Text style={[base, style]}>{children}</Text>;

  const jitter = theme.corruption * 2.5;
  return (
    <View>
      <Text
        style={[
          base,
          style,
          StyleSheet.absoluteFill,
          {
            color: withAlpha(theme.accent, 0.5),
            transform: [{ translateX: noise(tick, 1) * jitter }, { translateY: noise(tick, 2) * jitter * 0.5 }],
          },
        ]}
      >
        {children}
      </Text>
      <Text style={[base, style]}>{corruptText(children, theme.corruption, tick)}</Text>
    </View>
  );
}

/** Texte monospace simple, aux couleurs du thème. */
export function Mono({
  children,
  size = 13,
  weight = '400',
  color,
  style,
}: {
  children: ReactNode;
  size?: number;
  weight?: TextStyle['fontWeight'];
  color?: string;
  style?: StyleProp<TextStyle>;
}) {
  const theme = useTheme();
  return (
    <Text style={[{ fontFamily: theme.mono, fontSize: size, fontWeight: weight, color: color ?? theme.text }, style]}>
      {children}
    </Text>
  );
}

export function Panel({ title, children, style }: { title?: string; children: ReactNode; style?: StyleProp<ViewStyle> }) {
  const theme = useTheme();
  return (
    <View
      style={[
        styles.panel,
        { backgroundColor: withAlpha(theme.surface, 0.92), borderColor: withAlpha(theme.accent, 0.25) },
        style,
      ]}
    >
      {title ? (
        <Mono size={11} weight="600" color={theme.muted} style={styles.panelTitle}>
          {title.toUpperCase()}
        </Mono>
      ) : null}
      {children}
    </View>
  );
}

export function ActionButton({
  title,
  onPress,
  disabled,
  prominent = true,
  style,
}: {
  title: string;
  onPress: () => void;
  disabled?: boolean;
  prominent?: boolean;
  style?: StyleProp<ViewStyle>;
}) {
  const theme = useTheme();
  return (
    <Pressable
      accessibilityRole="button"
      onPress={onPress}
      disabled={disabled}
      style={({ pressed }) => [
        styles.button,
        {
          backgroundColor: prominent ? theme.accent : 'transparent',
          borderColor: theme.accent,
          opacity: disabled ? 0.35 : pressed ? 0.7 : 1,
        },
        style,
      ]}
    >
      <Mono size={14} weight="700" color={prominent ? theme.background : theme.accent} style={styles.buttonText}>
        {title.toUpperCase()}
      </Mono>
    </Pressable>
  );
}

/** Fond commun : grille de radar, et bandes de bruit qui pulsent quand l'infection gagne. */
export function ThemedBackground() {
  const theme = useTheme();
  const glitching = theme.corruption > 0;
  const tick = useTick(150, glitching);
  const lines = glitching ? Math.round(3 + theme.corruption * 9) : 0;

  return (
    <View pointerEvents="none" style={[StyleSheet.absoluteFill, { backgroundColor: theme.background }]}>
      {Array.from({ length: 40 }, (_, i) => (
        <View
          key={`h${i}`}
          style={[styles.gridLine, { top: i * 32, left: 0, right: 0, height: StyleSheet.hairlineWidth, backgroundColor: withAlpha(theme.accent, 0.06) }]}
        />
      ))}
      {Array.from({ length: 16 }, (_, i) => (
        <View
          key={`v${i}`}
          style={[styles.gridLine, { left: i * 32, top: 0, bottom: 0, width: StyleSheet.hairlineWidth, backgroundColor: withAlpha(theme.accent, 0.06) }]}
        />
      ))}
      {Array.from({ length: lines }, (_, i) => (
        <View
          key={`n${i}`}
          style={[
            styles.gridLine,
            {
              left: 0,
              right: 0,
              top: `${(noise(tick, i) * 0.5 + 0.5) * 100}%`,
              height: 1 + (noise(tick, i + 50) * 0.5 + 0.5) * 6 * theme.corruption,
              backgroundColor: withAlpha(theme.accent, 0.06 + 0.1 * theme.corruption),
            },
          ]}
        />
      ))}
    </View>
  );
}

export function ProgressBar({ progress, color }: { progress: number; color?: string }) {
  const theme = useTheme();
  return (
    <View style={[styles.bar, { backgroundColor: withAlpha(theme.muted, 0.25) }]}>
      <View
        style={{
          width: `${Math.min(Math.max(progress, 0), 1) * 100}%`,
          height: '100%',
          backgroundColor: color ?? (theme.isZombie ? theme.muted : theme.safe),
        }}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  panel: { padding: 16, borderRadius: 4, borderWidth: 1, gap: 12 },
  panelTitle: { letterSpacing: 2 },
  button: { paddingVertical: 12, borderRadius: 4, borderWidth: 1, alignItems: 'center' },
  buttonText: { letterSpacing: 1 },
  gridLine: { position: 'absolute' },
  bar: { height: 6, borderRadius: 3, overflow: 'hidden' },
});
