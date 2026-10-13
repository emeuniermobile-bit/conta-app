import { SymbolView, type SymbolViewProps } from 'expo-symbols';
import { useEffect, type ReactNode } from 'react';
import { Pressable, RefreshControl, ScrollView, StyleSheet, View, type ColorValue } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { withAlpha } from '@/lib/theme';
import { useGame } from '@/state/game-context';
import { useTheme } from '@/state/theme-context';
import { Mono, ProgressBar, ThemedBackground } from './ui';
import { useNow } from './use-tick';

/** Page défilante sur fond thématique, avec « tirer pour rafraîchir ». */
export function Screen({ children, onRefresh }: { children: ReactNode; onRefresh?: () => Promise<void> }) {
  const theme = useTheme();
  return (
    <View style={styles.fill}>
      <ThemedBackground />
      <SafeAreaView style={styles.fill} edges={['top']}>
        <ScrollView
          contentContainerStyle={styles.content}
          keyboardShouldPersistTaps="handled"
          refreshControl={
            onRefresh ? <RefreshControl refreshing={false} onRefresh={onRefresh} tintColor={theme.accent} /> : undefined
          }
        >
          {children}
        </ScrollView>
      </SafeAreaView>
    </View>
  );
}

export type SymbolName = Extract<SymbolViewProps['name'], string>;

/** Symbole iOS (SF Symbols), rien ailleurs. */
export function Icon({ name, color, size = 20 }: { name: SymbolName; color: ColorValue; size?: number }) {
  return <SymbolView name={name} tintColor={color} size={size} fallback={<View style={{ width: size, height: size }} />} />;
}

/** En-tête commun : souche en cours et barre du Laboratoire. */
export function SeasonHeader() {
  const { game } = useGame();
  const theme = useTheme();
  const now = useNow(60_000);
  const season = game?.season;
  if (!season) return null;
  const progress = Math.min(season.lab_points / Math.max(season.lab_goal, 1), 1);
  const daysLeft = Math.max(0, Math.ceil((Date.parse(season.ends_at) - now) / 86_400_000));
  return (
    <View style={{ gap: 6 }}>
      <View style={styles.row}>
        <Mono size={12} weight="700" color={theme.accent} style={{ letterSpacing: 2 }}>
          {season.strain_name.toUpperCase()}
        </Mono>
        <Mono size={11} color={theme.muted}>
          {daysLeft > 1 ? `Fin dans ${daysLeft} jours` : 'Dernier jour'}
        </Mono>
      </View>
      <ProgressBar progress={progress} />
      <View style={styles.row}>
        <Mono size={11} color={theme.muted}>Laboratoire {Math.floor(progress * 100)} %</Mono>
        <Mono size={11} color={theme.muted}>Infectés {Math.round(season.infection_ratio * 100)} %</Mono>
      </View>
    </View>
  );
}

/** Message éphémère en haut de l'écran. */
export function Toast() {
  const { toast, dismissToast } = useGame();
  const theme = useTheme();
  useEffect(() => {
    if (!toast) return;
    const timer = setTimeout(dismissToast, 3000);
    return () => clearTimeout(timer);
  }, [toast, dismissToast]);
  if (!toast) return null;
  return (
    <SafeAreaView pointerEvents="box-none" style={styles.toastWrap} edges={['top']}>
      <Pressable
        onPress={dismissToast}
        style={[styles.toast, { backgroundColor: theme.surface, borderColor: withAlpha(theme.accent, 0.6) }]}
      >
        <Mono size={13} weight="600">{toast}</Mono>
      </Pressable>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1 },
  content: { padding: 20, gap: 16, paddingBottom: 48 },
  row: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  toastWrap: { position: 'absolute', top: 0, left: 0, right: 0, alignItems: 'center' },
  toast: { marginTop: 8, paddingHorizontal: 16, paddingVertical: 10, borderRadius: 20, borderWidth: 1, maxWidth: '90%' },
});
