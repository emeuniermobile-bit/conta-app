import { View } from 'react-native';

import { Screen, SeasonHeader } from '@/components/screen';
import { Mono, Panel } from '@/components/ui';
import { useGame } from '@/state/game-context';
import { useTheme } from '@/state/theme-context';

/** Classement des meilleurs contaminateurs de la saison. */
export default function LeaderboardTab() {
  const { leaderboard, refresh } = useGame();
  const theme = useTheme();
  return (
    <Screen onRefresh={refresh}>
      <SeasonHeader />
      <Panel title="Meilleurs contaminateurs">
        {leaderboard.length === 0 ? (
          <Mono size={13} color={theme.muted}>Personne n&apos;a encore contaminé. Pour l&apos;instant.</Mono>
        ) : null}
        {leaderboard.map((entry) => (
          <View key={`${entry.rank}-${entry.display_name}`} style={{ flexDirection: 'row', alignItems: 'center', gap: 10 }}>
            <Mono size={13} weight="700" color={theme.muted}>{String(entry.rank).padStart(2, '0')}</Mono>
            <Mono size={15} weight={entry.is_me ? '900' : '400'} color={entry.is_me ? theme.accent : theme.text} style={{ flex: 1 }}>
              {entry.display_name}
            </Mono>
            <Mono size={15} weight="700" color={theme.danger}>{entry.contaminations}</Mono>
          </View>
        ))}
      </Panel>
    </Screen>
  );
}
