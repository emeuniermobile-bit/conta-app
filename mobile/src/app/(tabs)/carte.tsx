import { useState } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';
import MapView, { Marker, Polygon } from 'react-native-maps';
import { SafeAreaView } from 'react-native-safe-area-context';

import { useTick } from '@/components/use-tick';
import { Mono, Panel } from '@/components/ui';
import { ARRONDISSEMENTS, PARIS_REGION } from '@/lib/arrondissements';
import { arrondissementLabel, type ArrondissementStatus, type ZoneStatus } from '@/lib/game';
import { withAlpha } from '@/lib/theme';
import { useGame } from '@/state/game-context';
import { useTheme } from '@/state/theme-context';

/**
 * Carte de Paris par arrondissement : zones saines, disputées, tombées.
 * Uniquement des agrégats ; jamais de joueur individuel.
 */
export default function MapTab() {
  const { city } = useGame();
  const theme = useTheme();
  const [selected, setSelected] = useState<number | null>(null);
  // Les zones tombées pulsent, plus vite et plus fort côté zombie.
  const pulse = useTick(theme.isZombie ? 800 : 1200) % 2 === 1;

  const byCode = new Map(city.map((a) => [a.code, a]));
  const statusOf = (code: number): ZoneStatus => byCode.get(code)?.status ?? 'unknown';
  const colorOf = (status: ZoneStatus) =>
    ({ green: theme.safe, contested: theme.contested, red: theme.danger, unknown: theme.muted })[status];
  const fillOpacity = (status: ZoneStatus) => {
    if (status === 'unknown') return 0.08;
    if (status !== 'red') return 0.28;
    return pulse ? 0.28 + (theme.isZombie ? 0.3 : 0.12) : 0.28;
  };
  const detail = selected != null ? byCode.get(selected) : undefined;

  return (
    <View style={[styles.fill, { backgroundColor: theme.background }]}>
      <MapView
        style={styles.fill}
        initialRegion={PARIS_REGION}
        userInterfaceStyle="dark"
        showsUserLocation
        showsPointsOfInterests={false}
        showsBuildings={false}
        showsTraffic={false}
        rotateEnabled={false}
        pitchEnabled={false}
      >
        {ARRONDISSEMENTS.flatMap((shape) => {
          const status = statusOf(shape.code);
          const color = colorOf(status);
          return shape.rings.map((ring, i) => (
            <Polygon
              key={`${shape.code}-${i}`}
              coordinates={ring}
              fillColor={withAlpha(color, fillOpacity(status))}
              strokeColor={withAlpha(color, 0.9)}
              strokeWidth={1}
              tappable
              onPress={() => setSelected(shape.code)}
            />
          ));
        })}
        {ARRONDISSEMENTS.map((shape) => (
          <Marker key={`label-${shape.code}`} coordinate={shape.center} onPress={() => setSelected(shape.code)} tracksViewChanges={false}>
            <Mono size={11} weight="700">{arrondissementLabel(shape.code)}</Mono>
          </Marker>
        ))}
      </MapView>

      <SafeAreaView pointerEvents="box-none" style={styles.overlay} edges={['bottom']}>
        {selected != null ? (
          <Pressable onPress={() => setSelected(null)}>
            <ZoneDetail
              code={selected}
              name={ARRONDISSEMENTS.find((a) => a.code === selected)?.name ?? ''}
              status={detail}
            />
          </Pressable>
        ) : null}
        <View style={[styles.legend, { backgroundColor: withAlpha(theme.surface, 0.92) }]}>
          {(
            [
              ['green', 'Sain'],
              ['contested', 'Disputé'],
              ['red', theme.isZombie ? 'À nous' : 'Tombé'],
              ['unknown', 'Inconnu'],
            ] as [ZoneStatus, string][]
          ).map(([status, label]) => (
            <View key={status} style={styles.legendItem}>
              <View style={[styles.dot, { backgroundColor: colorOf(status) }]} />
              <Mono size={11}>{label}</Mono>
            </View>
          ))}
        </View>
      </SafeAreaView>
    </View>
  );
}

function ZoneDetail({ code, name, status }: { code: number; name: string; status?: ArrondissementStatus }) {
  const theme = useTheme();
  return (
    <Panel title={`Paris ${arrondissementLabel(code)} — ${name}`}>
      {status?.infection_ratio != null && status.active_players != null ? (
        <Mono size={13}>
          {Math.round(status.infection_ratio * 100)} % d&apos;infectés parmi {status.active_players} joueurs actifs
        </Mono>
      ) : (
        <Mono size={13} color={theme.muted}>Pas assez de joueurs pour publier des chiffres.</Mono>
      )}
    </Panel>
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1 },
  overlay: { position: 'absolute', left: 12, right: 12, bottom: 12, gap: 10 },
  legend: { flexDirection: 'row', justifyContent: 'space-around', paddingVertical: 8, borderRadius: 20 },
  legendItem: { flexDirection: 'row', alignItems: 'center', gap: 4 },
  dot: { width: 8, height: 8, borderRadius: 4 },
});
